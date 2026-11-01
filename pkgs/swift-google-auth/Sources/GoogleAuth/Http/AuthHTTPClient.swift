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
import AsyncHTTPClient
import NIOFoundationCompat
import struct Logging.Logger
import struct NIOCore.ByteBuffer
import struct NIOCore.ByteBufferAllocator
import NIOHTTP1

/// Internal protocol abstracting an HTTP client to support testing and mocking.
protocol HTTPClientProtocol: Sendable {
  /// Executes an HTTP request with a specified timeout and logger.
  ///
  /// - Parameters:
  ///   - request: The HTTP request to dispatch.
  ///   - timeout: Execution timeout duration.
  ///   - logger: Optional logger for diagnostic messages.
  /// - Returns: The HTTP response.
  @concurrent
  func execute(
    request: HTTPClientRequest,
    timeout: Duration,
    logger: Logger?
  ) async throws -> HTTPClientResponse
}

/// Automatically calls `shutdown()` on `AsyncHTTPClient.HTTPClient` during deinitialization.
///
/// `HTTPClient` requires an asynchronous call to `shutdown()` to release NIO event loops and
/// connection pools without leaking system resources. This wrapper ensures proper shutdown
/// via a background task when the holder is deinited.
///
/// SAFETY: calling `shutdown()` requires all requests to be finished. In the AuthHTTPClient struct
/// each HTTP request is executed within a function, therefore the object is live while the HTTP
/// request is in progress. By the time deinit starts, all starting a call requires having a
/// reference to the object, so shutdown
final class HTTPClientHolder: HTTPClientProtocol {
  let inner = HTTPClient(
    configuration: .init(
      timeout: .init(connect: .seconds(10), read: .seconds(30))
    )
  )
  deinit {
    // Use a background task to shutdown the inner client. In most cases, the application will
    // continue running and the HTTPClient is shutdown "eventually". Except for (maybe) some false
    // positives in leak detectors, there is no harm if the application terminates before this gets
    // to run.
    let copy = inner
    Task {
      // Note how we make a copy of `inner` to avoid capturing `self`.
      do {
        try await copy.shutdown()
      } catch {
        // Ignore any exceptions. If `shutdown()` failed there is nothing the application can do.
      }
    }
  }

  @concurrent
  func execute(
    request: HTTPClientRequest,
    timeout: Duration,
    logger: Logger?
  ) async throws -> HTTPClientResponse {
    try await self.inner.execute(request, timeout: .init(timeout), logger: logger)
  }
}

/// A lightweight, portable, and secure HTTP request client dedicated to authentication requests.
///
/// Used internally across authentication providers to communicate with:
/// - Google Cloud OAuth 2.0 token endpoints (`https://oauth2.googleapis.com/token`)
/// - Google Cloud Security Token Service (`https://sts.googleapis.com/v1/token`)
/// - Google Compute Engine Metadata Service (`http://metadata.google.internal`)
///
/// Enforces a maximum response size limit to guard against memory exhaustion and provides
/// standardized error handling and snake_case JSON decoding.
struct AuthHTTPClient: Sendable {
  /// Maximum permitted HTTP response body size in bytes (1 MB) to guard against memory exhaustion.
  static let maxResponseSize: Int = 1024 * 1024

  /// Default per-request HTTP execution timeout when no explicit override is supplied.
  static let defaultTimeout: Duration = .seconds(30)

  /// The underlying HTTP execution engine conforming to `HTTPClientProtocol`.
  let inner: any HTTPClientProtocol

  /// Initializes the client with the default asynchronous HTTP client configuration.
  init() {
    self.inner = HTTPClientHolder()
  }

  /// Initializes the client with a custom or mock `HTTPClientProtocol` implementation.
  ///
  /// - Parameter mock: The mock client implementation to use.
  init<T: HTTPClientProtocol>(mock: T) {
    self.inner = mock
  }

  /// Asynchronously dispatches a GET request and decodes the generic JSON response.
  ///
  /// - Parameters:
  ///   - url: The target URL of the request.
  ///   - headers: HTTP request headers.
  ///   - timeout: Optional execution timeout override (defaults to `defaultTimeout`).
  /// - Returns: The parsed JSON response structure.
  @concurrent
  func get<T: Decodable>(
    url: URL,
    headers: [String: String] = [:],
    timeout: Duration? = nil
  ) async throws -> T {
    return try await self.mapError {
      var request = HTTPClientRequest(url: url.absoluteString)
      request.method = .GET
      request.headers = .init(headers.map { ($0.key, $0.value) })
      let buffer = try await self.executeAndCollectBody(request, timeout: timeout)

      do {
        return try self.makeDecoder().decode(T.self, from: Data(buffer: buffer))
      } catch {
        throw AuthHTTPError.decodingError(error: error)
      }
    }
  }

  /// Asynchronously dispatches a GET request and returns the raw response body as a plain-text string.
  ///
  /// Used for endpoints that return plain-text payloads rather than JSON, such as the Compute Engine
  /// Metadata Server token and identity endpoints.
  ///
  /// - Parameters:
  ///   - url: The target URL of the request.
  ///   - headers: Optional HTTP request headers.
  ///   - timeout: Optional execution timeout override (defaults to `defaultTimeout`).
  /// - Returns: The plain-text UTF-8 string returned by the server.
  /// - Throws: `AuthHTTPError.unsuccessfulResponse` on non-2xx status, or `AuthHTTPError.decodingError` if invalid UTF-8.
  @concurrent
  func getString(
    url: URL,
    headers: [String: String] = [:],
    timeout: Duration? = nil
  ) async throws -> String {
    return try await self.mapError {
      var request = HTTPClientRequest(url: url.absoluteString)
      request.method = .GET
      request.headers = .init(headers.map { ($0.key, $0.value) })
      var buffer = try await self.executeAndCollectBody(request, timeout: timeout)

      do {
        guard let plainText = try buffer.readUTF8ValidatedString(length: buffer.readableBytes)
        else {
          throw AuthHTTPError.decodingError(error: AuthHTTPError.invalidUTF8Response)
        }
        return plainText
      } catch {
        throw AuthHTTPError.decodingError(error: error)
      }
    }
  }

  /// Asynchronously dispatches a POST request sending an encodable JSON body and decodes the JSON response.
  ///
  /// Encodable bodies are automatically converted using snake_case key encoding, and responses are
  /// decoded using snake_case key decoding.
  ///
  /// - Parameters:
  ///   - url: The target URL of the request.
  ///   - body: The encodable JSON body structure.
  ///   - headers: Optional HTTP request headers.
  ///   - timeout: Optional execution timeout override (defaults to `defaultTimeout`).
  /// - Returns: The parsed JSON response structure.
  /// - Throws: `AuthHTTPError.unsuccessfulResponse` on non-2xx status, or `AuthHTTPError.decodingError` on parse failure.
  @concurrent
  func post<Body: Encodable, Response: Decodable>(
    url: URL,
    body: Body,
    headers: [String: String] = [:],
    timeout: Duration? = nil
  ) async throws -> Response {
    return try await self.mapError {
      var request = HTTPClientRequest(url: url.absoluteString)
      request.method = .POST
      request.headers = .init(headers.map { ($0.key, $0.value) })
      request.headers.add(name: "Content-Type", value: "application/json")
      let encoder = self.makeEncoder()
      let buffer = try encoder.encodeAsByteBuffer(body, allocator: ByteBufferAllocator())
      request.body = .bytes(buffer)

      let recvBuffer = try await self.executeAndCollectBody(request, timeout: timeout)

      do {
        return try self.makeDecoder().decode(Response.self, from: recvBuffer)
      } catch {
        throw AuthHTTPError.decodingError(error: error)
      }
    }
  }

  /// Asynchronously dispatches a POST request sending raw byte data and decodes the JSON response.
  ///
  /// Typically used when posting `application/x-www-form-urlencoded` payloads during STS token exchange.
  ///
  /// - Parameters:
  ///   - url: The target URL of the request.
  ///   - bodyData: The raw data to send as the HTTP body.
  ///   - contentType: The `Content-Type` header value (e.g. `application/x-www-form-urlencoded`).
  ///   - headers: Optional HTTP request headers.
  ///   - timeout: Optional execution timeout override (defaults to `defaultTimeout`).
  /// - Returns: The parsed JSON response structure.
  /// - Throws: `AuthHTTPError.unsuccessfulResponse` on non-2xx status, or `AuthHTTPError.decodingError` on parse failure.
  @concurrent
  func postData<Response: Decodable>(
    url: URL,
    bodyData: Data,
    contentType: String,
    headers: [String: String] = [:],
    timeout: Duration? = nil
  ) async throws -> Response {
    return try await self.mapError {
      var request = HTTPClientRequest(url: url.absoluteString)
      request.method = .POST
      request.headers = .init(headers.map { ($0.key, $0.value) })
      request.headers.add(name: "Content-Type", value: contentType)
      request.body = .bytes(bodyData)

      let buffer = try await self.executeAndCollectBody(request, timeout: timeout)

      do {
        return try self.makeDecoder().decode(Response.self, from: Data(buffer: buffer))
      } catch {
        throw AuthHTTPError.decodingError(error: error)
      }
    }
  }

  /// Centralizes error mapping logic to wrap any transport or unknown failures in AuthHTTPError.
  private func mapError<T>(
    _ operation: () async throws -> T
  ) async throws -> T {
    do {
      return try await operation()
    } catch let error as AuthHTTPError {
      throw error
    } catch let error as CancellationError {
      throw error
    } catch  where Task.isCancelled {
      throw CancellationError()
    } catch let error as URLError {
      throw AuthHTTPError.transportError(error)
    } catch {
      throw AuthHTTPError.unknown(error)
    }
  }

  /// Executes `request` and collects the validated response body within a single overall deadline.
  @concurrent
  private func executeAndCollectBody(
    _ request: HTTPClientRequest,
    timeout: Duration? = nil
  ) async throws -> ByteBuffer {
    let effectiveTimeout = timeout ?? Self.defaultTimeout
    let deadline = ContinuousClock.now.advanced(by: effectiveTimeout)
    let response = try await self.performRequest(request, timeout: effectiveTimeout)
    return try await self.collectBody(response, deadline: deadline)
  }

  @concurrent
  private func performRequest(
    _ request: HTTPClientRequest,
    timeout: Duration
  ) async throws -> HTTPClientResponse {
    return try await inner.execute(request: request, timeout: timeout, logger: nil)
  }

  /// Collects `response.body` up to `Self.maxResponseSize` within the remaining `deadline`.
  ///
  /// `AsyncHTTPClient`'s per-request `timeout` only bounds arrival of the HTTP response head, so
  /// racing body collection against `ContinuousClock` ensures a stalled response stream cannot
  /// exceed the overall request timeout.
  @concurrent
  private func collectBodyBytes(
    _ response: HTTPClientResponse,
    deadline: ContinuousClock.Instant
  ) async throws -> ByteBuffer {
    try Task.checkCancellation()
    return try await withThrowingTaskGroup(of: ByteBuffer.self) { group in
      group.addTask {
        let buffer = try await response.body.collect(upTo: Self.maxResponseSize)
        try Task.checkCancellation()
        return buffer
      }
      group.addTask {
        try await ContinuousClock().sleep(until: deadline)
        try Task.checkCancellation()
        throw URLError(.timedOut)
      }

      guard let buffer = try await group.next() else {
        throw CancellationError()
      }
      group.cancelAll()
      try Task.checkCancellation()
      return buffer
    }
  }

  private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }

  private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }

  /// Validates that the HTTP status code is in the 200–299 range and collects the response body.
  ///
  /// For 2xx responses, collects `response.body` up to `Self.maxResponseSize` without copying into
  /// `Data`. For non-2xx responses, attempts to collect `response.body` on a best-effort basis so
  /// structured error payloads are preserved on `AuthHTTPError.unsuccessfulResponse` and small
  /// error bodies are drained for connection reuse; if collecting the error body fails or exceeds
  /// `deadline` (for example, `NIOTooManyBytesError` on an oversized error page, a mid-stream read
  /// error, or a stalled error stream), `AuthHTTPError.unsuccessfulResponse` is still thrown with
  /// empty `Data` so the HTTP status code and retryability classification are preserved.
  /// `CancellationError` is rethrown directly, and any error thrown after task cancellation is
  /// propagated as `CancellationError` without wrapping.
  ///
  /// Only response metadata (`version`, `status`, `headers`) is retained on the thrown error so
  /// `response.body` (and any underlying `AsyncHTTPClient` stream/transaction or request history)
  /// is released immediately upon unwinding.
  private func collectBody(
    _ response: HTTPClientResponse,
    deadline: ContinuousClock.Instant
  ) async throws -> ByteBuffer {
    guard (200...299).contains(response.status.code) else {
      let data: Data
      do {
        let buffer = try await self.collectBodyBytes(response, deadline: deadline)
        data = Data(buffer: buffer)
      } catch let error as CancellationError {
        throw error
      } catch  where Task.isCancelled {
        throw CancellationError()
      } catch {
        data = Data()
      }
      let metadataResponse = HTTPClientResponse(
        version: response.version,
        status: response.status,
        headers: response.headers
      )
      throw AuthHTTPError.unsuccessfulResponse(response: metadataResponse, data: data)
    }
    return try await self.collectBodyBytes(response, deadline: deadline)
  }
}
