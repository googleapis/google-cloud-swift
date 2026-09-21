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

import Testing

@testable import GoogleAuth

@Suite struct AuthHeadersTests {
  @Test func emptyByDefault() {
    let headers = AuthHeaders()
    #expect(headers.isEmpty)
    #expect(headers.count == 0)
    #expect(headers == [])
  }

  @Test func arrayLiteralPreservesOrder() {
    let headers: AuthHeaders = [
      ("Authorization", "Bearer token"),
      ("x-goog-user-project", "my-project"),
    ]
    #expect(headers.count == 2)
    #expect(headers.map(\.name) == ["Authorization", "x-goog-user-project"])
    #expect(headers.map(\.value) == ["Bearer token", "my-project"])
  }

  @Test func appendPreservesDuplicateNames() {
    var headers = AuthHeaders()
    headers.append(name: "x-goog-ext", value: "first")
    headers.append(name: "x-goog-ext", value: "second")

    #expect(headers.count == 2)
    #expect(headers == [("x-goog-ext", "first"), ("x-goog-ext", "second")])
  }

  @Test func equalityMatchesOnNameValueAndOrder() {
    let headers: AuthHeaders = [("a", "1"), ("b", "2")]

    #expect(headers == [("a", "1"), ("b", "2")])
    #expect(headers != [("a", "1")])
    #expect(headers != [("a", "1"), ("b", "2"), ("c", "3")])
    #expect(headers != [("a", "1"), ("b", "99")])
    #expect(headers != [("a", "1"), ("z", "2")])
  }

  @Test func equalityIsOrderSensitive() {
    let headers: AuthHeaders = [("a", "1"), ("b", "2")]
    #expect(headers != [("b", "2"), ("a", "1")])
  }

  @Test func equalityIsCaseSensitive() {
    let headers: AuthHeaders = [("Authorization", "Bearer token")]
    #expect(headers != [("authorization", "Bearer token")])
  }

  @Test func initFromArrayMatchesArrayLiteral() {
    let fromArray = AuthHeaders([("a", "1"), ("b", "2")])
    let fromLiteral: AuthHeaders = [("a", "1"), ("b", "2")]
    #expect(fromArray == fromLiteral)
  }

  @Test func supportsTupleDestructuringIteration() {
    let headers: AuthHeaders = [("a", "1"), ("b", "2")]

    var visited: [String] = []
    for (name, value) in headers {
      visited.append("\(name)=\(value)")
    }
    #expect(visited == ["a=1", "b=2"])
  }

  @Test func exposesRandomAccessCollectionMembers() {
    let headers: AuthHeaders = [("a", "1"), ("b", "2"), ("c", "3")]

    #expect(headers.first?.name == "a")
    #expect(headers.last?.value == "3")
    #expect(headers[1] == ("b", "2"))
    #expect(headers.contains { $0.name == "c" })
  }
}
