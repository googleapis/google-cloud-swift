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
@_spi(GoogleCloudInternal) import GoogleWKT

/// Helpers to write wire fixtures as JSON in tests.
enum WireJSON {
  /// Decodes a generated message from ProtoJSON text.
  static func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
    try _ProtoJSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  /// Encodes a generated message and parses it back as a JSON object, for comparisons that do
  /// not depend on key order.
  static func object(_ value: some Encodable) throws -> NSDictionary {
    let data = try _ProtoJSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data) as? NSDictionary ?? [:]
  }

  /// Parses JSON text as an object, for comparison with ``object(_:)``.
  static func object(_ json: String) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary ?? [:]
  }
}
