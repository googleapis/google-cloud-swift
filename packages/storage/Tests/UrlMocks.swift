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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
@testable import GoogleCloudStorage

import Testing

/// Defines what a mock response should return
public enum MockResponse: Sendable {
  case success(statusCode: Int, data: Data, headers: [String: String]?)
  case failure(Error)
}

/// Mock UploadSource that can throw errors
public struct MockUploadSource: SeekableUploadSource {
  public var data: Data
  public var totalSize: Int64?
  public var readError: Error?
  public var seekError: Error?
  private var offset: Int64 = 0

  public init(data: Data, totalSize: Int64? = nil, readError: Error? = nil, seekError: Error? = nil)
  {
    self.data = data
    self.totalSize = totalSize ?? Int64(data.count)
    self.readError = readError
    self.seekError = seekError
  }

  public mutating func read(maxBytes: Int) async throws -> Data? {
    if let error = readError {
      throw error
    }
    guard offset < data.count else { return nil }
    let end = min(offset + Int64(maxBytes), Int64(data.count))
    let chunk = data.subdata(in: Int(offset)..<Int(end))
    offset = end
    return chunk
  }

  public mutating func seek(to offset: Int64) async throws {
    if let error = seekError {
      throw error
    }
    guard offset >= 0 && offset <= data.count else {
      throw UploadError.internalError("Invalid seek offset: \(offset)")
    }
    self.offset = offset
  }
}

public func makeObjectJSON(
  name: String = "test-object", bucket: String = "test-bucket", size: Int = 10 * 1024 * 1024
) -> Data {
  let json = """
    {
      "name": "\(name)",
      "bucket": "\(bucket)",
      "generation": "1",
      "metageneration": "1",
      "size": "\(size)",
      "contentType": "application/octet-stream",
      "storageClass": "STANDARD"
    }
    """
  return Data(json.utf8)
}

/// Helper to assert that an async action throws an error of type `E` and returns the caught error.
@discardableResult
public func expectError<E: Error>(
  _ errorType: E.Type = E.self,
  performing action: () async throws -> Any?
) async -> E? {
  do {
    _ = try await action()
    Issue.record("Expected error of type \(E.self) to be thrown")
    return nil
  } catch let error as E {
    return error
  } catch {
    Issue.record("Expected error of type \(E.self), but got \(error)")
    return nil
  }
}

/// Helper to assert that an async action throws an `UploadError` and returns the caught error.
@discardableResult
public func expectUploadError(
  performing action: () async throws -> Any?
) async -> UploadError? {
  await expectError(UploadError.self, performing: action)
}

/// A thread-safe registry to store mocks for a specific test run
public final class MockRegistry: @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var registries: [String: MockRegistry] = [:]

  public static func create() -> MockRegistry {
    let id = "test-" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let registry = MockRegistry(id: id)
    lock.withLock {
      registries[id] = registry
    }
    return registry
  }

  internal static func registry(for id: String) -> MockRegistry? {
    lock.withLock {
      registries[id]
    }
  }

  public let id: String
  private var mocks: [URL: [MockResponse]] = [:]
  private let queue = DispatchQueue(label: "com.mockregistry.queue", attributes: .concurrent)

  private init(id: String) {
    self.id = id
  }

  public var endpoint: String {
    return "http://\(id)"
  }

  public func url(_ path: String) -> URL {
    let p = path.hasPrefix("/") ? path : "/\(path)"
    return URL(string: "\(endpoint)\(p)")!
  }

  public func register(response: MockResponse, for url: URL) {
    queue.async(flags: .barrier) {
      self.mocks[url, default: []].append(response)
    }
  }

  internal func response(for url: URL) -> MockResponse? {
    var response: MockResponse?
    queue.sync(flags: .barrier) {
      if var responses = self.mocks[url], !responses.isEmpty {
        response = responses.removeFirst()
        self.mocks[url] = responses
      }
    }
    return response
  }
}

public final class MockURLProtocol: URLProtocol {
  public override class func canInit(with request: URLRequest) -> Bool {
    return true
  }

  public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  public override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    guard let host = url.host,
      let registry = MockRegistry.registry(for: host),
      let mock = registry.response(for: url)
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
      return
    }

    switch mock {
    case .success(let statusCode, let data, let headers):
      if let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: headers
      ) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
      }
      client?.urlProtocolDidFinishLoading(self)

    case .failure(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  public override func stopLoading() {
    // No-op
  }
}
