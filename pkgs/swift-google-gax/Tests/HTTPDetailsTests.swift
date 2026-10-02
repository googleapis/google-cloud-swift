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

@Suite struct HTTPDetailsTests {
  @Test func defaults() {
    let details = HTTPDetails(statusCode: 200)
    #expect(details.statusCode == 200)
    #expect(details.headers.count == 0)
    #expect(details.payload.isEmpty)
  }

  @Test func customValues() {
    let headers = HTTPHeaders([("x-test", "value")])
    let payload = Data("error body".utf8)
    let details = HTTPDetails(statusCode: 404, headers: headers, payload: payload)
    #expect(details.statusCode == 404)
    #expect(details.headers == headers)
    #expect(details.payload == payload)
  }
}
