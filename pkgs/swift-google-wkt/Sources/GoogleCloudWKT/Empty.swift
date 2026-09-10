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
/// The JSON representation for `Empty` is empty JSON object `{}`.
public struct Empty: Codable, Equatable, Sendable {
  public init() {}
}

// Makes `Empty` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `Any`.
extension Empty: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Empty"
  }

  public init(fromAny any: `Any`) throws {
    if Self._anyTypeUrl != any._type {
      throw AnyError.mismatchedTypeUrl
    }
    if any.fields.isEmpty {
      self = Empty()
      return
    }
    guard case let .object(v)? = any.fields[`Any`.valueField] else {
      throw AnyError.invalidValueField
    }
    if !v.isEmpty {
      throw AnyError.invalidValueField
    }
    self = Empty()
  }

  public func _pack() throws -> Struct {
    return [`Any`.valueField: Value(object: [:])]
  }
}
