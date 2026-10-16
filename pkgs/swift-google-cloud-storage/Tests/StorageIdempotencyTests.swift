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
import GoogleIAMV1
import GoogleLongRunning
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct StorageIdempotencyTests {
  @Test func readRequestsAreIdempotentWithoutToken() {
    let initialOptions = RequestOptions()

    let getBucket = GetBucketRequest().resolveIdempotency(options: initialOptions)
    #expect(getBucket.idempotent == true)
    #expect(getBucket.headers[idempotencyToken] == nil)

    let listBuckets = ListBucketsRequest().resolveIdempotency(options: initialOptions)
    #expect(listBuckets.idempotent == true)
    #expect(listBuckets.headers[idempotencyToken] == nil)

    let getObject = GetObjectRequest().resolveIdempotency(options: initialOptions)
    #expect(getObject.idempotent == true)
    #expect(getObject.headers[idempotencyToken] == nil)

    let listObjects = ListObjectsRequest().resolveIdempotency(options: initialOptions)
    #expect(listObjects.idempotent == true)
    #expect(listObjects.headers[idempotencyToken] == nil)
  }

  @Test func createBucketIsIdempotent() {
    let options = CreateBucketRequest().resolveIdempotency(options: RequestOptions())
    #expect(options.idempotent == true)
    #expect(options.headers[idempotencyToken] != nil)
  }

  @Test func deleteObjectPreconditions() {
    // Without preconditions: not idempotent, no token
    let unconditioned = DeleteObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotent == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    // With generation != 0: idempotent, token stamped
    let withGen = DeleteObjectRequest().with { $0.generation = 42 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withGen.idempotent == true)
    #expect(withGen.headers[idempotencyToken] != nil)

    // With ifGenerationMatch: idempotent, token stamped
    let withGenMatch = DeleteObjectRequest().with { $0.ifGenerationMatch = 42 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withGenMatch.idempotent == true)
    #expect(withGenMatch.headers[idempotencyToken] != nil)
  }

  @Test func deleteBucketIsIdempotent() {
    let options = DeleteBucketRequest().resolveIdempotency(options: RequestOptions())
    #expect(options.idempotent == true)
    #expect(options.headers[idempotencyToken] != nil)
  }

  @Test func updateBucketPreconditions() {
    let unconditioned = UpdateBucketRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotent == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let conditioned = UpdateBucketRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(conditioned.idempotent == true)
    #expect(conditioned.headers[idempotencyToken] != nil)
  }

  @Test func updateObjectPreconditions() {
    let unconditioned = UpdateObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotent == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let withGenMatch = UpdateObjectRequest().with { $0.ifGenerationMatch = 10 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withGenMatch.idempotent == false)
    #expect(withGenMatch.headers[idempotencyToken] == nil)

    let withMetaMatch = UpdateObjectRequest().with { $0.ifMetagenerationMatch = 2 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withMetaMatch.idempotent == true)
    #expect(withMetaMatch.headers[idempotencyToken] != nil)
  }

  @Test func restoreObjectPreconditions() {
    let unconditioned = RestoreObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotent == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let withGenMatch = RestoreObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withGenMatch.idempotent == true)
    #expect(withGenMatch.headers[idempotencyToken] != nil)

    let withMetaMatch = RestoreObjectRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(withMetaMatch.idempotent == true)
    #expect(withMetaMatch.headers[idempotencyToken] != nil)
  }

  @Test func composeObjectPreconditions() {
    let unconditioned = ComposeObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotent == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let conditioned = ComposeObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(conditioned.idempotent == true)
    #expect(conditioned.headers[idempotencyToken] != nil)
  }

  @Test func rewriteObjectPreconditions() {
    let unconditioned = RewriteObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotent == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let conditioned = RewriteObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(conditioned.idempotent == true)
    #expect(conditioned.headers[idempotencyToken] != nil)
  }

  @Test func moveObjectPreconditions() {
    let unconditioned = MoveObjectRequest().resolveIdempotency(options: RequestOptions())
    #expect(unconditioned.idempotent == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let sourceOnly = MoveObjectRequest().with { $0.ifSourceGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(sourceOnly.idempotent == false)
    #expect(sourceOnly.headers[idempotencyToken] == nil)

    let destOnly = MoveObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: RequestOptions())
    #expect(destOnly.idempotent == false)
    #expect(destOnly.headers[idempotencyToken] == nil)

    let both = MoveObjectRequest().with {
      $0.ifSourceGenerationMatch = 1
      $0.ifGenerationMatch = 2
    }.resolveIdempotency(options: RequestOptions())
    #expect(both.idempotent == true)
    #expect(both.headers[idempotencyToken] != nil)
  }

  @Test func lockBucketRetentionPolicyPreconditions() {
    let unconditioned = LockBucketRetentionPolicyRequest().resolveIdempotency(
      options: RequestOptions())
    #expect(unconditioned.idempotent == false)
    #expect(unconditioned.headers[idempotencyToken] == nil)

    let zero = LockBucketRetentionPolicyRequest().with { $0.ifMetagenerationMatch = 0 }
      .resolveIdempotency(options: RequestOptions())
    #expect(zero.idempotent == false)
    #expect(zero.headers[idempotencyToken] == nil)

    let positive = LockBucketRetentionPolicyRequest().with { $0.ifMetagenerationMatch = 5 }
      .resolveIdempotency(options: RequestOptions())
    #expect(positive.idempotent == true)
    #expect(positive.headers[idempotencyToken] != nil)
  }

  @Test func explicitIdempotencyOverrideIsPreserved() {
    // Explicit override true on a non-idempotent request causes token injection
    let overrideTrue = RequestOptions().with { $0.idempotent = true }
    let resTrue = DeleteObjectRequest().resolveIdempotency(options: overrideTrue)
    #expect(resTrue.idempotent == true)
    #expect(resTrue.headers[idempotencyToken] != nil)

    // Explicit override false on an idempotent request
    let overrideFalse = RequestOptions().with { $0.idempotent = false }
    let resFalse = GetObjectRequest().resolveIdempotency(options: overrideFalse)
    #expect(resFalse.idempotent == false)
  }

  @Test func existingIdempotencyTokenIsNotOverwritten() {
    let existingToken = "custom-token-xyz"
    let options = RequestOptions().with {
      $0.headers[idempotencyToken] = existingToken
    }
    let res = DeleteObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: options)
    #expect(res.headers[idempotencyToken] == existingToken)

    let mixedCaseOptions = RequestOptions().with {
      $0.headers["X-Goog-GCS-Idempotency-Token"] = existingToken
    }
    let mixedCaseRes = DeleteObjectRequest().with { $0.ifGenerationMatch = 1 }
      .resolveIdempotency(options: mixedCaseOptions)
    #expect(mixedCaseRes.headers.values(for: idempotencyToken) == [existingToken])
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

    final class MockStorageStub: GoogleCloudStorage.Clients.StorageStub, @unchecked Sendable {
      let tracker: CallTracker
      init(tracker: CallTracker) { self.tracker = tracker }

      func deleteObject(request: DeleteObjectRequest, options: RequestOptions) async throws {
        let shouldSucceed = await tracker.record(options: options)
        if !shouldSucceed {
          throw RequestError.http(HTTPDetails(statusCode: 503, headers: []))
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
      initialDelay: .milliseconds(1),
      maximumDelay: .milliseconds(2)
    )

    let stub = MockStorageStub(tracker: tracker)
    let retryStub = GoogleCloudStorage.Clients.StorageRetry(stub, options: clientOptions)

    let request = DeleteObjectRequest().with { $0.ifGenerationMatch = 123 }
    try await retryStub.deleteObject(request: request, options: RequestOptions())

    let recordedTokens = await tracker.tokens
    #expect(recordedTokens.count == 2)
    #expect(recordedTokens[0] != nil)
    #expect(recordedTokens[0] == recordedTokens[1])
  }

  @Test func iamReadRequestsAreIdempotentWithoutToken() {
    let initialOptions = RequestOptions()

    let getIamPolicy = GoogleIAMV1.GetIamPolicyRequest().resolveIdempotency(
      options: initialOptions)
    #expect(getIamPolicy.idempotent == true)
    #expect(getIamPolicy.headers[idempotencyToken] == nil)

    let testIamPermissions = GoogleIAMV1.TestIamPermissionsRequest().resolveIdempotency(
      options: initialOptions)
    #expect(testIamPermissions.idempotent == true)
    #expect(testIamPermissions.headers[idempotencyToken] == nil)
  }

  @Test func setIamPolicyPreconditions() {
    // Without policy: not idempotent, no token
    let withoutPolicy = GoogleIAMV1.SetIamPolicyRequest().resolveIdempotency(
      options: RequestOptions())
    #expect(withoutPolicy.idempotent == false)
    #expect(withoutPolicy.headers[idempotencyToken] == nil)

    // With empty etag: not idempotent, no token
    let emptyEtag = GoogleIAMV1.SetIamPolicyRequest().with {
      $0.policy = GoogleIAMV1.Policy()
    }.resolveIdempotency(options: RequestOptions())
    #expect(emptyEtag.idempotent == false)
    #expect(emptyEtag.headers[idempotencyToken] == nil)

    // With non-empty etag: idempotent, token stamped
    let withEtag = GoogleIAMV1.SetIamPolicyRequest().with {
      $0.policy = GoogleIAMV1.Policy().with { $0.etag = Data("etag-1".utf8) }
    }.resolveIdempotency(options: RequestOptions())
    #expect(withEtag.idempotent == true)
    #expect(withEtag.headers[idempotencyToken] != nil)
  }

  @Test func storageControlReadRequestsAreIdempotentWithoutToken() {
    let initialOptions = RequestOptions()

    let getFolder = GetFolderRequest().resolveIdempotency(options: initialOptions)
    #expect(getFolder.idempotent == true)
    #expect(getFolder.headers[idempotencyToken] == nil)

    let listFolders = ListFoldersRequest().resolveIdempotency(options: initialOptions)
    #expect(listFolders.idempotent == true)
    #expect(listFolders.headers[idempotencyToken] == nil)

    let getStorageLayout = GetStorageLayoutRequest().resolveIdempotency(options: initialOptions)
    #expect(getStorageLayout.idempotent == true)
    #expect(getStorageLayout.headers[idempotencyToken] == nil)

    let getManagedFolder = GetManagedFolderRequest().resolveIdempotency(options: initialOptions)
    #expect(getManagedFolder.idempotent == true)
    #expect(getManagedFolder.headers[idempotencyToken] == nil)

    let listManagedFolders = ListManagedFoldersRequest().resolveIdempotency(options: initialOptions)
    #expect(listManagedFolders.idempotent == true)
    #expect(listManagedFolders.headers[idempotencyToken] == nil)

    let getAnywhereCache = GetAnywhereCacheRequest().resolveIdempotency(options: initialOptions)
    #expect(getAnywhereCache.idempotent == true)
    #expect(getAnywhereCache.headers[idempotencyToken] == nil)

    let listAnywhereCaches = ListAnywhereCachesRequest().resolveIdempotency(options: initialOptions)
    #expect(listAnywhereCaches.idempotent == true)
    #expect(listAnywhereCaches.headers[idempotencyToken] == nil)

    let getRapidCache = GetRapidCacheRequest().resolveIdempotency(options: initialOptions)
    #expect(getRapidCache.idempotent == true)
    #expect(getRapidCache.headers[idempotencyToken] == nil)

    let listRapidCaches = ListRapidCachesRequest().resolveIdempotency(options: initialOptions)
    #expect(listRapidCaches.idempotent == true)
    #expect(listRapidCaches.headers[idempotencyToken] == nil)

    let getProjectIntel = GetProjectIntelligenceConfigRequest().resolveIdempotency(
      options: initialOptions)
    #expect(getProjectIntel.idempotent == true)
    #expect(getProjectIntel.headers[idempotencyToken] == nil)

    let getFolderIntel = GetFolderIntelligenceConfigRequest().resolveIdempotency(
      options: initialOptions)
    #expect(getFolderIntel.idempotent == true)
    #expect(getFolderIntel.headers[idempotencyToken] == nil)

    let getOrgIntel = GetOrganizationIntelligenceConfigRequest().resolveIdempotency(
      options: initialOptions)
    #expect(getOrgIntel.idempotent == true)
    #expect(getOrgIntel.headers[idempotencyToken] == nil)

    let getFinding = GetIntelligenceFindingRequest().resolveIdempotency(options: initialOptions)
    #expect(getFinding.idempotent == true)
    #expect(getFinding.headers[idempotencyToken] == nil)

    let listFindings = ListIntelligenceFindingsRequest().resolveIdempotency(options: initialOptions)
    #expect(listFindings.idempotent == true)
    #expect(listFindings.headers[idempotencyToken] == nil)

    let summarizeFindings = SummarizeIntelligenceFindingsRequest().resolveIdempotency(
      options: initialOptions)
    #expect(summarizeFindings.idempotent == true)
    #expect(summarizeFindings.headers[idempotencyToken] == nil)

    let getFindingRevision = GetIntelligenceFindingRevisionRequest().resolveIdempotency(
      options: initialOptions)
    #expect(getFindingRevision.idempotent == true)
    #expect(getFindingRevision.headers[idempotencyToken] == nil)

    let listFindingRevisions = ListIntelligenceFindingRevisionsRequest().resolveIdempotency(
      options: initialOptions)
    #expect(listFindingRevisions.idempotent == true)
    #expect(listFindingRevisions.headers[idempotencyToken] == nil)

    let viewObjectFullContext = ViewObjectFullContextRequest().resolveIdempotency(
      options: initialOptions)
    #expect(viewObjectFullContext.idempotent == true)
    #expect(viewObjectFullContext.headers[idempotencyToken] == nil)

    let getOperation = GoogleLongRunning.GetOperationRequest().resolveIdempotency(
      options: initialOptions)
    #expect(getOperation.idempotent == true)
    #expect(getOperation.headers[idempotencyToken] == nil)
  }

  @Test func storageControlMetagenerationPreconditions() {
    let initialOptions = RequestOptions()

    #expect(DeleteFolderRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    let deleteFolder = DeleteFolderRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: initialOptions)
    #expect(deleteFolder.idempotent == true)
    #expect(deleteFolder.headers[idempotencyToken] == nil)

    #expect(RenameFolderRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    let renameFolder = RenameFolderRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: initialOptions)
    #expect(renameFolder.idempotent == true)
    #expect(renameFolder.headers[idempotencyToken] == nil)

    #expect(
      DeleteFolderRecursiveRequest().resolveIdempotency(options: initialOptions).idempotent == false
    )
    let deleteFolderRecursive = DeleteFolderRecursiveRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: initialOptions)
    #expect(deleteFolderRecursive.idempotent == true)
    #expect(deleteFolderRecursive.headers[idempotencyToken] == nil)

    #expect(
      DeleteManagedFolderRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    let deleteManagedFolder = DeleteManagedFolderRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: initialOptions)
    #expect(deleteManagedFolder.idempotent == true)
    #expect(deleteManagedFolder.headers[idempotencyToken] == nil)

    #expect(
      UpdateManagedFolderRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    let updateManagedFolder = UpdateManagedFolderRequest().with { $0.ifMetagenerationMatch = 1 }
      .resolveIdempotency(options: initialOptions)
    #expect(updateManagedFolder.idempotent == true)
    #expect(updateManagedFolder.headers[idempotencyToken] == nil)
  }

  @Test func storageControlRequestIdPreconditions() {
    let initialOptions = RequestOptions()

    #expect(CreateFolderRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    let createFolder = CreateFolderRequest().with { $0.requestId = "req-1" }
      .resolveIdempotency(options: initialOptions)
    #expect(createFolder.idempotent == true)
    #expect(createFolder.headers[idempotencyToken] == nil)

    #expect(
      CreateManagedFolderRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    let createManagedFolder = CreateManagedFolderRequest().with { $0.requestId = "req-1" }
      .resolveIdempotency(options: initialOptions)
    #expect(createManagedFolder.idempotent == true)
    #expect(createManagedFolder.headers[idempotencyToken] == nil)

    #expect(
      CreateAnywhereCacheRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    #expect(
      CreateAnywhereCacheRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      UpdateAnywhereCacheRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    #expect(
      UpdateAnywhereCacheRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      DisableAnywhereCacheRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    #expect(
      DisableAnywhereCacheRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      PauseAnywhereCacheRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    #expect(
      PauseAnywhereCacheRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      ResumeAnywhereCacheRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    #expect(
      ResumeAnywhereCacheRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      CreateRapidCacheRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    #expect(
      CreateRapidCacheRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      UpdateRapidCacheRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    #expect(
      UpdateRapidCacheRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      DisableRapidCacheRequest().resolveIdempotency(options: initialOptions).idempotent == false)
    #expect(
      DisableRapidCacheRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      UpdateProjectIntelligenceConfigRequest().resolveIdempotency(options: initialOptions)
        .idempotent == false)
    #expect(
      UpdateProjectIntelligenceConfigRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      UpdateFolderIntelligenceConfigRequest().resolveIdempotency(options: initialOptions).idempotent
        == false)
    #expect(
      UpdateFolderIntelligenceConfigRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)

    #expect(
      UpdateOrganizationIntelligenceConfigRequest().resolveIdempotency(options: initialOptions)
        .idempotent == false)
    #expect(
      UpdateOrganizationIntelligenceConfigRequest().with { $0.requestId = "req-1" }
        .resolveIdempotency(options: initialOptions).idempotent == true)
  }

  @Test func storageControlRetryStubRetriesReadAndConditionedIamRequests() async throws {
    actor ControlCallTracker {
      var getIamCalls = 0
      var testIamCalls = 0
      var getRapidCacheCalls = 0
      var listRapidCachesCalls = 0
      var setIamTokens: [String?] = []

      func recordGetIam() -> Bool {
        getIamCalls += 1
        return getIamCalls >= 2
      }

      func recordTestIam() -> Bool {
        testIamCalls += 1
        return testIamCalls >= 2
      }

      func recordGetRapidCache() -> Bool {
        getRapidCacheCalls += 1
        return getRapidCacheCalls >= 2
      }

      func recordListRapidCaches() -> Bool {
        listRapidCachesCalls += 1
        return listRapidCachesCalls >= 2
      }

      func recordSetIam(options: RequestOptions) -> Bool {
        setIamTokens.append(options.headers[idempotencyToken])
        return setIamTokens.count >= 2
      }

      func resetSetIam() {
        setIamTokens.removeAll()
      }
    }

    final class MockStorageControlStub: GoogleCloudStorage.Clients.StorageControlStub,
      @unchecked Sendable
    {
      let tracker: ControlCallTracker
      init(tracker: ControlCallTracker) { self.tracker = tracker }

      func getIamPolicy(
        request: GoogleIAMV1.GetIamPolicyRequest, options: RequestOptions
      ) async throws -> GoogleIAMV1.Policy {
        if !(await tracker.recordGetIam()) {
          throw RequestError.http(HTTPDetails(statusCode: 503, headers: []))
        }
        return GoogleIAMV1.Policy()
      }

      func setIamPolicy(
        request: GoogleIAMV1.SetIamPolicyRequest, options: RequestOptions
      ) async throws -> GoogleIAMV1.Policy {
        if !(await tracker.recordSetIam(options: options)) {
          throw RequestError.http(HTTPDetails(statusCode: 503, headers: []))
        }
        return GoogleIAMV1.Policy()
      }

      func testIamPermissions(
        request: GoogleIAMV1.TestIamPermissionsRequest, options: RequestOptions
      ) async throws -> GoogleIAMV1.TestIamPermissionsResponse {
        if !(await tracker.recordTestIam()) {
          throw RequestError.http(HTTPDetails(statusCode: 503, headers: []))
        }
        return GoogleIAMV1.TestIamPermissionsResponse()
      }

      func getRapidCache(
        request: GetRapidCacheRequest, options: RequestOptions
      ) async throws -> RapidCache {
        if !(await tracker.recordGetRapidCache()) {
          throw RequestError.http(HTTPDetails(statusCode: 503, headers: []))
        }
        return RapidCache()
      }

      func listRapidCaches(
        request: ListRapidCachesRequest, options: RequestOptions
      ) async throws -> ListRapidCachesResponse {
        if !(await tracker.recordListRapidCaches()) {
          throw RequestError.http(HTTPDetails(statusCode: 503, headers: []))
        }
        return ListRapidCachesResponse()
      }

      func createFolder(request: CreateFolderRequest, options: RequestOptions) async throws
        -> Folder
      { Folder() }
      func deleteFolder(request: DeleteFolderRequest, options: RequestOptions) async throws {}
      func getFolder(request: GetFolderRequest, options: RequestOptions) async throws -> Folder {
        Folder()
      }
      func listFolders(request: ListFoldersRequest, options: RequestOptions) async throws
        -> ListFoldersResponse
      { ListFoldersResponse() }
      func renameFolder(request: RenameFolderRequest, options: RequestOptions) async throws
        -> GoogleLongRunning.Operation
      { GoogleLongRunning.Operation() }
      func deleteFolderRecursive(
        request: DeleteFolderRecursiveRequest, options: RequestOptions
      ) async throws -> GoogleLongRunning.Operation { GoogleLongRunning.Operation() }
      func getStorageLayout(request: GetStorageLayoutRequest, options: RequestOptions) async throws
        -> StorageLayout
      { StorageLayout() }
      func createManagedFolder(
        request: CreateManagedFolderRequest, options: RequestOptions
      ) async throws -> ManagedFolder { ManagedFolder() }
      func deleteManagedFolder(
        request: DeleteManagedFolderRequest, options: RequestOptions
      ) async throws {}
      func getManagedFolder(request: GetManagedFolderRequest, options: RequestOptions) async throws
        -> ManagedFolder
      { ManagedFolder() }
      func listManagedFolders(
        request: ListManagedFoldersRequest, options: RequestOptions
      ) async throws -> ListManagedFoldersResponse { ListManagedFoldersResponse() }
      func updateManagedFolder(
        request: UpdateManagedFolderRequest, options: RequestOptions
      ) async throws -> ManagedFolder { ManagedFolder() }
      func createAnywhereCache(
        request: CreateAnywhereCacheRequest, options: RequestOptions
      ) async throws -> GoogleLongRunning.Operation { GoogleLongRunning.Operation() }
      func updateAnywhereCache(
        request: UpdateAnywhereCacheRequest, options: RequestOptions
      ) async throws -> GoogleLongRunning.Operation { GoogleLongRunning.Operation() }
      func disableAnywhereCache(
        request: DisableAnywhereCacheRequest, options: RequestOptions
      ) async throws -> AnywhereCache { AnywhereCache() }
      func pauseAnywhereCache(
        request: PauseAnywhereCacheRequest, options: RequestOptions
      ) async throws -> AnywhereCache { AnywhereCache() }
      func resumeAnywhereCache(
        request: ResumeAnywhereCacheRequest, options: RequestOptions
      ) async throws -> AnywhereCache { AnywhereCache() }
      func getAnywhereCache(request: GetAnywhereCacheRequest, options: RequestOptions) async throws
        -> AnywhereCache
      { AnywhereCache() }
      func listAnywhereCaches(
        request: ListAnywhereCachesRequest, options: RequestOptions
      ) async throws -> ListAnywhereCachesResponse { ListAnywhereCachesResponse() }
      func createRapidCache(request: CreateRapidCacheRequest, options: RequestOptions) async throws
        -> GoogleLongRunning.Operation
      { GoogleLongRunning.Operation() }
      func updateRapidCache(request: UpdateRapidCacheRequest, options: RequestOptions) async throws
        -> GoogleLongRunning.Operation
      { GoogleLongRunning.Operation() }
      func disableRapidCache(
        request: DisableRapidCacheRequest, options: RequestOptions
      ) async throws -> GoogleLongRunning.Operation { GoogleLongRunning.Operation() }
      func getProjectIntelligenceConfig(
        request: GetProjectIntelligenceConfigRequest, options: RequestOptions
      ) async throws -> IntelligenceConfig { IntelligenceConfig() }
      func updateProjectIntelligenceConfig(
        request: UpdateProjectIntelligenceConfigRequest, options: RequestOptions
      ) async throws -> IntelligenceConfig { IntelligenceConfig() }
      func getFolderIntelligenceConfig(
        request: GetFolderIntelligenceConfigRequest, options: RequestOptions
      ) async throws -> IntelligenceConfig { IntelligenceConfig() }
      func updateFolderIntelligenceConfig(
        request: UpdateFolderIntelligenceConfigRequest, options: RequestOptions
      ) async throws -> IntelligenceConfig { IntelligenceConfig() }
      func getOrganizationIntelligenceConfig(
        request: GetOrganizationIntelligenceConfigRequest, options: RequestOptions
      ) async throws -> IntelligenceConfig { IntelligenceConfig() }
      func updateOrganizationIntelligenceConfig(
        request: UpdateOrganizationIntelligenceConfigRequest, options: RequestOptions
      ) async throws -> IntelligenceConfig { IntelligenceConfig() }
      func getIntelligenceFinding(
        request: GetIntelligenceFindingRequest, options: RequestOptions
      ) async throws -> IntelligenceFinding { IntelligenceFinding() }
      func listIntelligenceFindings(
        request: ListIntelligenceFindingsRequest, options: RequestOptions
      ) async throws -> ListIntelligenceFindingsResponse { ListIntelligenceFindingsResponse() }
      func summarizeIntelligenceFindings(
        request: SummarizeIntelligenceFindingsRequest, options: RequestOptions
      ) async throws -> SummarizeIntelligenceFindingsResponse {
        SummarizeIntelligenceFindingsResponse()
      }
      func getIntelligenceFindingRevision(
        request: GetIntelligenceFindingRevisionRequest, options: RequestOptions
      ) async throws -> IntelligenceFindingRevision { IntelligenceFindingRevision() }
      func listIntelligenceFindingRevisions(
        request: ListIntelligenceFindingRevisionsRequest, options: RequestOptions
      ) async throws -> ListIntelligenceFindingRevisionsResponse {
        ListIntelligenceFindingRevisionsResponse()
      }
      func viewObjectFullContext(
        request: ViewObjectFullContextRequest, options: RequestOptions
      ) async throws -> ObjectFullContext { ObjectFullContext() }
      func getOperation(
        request: GoogleLongRunning.GetOperationRequest, options: RequestOptions
      ) async throws -> GoogleLongRunning.Operation { GoogleLongRunning.Operation() }
    }

    var clientOptions = ClientOptions()
    clientOptions.retryPolicy = StorageBaseRetryPolicy.defaultPolicy
    clientOptions.backoffPolicy = try ExponentialBackoff(
      initialDelay: .milliseconds(1),
      maximumDelay: .milliseconds(2)
    )

    let tracker = ControlCallTracker()
    let stub = MockStorageControlStub(tracker: tracker)
    let retryStub = GoogleCloudStorage.Clients.StorageControlRetry(stub, options: clientOptions)

    _ = try await retryStub.getIamPolicy(
      request: GoogleIAMV1.GetIamPolicyRequest(), options: RequestOptions())
    #expect(await tracker.getIamCalls == 2)

    _ = try await retryStub.testIamPermissions(
      request: GoogleIAMV1.TestIamPermissionsRequest(), options: RequestOptions())
    #expect(await tracker.testIamCalls == 2)

    _ = try await retryStub.getRapidCache(
      request: GetRapidCacheRequest(), options: RequestOptions())
    #expect(await tracker.getRapidCacheCalls == 2)

    _ = try await retryStub.listRapidCaches(
      request: ListRapidCachesRequest(), options: RequestOptions())
    #expect(await tracker.listRapidCachesCalls == 2)

    // Unconditioned setIamPolicy should not retry on 503
    await #expect(throws: RequestError.self) {
      _ = try await retryStub.setIamPolicy(
        request: GoogleIAMV1.SetIamPolicyRequest(), options: RequestOptions())
    }
    #expect(await tracker.setIamTokens.count == 1)
    #expect(await tracker.setIamTokens[0] == nil)

    // Conditioned setIamPolicy (non-empty etag) should retry and share the same token
    await tracker.resetSetIam()
    let conditionedSetIam = GoogleIAMV1.SetIamPolicyRequest().with {
      $0.policy = GoogleIAMV1.Policy().with { $0.etag = Data("etag-value".utf8) }
    }
    _ = try await retryStub.setIamPolicy(request: conditionedSetIam, options: RequestOptions())
    let recordedTokens = await tracker.setIamTokens
    #expect(recordedTokens.count == 2)
    #expect(recordedTokens[0] != nil)
    #expect(recordedTokens[0] == recordedTokens[1])
  }
}
