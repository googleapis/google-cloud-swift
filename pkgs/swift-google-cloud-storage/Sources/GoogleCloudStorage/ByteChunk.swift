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
import NIOFoundationCompat

/// A container representing a sequence of bytes backed either by `Foundation.Data`
/// or an internal network buffer without unnecessary memory copying.
public struct ByteChunk: Sendable, ContiguousBytes {
  internal enum Storage: Sendable {
    case data(Data)
    case byteBuffer(NIOCore.ByteBuffer)
  }

  internal let storage: Storage

  // MARK: - Initializers

  /// Creates a byte chunk wrapping a `Foundation.Data` instance (zero-copy).
  public init(_ data: Data) {
    self.storage = .data(data)
  }

  /// Creates a byte chunk wrapping a `NIOCore.ByteBuffer` instance (zero-copy).
  internal init(_ buffer: NIOCore.ByteBuffer) {
    self.storage = .byteBuffer(buffer)
  }

  /// Creates an empty byte chunk instance.
  public init() {
    self.storage = .byteBuffer(NIOCore.ByteBuffer())
  }

  /// Creates a byte chunk from an array of bytes.
  public init(_ bytes: [UInt8]) {
    self.storage = .byteBuffer(NIOCore.ByteBuffer(bytes: bytes))
  }

  /// Creates a byte chunk from a contiguous raw buffer pointer.
  // Marked `@safe` to override SE-0458's implicit `@unsafe` inference on `UnsafeRawBufferPointer`:
  // `NIOCore.ByteBuffer(bytes:)` immediately copies `bufferPointer.count` bytes into managed storage.
  @safe
  public init(_ bufferPointer: UnsafeRawBufferPointer) {
    self.storage = .byteBuffer(unsafe NIOCore.ByteBuffer(bytes: bufferPointer))
  }
}

// MARK: - Core Properties & Accessors

extension ByteChunk {
  /// The total number of readable bytes stored.
  public var count: Int {
    switch storage {
    case .data(let data):
      return data.count
    case .byteBuffer(let buffer):
      return buffer.readableBytes
    }
  }

  /// Indicates whether the chunk contains zero bytes.
  @inlinable
  public var isEmpty: Bool {
    count == 0
  }

  /// Calls a closure with a pointer to the contiguous bytes without copying.
  // Marked `@safe` (matching `Array.withUnsafeBytes` in the Swift stdlib) to override SE-0458's
  // implicit `@unsafe` inference from the `UnsafeRawBufferPointer` closure argument: `ByteChunk`
  // owns the backing storage and guarantees the pointer's lifetime and bounds for `body`'s duration.
  @safe
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    switch storage {
    case .data(let data):
      // `Foundation.Data.withUnsafeBytes` is not yet marked `@safe` in `FoundationEssentials`.
      return try unsafe data.withUnsafeBytes(body)
    case .byteBuffer(let buffer):
      // `NIOCore.ByteBuffer.withUnsafeReadableBytes` is not yet marked `@safe` in SwiftNIO.
      return try unsafe buffer.withUnsafeReadableBytes(body)
    }
  }

  /// Executes a closure on the sequence's contiguous storage.
  // Marked `@safe` (matching `Sequence.withContiguousStorageIfAvailable` in the Swift stdlib) because
  // the pointer yielded to `body` is guaranteed valid for the duration of the call.
  @safe
  @inlinable
  public func withContiguousStorageIfAvailable<R>(
    _ body: (UnsafeBufferPointer<UInt8>) throws -> R
  ) rethrows -> R? {
    try withUnsafeBytes { rawBuffer in
      // SAFETY: Rebinding raw bytes to `UInt8` is always trivial and alignment-safe (stride == 1).
      try unsafe rawBuffer.withMemoryRebound(to: UInt8.self) { buffer in
        try unsafe body(buffer)
      }
    }
  }

  /// The underlying contents as a `Foundation.Data` instance.
  ///
  /// - Returns: The original `Data` with zero copies if backed by `Data`, or a `Data` instance
  ///   created via SwiftNIO's automatic byte transfer strategy if backed by an internal network
  ///   buffer (copying buffers up to 256 KiB and sharing underlying buffer storage without copying
  ///   for larger buffers).
  public var data: Data {
    switch storage {
    case .data(let data):
      return data
    case .byteBuffer(let buffer):
      return Data(buffer: buffer)
    }
  }

  /// The underlying contents as a `NIOCore.ByteBuffer` instance.
  ///
  /// - Returns: The original `NIOCore.ByteBuffer` with zero copies if backed by `NIOCore.ByteBuffer`,
  ///   or copies the bytes into a new `NIOCore.ByteBuffer` instance if backed by `Data`.
  internal var byteBuffer: NIOCore.ByteBuffer {
    switch storage {
    case .byteBuffer(let buffer):
      return buffer
    case .data(let data):
      return NIOCore.ByteBuffer(data: data)
    }
  }

  /// Returns a zero-copy sub-chunk within the specified byte range.
  public func subdata(in range: Range<Int>) -> ByteChunk {
    switch storage {
    case .data(let data):
      let start = data.startIndex.advanced(by: range.lowerBound)
      let end = data.startIndex.advanced(by: range.upperBound)
      return ByteChunk(data[start..<end])
    case .byteBuffer(let nioBuffer):
      var copy = nioBuffer
      copy.moveReaderIndex(to: nioBuffer.readerIndex + range.lowerBound)
      if let slice = copy.readSlice(length: range.count) {
        return ByteChunk(slice)
      }
      return ByteChunk()
    }
  }
}

// MARK: - RandomAccessCollection Conformance

extension ByteChunk: RandomAccessCollection {
  public typealias Element = UInt8
  public typealias Index = Int

  @inlinable
  public var startIndex: Int { 0 }

  @inlinable
  public var endIndex: Int { count }

  public subscript(position: Int) -> UInt8 {
    precondition(position >= 0 && position < count, "Index \(position) out of bounds 0..<\(count)")
    switch storage {
    case .data(let data):
      return data[data.startIndex.advanced(by: position)]
    case .byteBuffer(let buffer):
      return buffer.getInteger(at: buffer.readerIndex + position, as: UInt8.self)!
    }
  }
}

// MARK: - Equatable & Hashable

extension ByteChunk: Equatable {
  public static func == (lhs: ByteChunk, rhs: ByteChunk) -> Bool {
    guard lhs.count == rhs.count else { return false }
    if lhs.isEmpty { return true }
    return lhs.withUnsafeBytes { lhsBytes in
      rhs.withUnsafeBytes { rhsBytes in
        guard let lhsBase = lhsBytes.baseAddress, let rhsBase = rhsBytes.baseAddress else {
          // `UnsafeRawBufferPointer.isEmpty` requires `unsafe` because its `Collection` conformance is `@unsafe`.
          return unsafe lhsBytes.isEmpty && rhsBytes.isEmpty
        }
        // SAFETY: `lhs.count == rhs.count` is verified above, and both pointers are non-nil and valid.
        return unsafe memcmp(lhsBase, rhsBase, lhsBytes.count) == 0
      }
    }
  }
}

extension ByteChunk: Hashable {
  @inlinable
  public func hash(into hasher: inout Hasher) {
    // SAFETY: `Hasher.combine(bytes:)` is implicitly `@unsafe` due to its `UnsafeRawBufferPointer` parameter.
    withUnsafeBytes { unsafe hasher.combine(bytes: $0) }
  }
}

// MARK: - Literal & Description Conformances

extension ByteChunk: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: UInt8...) {
    self.init(elements)
  }
}

extension ByteChunk: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "\(count) bytes"
  }

  public var debugDescription: String {
    let backing: String
    switch storage {
    case .data: backing = "Data"
    case .byteBuffer: backing = "NIOCore.ByteBuffer"
    }
    return "ByteChunk(\(count) bytes, backing: \(backing))"
  }
}
