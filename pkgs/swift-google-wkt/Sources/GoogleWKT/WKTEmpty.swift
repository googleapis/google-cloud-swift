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

/// A generic empty message that you can re-use to avoid defining duplicated
/// empty messages in your APIs. A typical example is to use it as the request
/// or the response type of an API method. For instance:
///
///     service Foo {
///       rpc Bar(google.protobuf.Empty) returns (google.protobuf.Empty);
///     }
///
/// The JSON representation for `WKTEmpty` is empty JSON object `{}`.
public struct WKTEmpty: Codable, Equatable, Sendable {
  public init() {}
}

// Makes `WKTEmpty` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `WKTAny`.
extension WKTEmpty: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Empty"
  }

  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeUrl
    }
    if any.fields.isEmpty {
      self = WKTEmpty()
      return
    }
    guard case let .object(v)? = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.invalidValueField
    }
    if !v.isEmpty {
      throw WKTAnyError.invalidValueField
    }
    self = WKTEmpty()
  }

  public func _pack() throws -> WKTStruct {
    return [:]
  }
}
