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

import GoogleCloudWKT
import SwiftProtobuf

extension GoogleCloudWKT.Timestamp {
  public init(proto: SwiftProtobuf.Google_Protobuf_Timestamp) throws {
    try self.init(seconds: proto.seconds, nanos: Int64(proto.nanos))
  }

  public func toProto() throws -> SwiftProtobuf.Google_Protobuf_Timestamp {
    var proto = SwiftProtobuf.Google_Protobuf_Timestamp()
    proto.seconds = self.seconds
    proto.nanos = Int32(self.nanos)
    return proto
  }
}
