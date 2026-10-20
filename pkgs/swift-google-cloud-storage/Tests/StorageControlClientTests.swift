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
import Synchronization
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

  @Test func mockPaginationDelegation() async throws {
    let mock = MockStorageControl(listBuckets: [
      { req, _ in
        #expect(req.pageToken.isEmpty)
        var response = ListBucketsResponse()
        var b = Bucket()
        b.name = "bucket-1"
        response.buckets = [b]
        response.nextPageToken = "token-page-2"
        return response
      },
      { req, _ in
        #expect(req.pageToken == "token-page-2")
        var response = ListBucketsResponse()
        var b = Bucket()
        b.name = "bucket-2"
        response.buckets = [b]
        response.nextPageToken = ""
        return response
      },
    ])

    let client: any StorageControlProtocol = mock
    let sequence = client.listBucketsByItems(request: .init())
    var names: [String] = []
    for try await bucket in sequence {
      names.append(bucket.name)
    }
    #expect(names == ["bucket-1", "bucket-2"])
    #expect(mock.isExhausted)
  }

  @Test func mockConvenienceOverloadDelegation() async throws {
    let mock = MockStorageControl(listBuckets: [
      { req, _ in
        #expect(req.parent == "projects/test-project")
        var response = ListBucketsResponse()
        var b = Bucket()
        b.name = "bucket-1"
        response.buckets = [b]
        return response
      }
    ])

    let client: any StorageControlProtocol = mock
    let response = try await client.listBuckets(
      request: .init().with { $0.parent = "projects/test-project" })
    #expect(response.buckets.count == 1)
    #expect(mock.isExhausted)
  }

  @MainActor
  struct BucketListModel {
    let client: any StorageControlProtocol

    func streamBucketNamesInBackground() -> Task<[String], any Swift.Error> {
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
    let mock = MockStorageControl(listBuckets: [
      { req, _ in
        #expect(req.pageToken.isEmpty)
        var response = ListBucketsResponse()
        var b = Bucket()
        b.name = "bucket-1"
        response.buckets = [b]
        response.nextPageToken = "token-page-2"
        return response
      },
      { req, _ in
        #expect(req.pageToken == "token-page-2")
        var response = ListBucketsResponse()
        var b = Bucket()
        b.name = "bucket-2"
        response.buckets = [b]
        response.nextPageToken = ""
        return response
      },
    ])

    let model = BucketListModel(client: mock)
    let task = await model.streamBucketNamesInBackground()
    let names = try await task.value
    #expect(names == ["bucket-1", "bucket-2"])
    #expect(mock.isExhausted)
  }

  @Test func mockLROConvenienceOverloadDelegation() async throws {
    let mock = MockStorageControl(renameFolder: [
      { req, _ in
        #expect(req.name == "projects/_/buckets/b/folders/f1")
        return Folder().with { $0.name = "projects/_/buckets/b/folders/f2" }
      }
    ])

    let client: any StorageControlProtocol = mock
    let folder = try await client.renameFolderPollingUntilDone(
      request: .init().with { $0.name = "projects/_/buckets/b/folders/f1" })
    #expect(folder.name == "projects/_/buckets/b/folders/f2")
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectUntilDoneSingleStep() async throws {
    let expectedObject = Object().with {
      $0.bucket = "projects/_/buckets/dest-bucket"
      $0.name = "dest-obj"
      $0.size = 1024
    }
    let mock = MockStorageControl(rewriteObject: [
      { req, _ in
        #expect(req.sourceBucket == "projects/_/buckets/src-bucket")
        #expect(req.sourceObject == "src-obj")
        #expect(req.destinationBucket == "projects/_/buckets/dest-bucket")
        #expect(req.destinationName == "dest-obj")
        #expect(req.rewriteToken.isEmpty)
        return RewriteResponse().with {
          $0.done = true
          $0.totalBytesRewritten = 1024
          $0.objectSize = 1024
          $0.resource = expectedObject
        }
      }
    ])

    let client: any StorageControlProtocol = mock
    let request = RewriteObjectRequest().with {
      $0.sourceBucket = "projects/_/buckets/src-bucket"
      $0.sourceObject = "src-obj"
      $0.destinationBucket = "projects/_/buckets/dest-bucket"
      $0.destinationName = "dest-obj"
    }
    let result = try await client.rewriteObjectUntilDone(request: request)
    #expect(result == expectedObject)
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectUntilDoneMultiStepAndProgress() async throws {
    let expectedObject = Object().with {
      $0.bucket = "projects/_/buckets/dest-bucket"
      $0.name = "dest-obj"
      $0.size = 3000
    }
    let mock = MockStorageControl(rewriteObject: [
      { req, opts in
        #expect(req.sourceBucket == "projects/_/buckets/src-bucket")
        #expect(req.destinationName == "dest-obj")
        #expect(opts.headers["x-custom"] == "test-val")
        #expect(req.rewriteToken.isEmpty)
        return RewriteResponse().with {
          $0.done = false
          $0.totalBytesRewritten = 1000
          $0.objectSize = 3000
          $0.rewriteToken = "token-1"
        }
      },
      { req, opts in
        #expect(req.sourceBucket == "projects/_/buckets/src-bucket")
        #expect(req.destinationName == "dest-obj")
        #expect(opts.headers["x-custom"] == "test-val")
        #expect(req.rewriteToken == "token-1")
        return RewriteResponse().with {
          $0.done = false
          $0.totalBytesRewritten = 2000
          $0.objectSize = 3000
          $0.rewriteToken = "token-2"
        }
      },
      { req, opts in
        #expect(req.sourceBucket == "projects/_/buckets/src-bucket")
        #expect(req.destinationName == "dest-obj")
        #expect(opts.headers["x-custom"] == "test-val")
        #expect(req.rewriteToken == "token-2")
        return RewriteResponse().with {
          $0.done = true
          $0.totalBytesRewritten = 3000
          $0.objectSize = 3000
          $0.resource = expectedObject
        }
      },
    ])

    let client: any StorageControlProtocol = mock
    let request = RewriteObjectRequest().with {
      $0.sourceBucket = "projects/_/buckets/src-bucket"
      $0.sourceObject = "src-obj"
      $0.destinationBucket = "projects/_/buckets/dest-bucket"
      $0.destinationName = "dest-obj"
    }
    var options = GoogleGax.RequestOptions()
    options.headers["x-custom"] = "test-val"

    let progressBytes = Mutex<[Int64]>([])
    let result = try await client.rewriteObjectUntilDone(
      request: request,
      options: options
    ) { response in
      progressBytes.withLock { $0.append(response.totalBytesRewritten) }
    }

    #expect(result == expectedObject)
    #expect(progressBytes.withLock { $0 } == [1000, 2000, 3000])
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectProgressSequence() async throws {
    let expectedObject = Object().with { $0.name = "dest-obj" }
    let mock = MockStorageControl(rewriteObject: [
      { req, _ in
        #expect(req.rewriteToken.isEmpty)
        return RewriteResponse().with {
          $0.done = false
          $0.totalBytesRewritten = 512
          $0.objectSize = 1024
          $0.rewriteToken = "next-token"
        }
      },
      { req, _ in
        #expect(req.rewriteToken == "next-token")
        return RewriteResponse().with {
          $0.done = true
          $0.totalBytesRewritten = 1024
          $0.objectSize = 1024
          $0.resource = expectedObject
        }
      },
    ])

    let client: any StorageControlProtocol = mock
    let sequence = client.rewriteObjectProgress(
      request: .init().with { $0.destinationName = "dest-obj" })
    var responses: [RewriteResponse] = []
    for try await response in sequence {
      responses.append(response)
    }
    #expect(responses.count == 2)
    #expect(!responses[0].done)
    #expect(responses[0].totalBytesRewritten == 512)
    #expect(responses[1].done)
    #expect(responses[1].resource == expectedObject)
    #expect(mock.isExhausted)
  }

  @MainActor
  struct RewriteProgressModel {
    let client: any StorageControlProtocol

    func streamRewriteInBackground() -> Task<[Int64], any Swift.Error> {
      let progress = client.rewriteObjectProgress(
        request: .init().with { $0.destinationName = "dest-obj" })
      return Task.detached {
        var bytes: [Int64] = []
        for try await step in progress {
          bytes.append(step.totalBytesRewritten)
        }
        return bytes
      }
    }
  }

  @Test func rewriteObjectProgressStreamedInDetachedTaskFromMainActor() async throws {
    let mock = MockStorageControl(rewriteObject: [
      { req, _ in
        #expect(req.rewriteToken.isEmpty)
        return RewriteResponse().with {
          $0.done = false
          $0.totalBytesRewritten = 100
          $0.objectSize = 200
          $0.rewriteToken = "t1"
        }
      },
      { req, _ in
        #expect(req.rewriteToken == "t1")
        return RewriteResponse().with {
          $0.done = true
          $0.totalBytesRewritten = 200
          $0.objectSize = 200
          $0.resource = Object().with { $0.name = "dest-obj" }
        }
      },
    ])

    let model = RewriteProgressModel(client: mock)
    let task = await model.streamRewriteInBackground()
    let bytes = try await task.value
    #expect(bytes == [100, 200])
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectUntilDoneErrorPropagation() async throws {
    let mock = MockStorageControl(rewriteObject: [
      { req, _ in
        #expect(req.rewriteToken.isEmpty)
        return RewriteResponse().with {
          $0.done = false
          $0.rewriteToken = "token-1"
        }
      },
      { req, _ in
        #expect(req.rewriteToken == "token-1")
        throw GoogleGax.RequestError.unimplemented
      },
    ])

    let client: any StorageControlProtocol = mock
    await #expect(throws: GoogleGax.RequestError.self) {
      _ = try await client.rewriteObjectUntilDone(request: .init())
    }
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectUntilDoneMissingResourceThrowsMalformedResponse() async throws {
    let mock = MockStorageControl(rewriteObject: [
      { _, _ in
        RewriteResponse().with {
          $0.done = true
          $0.resource = nil
        }
      }
    ])

    let client: any StorageControlProtocol = mock
    await #expect {
      _ = try await client.rewriteObjectUntilDone(request: .init())
    } throws: { error in
      guard case GoogleGax.RequestError.malformedResponse = error else {
        return false
      }
      return true
    }
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectEmptyTokenWhenNotDoneThrowsMalformedResponse() async throws {
    let mock = MockStorageControl(rewriteObject: [
      { _, _ in
        RewriteResponse().with {
          $0.done = false
          $0.rewriteToken = ""
        }
      }
    ])

    let client: any StorageControlProtocol = mock
    await #expect {
      _ = try await client.rewriteObjectUntilDone(request: .init())
    } throws: { error in
      guard case GoogleGax.RequestError.malformedResponse = error else {
        return false
      }
      return true
    }
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectProgressIteratorReturnsNilAfterError() async throws {
    let mock = MockStorageControl(rewriteObject: [
      { _, _ in
        throw GoogleGax.RequestError.unimplemented
      }
    ])

    let client: any StorageControlProtocol = mock
    let sequence = client.rewriteObjectProgress(request: .init())
    var iterator = sequence.makeAsyncIterator()

    await #expect(throws: GoogleGax.RequestError.self) {
      _ = try await iterator.next(isolation: #isolation)
    }
    let subsequent = try await iterator.next(isolation: #isolation)
    #expect(subsequent == nil)
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectProgressIndependentIterators() async throws {
    let expectedObject = Object().with { $0.name = "dest-obj" }
    let mock = MockStorageControl(rewriteObject: [
      // First iterator: step 1 & step 2
      { req, _ in
        #expect(req.rewriteToken.isEmpty)
        return RewriteResponse().with {
          $0.done = false
          $0.rewriteToken = "iter1-token"
        }
      },
      { req, _ in
        #expect(req.rewriteToken == "iter1-token")
        return RewriteResponse().with {
          $0.done = true
          $0.resource = expectedObject
        }
      },
      // Second iterator created from the same sequence: starts fresh with empty rewriteToken
      { req, _ in
        #expect(req.rewriteToken.isEmpty)
        return RewriteResponse().with {
          $0.done = false
          $0.rewriteToken = "iter2-token"
        }
      },
      { req, _ in
        #expect(req.rewriteToken == "iter2-token")
        return RewriteResponse().with {
          $0.done = true
          $0.resource = expectedObject
        }
      },
    ])

    let client: any StorageControlProtocol = mock
    let sequence = client.rewriteObjectProgress(
      request: .init().with { $0.destinationName = "dest-obj" })

    var firstRunCount = 0
    for try await _ in sequence {
      firstRunCount += 1
    }
    #expect(firstRunCount == 2)

    var secondRunCount = 0
    for try await _ in sequence {
      secondRunCount += 1
    }
    #expect(secondRunCount == 2)
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectUntilDoneOnProgressErrorHaltsSubsequentSteps() async throws {
    struct ProgressAbortError: Error, Equatable {}

    let mock = MockStorageControl(rewriteObject: [
      { req, _ in
        #expect(req.rewriteToken.isEmpty)
        return RewriteResponse().with {
          $0.done = false
          $0.totalBytesRewritten = 500
          $0.objectSize = 1000
          $0.rewriteToken = "token-1"
        }
      }
    ])

    let client: any StorageControlProtocol = mock
    await #expect(throws: ProgressAbortError.self) {
      _ = try await client.rewriteObjectUntilDone(request: .init()) { _ in
        throw ProgressAbortError()
      }
    }
    #expect(mock.isExhausted)
  }

  @Test func rewriteObjectResumesFromInitialRewriteToken() async throws {
    let expectedObject = Object().with { $0.name = "dest-obj" }
    let mock = MockStorageControl(rewriteObject: [
      { req, _ in
        #expect(req.rewriteToken == "saved-checkpoint-token")
        return RewriteResponse().with {
          $0.done = false
          $0.totalBytesRewritten = 2000
          $0.objectSize = 3000
          $0.rewriteToken = "next-checkpoint-token"
        }
      },
      { req, _ in
        #expect(req.rewriteToken == "next-checkpoint-token")
        return RewriteResponse().with {
          $0.done = true
          $0.totalBytesRewritten = 3000
          $0.objectSize = 3000
          $0.resource = expectedObject
        }
      },
    ])

    let client: any StorageControlProtocol = mock
    let resumeRequest = RewriteObjectRequest().with {
      $0.destinationName = "dest-obj"
      $0.rewriteToken = "saved-checkpoint-token"
    }
    let result = try await client.rewriteObjectUntilDone(request: resumeRequest)
    #expect(result == expectedObject)
    #expect(mock.isExhausted)
  }
}
