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

/// Wrapper message for uint64.
///
/// The JSON representation for UInt64Value is JSON number.
public typealias UInt64Value = Swift.UInt64

extension Swift.UInt64: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.UInt64Value"
  }

  public init(fromAny any: `Any`) throws {
    if Self._anyTypeUrl != any._type {
      throw AnyError.mismatchedTypeUrl
    }
    guard let v = any.fields[`Any`.valueField] else {
      throw AnyError.missingValueField
    }
    guard case let .number(n) = v else {
      throw AnyError.invalidValueField
    }
    self = UInt64(n)
  }

  public func _pack() throws -> Struct {
    return [`Any`.valueField: Value(number: Double(self))]
  }
}
