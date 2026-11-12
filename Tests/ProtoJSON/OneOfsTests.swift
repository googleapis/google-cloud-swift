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

@Suite struct OneOfsTests {
  @Test(
    "OneOf serialization",
    arguments: [
      (
        #"{"stringContents":"test"}"#,
        MessageWithOneOf().with { $0.singleString = .stringContents("test") }
      ),
      (
        #"{"stringContentsOne":"test"}"#,
        MessageWithOneOf().with { $0.twoStrings = .stringContentsOne("test") }
      ),
      (
        #"{"stringContentsTwo":"test"}"#,
        MessageWithOneOf().with { $0.twoStrings = .stringContentsTwo("test") }
      ),
      (
        #"{"messageValue":{"parent":"test"}}"#,
        MessageWithOneOf().with {
          $0.oneMessage = .messageValue(MessageWithOneOf.Message().with { $0.parent = "test" })
        }
      ),
      (
        #"{"anotherMessage":{"parent":"test"}}"#,
        MessageWithOneOf().with {
          $0.mixed = .anotherMessage(MessageWithOneOf.Message().with { $0.parent = "test" })
        }
      ),
      (#"{"string":"test"}"#, MessageWithOneOf().with { $0.mixed = .string("test") }),
      (
        #"{"duration":"10s"}"#,
        MessageWithOneOf().with { $0.mixed = .duration(try! WKTDuration(seconds: 10, nanos: 0)) }
      ),
    ]
  )
  func oneOfSerialization(expectedJSON: String, input: MessageWithOneOf) throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let jsonString = String(data: data, encoding: .utf8)!
    #expect(jsonString == expectedJSON)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(MessageWithOneOf.self, from: data)
    #expect(input == roundtrip)
  }

  @Test(
    "ComplexOneOf serialization",
    arguments: [
      (#"{"boolValue":true}"#, MessageWithComplexOneOf().with { $0.complex = .boolValue(true) }),
      (
        #"{"bytesValue":"AQID"}"#,
        MessageWithComplexOneOf().with { $0.complex = .bytesValue(Data([1, 2, 3])) }
      ),
      (
        #"{"stringValue":"test"}"#,
        MessageWithComplexOneOf().with { $0.complex = .stringValue("test") }
      ),
      (#"{"floatValue":1.5}"#, MessageWithComplexOneOf().with { $0.complex = .floatValue(1.5) }),
      (#"{"doubleValue":2.5}"#, MessageWithComplexOneOf().with { $0.complex = .doubleValue(2.5) }),
      (#"{"int32":42}"#, MessageWithComplexOneOf().with { $0.complex = .int32(42) }),
      (#"{"int64":"42"}"#, MessageWithComplexOneOf().with { $0.complex = .int64(42) }),
      (#"{"enum":"BLACK"}"#, MessageWithComplexOneOf().with { $0.complex = .enum(.black) }),
      (
        #"{"inner":{"strings":["a","b"]}}"#,
        MessageWithComplexOneOf().with {
          $0.complex = .inner(MessageWithComplexOneOf.Inner().with { $0.strings = ["a", "b"] })
        }
      ),
      (
        #"{"duration":"10s"}"#,
        MessageWithComplexOneOf().with {
          $0.complex = .duration(try! WKTDuration(seconds: 10, nanos: 0))
        }
      ),
      (
        #"{"value":"hello"}"#,
        MessageWithComplexOneOf().with { $0.complex = .value(.string("hello")) }
      ),
      (
        #"{"value":null}"#,
        MessageWithComplexOneOf().with { $0.complex = .value(.null(WKTNullValue())) }
      ),
      (
        #"{"null":null}"#,
        MessageWithComplexOneOf().with { $0.complex = .null(WKTNullValue()) }
      ),
      (
        #"{"optionalDouble":1.5}"#,
        MessageWithComplexOneOf().with { $0.complex = .optionalDouble(1.5) }
      ),
    ]
  )
  func complexOneOfSerialization(expectedJSON: String, input: MessageWithComplexOneOf) throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let jsonString = String(data: data, encoding: .utf8)!
    #expect(jsonString == expectedJSON)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(MessageWithComplexOneOf.self, from: data)
    #expect(input == roundtrip)
  }

  @Test(
    "ComplexOneOf null WKT fields roundtrip through WKTAny",
    arguments: [
      MessageWithComplexOneOf().with { $0.complex = .null(WKTNullValue()) },
      MessageWithComplexOneOf().with { $0.complex = .value(.null(WKTNullValue())) },
    ]
  )
  func complexOneOfNullAnyRoundtrip(input: MessageWithComplexOneOf) throws {
    let any = try WKTAny(fromMessage: input)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(any)
    let decoder = _ProtoJSONDecoder()
    let decodedAny = try decoder.decode(WKTAny.self, from: data)
    let roundtrip = try MessageWithComplexOneOf(fromAny: decodedAny)
    #expect(roundtrip == input)
  }

  @Test(
    "ComplexOneOf rejects duplicate fields when combined with explicit null",
    arguments: [
      #"{"null":null,"boolValue":true}"#,
      #"{"value":null,"boolValue":true}"#,
      #"{"null":null,"value":null}"#,
    ]
  )
  func complexOneOfDuplicateWithNull(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    #expect(throws: DecodingError.self) {
      _ = try decoder.decode(MessageWithComplexOneOf.self, from: Data(input.utf8))
    }
  }

  @Test(
    "OneOf null fields decode as unset",
    arguments: [
      (#"{"stringContents":null}"#, MessageWithOneOf()),
      (#"{"messageValue":null}"#, MessageWithOneOf()),
      (#"{"duration":null}"#, MessageWithOneOf()),
      (
        #"{"stringContentsOne":null,"stringContentsTwo":"test"}"#,
        MessageWithOneOf().with { $0.twoStrings = .stringContentsTwo("test") }
      ),
    ]
  )
  func oneOfNullDeserialization(input: String, want: MessageWithOneOf) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(MessageWithOneOf.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "ComplexOneOf null fields decode as unset except NullValue and Value",
    arguments: [
      (
        #"{"int32":null,"boolValue":true}"#,
        MessageWithComplexOneOf().with { $0.complex = .boolValue(true) }
      ),
      (
        #"{"enum":null,"inner":null,"optionalDouble":null}"#,
        MessageWithComplexOneOf()
      ),
      (
        #"{"int32":null,"null":null}"#,
        MessageWithComplexOneOf().with { $0.complex = .null(WKTNullValue()) }
      ),
      (
        #"{"int32":null,"value":null}"#,
        MessageWithComplexOneOf().with { $0.complex = .value(.null(WKTNullValue())) }
      ),
    ]
  )
  func complexOneOfNullDeserialization(input: String, want: MessageWithComplexOneOf) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(MessageWithComplexOneOf.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test("Use oneof with @unknown")
  func useOneof() throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(
      MessageWithOneOf.self, from: Data(#"{"stringContents":"test"}"#.utf8))
    #expect(got.singleString == .stringContents("test"))
    switch got.singleString! {
    case .stringContents(let s):
      #expect(s == "test", "\(got)")
    @unknown default:
      #expect(Bool(false), "\(got)")
    }
  }

  @Test(
    "ComplexOneOf null WKT fields decode and roundtrip with Foundation JSONDecoder",
    arguments: [
      (#"{}"#, MessageWithComplexOneOf()),
      (#"{"null":null}"#, MessageWithComplexOneOf().with { $0.complex = .null(WKTNullValue()) }),
      (
        #"{"value":null}"#,
        MessageWithComplexOneOf().with { $0.complex = .value(.null(WKTNullValue())) }
      ),
      (
        #"{"int32":null,"null":null}"#,
        MessageWithComplexOneOf().with { $0.complex = .null(WKTNullValue()) }
      ),
      (
        #"{"int32":null,"value":null}"#,
        MessageWithComplexOneOf().with { $0.complex = .value(.null(WKTNullValue())) }
      ),
    ]
  )
  func complexOneOfFoundationJSONDecoderNulls(input: String, want: MessageWithComplexOneOf) throws {
    let decoder = JSONDecoder()
    let got = try decoder.decode(MessageWithComplexOneOf.self, from: Data(input.utf8))
    #expect(got == want)

    let encoded = try JSONEncoder().encode(got)
    let roundtrip = try decoder.decode(MessageWithComplexOneOf.self, from: encoded)
    #expect(roundtrip == want)
  }
}
