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

/// A wrapper class to support recursive structures in Swift.
///
/// Classes are reference types, so they break reference cycles and prevent the
/// compiler error "value type has infinite size".
public final class Recursive<T: Codable & Sendable>: Codable, Sendable {
  /// The wrapped recursive value stored inside this reference container.
  public let value: T

  /// Creates a new reference wrapper for the specified recursive value.
  ///
  /// - Parameter value: The recursive value to wrap.
  public init(value: T) {
    self.value = value
  }

  /// Decodes a wrapped recursive value from the given decoder.
  ///
  /// This initializer decodes the wrapped value directly from the decoder,
  /// preserving the transparent ProtoJSON representation of the wrapped type.
  ///
  /// - Parameter decoder: The decoder to read data from.
  /// - Throws: An error if decoding fails.
  public init(from decoder: Decoder) throws {
    self.value = try T(from: decoder)
  }

  /// Encodes the wrapped recursive value into the given encoder.
  ///
  /// This method encodes the wrapped value directly into the encoder,
  /// preserving the transparent ProtoJSON representation of the wrapped type.
  ///
  /// - Parameter encoder: The encoder to write data to.
  /// - Throws: An error if encoding fails.
  public func encode(to encoder: Encoder) throws {
    try value.encode(to: encoder)
  }
}

extension Recursive: Equatable where T: Equatable {
  public static func == (lhs: Recursive<T>, rhs: Recursive<T>) -> Bool {
    return lhs.value == rhs.value
  }
}
