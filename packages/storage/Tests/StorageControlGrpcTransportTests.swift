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
import GRPC
import GoogleCloudAuth
import GoogleCloudGax
import NIO
import StorageControlProtos
import SwiftProtobuf
import Testing
@testable import GoogleCloudStorage

extension Google_Storage_Control_V2_StorageControlAsyncProvider {
  func createFolder(
    request: Google_Storage_Control_V2_CreateFolderRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_Folder {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func deleteFolder(
    request: Google_Storage_Control_V2_DeleteFolderRequest, context: GRPCAsyncServerCallContext
  ) async throws -> SwiftProtobuf.Google_Protobuf_Empty {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getFolder(
    request: Google_Storage_Control_V2_GetFolderRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_Folder {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func listFolders(
    request: Google_Storage_Control_V2_ListFoldersRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ListFoldersResponse {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func renameFolder(
    request: Google_Storage_Control_V2_RenameFolderRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Longrunning_Operation {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func deleteFolderRecursive(
    request: Google_Storage_Control_V2_DeleteFolderRecursiveRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Longrunning_Operation {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getStorageLayout(
    request: Google_Storage_Control_V2_GetStorageLayoutRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_StorageLayout {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func createManagedFolder(
    request: Google_Storage_Control_V2_CreateManagedFolderRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ManagedFolder {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func deleteManagedFolder(
    request: Google_Storage_Control_V2_DeleteManagedFolderRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> SwiftProtobuf.Google_Protobuf_Empty {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getManagedFolder(
    request: Google_Storage_Control_V2_GetManagedFolderRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ManagedFolder {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func listManagedFolders(
    request: Google_Storage_Control_V2_ListManagedFoldersRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ListManagedFoldersResponse {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func updateManagedFolder(
    request: Google_Storage_Control_V2_UpdateManagedFolderRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ManagedFolder {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func createAnywhereCache(
    request: Google_Storage_Control_V2_CreateAnywhereCacheRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Longrunning_Operation {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func updateAnywhereCache(
    request: Google_Storage_Control_V2_UpdateAnywhereCacheRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Longrunning_Operation {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func disableAnywhereCache(
    request: Google_Storage_Control_V2_DisableAnywhereCacheRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_AnywhereCache {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func pauseAnywhereCache(
    request: Google_Storage_Control_V2_PauseAnywhereCacheRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_AnywhereCache {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func resumeAnywhereCache(
    request: Google_Storage_Control_V2_ResumeAnywhereCacheRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_AnywhereCache {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getAnywhereCache(
    request: Google_Storage_Control_V2_GetAnywhereCacheRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_AnywhereCache {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func listAnywhereCaches(
    request: Google_Storage_Control_V2_ListAnywhereCachesRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ListAnywhereCachesResponse {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func createRapidCache(
    request: Google_Storage_Control_V2_CreateRapidCacheRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Longrunning_Operation {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func updateRapidCache(
    request: Google_Storage_Control_V2_UpdateRapidCacheRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Longrunning_Operation {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getRapidCache(
    request: Google_Storage_Control_V2_GetRapidCacheRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_RapidCache {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func listRapidCaches(
    request: Google_Storage_Control_V2_ListRapidCachesRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ListRapidCachesResponse {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getProjectIntelligenceConfig(
    request: Google_Storage_Control_V2_GetProjectIntelligenceConfigRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_IntelligenceConfig {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func updateProjectIntelligenceConfig(
    request: Google_Storage_Control_V2_UpdateProjectIntelligenceConfigRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_IntelligenceConfig {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getFolderIntelligenceConfig(
    request: Google_Storage_Control_V2_GetFolderIntelligenceConfigRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_IntelligenceConfig {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func updateFolderIntelligenceConfig(
    request: Google_Storage_Control_V2_UpdateFolderIntelligenceConfigRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_IntelligenceConfig {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getOrganizationIntelligenceConfig(
    request: Google_Storage_Control_V2_GetOrganizationIntelligenceConfigRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_IntelligenceConfig {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func updateOrganizationIntelligenceConfig(
    request: Google_Storage_Control_V2_UpdateOrganizationIntelligenceConfigRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_IntelligenceConfig {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getIamPolicy(request: Google_Iam_V1_GetIamPolicyRequest, context: GRPCAsyncServerCallContext)
    async throws -> Google_Iam_V1_Policy
  { throw GRPCStatus(code: .unimplemented, message: nil) }
  func setIamPolicy(request: Google_Iam_V1_SetIamPolicyRequest, context: GRPCAsyncServerCallContext)
    async throws -> Google_Iam_V1_Policy
  { throw GRPCStatus(code: .unimplemented, message: nil) }
  func testIamPermissions(
    request: Google_Iam_V1_TestIamPermissionsRequest, context: GRPCAsyncServerCallContext
  ) async throws -> Google_Iam_V1_TestIamPermissionsResponse {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getIntelligenceFinding(
    request: Google_Storage_Control_V2_GetIntelligenceFindingRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_IntelligenceFinding {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func listIntelligenceFindings(
    request: Google_Storage_Control_V2_ListIntelligenceFindingsRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ListIntelligenceFindingsResponse {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func summarizeIntelligenceFindings(
    request: Google_Storage_Control_V2_SummarizeIntelligenceFindingsRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_SummarizeIntelligenceFindingsResponse {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func getIntelligenceFindingRevision(
    request: Google_Storage_Control_V2_GetIntelligenceFindingRevisionRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_IntelligenceFindingRevision {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
  func listIntelligenceFindingRevisions(
    request: Google_Storage_Control_V2_ListIntelligenceFindingRevisionsRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ListIntelligenceFindingRevisionsResponse {
    throw GRPCStatus(code: .unimplemented, message: nil)
  }
}

final class MockStorageControlProvider: Google_Storage_Control_V2_StorageControlAsyncProvider,
  @unchecked Sendable
{
  var lastCreatedFolderRequest: Google_Storage_Control_V2_CreateFolderRequest?
  var lastDeletedFolderRequest: Google_Storage_Control_V2_DeleteFolderRequest?
  var lastGetFolderRequest: Google_Storage_Control_V2_GetFolderRequest?
  var lastListFoldersRequest: Google_Storage_Control_V2_ListFoldersRequest?
  var lastRenameFolderRequest: Google_Storage_Control_V2_RenameFolderRequest?

  func createFolder(
    request: Google_Storage_Control_V2_CreateFolderRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_Folder {
    self.lastCreatedFolderRequest = request
    var folder = Google_Storage_Control_V2_Folder()
    folder.name = "\(request.parent)/folders/\(request.folderID)"
    folder.metageneration = 1
    return folder
  }

  func deleteFolder(
    request: Google_Storage_Control_V2_DeleteFolderRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> SwiftProtobuf.Google_Protobuf_Empty {
    self.lastDeletedFolderRequest = request
    return SwiftProtobuf.Google_Protobuf_Empty()
  }

  func getFolder(
    request: Google_Storage_Control_V2_GetFolderRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_Folder {
    self.lastGetFolderRequest = request
    var folder = Google_Storage_Control_V2_Folder()
    folder.name = request.name
    folder.metageneration = 42
    return folder
  }

  func listFolders(
    request: Google_Storage_Control_V2_ListFoldersRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Storage_Control_V2_ListFoldersResponse {
    self.lastListFoldersRequest = request
    var response = Google_Storage_Control_V2_ListFoldersResponse()
    var folder1 = Google_Storage_Control_V2_Folder()
    folder1.name = "\(request.parent)/folders/folder1"
    response.folders = [folder1]
    return response
  }

  func renameFolder(
    request: Google_Storage_Control_V2_RenameFolderRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Google_Longrunning_Operation {
    self.lastRenameFolderRequest = request
    var op = Google_Longrunning_Operation()
    op.name = "\(request.name)/operations/rename-123"
    op.done = true
    return op
  }
}

@Suite struct StorageControlGrpcTransportTests {
  @Test func createFolderEndToEnd() async throws {
    let mock = MockStorageControlProvider()
    let group = MultiThreadedEventLoopGroup.singleton
    let server = try await Server.insecure(group: group)
      .withServiceProviders([mock])
      .bind(host: "127.0.0.1", port: 0)
      .get()
    defer { _ = server.close() }

    let port = server.channel.localAddress!.port!
    var options = ClientOptions()
    options.endpoint = "http://127.0.0.1:\(port)"
    options.credentials = try Credentials(configuration: .anonymous)

    let client = try StorageControlClient(options)
    let request = CreateFolderRequest().with {
      $0.parent = "projects/_/buckets/test-bucket"
      $0.folderId = "test-folder"
    }

    let folder = try await client.createFolder(request: request)
    #expect(folder.name == "projects/_/buckets/test-bucket/folders/test-folder")
    #expect(folder.metageneration == 1)

    #expect(mock.lastCreatedFolderRequest?.parent == "projects/_/buckets/test-bucket")
    #expect(mock.lastCreatedFolderRequest?.folderID == "test-folder")
  }

  @Test func deleteFolderEndToEnd() async throws {
    let mock = MockStorageControlProvider()
    let group = MultiThreadedEventLoopGroup.singleton
    let server = try await Server.insecure(group: group)
      .withServiceProviders([mock])
      .bind(host: "127.0.0.1", port: 0)
      .get()
    defer { _ = server.close() }

    let port = server.channel.localAddress!.port!
    var options = ClientOptions()
    options.endpoint = "http://127.0.0.1:\(port)"
    options.credentials = try Credentials(configuration: .anonymous)

    let client = try StorageControlClient(options)
    let request = DeleteFolderRequest().with {
      $0.name = "projects/_/buckets/test-bucket/folders/test-folder"
    }

    try await client.deleteFolder(request: request)
    #expect(
      mock.lastDeletedFolderRequest?.name == "projects/_/buckets/test-bucket/folders/test-folder")
  }

  @Test func getFolderEndToEnd() async throws {
    let mock = MockStorageControlProvider()
    let group = MultiThreadedEventLoopGroup.singleton
    let server = try await Server.insecure(group: group)
      .withServiceProviders([mock])
      .bind(host: "127.0.0.1", port: 0)
      .get()
    defer { _ = server.close() }

    let port = server.channel.localAddress!.port!
    var options = ClientOptions()
    options.endpoint = "http://127.0.0.1:\(port)"
    options.credentials = try Credentials(configuration: .anonymous)

    let client = try StorageControlClient(options)
    let request = GetFolderRequest().with {
      $0.name = "projects/_/buckets/test-bucket/folders/my-folder"
    }

    let folder = try await client.getFolder(request: request)
    #expect(folder.name == "projects/_/buckets/test-bucket/folders/my-folder")
    #expect(folder.metageneration == 42)
    #expect(mock.lastGetFolderRequest?.name == "projects/_/buckets/test-bucket/folders/my-folder")
  }

  @Test func listFoldersEndToEnd() async throws {
    let mock = MockStorageControlProvider()
    let group = MultiThreadedEventLoopGroup.singleton
    let server = try await Server.insecure(group: group)
      .withServiceProviders([mock])
      .bind(host: "127.0.0.1", port: 0)
      .get()
    defer { _ = server.close() }

    let port = server.channel.localAddress!.port!
    var options = ClientOptions()
    options.endpoint = "http://127.0.0.1:\(port)"
    options.credentials = try Credentials(configuration: .anonymous)

    let client = try StorageControlClient(options)
    let request = ListFoldersRequest().with {
      $0.parent = "projects/_/buckets/test-bucket"
    }

    let response = try await client.listFolders(request: request)
    #expect(response.folders.count == 1)
    #expect(response.folders.first?.name == "projects/_/buckets/test-bucket/folders/folder1")
    #expect(mock.lastListFoldersRequest?.parent == "projects/_/buckets/test-bucket")
  }
}
