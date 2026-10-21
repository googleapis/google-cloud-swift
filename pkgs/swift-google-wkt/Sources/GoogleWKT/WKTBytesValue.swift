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
  /// The type URL for `WKTBytesValue`: `"type.googleapis.com/google.protobuf.BytesValue"`.
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.BytesValue"
  }

  /// Initialize an instance of `WKTBytesValue` by unpacking from a `WKTAny`.
  ///
  /// - Parameter any: The `WKTAny` instance to unpack.
  /// - Throws: An error if the type URL in `any` does not match `"type.googleapis.com/google.protobuf.BytesValue"`,
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
    guard let d = decodeProtoBase64(s) else {
      throw WKTAnyError.invalidValueField
    }
    self = d
  }

  /// Packs this `WKTBytesValue` into a `WKTStruct` representation.
  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: .string(self.base64EncodedString())]
  }
}

/// Decodes a Base64 or URL-safe Base64 string, with or without `=` padding, as permitted by the
/// Protobuf JSON Mapping specification for `bytes`.
func decodeProtoBase64(_ input: String) -> Data? {
  var hasStandard = false
  var hasURLSafe = false
  var hasWhitespace = false
  var dataCount = 0
  var padCount = 0

  for byte in input.utf8 {
    switch byte {
    case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"):
      hasWhitespace = true
    case UInt8(ascii: "="):
      padCount += 1
    default:
      if padCount > 0 {
        return nil
      }
      if byte == UInt8(ascii: "+") || byte == UInt8(ascii: "/") {
        hasStandard = true
      } else if byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") {
        hasURLSafe = true
      }
      dataCount += 1
    }
  }

  if hasStandard && hasURLSafe {
    return nil
  }

  let remainder = dataCount % 4
  if remainder == 1 {
    return nil
  }
  let expectedPad = (4 - remainder) % 4
  if padCount != 0 && padCount != expectedPad {
    return nil
  }

  if !hasURLSafe && !hasWhitespace && padCount == expectedPad {
    return Data(base64Encoded: input)
  }

  var bytes: [UInt8] = []
  bytes.reserveCapacity(dataCount + expectedPad)
  for byte in input.utf8 {
    switch byte {
    case UInt8(ascii: "-"):
      bytes.append(UInt8(ascii: "+"))
    case UInt8(ascii: "_"):
      bytes.append(UInt8(ascii: "/"))
    case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
      UInt8(ascii: "="):
      continue
    default:
      bytes.append(byte)
    }
  }
  for _ in 0..<expectedPad {
    bytes.append(UInt8(ascii: "="))
  }

  return Data(base64Encoded: String(decoding: bytes, as: UTF8.self))
}
