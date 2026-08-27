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
import SwiftProtobuf

/// A Protobuf message deserializer for gRPC Swift 2.
///
/// ## Architectural Background
/// In gRPC Swift 2 (`GRPCCore`), the core RPC execution engine is decoupled from any specific serialization
/// format (such as Protocol Buffers, JSON, or FlatBuffers). Incoming message payloads are delivered from
/// the transport as raw bytes conforming to `GRPCContiguousBytes`, and deserialization is delegated to
/// types conforming to `GRPCCore.MessageDeserializer`.
///
/// While the official companion package [`grpc-swift-protobuf`](https://github.com/grpc/grpc-swift-protobuf)
/// provides protobuf deserialization, implementing this lightweight bridge directly avoids an additional
/// package dependency while fulfilling the `GRPCCore.MessageDeserializer` protocol requirement.
struct ProtobufDeserializer<Message: SwiftProtobuf.Message>: MessageDeserializer {
  func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> Message {
    try serializedMessageBytes.withUnsafeBytes { rawBuffer in
      let data = Data(rawBuffer)
      return try Message(serializedBytes: data)
    }
  }
}
