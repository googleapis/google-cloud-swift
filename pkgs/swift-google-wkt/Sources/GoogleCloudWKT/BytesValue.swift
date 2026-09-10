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

/// Wrapper message for bytes.
///
/// The JSON representation for BytesValue is JSON string (base64 encoded).
public typealias BytesValue = Foundation.Data

extension Foundation.Data: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.BytesValue"
  }

  public init(fromAny any: `Any`) throws {
    if Self._anyTypeUrl != any._type {
      throw AnyError.mismatchedTypeUrl
    }
    guard let v = any.fields[`Any`.valueField] else {
      throw AnyError.missingValueField
    }
    guard case let .string(s) = v else {
      throw AnyError.invalidValueField
    }
    guard let d = Data(base64Encoded: s) else {
      throw AnyError.invalidValueField
    }
    self = d
  }

  public func _pack() throws -> Struct {
    return [`Any`.valueField: Value(string: self.base64EncodedString())]
  }
}
