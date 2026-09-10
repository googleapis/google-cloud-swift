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
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct StorageClientTests {
  @Test func initializationWithOptions() throws {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = "https://override.googleapis.com"
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options)
    #expect(client.options.client.endpoint == "https://override.googleapis.com")
  }

  static func assertSendable<T: Sendable>(_ type: T.Type) {}

  @Test func clientIsSendable() {
    Self.assertSendable(StorageClient.self)
  }

  @Test(arguments: [
    ("https://private.googleapis.com", "storage.googleapis.com"),
    ("https://my-psc.p.googleapis.com", "storage.googleapis.com"),
    ("https://restricted.googleapis.com", "storage.googleapis.com"),
    ("https://storage.us-central1.rep.googleapis.com", "storage.us-central1.rep.googleapis.com"),
    ("https://us-central1-storage.googleapis.com", "us-central1-storage.googleapis.com"),
    ("https://storage.googleapis.com", "storage.googleapis.com"),
  ]) func hostHeaderWithEndpoint(endpoint: String, expectedHost: String) async throws {
    let registry = MockRegistry.create()
    let requestUrl = "\(endpoint)/storage/v1/b/test-bucket/o/test-obj?alt=media"
    registry.register(
      response: .success(statusCode: 200, data: Data("data".utf8)),
      for: requestUrl
    )

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry)
    let task = client.readObject(from: "test-bucket", object: "test-obj")
    _ = try await task.metadata

    let request = registry.lastRequest(for: requestUrl)
    #expect(request?.value(forHTTPHeaderField: "Host") == expectedHost)
  }

  @Test func hostHeaderWithUniverseDomain() async throws {
    let registry = MockRegistry.create()
    let requestUrl =
      "https://storage.my-universe.com/storage/v1/b/test-bucket/o/test-obj?alt=media"
    registry.register(
      response: .success(statusCode: 200, data: Data("data".utf8)),
      for: requestUrl
    )

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = "https://storage.my-universe.com"
        $0.universeDomain = "my-universe.com"
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry)
    let task = client.readObject(from: "test-bucket", object: "test-obj")
    _ = try await task.metadata

    let request = registry.lastRequest(for: requestUrl)
    #expect(request?.value(forHTTPHeaderField: "Host") == "storage.my-universe.com")
  }

  @Test func uploadHostHeaderWithOddEndpoint() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-obj"
    let endpoint = "https://private.googleapis.com"
    let uploadUrl =
      "\(endpoint)/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)"

    registry.register(
      response: .success(
        statusCode: 200, data: Data("{\"name\":\"\(objectName)\"}".utf8),
        headers: ["Content-Type": "application/json"]),
      for: uploadUrl
    )

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry)
    let data = Data("hello world".utf8)
    _ = try await client.upload(data, to: bucket, as: objectName)

    let request = registry.lastRequest(for: uploadUrl)
    #expect(request?.value(forHTTPHeaderField: "Host") == "storage.googleapis.com")
  }
}
