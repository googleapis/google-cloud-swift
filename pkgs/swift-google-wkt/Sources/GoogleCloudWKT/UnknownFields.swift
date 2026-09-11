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

/// Stores unknown fields encountered during JSON (`Codable`) or Protobuf decoding.
///
/// This type is an implementation detail of the Google Cloud client libraries for Swift.
/// Do not use it directly.
@_spi(GoogleCloudInternal)
public struct _UnknownFields: Equatable, Sendable {
  /// Unknown fields encountered during JSON decoding, keyed by JSON field name.
  public var json: [String: Value]

  /// Unknown fields encountered during Protobuf decoding, stored as raw wire-format bytes.
  public var proto: Data

  /// Initialize a new instance of `_UnknownFields`.
  public init(json: [String: Value] = [:], proto: Data = Data()) {
    self.json = json
    self.proto = proto
  }
}

/// A dynamic `CodingKey` used for encoding and decoding unknown JSON fields.
///
/// This type is an implementation detail of the Google Cloud client libraries for Swift.
/// Do not use it directly.
@_spi(GoogleCloudInternal)
public struct _DynamicCodingKey: CodingKey, Hashable, Sendable {
  public var stringValue: String
  public var intValue: Int?

  public init(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  public init?(intValue: Int) {
    self.stringValue = "\(intValue)"
    self.intValue = intValue
  }
}
