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

/// An error that occurs when extracting messages from an ``Any``.
public enum AnyError: Error {
  /// The typeUrl of the message does not match the contents in the `Any`.
  ///
  /// Each `Any` carries a field indicating the type URL of its contents. This error indicates that
  /// the caller attempted to extract a message from the `Any` that has a different type URL from
  /// the contents of the Any itself.
  case mismatchedTypeUrl

  /// The @type field in a nested `Any` is missing or invalid.
  ///
  /// It is possible to store `Any` into an `Any`. This error indicates that the nested `@type`
  /// field for the inner `Any` contents was missing or was not a JSON string.
  case invalidNestedAnyType

  /// The message is encoded as a JSON string but the `value` field is missing.
  ///
  /// Some messages, notably many well-known types, are JSON encoded to strings. When stored in an
  /// `Any`, such messages are stored as:
  ///
  ///     {"@type": "<typeUrl>", "value": "<encoded-JSON-string-value>"}
  ///
  /// For example, a ``Duration`` of 123.45s would be encoded as:
  ///
  ///     {"@type": "type.googleapis.com/google.protobuf.Duration", "value": "123.45s"}
  ///
  /// This error indicates that the `value` field is missing.

  case missingValueField
  /// The message is encoded as a JSON string but the `value` field is not a string.
  ///
  /// Some messages, notably many well-known types, are JSON encoded to strings. When stored in an
  /// `Any`, such messages are stored as:
  ///
  ///     {"@type": "<typeUrl>", "value": "<encoded-JSON-string-value>"}
  ///
  /// For example, a ``Duration`` of 123.45s would be encoded as:
  ///
  ///     {"@type": "type.googleapis.com/google.protobuf.Duration", "value": "123.45s"}
  ///
  /// This error indicates that the `value` field is present, but it is not of string type.
  case invalidValueField
}
