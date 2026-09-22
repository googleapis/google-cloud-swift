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
import NIOCore

/// A write object source that wraps an arbitrary AsyncSequence of ByteChunk or Data chunks.
public struct StreamSource: WriteObjectSource {
  private final class StateBox: @unchecked Sendable {
    var nextChunk: () async throws -> NIOCore.ByteBuffer?

    init(nextChunk: @escaping () async throws -> NIOCore.ByteBuffer?) {
      self.nextChunk = nextChunk
    }
  }

  public var totalSize: UInt64? { return totalSizeValue }
  private let totalSizeValue: UInt64?
  private let stateBox: StateBox
  private var buffer = NIOCore.ByteBuffer()

  public init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: UInt64? = nil
  ) where S.Element == ByteChunk {
    self.totalSizeValue = totalSize
    var iterator = sequence.makeAsyncIterator()
    self.stateBox = StateBox {
      guard let next = try await iterator.next() else { return nil }
      return next.byteBuffer
    }
  }

  public init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: UInt64? = nil
  ) where S.Element == Data {
    self.totalSizeValue = totalSize
    var iterator = sequence.makeAsyncIterator()
    self.stateBox = StateBox {
      guard let next = try await iterator.next() else { return nil }
      return ByteChunk(next).byteBuffer
    }
  }

  internal init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: UInt64? = nil
  ) where S.Element == NIOCore.ByteBuffer {
    self.totalSizeValue = totalSize
    var iterator = sequence.makeAsyncIterator()
    self.stateBox = StateBox {
      try await iterator.next()
    }
  }

  public mutating func read(maxBytes: Int) async throws -> ByteChunk? {
    guard maxBytes > 0 else { return nil }
    while buffer.readableBytes < maxBytes {
      guard let nextChunk = try await stateBox.nextChunk() else {
        break
      }
      var next = nextChunk
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
