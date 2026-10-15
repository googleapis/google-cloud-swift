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
import Synchronization
import Testing

/// Mock `SeekableWriteObjectSource` backed by deques of closures for `read` and `seek`.
///
/// Each `read(maxBytes:)` or `seek(to:)` call pops and invokes the next queued handler from its
/// corresponding deque, or throws `MockError.empty` if no handler remains. Call `verify()` at the
/// end of a test to assert that all queued read and seek handlers were consumed.
final class MockUploadSource: SeekableWriteObjectSource, Sendable {
  typealias ReadHandler = @Sendable (Int) async throws -> ByteChunk?
  typealias SeekHandler = @Sendable (UInt64) async throws -> Void

  enum MockError: Error, Sendable {
    case empty
  }

  let totalSize: UInt64?
  private let readHandlers: Mutex<Deque<ReadHandler>>
  private let seekHandlers: Mutex<Deque<SeekHandler>>

  init(
    totalSize: UInt64? = nil,
    read: [ReadHandler] = [],
    seek: [SeekHandler] = []
  ) {
    self.totalSize = totalSize
    self.readHandlers = Mutex(Deque(read))
    self.seekHandlers = Mutex(Deque(seek))
  }

  /// Asserts that all queued `read` and `seek` handlers have been consumed.
  func verify(sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(readHandlers.withLock { $0.isEmpty }, sourceLocation: sourceLocation)
    #expect(seekHandlers.withLock { $0.isEmpty }, sourceLocation: sourceLocation)
  }

  func read(maxBytes: Int) async throws -> ByteChunk? {
    guard let handler = readHandlers.withLock({ $0.popFirst() }) else {
      throw MockError.empty
    }
    return try await handler(maxBytes)
  }

  func seek(to offset: UInt64) async throws {
    guard let handler = seekHandlers.withLock({ $0.popFirst() }) else {
      throw MockError.empty
    }
    try await handler(offset)
  }
}
