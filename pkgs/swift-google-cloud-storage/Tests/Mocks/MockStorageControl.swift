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

import struct DequeModule.Deque
import GoogleCloudStorage
import GoogleGax
import Synchronization

/// Mock `StorageControlProtocol` backed by deques of handler closures for each RPC.
///
/// Each RPC call pops and invokes the next queued handler from its corresponding deque, or throws
/// `GoogleGax.RequestError.unimplemented` if no handler remains. Assert `#expect(mock.isExhausted)`
/// at the end of a test to verify that all queued handlers were consumed.
final class MockStorageControl: StorageControlProtocol, Sendable {
  typealias ListBucketsHandler =
    @Sendable (ListBucketsRequest, GoogleGax.RequestOptions) async throws -> ListBucketsResponse
  typealias RenameFolderHandler =
    @Sendable (RenameFolderRequest, GoogleGax.RequestOptions) async throws -> Folder
  typealias RewriteHandler =
    @Sendable (RewriteObjectRequest, GoogleGax.RequestOptions) async throws -> RewriteResponse

  private let listBucketsHandlers: Mutex<Deque<ListBucketsHandler>>
  private let renameFolderHandlers: Mutex<Deque<RenameFolderHandler>>
  private let rewriteHandlers: Mutex<Deque<RewriteHandler>>

  init(
    listBuckets: [ListBucketsHandler] = [],
    renameFolder: [RenameFolderHandler] = [],
    rewriteObject: [RewriteHandler] = []
  ) {
    self.listBucketsHandlers = Mutex(Deque(listBuckets))
    self.renameFolderHandlers = Mutex(Deque(renameFolder))
    self.rewriteHandlers = Mutex(Deque(rewriteObject))
  }

  /// Whether all queued RPC handlers have been consumed.
  var isExhausted: Bool {
    listBucketsHandlers.withLock { $0.isEmpty }
      && renameFolderHandlers.withLock { $0.isEmpty }
      && rewriteHandlers.withLock { $0.isEmpty }
  }

  func listBuckets(
    request: ListBucketsRequest, options: GoogleGax.RequestOptions
  ) async throws -> ListBucketsResponse {
    guard let handler = listBucketsHandlers.withLock({ $0.popFirst() }) else {
      throw GoogleGax.RequestError.unimplemented
    }
    return try await handler(request, options)
  }

  func renameFolderPollingUntilDone(
    request: RenameFolderRequest, options: GoogleGax.RequestOptions
  ) async throws -> Folder {
    guard let handler = renameFolderHandlers.withLock({ $0.popFirst() }) else {
      throw GoogleGax.RequestError.unimplemented
    }
    return try await handler(request, options)
  }

  func rewriteObject(
    request: RewriteObjectRequest, options: GoogleGax.RequestOptions
  ) async throws -> RewriteResponse {
    guard let handler = rewriteHandlers.withLock({ $0.popFirst() }) else {
      throw GoogleGax.RequestError.unimplemented
    }
    return try await handler(request, options)
  }
}
