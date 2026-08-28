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
import NIOFoundationCompat

/// A container representing a sequence of bytes backed either by `Foundation.Data`
/// or `NIOCore.ByteBuffer` without unnecessary memory copying.
public struct ByteBuffer: Sendable {
  @usableFromInline
  internal enum Storage: Sendable {
    case data(Data)
    case byteBuffer(NIOCore.ByteBuffer)
  }

  @usableFromInline
  internal let storage: Storage

  // MARK: - Initializers

  /// Creates a byte buffer wrapping a `Foundation.Data` instance (zero-copy).
  @inlinable
  public init(_ data: Data) {
    self.storage = .data(data)
  }

  /// Creates a byte buffer wrapping a `NIOCore.ByteBuffer` instance (zero-copy).
  @inlinable
  public init(_ buffer: NIOCore.ByteBuffer) {
    self.storage = .byteBuffer(buffer)
  }

  /// Creates an empty byte buffer instance.
  @inlinable
  public init() {
    self.storage = .data(Data())
  }

  /// Creates a byte buffer from an array of bytes.
  @inlinable
  public init(_ bytes: [UInt8]) {
    self.storage = .data(Data(bytes))
  }

  /// Creates a byte buffer from a contiguous raw buffer pointer.
  @inlinable
  public init(_ bufferPointer: UnsafeRawBufferPointer) {
    self.storage = .data(Data(bufferPointer))
  }
}

// MARK: - Core Properties & Accessors

extension ByteBuffer {
  /// The total number of readable bytes stored.
  @inlinable
  public var count: Int {
    switch storage {
    case .data(let data):
      return data.count
    case .byteBuffer(let buffer):
      return buffer.readableBytes
    }
  }

  /// Indicates whether the buffer contains zero bytes.
  @inlinable
  public var isEmpty: Bool {
    count == 0
  }

  /// Calls a closure with a pointer to the contiguous bytes without copying.
  @inlinable
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    switch storage {
    case .data(let data):
      return try data.withUnsafeBytes(body)
    case .byteBuffer(let buffer):
      return try buffer.withUnsafeReadableBytes(body)
    }
  }

  /// The underlying contents as a `Foundation.Data` instance.
  ///
  /// - Returns: The original `Data` with zero copies if backed by `Data`,
  ///   or copies the bytes into a new `Data` instance if backed by `NIOCore.ByteBuffer`.
  @inlinable
  public var data: Data {
    switch storage {
    case .data(let data):
      return data
    case .byteBuffer(let buffer):
      return buffer.withUnsafeReadableBytes { Data($0) }
    }
  }

  /// The underlying contents as a `NIOCore.ByteBuffer` instance.
  ///
  /// - Returns: The original `NIOCore.ByteBuffer` with zero copies if backed by `NIOCore.ByteBuffer`,
  ///   or copies the bytes into a new `NIOCore.ByteBuffer` instance if backed by `Data`.
  @inlinable
  public var byteBuffer: NIOCore.ByteBuffer {
    switch storage {
    case .byteBuffer(let buffer):
      return buffer
    case .data(let data):
      return data.withUnsafeBytes { rawBuffer in
        var buf = ByteBufferAllocator().buffer(capacity: rawBuffer.count)
        buf.writeBytes(rawBuffer)
        return buf
      }
    }
  }

  /// Returns the bytes as a newly allocated `[UInt8]` array.
  @inlinable
  public var byteArray: [UInt8] {
    withUnsafeBytes { Array($0) }
  }
}

// MARK: - RandomAccessCollection Conformance

extension ByteBuffer: RandomAccessCollection {
  public typealias Element = UInt8
  public typealias Index = Int

  @inlinable
  public var startIndex: Int { 0 }

  @inlinable
  public var endIndex: Int { count }

  @inlinable
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

extension ByteBuffer: Equatable {
  public static func == (lhs: ByteBuffer, rhs: ByteBuffer) -> Bool {
    guard lhs.count == rhs.count else { return false }
    if lhs.isEmpty { return true }
    return lhs.withUnsafeBytes { lhsBytes in
      rhs.withUnsafeBytes { rhsBytes in
        guard let lhsBase = lhsBytes.baseAddress, let rhsBase = rhsBytes.baseAddress else {
          return lhsBytes.isEmpty && rhsBytes.isEmpty
        }
        return memcmp(lhsBase, rhsBase, lhsBytes.count) == 0
      }
    }
  }
}

extension ByteBuffer: Hashable {
  public func hash(into hasher: inout Hasher) {
    withUnsafeBytes { hasher.combine(bytes: $0) }
  }
}

// MARK: - Literal & Description Conformances

extension ByteBuffer: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: UInt8...) {
    self.init(Data(elements))
  }
}

extension ByteBuffer: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "\(count) bytes"
  }

  public var debugDescription: String {
    let backing: String
    switch storage {
    case .data: backing = "Data"
    case .byteBuffer: backing = "NIOCore.ByteBuffer"
    }
    return "ByteBuffer(\(count) bytes, backing: \(backing))"
  }
}
