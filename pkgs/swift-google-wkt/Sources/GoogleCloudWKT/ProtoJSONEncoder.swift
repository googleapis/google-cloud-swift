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

/// Encodes values using the ProtoJSON mapping.
///
/// The Google Cloud client libraries for Swift use HTTP+JSON as their primary transport.
/// The ProtoJSON encoding differs from typical JSON in a number of ways, including:
/// - Non-number floating point values (NaN, +Inf, -Inf) are represented as strings.
///
/// This encoder configures the native Swift JSON encoder to implement ProtoJSON rules.
@_spi(GoogleCloudInternal) final public class _ProtoJSONEncoder {
  public var outputFormatting: JSONEncoder.OutputFormatting = [.withoutEscapingSlashes]

  public init() {}

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {
    let encoder = JSONEncoder()
    encoder.outputFormatting = self.outputFormatting
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    return try encoder.encode(value)
  }
}
