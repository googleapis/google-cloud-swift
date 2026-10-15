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

  /// Tests that CancellationError thrown by the underlying sequence is rethrown directly without wrapping.
  @Test func cancellationErrorIsRethrownDirectly() async throws {
    let stream = AsyncThrowingStream<Data, any Error> { continuation in
      continuation.finish(throwing: CancellationError())
    }

    var source = StreamSource(sequence: stream)
    await #expect(throws: CancellationError.self) {
      _ = try await source.read(maxBytes: 10)
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

  /// Tests that overlapping concurrent reads on copies of a StreamSource are rejected while preserving the active read.
  @Test func concurrentReadThrowsErrorAndPreservesActiveRead() async throws {
    let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()
    let (dataStream, dataContinuation) = AsyncStream<ByteChunk>.makeStream()

    struct SignalingSequence: AsyncSequence, Sendable {
      typealias Element = ByteChunk
      let enteredContinuation: AsyncStream<Void>.Continuation
      let dataStream: AsyncStream<ByteChunk>

      struct AsyncIterator: AsyncIteratorProtocol {
        var enteredContinuation: AsyncStream<Void>.Continuation?
        var inner: AsyncStream<ByteChunk>.AsyncIterator

        @concurrent mutating func next() async -> ByteChunk? {
          enteredContinuation?.yield()
          enteredContinuation?.finish()
          enteredContinuation = nil
          return await inner.next()
        }
      }

      func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
          enteredContinuation: enteredContinuation,
          inner: dataStream.makeAsyncIterator()
        )
      }
    }

    let source = StreamSource(
      sequence: SignalingSequence(
        enteredContinuation: enteredContinuation,
        dataStream: dataStream
      )
    )

    // Start first read and wait until it is deterministically suspended inside `next()`.
    let firstTask = Task {
      var s = source
      return try await s.read(maxBytes: 4)
    }
    var enteredIter = enteredStream.makeAsyncIterator()
    _ = await enteredIter.next()

    // A second concurrent read while `firstTask` is in flight should fail immediately.
    var secondCopy = source
    let err = await expectError(WriteObjectSourceError.self) {
      _ = try await secondCopy.read(maxBytes: 4)
    }
    if case .readFailed(let underlying) = err {
      #expect(underlying is StreamSourceConcurrentReadError)
    } else {
      Issue.record("Expected WriteObjectSourceError.readFailed, got \(String(describing: err))")
    }

    // Now yield 8 bytes and finish `dataStream`.
    dataContinuation.yield(ByteChunk([1, 2, 3, 4, 5, 6, 7, 8]))
    dataContinuation.finish()

    let chunk1 = try await firstTask.value
    #expect(chunk1 == [1, 2, 3, 4])

    // Subsequent sequential read should still receive the remaining [5, 6, 7, 8].
    let chunk2 = try await secondCopy.read(maxBytes: 4)
    #expect(chunk2 == [5, 6, 7, 8])
  }
}
