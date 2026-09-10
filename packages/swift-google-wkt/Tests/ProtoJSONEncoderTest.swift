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
}
