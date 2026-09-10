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
import GoogleCloudGax
import Testing

@Suite struct ApiClientHeader {
  @Test(arguments: ["1.2.3", "2.3.4", "0.0.0-preview"])
  func gapic(version: String) {
    let got = _gapicApiClientHeader(packageVersion: version)
    #expect(got.contains("gl-swift/"), "got=\(got)")
    #expect(got.contains("gax/"), "got=\(got)")
    #expect(got.contains("rest/"), "got=\(got)")
    #expect(got.contains("gapic/\(version)"), "got=\(got)")
  }

  @Test(arguments: ["1.2.3", "2.3.4", "0.0.0-preview"])
  func veneer(version: String) {
    let got = _veneerApiClientHeader(packageVersion: version)
    #expect(got.contains("gl-swift/"), "got=\(got)")
    #expect(got.contains("gax/"), "got=\(got)")
    #expect(got.contains("rest/"), "got=\(got)")
    #expect(got.contains("gccl/\(version)"), "got=\(got)")
  }
}
