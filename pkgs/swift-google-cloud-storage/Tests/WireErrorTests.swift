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

@Suite struct StorageClientWireErrorTests {
  // The actual JSON error format returned on the wire by Google Cloud Storage.
  // Note that `error.code` is an HTTP status code (404), and `error.status` is omitted.
  private static let rawWireErrorJson = """
    {
      "error": {
        "code": 404,
        "message": "The specified bucket does not exist.",
        "errors": [
          {
            "message": "The specified bucket does not exist.",
            "domain": "global",
            "reason": "notFound"
          }
        ]
      }
    }
    """

  private func makeClient(registry: MockRegistry) throws -> StorageClient {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    return try StorageClient(options, mock: registry)
  }

  /// Tests that a simple upload to a non-existent bucket fails with a `.notFound` ServiceError.
  @Test func simpleUploadWithWireErrorReturnsNotFound() async throws {
    let registry = MockRegistry.create()
    let bucket = "non-existent-bucket"
    let objectName = "test-object"
    let uploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")
    registry.register(
      response: .success(
        statusCode: 404,
        data: Data(Self.rawWireErrorJson.utf8),
        headers: ["content-type": "application/json; charset=UTF-8"]
      ),
      for: uploadUrl
    )

    let client = try makeClient(registry: registry)
    let data = Data("Hello World".utf8)
    do {
      _ = try await client.upload(data, to: bucket, as: objectName)
      Issue.record("Expected upload to fail, but it succeeded")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == .notFound)
      #expect(serviceError.message == "The specified bucket does not exist.")
    } catch {
      Issue.record("Expected RequestError.service, but got \(error)")
    }
  }

  /// Tests that initiating a resumable upload to a non-existent bucket fails with a `.notFound` ServiceError.
  @Test func resumableUploadWithWireErrorReturnsNotFound() async throws {
    let registry = MockRegistry.create()
    let bucket = "non-existent-bucket"
    let objectName = "test-object"
    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    registry.register(
      response: .success(
        statusCode: 404,
        data: Data(Self.rawWireErrorJson.utf8),
        headers: ["content-type": "application/json; charset=UTF-8"]
      ),
      for: startUrl
    )

    let client = try makeClient(registry: registry)
    // 16MB payload triggers resumable upload path (> 8MB default threshold)
    let data = Data(repeating: 0x42, count: 16 * 1024 * 1024)
    do {
      _ = try await client.upload(data, to: bucket, as: objectName)
      Issue.record("Expected resumable upload to fail, but it succeeded")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == .notFound)
      #expect(serviceError.message == "The specified bucket does not exist.")
    } catch {
      Issue.record("Expected RequestError.service, but got \(error)")
    }
  }

  /// Tests that downloading a non-existent object fails with HTTP 404.
  @Test func downloadWithWireErrorReturnsNotFound() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "nonexistent.txt"
    let downloadUrl = registry.url(
      "/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 404,
        data: Data(Self.rawWireErrorJson.utf8),
        headers: ["content-type": "application/json; charset=UTF-8"]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    do {
      _ = try await client.readObject(from: bucket, object: objectName).metadata
      Issue.record("Expected download to fail, but it succeeded")
    } catch DownloadError.unexpectedServerResponse(let statusCode, let message) {
      #expect(statusCode == 404)
      #expect(message == "The specified bucket does not exist.")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == .notFound)
    } catch {
      Issue.record("Expected 404 not found error, but got \(error)")
    }
  }
}
