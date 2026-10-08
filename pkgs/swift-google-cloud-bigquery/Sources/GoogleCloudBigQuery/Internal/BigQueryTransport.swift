// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import GoogleCloudBigQueryV2
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) import GoogleWKT

/// Sends BigQuery requests: retries, error mapping, and JSON decoding.
///
/// Every RPC in the client goes through one of these methods:
/// - ``json(_:idempotent:)`` decodes a 2xx body. Use ``jsonOrNil(_:as:idempotent:)`` for `get*`.
/// - ``deleteOrFalse(_:idempotent:)`` maps 404 to `false`.
/// - ``send(_:idempotent:)`` returns the raw 2xx response.
/// - ``json(idempotent:options:request:validate:)`` builds the request for each attempt and
///   validates each decoded response inside the retry loop.
/// - ``sendOnce(_:)`` sends a single attempt and returns any status (resumable uploads).
///
/// After the retry loop, an HTTP error status becomes ``BigQueryError`` with kind
/// ``BigQueryError/Kind-swift.struct/service``, whichever retry limit stopped the loop.
struct BigQueryTransport: Sendable {
  let http: any HTTPTransport
  let clientOptions: ClientOptions
  let sleep: @Sendable (Duration) async throws -> Void

  init(
    http: any HTTPTransport,
    clientOptions: ClientOptions,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.http = http
    self.clientOptions = clientOptions
    self.sleep = sleep
  }

  /// Sends `request` with retries and decodes the 2xx response body.
  func json<R: Decodable>(_ request: HTTPRequest, idempotent: Bool) async throws -> R {
    try await self.json(idempotent: idempotent, options: request.options) { _ in request }
  }

  /// Like ``json(_:idempotent:)``, but returns `nil` if the resource does not exist (HTTP 404).
  ///
  /// The response type is explicit because inference from an optional result would pick
  /// `Optional<R>`, which the ProtoJSON decoder cannot decode.
  func jsonOrNil<R: Decodable>(
    _ request: HTTPRequest, as type: R.Type, idempotent: Bool = true
  ) async throws -> R? {
    do {
      return try await self.json(request, idempotent: idempotent) as R
    } catch let error as BigQueryError where error.isHTTPNotFound {
      return nil
    }
  }

  /// Sends a request that has no useful response body. Returns `false` on HTTP 404.
  func deleteOrFalse(_ request: HTTPRequest, idempotent: Bool = true) async throws -> Bool {
    do {
      _ = try await self.send(request, idempotent: idempotent)
      return true
    } catch let error as BigQueryError where error.isHTTPNotFound {
      return false
    }
  }

  /// Sends `request` with retries and returns the 2xx response.
  func send(_ request: HTTPRequest, idempotent: Bool) async throws -> HTTPResponse {
    try await self.run(idempotent: idempotent, options: request.options) { _, timeout in
      try await self.attempt(request, timeout: timeout)
    }
  }

  /// Sends a request with retries, building the request for each attempt.
  ///
  /// - Parameters:
  ///   - idempotent: whether the retry policy may retry the request.
  ///   - options: the per-call options that configure the retry loop.
  ///   - request: returns the request for an attempt. Attempts are numbered from 1.
  ///   - validate: checks each decoded response. Throw a retryable `RequestError` (for example
  ///     ``GoogleGax/RequestError/jobRateLimited(_:)``) to retry, or any other error to stop.
  func json<R: Decodable>(
    idempotent: Bool,
    options: RequestOptions,
    request: (_ attempt: Int) throws -> HTTPRequest,
    validate: (R) throws -> Void = { _ in }
  ) async throws -> R {
    try await self.run(idempotent: idempotent, options: options) { attempt, timeout in
      let response = try await self.attempt(request(attempt), timeout: timeout)
      let value: R = try Self.decode(response.body)
      try validate(value)
      return value
    }
  }

  /// Sends a single attempt, without retries, and returns the response whatever its status.
  func sendOnce(_ request: HTTPRequest) async throws -> HTTPResponse {
    let timeout = request.options.attemptTimeout ?? self.clientOptions.attemptTimeout
    return try await self.sendWrappingIO(request, timeout: timeout)
  }

  /// Runs `body` in the retry loop and maps the final error.
  func run<Result>(
    idempotent: Bool,
    options: RequestOptions,
    _ body: (_ attempt: Int, _ timeout: Duration?) async throws -> Result
  ) async throws -> Result {
    let loop = _RetryLoop(options: options, withDefault: self.clientOptions, idempotent: idempotent)
    var attempt = 0
    do {
      return try await loop.run(
        inner: { timeout in
          attempt += 1
          return try await body(attempt, timeout)
        },
        sleep: self.sleep)
    } catch let error as RequestError {
      throw Self.map(error)
    }
  }

  /// Sends one attempt and turns a non-2xx status into `RequestError.http`.
  func attempt(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPResponse {
    let response = try await self.sendWrappingIO(request, timeout: timeout)
    guard (200..<300).contains(response.statusCode) else {
      throw RequestError.http(
        HTTPDetails(
          statusCode: response.statusCode,
          headers: HTTPHeaders(response.headers.map { (name: $0.key, value: $0.value) }),
          payload: response.body))
    }
    return response
  }

  private func sendWrappingIO(_ request: HTTPRequest, timeout: Duration?) async throws
    -> HTTPResponse
  {
    do {
      return try await self.http.send(Self.prepare(request), timeout: timeout)
    } catch let error as RequestError {
      throw error
    } catch let error as CancellationError {
      throw error
    } catch {
      throw RequestError.io(error)
    }
  }

  /// Adds the query parameters common to every BigQuery API request.
  static func prepare(_ request: HTTPRequest) -> HTTPRequest {
    guard case .path = request.target, !request.query.contains(where: { $0.name == "prettyPrint" })
    else {
      return request
    }
    var request = request
    request.query.append(URLQueryItem(name: "prettyPrint", value: "false"))
    return request
  }

  /// Decodes a ProtoJSON response body. An empty body decodes as `{}`.
  static func decode<R: Decodable>(_ body: Data) throws -> R {
    do {
      return try _ProtoJSONDecoder().decode(R.self, from: body.isEmpty ? Data("{}".utf8) : body)
    } catch {
      throw RequestError.malformedResponse("cannot decode \(R.self): \(error)")
    }
  }

  /// Maps the error that ended a retry loop to the error reported to callers.
  static func map(_ error: RequestError) -> any Error {
    switch error {
    case .http(let details):
      return BigQueryError(httpStatusCode: details.statusCode, payload: details.payload)
    case .exhausted(.elapsedTime(_, .some(.http(let details)))):
      return BigQueryError(httpStatusCode: details.statusCode, payload: details.payload)
    default:
      return error
    }
  }
}

extension BigQueryError {
  /// `true` for a service error with HTTP status 404.
  var isHTTPNotFound: Bool { self.kind == .service && self.httpStatusCode == 404 }
}

extension RequestError {
  /// A retryable HTTP 429 error for a 2xx job or query response that reports a job-level rate
  /// limit (`rateLimitExceeded` or `jobRateLimitExceeded`).
  ///
  /// The retry policy classifies it like a real 429, and if the loop gives up it surfaces as a
  /// ``BigQueryError`` with the original error details.
  static func jobRateLimited(_ errors: [GoogleCloudBigQueryV2.ErrorProto]) -> RequestError {
    let body = ErrorBody(
      error: ErrorBody.Status(
        code: 429,
        message: errors.first?.message.nonEmpty ?? "job rate limit exceeded",
        status: "RESOURCE_EXHAUSTED",
        errors: errors.map {
          ErrorBody.Item(
            reason: $0.reason.nonEmpty, location: $0.location.nonEmpty,
            message: $0.message.nonEmpty, debugInfo: $0.debugInfo.nonEmpty)
        }))
    let payload = (try? JSONEncoder().encode(body)) ?? Data()
    return .http(HTTPDetails(statusCode: 429, payload: payload))
  }
}
