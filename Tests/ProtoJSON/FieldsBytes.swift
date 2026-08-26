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

@Suite struct BytesFields {
  typealias T = MessageWithBytes

  @Test(
    "bytes fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular": ""            }"#, T()),
      (#"{"singular": "NDI="        }"#, T().with { $0.singular = Data("42".utf8) }),
      (#"{"option":   null          }"#, T()),
      (#"{"option":   ""            }"#, T().with { $0.option = Data() }),
      (#"{"option":   "NDI="        }"#, T().with { $0.option = Data("42".utf8) }),
      (#"{"repeated": []            }"#, T()),
      (#"{"repeated": ["NDI="]      }"#, T().with { $0.repeated = [Data("42".utf8)] }),
      (#"{"repeated": ["NDI=", ""]  }"#, T().with { $0.repeated = [Data("42".utf8), Data()] }),
      (#"{"map":      {}            }"#, T()),
      (#"{"map":      {"a": "NDI="} }"#, T().with { $0.map = ["a": Data("42".utf8)] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }
}
