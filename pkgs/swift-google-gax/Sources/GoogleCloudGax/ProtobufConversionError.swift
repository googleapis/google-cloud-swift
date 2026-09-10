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

public enum ProtobufConversionError: Error, CustomStringConvertible, Sendable, Equatable {
  /// Thrown when an unknown string enum value is serialized back to binary protobuf raw value.
  case noIntegerValue(enumType: String, stringValue: String)

  /// Thrown when a type URL wrapped in an Any message is unrecognized by the type registry.
  case unknownTypeUrl(typeUrl: String)

  public var description: String {
    switch self {
    case .noIntegerValue(let enumType, let stringValue):
      return
        "Cannot convert native enum \(enumType) to Protobuf: unknown string value '\(stringValue)' has no corresponding integer value."
    case .unknownTypeUrl(let typeUrl):
      return
        "Cannot convert Any message: type URL '\(typeUrl)' is not registered with SwiftProtobuf."
    }
  }
}
