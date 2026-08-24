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

import GRPCCore
import SwiftProtobuf

/// A Protobuf message serializer for gRPC Swift 2.
///
/// ## Background
///
/// In gRPC Swift 2 (`GRPCCore`), the core RPC execution engine is decoupled from any specific serialization
/// format (such as Protocol Buffers, JSON, or FlatBuffers). `GRPCCore` operates exclusively on generic
/// byte representations conforming to `GRPCContiguousBytes` and delegates message transformation to types
/// conforming to `GRPCCore.MessageSerializer`.
///
/// While the official companion package [`grpc-swift-protobuf`](https://github.com/grpc/grpc-swift-protobuf)
/// provides protobuf serialization, implementing this lightweight bridge directly avoids an additional
/// package dependency while fulfilling the `GRPCCore.MessageSerializer` protocol requirement.
///
/// If we need to change this and take the dependency, that is an easy change that does not affect the public API.
struct ProtobufSerializer<Message: SwiftProtobuf.Message>: MessageSerializer {
  func serialize<Bytes: GRPCContiguousBytes>(_ message: Message) throws -> Bytes {
    let data = try message.serializedData()
    return Bytes(data)
  }
}
