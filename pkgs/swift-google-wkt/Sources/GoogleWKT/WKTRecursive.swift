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

/// A wrapper to support recursive structures in Swift.
///
/// Swift value types cannot (directly or indirectly) contain themselves: the
/// compiler must compute their size, and the size of such a type would be
/// infinite. This wrapper stores the value in a heap-allocated box. The box is
/// a class, i.e. a reference type, and always has the size of a pointer. That
/// breaks the cycle in the type layout and prevents the compiler error "value
/// type has infinite size".
///
/// `WKTRecursive` itself is a `struct`, with the box as its only stored
/// property. It preserves value semantics via copy-on-write: mutating `value`
/// mutates the box in place when this is the only reference to it, and
/// otherwise copies the box first. Copies of a `WKTRecursive` therefore never
/// observe each other's mutations, and `value` can be declared `var`,
/// supporting in-place mutation such as:
///
/// ```swift
/// var schema = Schema()
/// schema.items = WKTRecursive(value: Schema())
/// schema.items?.value.type = .string
/// ```
public struct WKTRecursive<T: Codable & Sendable>: Codable, Sendable {
  /// The heap-allocated box holding the wrapped value.
  ///
  /// This class is `@unchecked Sendable` because the compiler cannot verify
  /// the copy-on-write discipline. It is safe because (a) `T` is `Sendable`,
  /// and (b) `value` is only mutated when `isKnownUniquelyReferenced()`
  /// returns `true`, i.e. only when no other value (and therefore no other
  /// isolation domain) can observe the box.
  private final class Storage: @unchecked Sendable {
    var value: T

    init(_ value: T) {
      self.value = value
    }
  }

  private var storage: Storage

  /// The wrapped recursive value.
  public var value: T {
    get { storage.value }
    set {
      if isKnownUniquelyReferenced(&storage) {
        storage.value = newValue
      } else {
        storage = Storage(newValue)
      }
    }
    // Yields the wrapped value in place. Without this accessor, mutations such
    // as `schema.items?.value.type = .string` read a full copy of the wrapped
    // value, mutate the copy, and then write it back.
    _modify {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage.value)
      }
      yield &storage.value
    }
  }

  /// Creates a new wrapper for the specified recursive value.
  ///
  /// - Parameter value: The recursive value to wrap.
  public init(value: T) {
    self.storage = Storage(value)
  }

  /// Decodes a wrapped recursive value from the given decoder.
  ///
  /// This initializer decodes the wrapped value directly from the decoder,
  /// preserving the transparent ProtoJSON representation of the wrapped type.
  ///
  /// - Parameter decoder: The decoder to read data from.
  /// - Throws: An error if decoding fails.
  public init(from decoder: Decoder) throws {
    self.storage = Storage(try T(from: decoder))
  }

  /// Encodes the wrapped recursive value into the given encoder.
  ///
  /// This method encodes the wrapped value directly into the encoder,
  /// preserving the transparent ProtoJSON representation of the wrapped type.
  ///
  /// - Parameter encoder: The encoder to write data to.
  /// - Throws: An error if encoding fails.
  public func encode(to encoder: Encoder) throws {
    try storage.value.encode(to: encoder)
  }
}

extension WKTRecursive: Equatable where T: Equatable {
  public static func == (lhs: WKTRecursive<T>, rhs: WKTRecursive<T>) -> Bool {
    return lhs.value == rhs.value
  }
}
