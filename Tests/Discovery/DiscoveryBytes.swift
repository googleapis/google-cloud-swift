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

// Verify the generated code can deserialize `bytes` as url-safe base64 encoded strings.
//
// The encoding for bytes is defined here:
//   https://developers.google.com/discovery/v1/type-format
//   https://datatracker.ietf.org/doc/html/rfc4648#section-5
// This is not the same encoding as defined in ProtoJSON.
//
// We use the `???` test string because (a) it is short, (b) it encodes differently under
// the two alphabets: `Pz8/` and `Pz8_`.
//
// We use `????` to verify padding (or lack thereof) also works.
@Suite struct DiscoveryBytes {
  typealias T = DiscoveryWithBytes

  @Test(
    arguments: [
      (#"{}"#, T()),
      (#"{"optional": null            }"#, T()),
      (#"{"optional": ""              }"#, T().with { $0.optional = Data() }),
      (#"{"optional": "Pz8_"          }"#, T().with { $0.optional = Data("???".utf8) }),
      (#"{"optional": "Pz8_Pw"        }"#, T().with { $0.optional = Data("????".utf8) }),
      (#"{"repeated": []              }"#, T()),
      (#"{"repeated": ["Pz8_"]        }"#, T().with { $0.repeated = [Data("???".utf8)] }),
      (#"{"repeated": ["Pz8_Pw", ""]  }"#, T().with { $0.repeated = [Data("????".utf8), Data()] }),
      (#"{"map":      {}              }"#, T()),
      (#"{"map":      {"a": "Pz8_"}   }"#, T().with { $0.map = ["a": Data("???".utf8)] }),
      (#"{"map":      {"a": "Pz8_Pw"} }"#, T().with { $0.map = ["a": Data("????".utf8)] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    arguments: [
      (#"{"map":{},"repeated":[]}"#, T()),
      (#"{"map":{},"optional":"","repeated":[]}"#, T().with { $0.optional = Data() }),
      (#"{"map":{},"optional":"Pz8_","repeated":[]}"#, T().with { $0.optional = Data("???".utf8) }),
      (#"{"map":{},"repeated":["Pz8_"]}"#, T().with { $0.repeated = [Data("???".utf8)] }),
      (
        #"{"map":{},"repeated":["Pz8_",""]}"#,
        T().with { $0.repeated = [Data("???".utf8), Data()] }
      ),
      (#"{"map":{"a":"Pz8_"},"repeated":[]}"#, T().with { $0.map = ["a": Data("???".utf8)] }),
    ])
  func roundtrip(want: String, input: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let got = String(data: data, encoding: .utf8)!
    #expect(want == got)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(T.self, from: data)
    #expect(input == roundtrip)
  }
}
