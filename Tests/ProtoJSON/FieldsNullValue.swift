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
@_spi(GoogleCloudInternal) import GoogleWKT

@Suite struct FieldsNullValue {
  typealias T = MessageWithNullValue

  @Test(
    "NullValue fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular":null}"#, T()),
      (#"{"optional":null}"#, T().with { $0.optional = WKTNullValue() }),
      (#"{}"#, T()),
      (#"{"repeated":[null]}"#, T().with { $0.repeated = [WKTNullValue()] }),
      (#"{}"#, T()),
      (#"{"map":{"a":null}}"#, T().with { $0.map = ["a": WKTNullValue()] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "NullValue fields serialize",
    arguments: [
      (#"{"singular":null}"#, T()),
      (
        #"{"optional":null,"singular":null}"#,
        T().with { $0.optional = WKTNullValue() }
      ),
      (
        #"{"repeated":[null],"singular":null}"#,
        T().with { $0.repeated = [WKTNullValue()] }
      ),
      (
        #"{"map":{"a":null},"singular":null}"#,
        T().with { $0.map = ["a": WKTNullValue()] }
      ),
    ]
  )
  func serialize(want: String, input: T) throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == want)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(T.self, from: data)
    #expect(input == roundtrip)
  }

  @Test(
    "NullValue fields reject non-null values",
    arguments: [
      #"{"singular":42}"#,
      #"{"singular":"NULL_VALUE"}"#,
      #"{"optional":42}"#,
      #"{"repeated":[42]}"#,
      #"{"map":{"a":42}}"#,
    ]
  )
  func rejectNonNull(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    #expect(throws: DecodingError.self) {
      _ = try decoder.decode(T.self, from: Data(input.utf8))
    }
    let jsonDecoder = JSONDecoder()
    #expect(throws: DecodingError.self) {
      _ = try jsonDecoder.decode(T.self, from: Data(input.utf8))
    }
  }

  @Test(
    "NullValue fields roundtrip through WKTAny",
    arguments: [
      T(),
      T().with { $0.optional = WKTNullValue() },
    ]
  )
  func anyRoundtrip(input: T) throws {
    let any = try WKTAny(fromMessage: input)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(any)
    let decoder = _ProtoJSONDecoder()
    let decodedAny = try decoder.decode(WKTAny.self, from: data)
    let roundtrip = try T(fromAny: decodedAny)
    #expect(roundtrip == input)
  }

  @Test(
    "NullValue fields decode and roundtrip with Foundation JSONDecoder",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular":null}"#, T()),
      (#"{"optional":null}"#, T().with { $0.optional = WKTNullValue() }),
      (#"{"repeated":[null]}"#, T().with { $0.repeated = [WKTNullValue()] }),
      (#"{"map":{"a":null}}"#, T().with { $0.map = ["a": WKTNullValue()] }),
    ]
  )
  func foundationJSONDecoderNulls(input: String, want: T) throws {
    let decoder = JSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)

    let encoded = try JSONEncoder().encode(got)
    let roundtrip = try decoder.decode(T.self, from: encoded)
    #expect(roundtrip == want)
  }
}
