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

/// Mock `ReadObjectHandleProtocol` returning preconfigured metadata and streaming chunks.
struct MockReadObjectHandle: ReadObjectHandleProtocol {
  var metadata: ReadObjectMetadata
  var chunks: [ByteChunk]

  var body: any AsyncSequence<ByteChunk, any Error> & Sendable {
    let chunks = self.chunks
    return AsyncThrowingStream { continuation in
      for chunk in chunks {
        continuation.yield(chunk)
      }
      continuation.finish()
    }
  }
}

private struct UnimplementedMockReadObjectHandle: ReadObjectHandleProtocol {}

/// Mock `StorageProtocol` backed by deques of handler closures for seekable writes and reads.
///
/// Each operation pops and invokes the next queued handler from its corresponding deque, or falls
/// back to throwing/returning `GoogleGax.RequestError.unimplemented` if no handler remains. Assert
/// `#expect(mock.isExhausted)` at the end of a test to verify that all queued handlers were
/// consumed.
final class MockStorage: StorageProtocol, Sendable {
  typealias WriteSeekableHandler =
    @Sendable (any SeekableWriteObjectSource, String, String, WriteObjectOptions) async throws ->
    Object
  typealias ReadHandler =
    @Sendable (String, String, ReadObjectOptions) -> any ReadObjectHandleProtocol

  private let writeSeekableHandlers: Mutex<Deque<WriteSeekableHandler>>
  private let readHandlers: Mutex<Deque<ReadHandler>>

  init(
    writeSeekable: [WriteSeekableHandler] = [],
    read: [ReadHandler] = []
  ) {
    self.writeSeekableHandlers = Mutex(Deque(writeSeekable))
    self.readHandlers = Mutex(Deque(read))
  }

  /// Whether all queued write and read handlers have been consumed.
  var isExhausted: Bool {
    writeSeekableHandlers.withLock { $0.isEmpty }
      && readHandlers.withLock { $0.isEmpty }
  }

  func writeObject(
    _ source: some SeekableWriteObjectSource,
    to bucket: String,
    as objectName: String,
    options: WriteObjectOptions
  ) async throws -> Object {
    guard let handler = writeSeekableHandlers.withLock({ $0.popFirst() }) else {
      throw GoogleGax.RequestError.unimplemented
    }
    return try await handler(source, bucket, objectName, options)
  }

  func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions
  ) -> any ReadObjectHandleProtocol {
    guard let handler = readHandlers.withLock({ $0.popFirst() }) else {
      return UnimplementedMockReadObjectHandle()
    }
    return handler(bucket, object, options)
  }
}

/// Mock `StorageProtocol` that only implements the non-seekable `writeObject(_:to:as:options:)`
/// requirement so tests can exercise the protocol extension's default delegation from
/// `SeekableWriteObjectSource` to `WriteObjectSource`.
final class UnseekableMockStorage: StorageProtocol, Sendable {
  typealias WriteHandler =
    @Sendable (any WriteObjectSource, String, String, WriteObjectOptions) async throws -> Object

  private let writeHandlers: Mutex<Deque<WriteHandler>>

  init(write: [WriteHandler] = []) {
    self.writeHandlers = Mutex(Deque(write))
  }

  /// Whether all queued write handlers have been consumed.
  var isExhausted: Bool {
    writeHandlers.withLock { $0.isEmpty }
  }

  func writeObject(
    _ source: some WriteObjectSource,
    to bucket: String,
    as objectName: String,
    options: WriteObjectOptions
  ) async throws -> Object {
    guard let handler = writeHandlers.withLock({ $0.popFirst() }) else {
      throw GoogleGax.RequestError.unimplemented
    }
    return try await handler(source, bucket, objectName, options)
  }
}
