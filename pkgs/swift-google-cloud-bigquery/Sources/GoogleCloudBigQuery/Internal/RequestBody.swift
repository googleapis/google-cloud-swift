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

/// A value written at a JSON path after a request body is encoded.
enum JSONOverride: Sendable, Equatable {
  /// An explicit JSON `null`. On PATCH this clears the field.
  case null
  /// Any JSON value, for example an empty string that the encoder would otherwise keep or drop.
  case value(WKTValue)
}

/// Builds JSON request bodies.
enum RequestBody {
  /// Encodes `wire` with the ProtoJSON encoder, then applies `setting` overrides.
  ///
  /// - Parameters:
  ///   - wire: the generated message to encode. `nil` fields and empty collections are omitted.
  ///   - setting: values to write, keyed by `.`-separated JSON path, for example
  ///     `"labels.env"` or `"externalDataConfiguration.csvOptions.quote"`. Intermediate objects
  ///     are created as needed.
  ///   - omitting: `.`-separated paths of fields to drop, for example proto3 defaults that a
  ///     PATCH must not send.
  static func json(
    _ wire: some Encodable, setting: [String: JSONOverride] = [:], omitting: [String] = []
  ) throws -> Data {
    try Self.json(
      wire,
      settingPaths: Dictionary(
        setting.map { ($0.key.split(separator: ".").map(String.init), $0.value) },
        uniquingKeysWith: { _, last in last }),
      omitting: omitting)
  }

  /// Like ``json(_:setting:omitting:)``, but each override path is given as its segments.
  ///
  /// Use this when a segment may contain `.`, for example a resource tag key such as
  /// `["resourceTags", "example.com:project/env"]`.
  static func json(
    _ wire: some Encodable, settingPaths: [[String]: JSONOverride], omitting: [String] = []
  ) throws -> Data {
    let encoder = _ProtoJSONEncoder()
    let encoded = try encoder.encode(wire, omitting: omitting)
    if settingPaths.isEmpty { return encoded }
    var object = try JSONDecoder().decode(WKTStruct.self, from: encoded)
    for (path, override) in settingPaths {
      let value: WKTValue
      switch override {
      case .null: value = .null(WKTNullValue())
      case .value(let v): value = v
      }
      Self.set(value, at: path[...], in: &object)
    }
    let output = JSONEncoder()
    output.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try output.encode(object)
  }

  private static func set(
    _ value: WKTValue, at path: ArraySlice<String>, in object: inout WKTStruct
  ) {
    guard let key = path.first else { return }
    let rest = path.dropFirst()
    if rest.isEmpty {
      object[key] = value
      return
    }
    var child: WKTStruct
    if case .object(let existing) = object[key] {
      child = existing
    } else {
      child = [:]
    }
    Self.set(value, at: rest, in: &child)
    object[key] = .object(child)
  }
}
