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
@testable import GoogleCloudStorage
import NIOCore
import Testing

@Suite struct StreamSourceTests {
  /// Tests reading from an AsyncStream of ByteChunk.
  @Test func readByteChunkSequence() async throws {
    let stream = AsyncStream<ByteChunk> { continuation in
      continuation.yield(ByteChunk([1, 2, 3]))
      continuation.yield(ByteChunk([4, 5, 6, 7]))
      continuation.finish()
    }

    var source = StreamSource(sequence: stream, totalSize: 7)
    #expect(source.totalSize == 7)

    let chunk1 = try await source.read(maxBytes: 2)
    #expect(chunk1 == [1, 2])

    let chunk2 = try await source.read(maxBytes: 3)
    #expect(chunk2 == [3, 4, 5])

    let chunk3 = try await source.read(maxBytes: 10)
    #expect(chunk3 == [6, 7])

    let chunk4 = try await source.read(maxBytes: 10)
    #expect(chunk4 == nil)
  }

  /// Tests reading from an AsyncStream of Foundation.Data.
  @Test func readDataSequence() async throws {
    let stream = AsyncStream<Data> { continuation in
      continuation.yield(Data([10, 20]))
      continuation.yield(Data([30, 40, 50]))
      continuation.finish()
    }

    var source = StreamSource(sequence: stream)
    #expect(source.totalSize == nil)

    let chunk1 = try await source.read(maxBytes: 4)
    #expect(chunk1 == [10, 20, 30, 40])

    let chunk2 = try await source.read(maxBytes: 4)
    #expect(chunk2 == [50])

    let chunk3 = try await source.read(maxBytes: 4)
    #expect(chunk3 == nil)
  }

  /// Tests reading from an AsyncStream of NIOCore.ByteBuffer.
  @Test func readNIOByteBufferSequence() async throws {
    let stream = AsyncStream<NIOCore.ByteBuffer> { continuation in
      var buf = NIOCore.ByteBuffer()
      buf.writeBytes([100, 101, 102])
      continuation.yield(buf)
      continuation.finish()
    }

    var source = StreamSource(sequence: stream, totalSize: 3)
    #expect(source.totalSize == 3)

    let chunk = try await source.read(maxBytes: 10)
    #expect(chunk == [100, 101, 102])

    let next = try await source.read(maxBytes: 10)
    #expect(next == nil)
  }

  /// Tests reading from an empty sequence.
  @Test func emptySequence() async throws {
    let stream = AsyncStream<Data> { continuation in
      continuation.finish()
    }

    var source = StreamSource(sequence: stream)
    let chunk = try await source.read(maxBytes: 10)
    #expect(chunk == nil)
  }

  /// Tests that an error thrown by the underlying sequence is wrapped in WriteObjectSourceError.readFailed.
  @Test func throwingSequenceThrowsReadFailed() async throws {
    struct CustomStreamError: Error {}
    let stream = AsyncThrowingStream<Data, any Error> { continuation in
      continuation.finish(throwing: CustomStreamError())
    }

    var source = StreamSource(sequence: stream)
    let err = await expectError(WriteObjectSourceError.self) {
      _ = try await source.read(maxBytes: 10)
    }
    if case .readFailed(let underlying) = err {
      #expect(underlying is CustomStreamError)
    } else {
      Issue.record("Expected WriteObjectSourceError.readFailed, got \(String(describing: err))")
    }
  }

  /// Tests that copying a StreamSource shares buffered unread bytes as well as the underlying iterator.
  @Test func copySharesBufferedState() async throws {
    let stream = AsyncStream<ByteChunk> { continuation in
      continuation.yield(ByteChunk([1, 2, 3, 4]))
      continuation.yield(ByteChunk([5, 6]))
      continuation.finish()
    }

    var sourceA = StreamSource(sequence: stream)
    let first = try await sourceA.read(maxBytes: 2)
    #expect(first == [1, 2])

    // Copy after sourceA has buffered [3, 4].
    var sourceB = sourceA
    let second = try await sourceB.read(maxBytes: 3)
    #expect(second == [3, 4, 5])

    let third = try await sourceA.read(maxBytes: 10)
    #expect(third == [6])

    let fourth = try await sourceB.read(maxBytes: 10)
    #expect(fourth == nil)
  }

  /// Tests that concurrent reads on copies of a StreamSource are serialized without data races or lost bytes.
  @Test func concurrentReadsAreSerialized() async throws {
    let chunkCount = 50
    let bytesPerChunk = 16
    let expectedBytes = (0..<(chunkCount * bytesPerChunk)).map { UInt8($0 & 0xFF) }

    let stream = AsyncStream<ByteChunk> { continuation in
      for i in 0..<chunkCount {
        let start = i * bytesPerChunk
        let slice = Array(expectedBytes[start..<(start + bytesPerChunk)])
        continuation.yield(ByteChunk(slice))
      }
      continuation.finish()
    }

    let source = StreamSource(sequence: stream, totalSize: UInt64(expectedBytes.count))

    let collectedChunks = try await withThrowingTaskGroup(of: [[UInt8]].self) { group in
      for _ in 0..<8 {
        group.addTask {
          var localSource = source
          var readChunks: [[UInt8]] = []
          while let chunk = try await localSource.read(maxBytes: 7) {
            readChunks.append(Array(chunk))
          }
          return readChunks
        }
      }

      var all: [UInt8] = []
      for try await workerChunks in group {
        for chunk in workerChunks {
          all.append(contentsOf: chunk)
        }
      }
      return all
    }

    #expect(collectedChunks.count == expectedBytes.count)
    #expect(collectedChunks.sorted() == expectedBytes.sorted())
  }

  /// Tests that a cancelled task waiting in the queue throws CancellationError without consuming from the sequence.
  @Test func cancelledWaiterThrowsAndPreservesStream() async throws {
    let (stream, continuation) = AsyncStream<ByteChunk>.makeStream()
    let source = StreamSource(sequence: stream)

    // Start first read which will suspend waiting for elements from `stream`.
    let firstTask = Task {
      var s = source
      return try await s.read(maxBytes: 4)
    }

    // Give firstTask a moment to enter `read` and suspend on `iter.next()`.
    try await Task.sleep(for: .milliseconds(20))

    // Start second read which will queue in `waiters`, then cancel it.
    let secondTask = Task {
      var s = source
      return try await s.read(maxBytes: 4)
    }
    try await Task.sleep(for: .milliseconds(20))
    secondTask.cancel()

    // Yield 8 bytes and finish.
    continuation.yield(ByteChunk([1, 2, 3, 4, 5, 6, 7, 8]))
    continuation.finish()

    let chunk1 = try await firstTask.value
    #expect(chunk1 == [1, 2, 3, 4])

    await #expect(throws: CancellationError.self) {
      _ = try await secondTask.value
    }

    // Subsequent read should still receive the remaining [5, 6, 7, 8].
    var remainingSource = source
    let chunk2 = try await remainingSource.read(maxBytes: 4)
    #expect(chunk2 == [5, 6, 7, 8])
  }
}
