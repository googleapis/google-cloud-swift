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
import GoogleGax
import Testing

@Suite struct ClientErrorTests {
  @Test func clientErrorConformances() {
    let error = ClientError.invalidEndpoint("bad://endpoint:123")
    #expect(error.description == "Invalid endpoint: bad://endpoint:123")
    #expect(error.debugDescription == "ClientError.invalidEndpoint(\"bad://endpoint:123\")")

    let identical = ClientError.invalidEndpoint("bad://endpoint:123")
    #expect(error == identical)
    let different = ClientError.invalidEndpoint("other://endpoint")
    #expect(error != different)
  }
}
