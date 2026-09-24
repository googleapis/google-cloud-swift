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
import GoogleAuth
import GoogleGax
@testable import GoogleCloudStorage
import Testing

@Suite struct StorageControlClientTests {
  @Test func defaultInitialization() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
    }
    let client = try StorageControlClient(options)
    #expect(
      client.pollingErrorPolicy
        is GoogleGax.LimitedElapsedTime<GoogleGax.BasePollingErrorPolicy>)
    #expect(client.pollingBackoffPolicy is GoogleGax.ExponentialBackoff)
  }

  @Test func customPollingPolicies() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let customErrorPolicy = GoogleGax.BasePollingErrorPolicy.unbounded().withTimeLimit(
      .seconds(120))
    let customBackoffPolicy = GoogleGax.ExponentialBackoff()
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.pollingErrorPolicy = customErrorPolicy
      $0.pollingBackoffPolicy = customBackoffPolicy
    }
    let client = try StorageControlClient(options)
    #expect(
      client.pollingErrorPolicy
        is GoogleGax.LimitedElapsedTime<GoogleGax.BasePollingErrorPolicy>)
    #expect(client.pollingBackoffPolicy is GoogleGax.ExponentialBackoff)
  }

  static func assertSendable<T: Sendable>(_ type: T.Type) {}

  @Test func clientIsSendable() {
    Self.assertSendable(StorageControlClient.self)
  }

  @Test func initializationWithCustomEndpoints() throws {
    let credentials = try Credentials(configuration: .anonymous)

    // With explicit https endpoint
    let secureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://custom.endpoint.com:443"
    }
    let _ = try StorageControlClient(secureOptions)

    // With explicit http endpoint (local emulator)
    let insecureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "http://127.0.0.1:8080"
    }
    let _ = try StorageControlClient(insecureOptions)

    // Without scheme
    let bareOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "custom.endpoint.com:443"
    }
    let _ = try StorageControlClient(bareOptions)

    // With universe domain
    let universeOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.universeDomain = "my-universe.com"
    }
    let _ = try StorageControlClient(universeOptions)

    // With VPC-SC odd endpoint
    let oddEndpointOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://private.googleapis.com"
    }
    let _ = try StorageControlClient(oddEndpointOptions)
  }

  @Test(arguments: [
    "",
    "http:///",
    "https:///",
  ]) func badEndpoint(input: String) throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = input
    }
    #expect(throws: ClientError.self) {
      _ = try StorageControlClient(options)
    }
  }

  @Test func defaultInitializationUsesStorageBaseRetryPolicy() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
    }
    #expect(options.retryPolicy == nil)
    _ = try StorageControlClient(options)
  }

  @Test func initializationPreservesExplicitRetryPolicy() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let explicitPolicy = NeverRetry()
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.retryPolicy = explicitPolicy
    }
    #expect(options.retryPolicy != nil)
    _ = try StorageControlClient(options)
  }

  @Test func protocolIsSendable() {
    Self.assertSendable((any StorageControlProtocol).self)
  }

  final class MockStorageControl: StorageControlProtocol, @unchecked Sendable {
    var listBucketsHandler:
      ((ListBucketsRequest, GoogleGax.RequestOptions) async throws -> ListBucketsResponse)?
    var renameFolderHandler:
      (
        (RenameFolderRequest, GoogleGax.RequestOptions) async throws -> any GoogleGax
          .PollableOperation<Folder>
      )?

    func listBuckets(
      request: ListBucketsRequest, options: GoogleGax.RequestOptions
    ) async throws -> ListBucketsResponse {
      if let handler = listBucketsHandler {
        return try await handler(request, options)
      }
      throw GoogleGax.RequestError.unimplemented
    }

    func renameFolderPollingUntilDone(
      request: RenameFolderRequest, options: GoogleGax.RequestOptions
    ) async throws -> any GoogleGax.PollableOperation<Folder> {
      if let handler = renameFolderHandler {
        return try await handler(request, options)
      }
      throw GoogleGax.RequestError.unimplemented
    }
  }

  @Test func mockPaginationDelegation() async throws {
    let mock = MockStorageControl()
    mock.listBucketsHandler = { req, opts in
      var response = ListBucketsResponse()
      if req.pageToken.isEmpty {
        var b = Bucket()
        b.name = "bucket-1"
        response.buckets = [b]
        response.nextPageToken = "token-page-2"
      } else if req.pageToken == "token-page-2" {
        var b = Bucket()
        b.name = "bucket-2"
        response.buckets = [b]
        response.nextPageToken = ""
      }
      return response
    }

    let client: any StorageControlProtocol = mock
    let sequence = client.listBucketsByItems(request: .init())
    var names: [String] = []
    for try await bucket in sequence {
      names.append(bucket.name)
    }
    #expect(names == ["bucket-1", "bucket-2"])
  }

  @Test func mockConvenienceOverloadDelegation() async throws {
    let mock = MockStorageControl()
    mock.listBucketsHandler = { req, opts in
      #expect(req.parent == "projects/test-project")
      var response = ListBucketsResponse()
      var b = Bucket()
      b.name = "bucket-1"
      response.buckets = [b]
      return response
    }

    let client: any StorageControlProtocol = mock
    let response = try await client.listBuckets(
      request: .init().with { $0.parent = "projects/test-project" })
    #expect(response.buckets.count == 1)
  }

  @MainActor
  struct BucketListModel {
    let client: any StorageControlProtocol

    func streamBucketNamesInBackground() -> Task<[String], Swift.Error> {
      // Construct the paginated sequence on @MainActor and stream it inside a detached task.
      let buckets = client.listBucketsByItems(
        request: .init().with { $0.parent = "projects/test-project" })
      return Task.detached {
        var names: [String] = []
        for try await bucket in buckets {
          names.append(bucket.name)
        }
        return names
      }
    }
  }

  @Test func mockPaginationStreamedInDetachedTaskFromMainActor() async throws {
    let mock = MockStorageControl()
    mock.listBucketsHandler = { req, _ in
      var response = ListBucketsResponse()
      if req.pageToken.isEmpty {
        var b = Bucket()
        b.name = "bucket-1"
        response.buckets = [b]
        response.nextPageToken = "token-page-2"
      } else if req.pageToken == "token-page-2" {
        var b = Bucket()
        b.name = "bucket-2"
        response.buckets = [b]
        response.nextPageToken = ""
      }
      return response
    }

    let model = BucketListModel(client: mock)
    let task = await model.streamBucketNamesInBackground()
    let names = try await task.value
    #expect(names == ["bucket-1", "bucket-2"])
  }

  struct MockPollableOperation<ResponseType>: PollableOperation {
    let result: Result<ResponseType, any Error>
    func wait() async throws -> ResponseType {
      try result.get()
    }
  }

  @Test func mockLROConvenienceOverloadDelegation() async throws {
    let mock = MockStorageControl()
    mock.renameFolderHandler = { req, opts in
      #expect(req.name == "projects/_/buckets/b/folders/f1")
      let folder = Folder().with { $0.name = "projects/_/buckets/b/folders/f2" }
      return MockPollableOperation(result: .success(folder))
    }

    let client: any StorageControlProtocol = mock
    let op = try await client.renameFolderPollingUntilDone(
      request: .init().with { $0.name = "projects/_/buckets/b/folders/f1" })
    let folder = try await op.wait()
    #expect(folder.name == "projects/_/buckets/b/folders/f2")
  }
}
