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

/// Wrapper message for string.
///
/// The JSON representation for StringValue is JSON string.
public typealias WKTStringValue = Swift.String

extension Swift.String: _AnyPackable {
  /// The type URL for `WKTStringValue`: `"type.googleapis.com/google.protobuf.StringValue"`.
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.StringValue"
  }

  /// Initialize an instance of `WKTStringValue` by unpacking from a `WKTAny`.
  ///
  /// - Parameter any: The `WKTAny` instance to unpack.
  /// - Throws: An error if the type URL in `any` does not match `"type.googleapis.com/google.protobuf.StringValue"`,
  ///   or if deserialization fails.
  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeURL
    }
    guard let v = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.missingValueField
    }
    guard case let .string(s) = v else {
      throw WKTAnyError.invalidValueField
    }
    self = s
  }

  /// Packs this `WKTStringValue` into a `WKTStruct` representation.
  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: .string(self)]
  }
}
