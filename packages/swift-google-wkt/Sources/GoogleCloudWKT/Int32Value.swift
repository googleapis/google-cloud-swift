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

/// Wrapper message for int32.
///
/// The JSON representation for Int32Value is JSON number.
public typealias Int32Value = Swift.Int32

extension Swift.Int32: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Int32Value"
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
    self = Int32(n)
  }

  public func _pack() throws -> Struct {
    return [`Any`.valueField: Value(number: Double(self))]
  }
}
