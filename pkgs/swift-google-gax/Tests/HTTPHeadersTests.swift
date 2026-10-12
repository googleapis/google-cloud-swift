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

import GoogleGax
import Testing

@Suite struct HTTPHeadersTests {
  @Test func emptyByDefault() {
    let headers = HTTPHeaders()
    #expect(headers.isEmpty)
    #expect(headers == [])
  }

  @Test func emptyArrayInitializerMatchesDefault() {
    #expect(HTTPHeaders([]) == HTTPHeaders())
  }

  @Test func arrayLiteralPreservesOrder() {
    let headers: HTTPHeaders = [
      ("Content-Type", "text/html; charset=UTF-8"),
      ("Retry-After", "120"),
    ]
    #expect(headers.count == 2)
    #expect(headers.map(\.name) == ["Content-Type", "Retry-After"])
    #expect(headers.map(\.value) == ["text/html; charset=UTF-8", "120"])
  }

  @Test func preservesDuplicateNames() {
    let headers: HTTPHeaders = [
      ("x-goog-ext", "first"),
      ("x-goog-ext", "second"),
    ]

    #expect(headers.count == 2)
    #expect(headers == [("x-goog-ext", "first"), ("x-goog-ext", "second")])
  }

  @Test func equalityRequiresSameNamesAndValues() {
    let headers: HTTPHeaders = [("a", "1"), ("b", "2")]

    #expect(headers == [("a", "1"), ("b", "2")])
    #expect(headers != [("a", "1")])
    #expect(headers != [("a", "1"), ("b", "2"), ("c", "3")])
    #expect(headers != [("a", "1"), ("b", "99")])
    #expect(headers != [("a", "1"), ("z", "2")])
  }

  @Test func equalityIsOrderSensitive() {
    let headers: HTTPHeaders = [("a", "1"), ("b", "2")]
    #expect(headers != [("b", "2"), ("a", "1")])
  }

  @Test func equalityIsCaseSensitive() {
    let headers: HTTPHeaders = [("Retry-After", "60")]
    #expect(headers != [("retry-after", "60")])
  }

  @Test func initFromArrayMatchesArrayLiteral() {
    let fromArray = HTTPHeaders([("a", "1"), ("b", "2")])
    let fromLiteral: HTTPHeaders = [("a", "1"), ("b", "2")]
    #expect(fromArray == fromLiteral)
  }

  @Test func supportsTupleDestructuringIteration() {
    let headers: HTTPHeaders = [("a", "1"), ("b", "2")]

    var visited: [String] = []
    for (name, value) in headers {
      visited.append("\(name)=\(value)")
    }
    #expect(visited == ["a=1", "b=2"])
  }

  @Test func supportsSequenceMethods() {
    let headers: HTTPHeaders = [("a", "1"), ("b", "2"), ("c", "3")]

    #expect(headers.contains { $0.name == "c" })
    #expect(headers.map(\.name) == ["a", "b", "c"])
  }

  @Test func makeIteratorReturnsDedicatedIteratorType() {
    let headers: HTTPHeaders = [("a", "1"), ("b", "2")]
    var iterator: HTTPHeaders.Iterator = headers.makeIterator()

    let first = iterator.next()
    #expect(first?.name == "a")
    #expect(first?.value == "1")

    let second = iterator.next()
    #expect(second?.name == "b")
    #expect(second?.value == "2")

    #expect(iterator.next() == nil)
  }

  @Test func lookupIgnoresNameCase() {
    let headers: HTTPHeaders = [
      ("Retry-After", "120"),
      ("x-goog-request-id", "req-123"),
    ]

    #expect(headers["RETRY-AFTER"] == "120")
    #expect(headers["retry-after"] == "120")
    #expect(headers["x-goog-REQUEST-id"] == "req-123")
    #expect(headers.contains(name: "retry-after"))
    #expect(headers.values(for: "RETRY-AFTER") == ["120"])
  }

  @Test func lookupMissesUnknownNames() {
    let headers: HTTPHeaders = [("Retry-After", "120")]

    #expect(headers["x-goog-request-id"] == nil)
    #expect(!headers.contains(name: "x-goog-request-id"))
    #expect(headers.values(for: "x-goog-request-id").isEmpty)
  }

  @Test func lookupReturnsFirstOfDuplicateNamesAndValuesReturnsAll() {
    let headers: HTTPHeaders = [("x-goog-ext", "first"), ("X-Goog-Ext", "second")]

    #expect(headers["x-goog-ext"] == "first")
    #expect(headers.values(for: "x-goog-ext") == ["first", "second"])
  }

  @Test func lookupFoldsOnlyASCIICase() {
    // Unicode case folding maps "İ" (U+0130) toward "i"; ASCII folding must keep them distinct.
    var headers: HTTPHeaders = [("i", "1")]
    #expect(headers["İ"] == nil)
    headers["İ"] = "2"
    #expect(headers == [("i", "1"), ("İ", "2")])

    // "-" (0x2D) and a carriage return (0x0D) differ only in the bit that distinguishes ASCII
    // letter case, so they must not be folded together either.
    var dashed: HTTPHeaders = [("x-a", "1")]
    #expect(dashed["x\ra"] == nil)
    dashed["x\ra"] = "2"
    #expect(dashed == [("x-a", "1"), ("x\ra", "2")])
  }

  @Test func emptyDictionaryLiteralMatchesDefault() {
    let headers: HTTPHeaders = [:]
    #expect(headers.isEmpty)
    #expect(headers == HTTPHeaders())
  }

  @Test func dictionaryLiteralPreservesOrderAndDuplicates() {
    let headers: HTTPHeaders = [
      "Content-Type": "application/json",
      "X-Request-Id": "abc-123",
      "x-request-id": "def-456",
    ]
    #expect(headers.count == 3)
    #expect(
      headers == [
        ("Content-Type", "application/json"),
        ("X-Request-Id", "abc-123"),
        ("x-request-id", "def-456"),
      ]
    )
    #expect(headers.values(for: "x-request-id") == ["abc-123", "def-456"])
  }

  @Test func subscriptSetterAppendsAndReplacesCaseInsensitively() {
    var headers = HTTPHeaders()
    headers["X-Goog-Custom"] = "first"
    headers["X-Other"] = "other"
    #expect(headers == [("X-Goog-Custom", "first"), ("X-Other", "other")])

    headers["x-goog-custom"] = "second"
    #expect(headers == [("x-goog-custom", "second"), ("X-Other", "other")])
    #expect(headers["X-GOOG-CUSTOM"] == "second")
  }

  @Test func subscriptSetterCollapsesDuplicates() {
    var headers: HTTPHeaders = [
      ("x-goog-ext", "first"),
      ("X-Other", "keep"),
      ("X-Goog-Ext", "second"),
    ]
    headers["X-GOOG-EXT"] = "replaced"
    #expect(headers == [("X-GOOG-EXT", "replaced"), ("X-Other", "keep")])
  }

  @Test func subscriptSetterNilRemovesAllMatchingCaseInsensitively() {
    var headers: HTTPHeaders = [
      ("x-goog-ext", "first"),
      ("X-Other", "keep"),
      ("X-Goog-Ext", "second"),
    ]
    headers["X-GOOG-EXT"] = nil
    #expect(headers == [("X-Other", "keep")])
    #expect(headers["x-goog-ext"] == nil)
  }
}
