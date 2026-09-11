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
import Testing
@_spi(GoogleCloudInternal) import GoogleCloudWKT

@Suite struct ProtoJSONEncoderTest {
  struct FloatModel: Codable, Equatable {
    var floatVal: Float32
    var doubleVal: Float64
    var url: String
  }

  @Test func encodeNonConformingFloats() throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let model = FloatModel(
      floatVal: .nan,
      doubleVal: .infinity,
      url: "https://example.com/foo/bar"
    )
    let data = try encoder.encode(model)
    let jsonString = try #require(String(data: data, encoding: .utf8))

    #expect(
      jsonString
        == #"{"doubleVal":"Infinity","floatVal":"NaN","url":"https://example.com/foo/bar"}"#
    )

    let negModel = FloatModel(
      floatVal: -.infinity,
      doubleVal: -.infinity,
      url: "test/url"
    )
    let negData = try encoder.encode(negModel)
    let negJson = try #require(String(data: negData, encoding: .utf8))
    #expect(
      negJson
        == #"{"doubleVal":"-Infinity","floatVal":"-Infinity","url":"test/url"}"#
    )
  }

  @Test func roundtripWithProtoJSONDecoder() throws {
    let encoder = _ProtoJSONEncoder()
    let decoder = _ProtoJSONDecoder()

    let model = FloatModel(
      floatVal: 3.14,
      doubleVal: .infinity,
      url: "https://example.com/test"
    )
    let data = try encoder.encode(model)
    let decoded = try decoder.decode(FloatModel.self, from: data)
    #expect(decoded == model)
  }

  struct Int64Model: Codable, Equatable {
    var singular: Int64
    var option: Int64?
    var repeated: [Int64]
    var mapValue: [String: Int64]
    var uint64Val: UInt64
    var uint64Option: UInt64?
    var uint64Repeated: [UInt64]
    var uint64Map: [String: UInt64]
  }

  @Test func encode64BitIntegers() throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let model = Int64Model(
      singular: 42,
      option: 123,
      repeated: [1, 2, 3],
      mapValue: ["key": 99],
      uint64Val: 42,
      uint64Option: 123,
      uint64Repeated: [1, 2, 3],
      uint64Map: ["key": 99]
    )
    let data = try encoder.encode(model)
    let jsonString = try #require(String(data: data, encoding: .utf8))
    #expect(
      jsonString
        == #"{"mapValue":{"key":"99"},"option":"123","repeated":["1","2","3"],"singular":"42","uint64Map":{"key":"99"},"uint64Option":"123","uint64Repeated":["1","2","3"],"uint64Val":"42"}"#
    )

    let decoder = _ProtoJSONDecoder()
    let decoded = try decoder.decode(Int64Model.self, from: data)
    #expect(decoded == model)
  }

  @Test func encode64BitIntegersMinMax() throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let model = Int64Model(
      singular: Int64.min,
      option: Int64.max,
      repeated: [Int64.min, 0, Int64.max],
      mapValue: ["min": Int64.min, "max": Int64.max],
      uint64Val: UInt64.min,
      uint64Option: UInt64.max,
      uint64Repeated: [UInt64.min, UInt64.max],
      uint64Map: ["min": UInt64.min, "max": UInt64.max]
    )
    let data = try encoder.encode(model)
    let jsonString = try #require(String(data: data, encoding: .utf8))
    #expect(
      jsonString
        == #"{"mapValue":{"max":"9223372036854775807","min":"-9223372036854775808"},"option":"9223372036854775807","repeated":["-9223372036854775808","0","9223372036854775807"],"singular":"-9223372036854775808","uint64Map":{"max":"18446744073709551615","min":"0"},"uint64Option":"18446744073709551615","uint64Repeated":["0","18446744073709551615"],"uint64Val":"0"}"#
    )

    let decoder = _ProtoJSONDecoder()
    let decoded = try decoder.decode(Int64Model.self, from: data)
    #expect(decoded == model)
  }
}
