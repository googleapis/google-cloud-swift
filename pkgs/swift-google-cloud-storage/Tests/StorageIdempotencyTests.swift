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
import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct StorageIdempotencyTests {
  @Test func readRequestsAreIdempotentWithoutToken() {
    let initialOptions = RequestOptions()

    let getBucket = GetBucketRequest().resolveIdempotency(options: initialOptions)
    #expect(getBucket.idempotency == true)
    #expect(getBucket.headers[idempotencyToken] == nil)

    let listBuckets = ListBucketsRequest().resolveIdempotency(options: initialOptions)
    #expect(listBuckets.idempotency == true)
    #expect(listBuckets.headers[idempotencyToken] == nil)

    let getObject = GetObjectRequest().resolveIdempotency(options: initialOptions)
    #expect(getObject.idempotency == true)
    #expect(getObject.headers[idempotencyToken] == nil)

    let listObjects = ListObjectsRequest().resolveIdempotency(options: initialOptions)
    #expect(listObjects.idempotency == true)
    #expect(listObjects.headers[idempotencyToken] == nil)
  }

  @Test func createBucketIsNotIdempotent() {
    let options = CreateBucketRequest().resolveIdempotency(options: RequestOptions())
    #expect(options.idempotency == true)
    #expect(options.headers[idempotencyToken] != nil)
  }

  @Test func deleteObjectPreconditions() {
    // Without preconditions: not idempotent, no token
    let unconditioned = DeleteObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    // With generation != 0: idempotent, token stamped
    let withGen = DeleteObjectRequest().with { $0.generation = 42 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withGen.idempotency == true)
    #expect(withGen.headers[idempotencyToken] != nil)

    // With ifGenerationMatch: idempotent, token stamped
    let withGenMatch = DeleteObjectRequest().with { $0.ifGenerationMatch = 42 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withGenMatch.idempotency == true)
    #expect(withGenMatch.headers[idempotencyToken] != nil)
  }

  @Test func deleteBucketPreconditions() {
    let unconditioned = DeleteBucketRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let conditioned = DeleteBucketRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(conditioned.idempotency == true)
    #expect(conditioned.headers[idempotencyToken] != nil)
  }

  @Test func updateBucketPreconditions() {
    let unconditioned = UpdateBucketRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let conditioned = UpdateBucketRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(conditioned.idempotency == true)
    #expect(conditioned.headers[idempotencyToken] != nil)
  }

  @Test func updateObjectPreconditions() {
    let unconditioned = UpdateObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let withGenMatch = UpdateObjectRequest().with { $0.ifGenerationMatch = 10 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withGenMatch.idempotency == true)
    #expect(withGenMatch.headers[idempotencyToken] != nil)

    let withMetaMatch = UpdateObjectRequest().with { $0.ifMetagenerationMatch = 2 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withMetaMatch.idempotency == true)
    #expect(withMetaMatch.headers[idempotencyToken] != nil)
  }

  @Test func restoreObjectPreconditions() {
    let unconditioned = RestoreObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let withGenMatch = RestoreObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withGenMatch.idempotency == true)
    #expect(withGenMatch.headers[idempotencyToken] != nil)

    let withMetaMatch = RestoreObjectRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withMetaMatch.idempotency == true)
    #expect(withMetaMatch.headers[idempotencyToken] != nil)
  }

  @Test func composeObjectPreconditions() {
    let unconditioned = ComposeObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let conditioned = ComposeObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(conditioned.idempotency == true)
    #expect(conditioned.headers[idempotencyToken] != nil)
  }

  @Test func rewriteObjectPreconditions() {
    let unconditioned = RewriteObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let conditioned = RewriteObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(conditioned.idempotency == true)
    #expect(conditioned.headers[idempotencyToken] != nil)
  }

  @Test func moveObjectPreconditions() {
    let unconditioned = MoveObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let sourceOnly = MoveObjectRequest().with { $0.ifSourceGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(sourceOnly.idempotency == false)
    #expect(sourceOnly.headers[idempotencyToken] == nil)

    let destOnly = MoveObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(destOnly.idempotency == false)
    #expect(destOnly.headers[idempotencyToken] == nil)

    let both = MoveObjectRequest().with {
      $0.ifSourceGenerationMatch = 1
      $0.ifGenerationMatch = 2
    }.resolveIdempotency(options: RequestOptions())
    #expect(both.idempotency == true)
    #expect(both.headers[idempotencyToken] != nil)
  }

  @Test func lockBucketRetentionPolicyPreconditions() {
    let unconditioned = LockBucketRetentionPolicyRequest().resolveIdempotency(
      options: RequestOptions())
    #expect(unconditioned.idempotency == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let zero = LockBucketRetentionPolicyRequest().with { $0.ifMetagenerationMatch = 0 }
      .resolveIdempotency(options: RequestOptions())
    #expect(zero.idempotency == false)
    #expect(zero.headers[idempotencyToken] == nil)

    let positive = LockBucketRetentionPolicyRequest().with { $0.ifMetagenerationMatch = 5 }
      .resolveIdempotency(options: RequestOptions())
    #expect(positive.idempotency == true)
    #expect(positive.headers[idempotencyToken] != nil)
  }

  @Test func explicitIdempotencyOverrideIsPreserved() {
    // Explicit override true on a non-idempotent request causes token injection
    let overrideTrue = RequestOptions().with { $0.idempotency = true }
    let resTrue = DeleteObjectRequest().resolveIdempotency(options: overrideTrue)
    #expect(resTrue.idempotency == true)
    #expect(resTrue.headers[idempotencyToken] != nil)

    // Explicit override false on an idempotent request
    let overrideFalse = RequestOptions().with { $0.idempotency = false }
    let resFalse = GetObjectRequest().resolveIdempotency(options: overrideFalse)
    #expect(resFalse.idempotency == false)
  }

  @Test func existingIdempotencyTokenIsNotOverwritten() {
    let existingToken = "custom-token-xyz"
    let options = RequestOptions().with {
      $0.headers[idempotencyToken] = existingToken
    }
    let res = DeleteObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: options)
    #expect(res.headers[idempotencyToken] == existingToken)
  }

  @Test func retryStubSharesSameTokenAcrossRetries() async throws {
    actor CallTracker {
      var tokens: [String?] = []
      var callCount = 0

      func record(options: RequestOptions) -> Bool {
        tokens.append(options.headers[idempotencyToken])
        callCount += 1
        return callCount >= 2
      }
    }
    let tracker = CallTracker()

    final class MockStorageStub: Clients.StorageStub, @unchecked Sendable {
      let tracker: CallTracker
      init(tracker: CallTracker) { self.tracker = tracker }

      func deleteObject(request: DeleteObjectRequest, options: RequestOptions) async throws {
        let shouldSucceed = await tracker.record(options: options)
        if !shouldSucceed {
          throw RequestError.http(HTTPDetails(httpStatusCode: 503, headers: [:]))
        }
      }

      // Stubs for other methods
      func deleteBucket(request: DeleteBucketRequest, options: RequestOptions) async throws {}
      func getBucket(request: GetBucketRequest, options: RequestOptions) async throws -> Bucket {
        Bucket()
      }
      func createBucket(request: CreateBucketRequest, options: RequestOptions) async throws
        -> Bucket
      { Bucket() }
      func listBuckets(request: ListBucketsRequest, options: RequestOptions) async throws
        -> ListBucketsResponse
      { ListBucketsResponse() }
      func lockBucketRetentionPolicy(
        request: LockBucketRetentionPolicyRequest, options: RequestOptions
      ) async throws -> Bucket { Bucket() }
      func updateBucket(request: UpdateBucketRequest, options: RequestOptions) async throws
        -> Bucket
      { Bucket() }
      func composeObject(request: ComposeObjectRequest, options: RequestOptions) async throws
        -> Object
      { Object() }
      func restoreObject(request: RestoreObjectRequest, options: RequestOptions) async throws
        -> Object
      { Object() }
      func getObject(request: GetObjectRequest, options: RequestOptions) async throws -> Object {
        Object()
      }
      func updateObject(request: UpdateObjectRequest, options: RequestOptions) async throws
        -> Object
      { Object() }
      func listObjects(request: ListObjectsRequest, options: RequestOptions) async throws
        -> ListObjectsResponse
      { ListObjectsResponse() }
      func rewriteObject(request: RewriteObjectRequest, options: RequestOptions) async throws
        -> RewriteResponse
      { RewriteResponse() }
      func moveObject(request: MoveObjectRequest, options: RequestOptions) async throws -> Object {
        Object()
      }
    }

    var clientOptions = ClientOptions()
    clientOptions.retryPolicy = StorageBaseRetryPolicy.defaultPolicy
    clientOptions.backoffPolicy = try ExponentialBackoff(
      config: .init().with {
        $0.initialDelay = .milliseconds(1)
        $0.maximumDelay = .milliseconds(2)
      }
    )

    let stub = MockStorageStub(tracker: tracker)
    let retryStub = Clients.StorageRetry(stub, options: clientOptions)

    let request = DeleteObjectRequest().with { $0.ifGenerationMatch = 123 }
    try await retryStub.deleteObject(request: request, options: RequestOptions())

    let recordedTokens = await tracker.tokens
    #expect(recordedTokens.count == 2)
    #expect(recordedTokens[0] != nil)
    #expect(recordedTokens[0] == recordedTokens[1])
  }
}
