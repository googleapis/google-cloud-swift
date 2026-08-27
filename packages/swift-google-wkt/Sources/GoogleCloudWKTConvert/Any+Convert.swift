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
import GoogleCloudWKT
import SwiftProtobuf

extension GoogleCloudWKT.`Any` {
  public init(proto: SwiftProtobuf.Google_Protobuf_Any) throws {
    let json = try proto.jsonUTF8Data()
    self = try JSONDecoder().decode(GoogleCloudWKT.`Any`.self, from: json)
  }

  public func toProto() throws -> SwiftProtobuf.Google_Protobuf_Any {
    let json = try JSONEncoder().encode(self)
    return try SwiftProtobuf.Google_Protobuf_Any(jsonUTF8Data: json)
  }
}
