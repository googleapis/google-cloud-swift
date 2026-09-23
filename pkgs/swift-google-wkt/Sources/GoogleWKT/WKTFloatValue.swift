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

/// Wrapper message for float.
///
/// The JSON representation for FloatValue is JSON number.
public typealias WKTFloatValue = Swift.Float

extension Swift.Float: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.FloatValue"
  }

  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeUrl
    }
    guard let v = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.missingValueField
    }
    guard case let .number(n) = v else {
      throw WKTAnyError.invalidValueField
    }
    self = Float(n)
  }

  public func _pack() throws -> WKTStruct {
    let rounded = Double(String(self)) ?? Double(self)
    return [WKTAny.valueField: WKTValue(number: rounded)]
  }
}
