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
import struct NIOCore.TimeAmount
import struct NIOCore.ByteBufferAllocator

protocol HTTPClientProtocol: Sendable {
  func execute(
    request: HTTPClientRequest,
    timeout: Duration,
    logger: Logger?
  ) async throws -> HTTPClientResponse
}

/// Automatically call shutdown() on a HTTPClient.
///
/// HTTPClient requires an (asynchronous) call to `shutdown()` or it leaks resources.
/// This class automates the call.
///
/// SAFETY: calling `shutdown()` requires all requests to be finished. In the AuthHTTPClient struct
/// each HTTP request is executed within a function, therefore the object is live while the HTTP
/// request is in progress. By the time deinit starts, all starting a call requires having a
/// reference to the object, so shutdown
final class HTTPClientHolder: HTTPClientProtocol {
  let inner = HTTPClient()
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

  func execute(
    request: HTTPClientRequest,
    timeout: Duration,
    logger: Logger?
  ) async throws -> HTTPClientResponse {
    try await self.inner.execute(request, timeout: .init(timeout), logger: logger)
  }
}

/// A lightweight, portable, and secure HTTP request client dedicated to authentication requests.
struct AuthHTTPClient: Sendable {
  static let maxResponseSize: Int = 1024 * 1024

  let inner: any HTTPClientProtocol

  /// Initializes the client with the default configuration.
  public init() {
    self.inner = HTTPClientHolder()
  }

  init<T: HTTPClientProtocol>(mock: T) {
    self.inner = mock
  }

  /// Asynchronously dispatches a GET request and decodes the generic JSON response.
  ///
  /// - Parameters:
  ///   - url: The target URL of the request.
  ///   - headers: HTTP request headers.
  /// - Returns: The parsed JSON response structure.
  func get<T: Decodable>(
    url: URL,
    headers: [String: String] = [:]
  ) async throws -> T {
    return try await self.mapError {
      var request = HTTPClientRequest(url: url.absoluteString)
      request.method = .GET
      request.headers = .init(headers.map { ($0.key, $0.value) })
      let response = try await self.performRequest(request)
      let buffer = try await response.body.collect(upTo: Self.maxResponseSize)
      try self.ensureSuccess(response)

      do {
        return try self.makeDecoder().decode(T.self, from: Data(buffer: buffer))
      } catch let error as DecodingError {
        throw AuthHTTPError.decodingError(error: error)
      }
    }
  }

  /// Asynchronously dispatches a GET request and returns the raw response body as a plain-text string.
  /// Statically required to support local GCE Metadata Server OIDC token and email fetches.
  func getString(
    url: URL,
    headers: [String: String] = [:]
  ) async throws -> String {
    return try await self.mapError {
      var request = HTTPClientRequest(url: url.absoluteString)
      request.method = .GET
      request.headers = .init(headers.map { ($0.key, $0.value) })
      let response = try await self.performRequest(request)
      try self.ensureSuccess(response)
      var buffer = try await response.body.collect(upTo: Self.maxResponseSize)

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

  /// Asynchronously dispatches a POST request sending generic JSON body and decodes the JSON response.
  ///
  /// - Parameters:
  ///   - url: The target URL of the request.
  ///   - body: The encodable JSON body structure.
  ///   - headers: HTTP request headers.
  /// - Returns: The parsed JSON response structure.
  func post<Body: Encodable, Response: Decodable>(
    url: URL,
    body: Body,
    headers: [String: String] = [:]
  ) async throws -> Response {
    return try await self.mapError {
      var request = HTTPClientRequest(url: url.absoluteString)
      request.method = .POST
      request.headers = .init(headers.map { ($0.key, $0.value) })
      request.headers.add(name: "Content-Type", value: "application/json")
      let encoder = JSONEncoder()
      let buffer = try encoder.encodeAsByteBuffer(body, allocator: ByteBufferAllocator())
      request.body = .bytes(buffer)

      let response = try await self.performRequest(request)
      try self.ensureSuccess(response)
      let recvBuffer = try await response.body.collect(upTo: Self.maxResponseSize)

      do {
        return try self.makeDecoder().decode(Response.self, from: recvBuffer)
      } catch let error as DecodingError {
        throw AuthHTTPError.decodingError(error: error)
      }
    }
  }

  /// Asynchronously dispatches a POST request sending raw data and decodes the JSON response.
  ///
  /// - Parameters:
  ///   - url: The target URL of the request.
  ///   - bodyData: The raw data to send as the HTTP body.
  ///   - contentType: The Content-Type header value.
  ///   - headers: HTTP request headers.
  /// - Returns: The parsed JSON response structure.
  func postData<Response: Decodable>(
    url: URL,
    bodyData: Data,
    contentType: String,
    headers: [String: String] = [:]
  ) async throws -> Response {
    return try await self.mapError {
      var request = HTTPClientRequest(url: url.absoluteString)
      request.method = .POST
      request.headers = .init(headers.map { ($0.key, $0.value) })
      request.headers.add(name: "Content-Type", value: contentType)
      request.body = .bytes(bodyData)

      let response = try await self.performRequest(request)
      try self.ensureSuccess(response)
      let buffer = try await response.body.collect(upTo: Self.maxResponseSize)

      do {
        return try self.makeDecoder().decode(Response.self, from: Data(buffer: buffer))
      } catch let error as DecodingError {
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
    } catch let error as URLError {
      throw AuthHTTPError.transportError(error)
    } catch {
      throw AuthHTTPError.unknown(error)
    }
  }

  private func performRequest(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
    return try await inner.execute(request: request, timeout: .seconds(30), logger: nil)
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

  private func ensureSuccess(_ response: HTTPClientResponse) throws {
    let statusCode = response.status.code
    guard (200...299).contains(statusCode) else {
      throw AuthHTTPError.unsuccessfulResponse(response: response)
    }
  }
}
