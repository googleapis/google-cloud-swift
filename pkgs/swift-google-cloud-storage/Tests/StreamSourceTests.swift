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
}
