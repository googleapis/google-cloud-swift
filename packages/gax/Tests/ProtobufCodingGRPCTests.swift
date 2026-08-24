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
import GRPCCore
@_spi(GoogleCloudInternal) @testable import GoogleCloudGaxGRPC
import SwiftProtobuf
import Testing

@Suite struct ProtobufCodingGRPCTests {
  @Test func roundtripDurationMessage() throws {
    var duration = Google_Protobuf_Duration()
    duration.seconds = 120
    duration.nanos = 500_000

    let serializer = ProtobufSerializer<Google_Protobuf_Duration>()
    let bytes: [UInt8] = try serializer.serialize(duration)

    let deserializer = ProtobufDeserializer<Google_Protobuf_Duration>()
    let decoded: Google_Protobuf_Duration = try deserializer.deserialize(bytes)

    #expect(decoded.seconds == duration.seconds)
    #expect(decoded.nanos == duration.nanos)
  }

  @Test func deserializeEmptyBytes() throws {
    let deserializer = ProtobufDeserializer<Google_Protobuf_Empty>()
    let emptyBytes: [UInt8] = []
    let decoded: Google_Protobuf_Empty = try deserializer.deserialize(emptyBytes)

    #expect(decoded == Google_Protobuf_Empty())
  }
}
