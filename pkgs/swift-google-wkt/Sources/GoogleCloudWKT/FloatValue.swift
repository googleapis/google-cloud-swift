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

/// Wrapper message for float.
///
/// The JSON representation for FloatValue is JSON number.
public typealias FloatValue = Swift.Float

extension Swift.Float: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.FloatValue"
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
    self = Float(n)
  }

  public func _pack() throws -> Struct {
    let rounded = Double(String(format: "%g", self)) ?? Double(self)
    return [`Any`.valueField: Value(number: rounded)]
  }
}
