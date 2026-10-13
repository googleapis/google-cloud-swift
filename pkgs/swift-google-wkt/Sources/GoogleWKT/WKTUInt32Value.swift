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

/// Wrapper message for uint32.
///
/// The JSON representation for UInt32Value is JSON number.
public typealias WKTUInt32Value = Swift.UInt32

extension Swift.UInt32: _AnyPackable {
  /// The type URL for `WKTUInt32Value`: `"type.googleapis.com/google.protobuf.UInt32Value"`.
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.UInt32Value"
  }

  /// Initialize an instance of `WKTUInt32Value` by unpacking from a `WKTAny`.
  ///
  /// - Parameter any: The `WKTAny` instance to unpack.
  /// - Throws: An error if the type URL in `any` does not match `"type.googleapis.com/google.protobuf.UInt32Value"`,
  ///   or if deserialization fails.
  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeURL
    }
    guard let v = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.missingValueField
    }
    switch v {
    case .number(let n):
      guard let n = UInt32(exactly: n) else {
        throw WKTAnyError.invalidValueField
      }
      self = n
    case .string(let s):
      guard let n = UInt32(s) else {
        throw WKTAnyError.invalidValueField
      }
      self = n
    default:
      throw WKTAnyError.invalidValueField
    }
  }

  /// Packs this `WKTUInt32Value` into a `WKTStruct` representation.
  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: .number(Double(self))]
  }
}
