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

public import Foundation
import NIOCore

/// A write object source that wraps an arbitrary AsyncSequence of ByteChunk or Data chunks.
public struct StreamSource: WriteObjectSource {
  /// Type-erased actor interface so `StreamSource` does not need a generic parameter for the underlying sequence.
  private protocol StreamReading: Actor {
    func read(maxBytes: Int) async throws -> ByteChunk?
  }

  /// Actor that owns both the sequence iterator and the unread byte buffer.
  ///
  /// Storing both in a single reference-typed actor ensures that copying a `StreamSource` value
  /// shares the buffered unread bytes as well as the iterator, while actor isolation protects
  /// against concurrent data races.
  private actor SequenceReader<S: AsyncSequence & Sendable>: StreamReading
  where S.Element: Sendable {
    private var iterator: S.AsyncIterator?
    private let toByteBuffer: @Sendable (S.Element) -> NIOCore.ByteBuffer
    private var buffer = NIOCore.ByteBuffer()
    private var isReading = false
    private var nextWaiterID: UInt64 = 0
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Void, Never>)] = []

    init(
      sequence: S,
      toByteBuffer: @escaping @Sendable (S.Element) -> NIOCore.ByteBuffer
    ) {
      self.iterator = sequence.makeAsyncIterator()
      self.toByteBuffer = toByteBuffer
    }

    private func cancelWaiter(id: UInt64) {
      if let index = waiters.firstIndex(where: { $0.id == id }) {
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume()
      }
    }

    func read(maxBytes: Int) async throws -> ByteChunk? {
      guard maxBytes > 0 else { return nil }

      // Swift actors are reentrant across suspension points (`await iter.next(isolation: self)`).
      // Queue concurrent callers in FIFO order so only one read operation pulls from the iterator
      // and mutates `buffer` at a time, while still allowing queued callers to exit early if cancelled.
      while isReading {
        try Task.checkCancellation()
        let waiterID = nextWaiterID
        nextWaiterID &+= 1
        await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            if Task.isCancelled {
              continuation.resume()
            } else {
              waiters.append((id: waiterID, continuation: continuation))
            }
          }
        } onCancel: {
          Task {
            await self.cancelWaiter(id: waiterID)
          }
        }
      }
      isReading = true
      defer {
        isReading = false
        if !waiters.isEmpty {
          let nextWaiter = waiters.removeFirst()
          nextWaiter.continuation.resume()
        }
      }
      try Task.checkCancellation()

      // Reclaim already-read prefix bytes before appending new chunks. Doing this here (rather than
      // unconditionally right after `readSlice` while `slice` is still in scope) avoids triggering a
      // Copy-on-Write reallocation when there are unread bytes remaining in `buffer`.
      if buffer.readableBytes < maxBytes {
        buffer.discardReadBytes()
      }
      while buffer.readableBytes < maxBytes {
        // Move `iterator` into a local variable before suspending so actor property exclusivity is
        // preserved across `await`. Leave `self.iterator` as `nil` until a non-nil element is produced
        // so that exhaustion (`nil`) or a thrown error permanently terminates future reads.
        guard var iter = iterator else {
          break
        }
        iterator = nil
        let element: S.Element?
        do {
          element = try await iter.next(isolation: self)
        } catch let error as CancellationError {
          throw error
        } catch let error as WriteObjectSourceError {
          throw error
        } catch {
          throw WriteObjectSourceError.readFailed(underlyingError: error)
        }
        guard let element else {
          break
        }
        iterator = iter
        var next = toByteBuffer(element)
        buffer.writeBuffer(&next)
      }

      guard buffer.readableBytes > 0 else {
        return nil
      }

      let chunkSize = min(maxBytes, buffer.readableBytes)
      guard let slice = buffer.readSlice(length: chunkSize) else {
        return nil
      }
      // When the buffer is completely drained, `discardReadBytes()` resets `readerIndex` and
      // `writerIndex` to 0 in O(1) without checking storage uniqueness or reallocating.
      if buffer.readableBytes == 0 {
        buffer.discardReadBytes()
      }
      return ByteChunk(slice)
    }
  }

  public var totalSize: UInt64? { return totalSizeValue }
  private let totalSizeValue: UInt64?
  private let reader: any StreamReading

  public init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: UInt64? = nil
  ) where S.Element == ByteChunk {
    self.totalSizeValue = totalSize
    self.reader = SequenceReader(sequence: sequence) { $0.byteBuffer }
  }

  public init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: UInt64? = nil
  ) where S.Element == Data {
    self.totalSizeValue = totalSize
    self.reader = SequenceReader(sequence: sequence) { ByteChunk($0).byteBuffer }
  }

  internal init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: UInt64? = nil
  ) where S.Element == NIOCore.ByteBuffer {
    self.totalSizeValue = totalSize
    self.reader = SequenceReader(sequence: sequence) { $0 }
  }

  public mutating func read(maxBytes: Int) async throws -> ByteChunk? {
    try await reader.read(maxBytes: maxBytes)
  }
}
