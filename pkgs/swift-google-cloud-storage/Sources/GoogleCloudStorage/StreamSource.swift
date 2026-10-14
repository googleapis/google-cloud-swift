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
  private protocol StreamReading: Actor {
    func read(maxBytes: Int) async throws -> ByteChunk?
  }

  private actor SequenceReader<S: AsyncSequence & Sendable>: StreamReading
  where S.Element: Sendable {
    private var iterator: S.AsyncIterator?
    private let toByteBuffer: @Sendable (S.Element) -> NIOCore.ByteBuffer
    private var buffer = NIOCore.ByteBuffer()
    private var isReading = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
      sequence: S,
      toByteBuffer: @escaping @Sendable (S.Element) -> NIOCore.ByteBuffer
    ) {
      self.iterator = sequence.makeAsyncIterator()
      self.toByteBuffer = toByteBuffer
    }

    func read(maxBytes: Int) async throws -> ByteChunk? {
      guard maxBytes > 0 else { return nil }

      while isReading {
        await withCheckedContinuation { continuation in
          waiters.append(continuation)
        }
      }
      isReading = true
      defer {
        isReading = false
        if !waiters.isEmpty {
          let nextWaiter = waiters.removeFirst()
          nextWaiter.resume()
        }
      }

      while buffer.readableBytes < maxBytes {
        guard var iter = iterator else {
          break
        }
        iterator = nil
        let element: S.Element?
        do {
          element = try await iter.next(isolation: self)
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
