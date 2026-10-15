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
import Testing

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

  deinit {
    #expect(writeSeekableHandlers.withLock { $0.isEmpty })
    #expect(readHandlers.withLock { $0.isEmpty })
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

final class UnseekableMockStorage: StorageProtocol, Sendable {
  typealias WriteHandler =
    @Sendable (any WriteObjectSource, String, String, WriteObjectOptions) async throws -> Object

  private let writeHandlers: Mutex<Deque<WriteHandler>>

  init(write: [WriteHandler] = []) {
    self.writeHandlers = Mutex(Deque(write))
  }

  deinit {
    #expect(writeHandlers.withLock { $0.isEmpty })
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
