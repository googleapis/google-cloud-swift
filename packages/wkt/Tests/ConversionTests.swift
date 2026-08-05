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

import GoogleCloudWkt
import GoogleCloudWktConvert
import SwiftProtobuf
import Testing

@Suite struct ConversionTests {
  @Test func durationProtoToNative() throws {
    var proto = SwiftProtobuf.Google_Protobuf_Duration()
    proto.seconds = 1234
    proto.nanos = 567800000

    let native = try GoogleCloudWkt.Duration(proto: proto)
    #expect(native.seconds == 1234)
    #expect(native.nanos == 567800000)
  }

  @Test func durationNativeToProto() throws {
    let native = try GoogleCloudWkt.Duration(seconds: 1234, nanos: 567800000)
    let proto = try native.toProto()

    #expect(proto.seconds == 1234)
    #expect(proto.nanos == 567800000)
  }

  @Test func emptyProtoToNative() throws {
    let proto = SwiftProtobuf.Google_Protobuf_Empty()
    let _ = try GoogleCloudWkt.Empty(proto: proto)
    // Just verifying it compiles and initializes without throwing
  }

  @Test func emptyNativeToProto() throws {
    let native = GoogleCloudWkt.Empty()
    let proto = try native.toProto()
    #expect(proto == SwiftProtobuf.Google_Protobuf_Empty())
  }

  @Test func fieldMaskProtoToNative() throws {
    var proto = SwiftProtobuf.Google_Protobuf_FieldMask()
    proto.paths = ["a.b", "c.d"]

    let native = try GoogleCloudWkt.FieldMask(proto: proto)
    #expect(native.paths == ["a.b", "c.d"])
  }

  @Test func fieldMaskNativeToProto() throws {
    let native = GoogleCloudWkt.FieldMask(paths: ["a.b", "c.d"])
    let proto = try native.toProto()
    #expect(proto.paths == ["a.b", "c.d"])
  }

  @Test func timestampProtoToNative() throws {
    var proto = SwiftProtobuf.Google_Protobuf_Timestamp()
    proto.seconds = 987654321
    proto.nanos = 123456789

    let native = try GoogleCloudWkt.Timestamp(proto: proto)
    #expect(native.seconds == 987654321)
    #expect(native.nanos == 123456789)
  }

  @Test func timestampNativeToProto() throws {
    let native = try GoogleCloudWkt.Timestamp(seconds: 987654321, nanos: 123456789)
    let proto = try native.toProto()

    #expect(proto.seconds == 987654321)
    #expect(proto.nanos == 123456789)
  }

  @Test func anyProtoToNative() throws {
    var durationProto = SwiftProtobuf.Google_Protobuf_Duration()
    durationProto.seconds = 123
    durationProto.nanos = 450000000
    let proto = try SwiftProtobuf.Google_Protobuf_Any(message: durationProto)

    let native = try GoogleCloudWkt.Any(proto: proto)
    #expect(native.typeUrl == "type.googleapis.com/google.protobuf.Duration")

    let unpackedDuration = try GoogleCloudWkt.Duration(fromAny: native)
    #expect(unpackedDuration.seconds == 123)
    #expect(unpackedDuration.nanos == 450000000)
  }

  @Test func anyNativeToProto() throws {
    let nativeDuration = try GoogleCloudWkt.Duration(seconds: 123, nanos: 450000000)
    let native = try GoogleCloudWkt.Any(fromMessage: nativeDuration)

    let proto = try native.toProto()
    #expect(proto.typeURL == "type.googleapis.com/google.protobuf.Duration")

    let unpackedProto = try SwiftProtobuf.Google_Protobuf_Duration(unpackingAny: proto)
    #expect(unpackedProto.seconds == 123)
    #expect(unpackedProto.nanos == 450000000)
  }
}
