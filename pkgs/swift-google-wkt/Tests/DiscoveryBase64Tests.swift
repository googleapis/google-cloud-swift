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

@Suite struct Base64Tests {
  @Test(arguments: [
    (Data(), ""),
    (Data("???".utf8), "Pz8_"),
    (Data("????".utf8), "Pz8_Pw"),
  ])
  func roundtrip(input: Data, want: String) throws {
    let got = _DiscoveryBase64.encode(input)
    #expect(got == want)

    let roundtrip = _DiscoveryBase64.decode(want)!
    #expect(input == roundtrip)
  }

  @Test(arguments: ["Pz8/", "Pz8/Pw"])
  func decodeError(input: String) throws {
    let got = _DiscoveryBase64.decode(input)
    #expect(got == nil)
  }
}
