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

/// Wrapper message for bytes.
///
/// The JSON representation for BytesValue is JSON string (base64 encoded).
public typealias WKTBytesValue = Foundation.Data

extension Foundation.Data: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.BytesValue"
  }

  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeUrl
    }
    guard let v = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.missingValueField
    }
    guard case let .string(s) = v else {
      throw WKTAnyError.invalidValueField
    }
    guard let d = Data(base64Encoded: s) else {
      throw WKTAnyError.invalidValueField
    }
    self = d
  }

  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: WKTValue(string: self.base64EncodedString())]
  }
}
