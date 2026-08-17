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
@_spi(GoogleCloudInternal) import GoogleCloudWkt

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
        MessageWithOneOf().with { $0.mixed = .duration(try! Duration(seconds: 10, nanos: 0)) }
      ),
    ]
  )
  func oneOfSerialization(expectedJSON: String, input: MessageWithOneOf) throws {
    let encoder = JSONEncoder()
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
      (#"{"int64":42}"#, MessageWithComplexOneOf().with { $0.complex = .int64(42) }),
      (#"{"enum":1}"#, MessageWithComplexOneOf().with { $0.complex = .enum(.black) }),
      (
        #"{"inner":{"strings":["a","b"]}}"#,
        MessageWithComplexOneOf().with {
          $0.complex = .inner(MessageWithComplexOneOf.Inner().with { $0.strings = ["a", "b"] })
        }
      ),
      (
        #"{"duration":"10s"}"#,
        MessageWithComplexOneOf().with {
          $0.complex = .duration(try! Duration(seconds: 10, nanos: 0))
        }
      ),
      (
        #"{"value":"hello"}"#,
        MessageWithComplexOneOf().with { $0.complex = .value(.string("hello")) }
      ),
      (
        #"{"optionalDouble":1.5}"#,
        MessageWithComplexOneOf().with { $0.complex = .optionalDouble(1.5) }
      ),
    ]
  )
  func complexOneOfSerialization(expectedJSON: String, input: MessageWithComplexOneOf) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let jsonString = String(data: data, encoding: .utf8)!
    #expect(jsonString == expectedJSON)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(MessageWithComplexOneOf.self, from: data)
    #expect(input == roundtrip)
  }

  // TODO(https://github.com/googleapis/librarian/issues/5260) - review if this is right.
  @Test func complexOneOfSerialization_null() throws {
    let input = MessageWithComplexOneOf().with { $0.complex = .null(NullValue()) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let jsonString = String(data: data, encoding: .utf8)!
    #expect(jsonString == #"{"null":null}"#)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(MessageWithComplexOneOf.self, from: data)
    // Currently decodes to nil because decodeIfPresent returns nil for null values.
    #expect(roundtrip == MessageWithComplexOneOf().with { $0.complex = nil })
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
}
