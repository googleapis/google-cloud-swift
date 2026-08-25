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
import Testing

@Suite struct RecursiveTests {
  // A co-recursive dummy struct to test compile and serialization.
  struct DummyNode: Codable, Equatable, Sendable {
    var name: String
    var next: GoogleCloudWKT.Recursive<DummyNode>?

    init(name: String, next: DummyNode? = nil) {
      self.name = name
      self.next = next.map { GoogleCloudWKT.Recursive(value: $0) }
    }
  }

  @Test("Verifies that identical payloads equate and differing payloads do not")
  func testRecursiveEquatable() {
    let recursive1 = Recursive(value: DummyNode(name: "A"))
    let recursive2 = Recursive(value: DummyNode(name: "A"))
    let recursive3 = Recursive(value: DummyNode(name: "B"))

    #expect(recursive1 == recursive2)
    #expect(recursive1 != recursive3)
  }

  @Test("Json Encoding")
  func testJsonEncoding() throws {
    let recursive = Recursive(value: DummyNode(name: "A"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let data = try encoder.encode(recursive)
    #expect(String(data: data, encoding: .utf8) == "{\"name\":\"A\"}")
  }

  @Test("JSON Encoding Is Transparent")
  func testJSONEncodingIsTransparent() throws {
    let node = DummyNode(name: "A")
    let recursive = Recursive(value: node)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let nodeData = try encoder.encode(node)
    let recursiveData = try encoder.encode(recursive)

    // Ensure encoded data is identical despite using Recursive wrapper
    #expect(nodeData == recursiveData)
  }

  @Test("JSON Decoding")
  func testJSONDecoding() throws {
    let jsonString = #"{"name":"A"}"#
    let data = Data(jsonString.utf8)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Recursive<DummyNode>.self, from: data)

    #expect(decoded.value.name == "A")
    #expect(decoded.value.next == nil)
  }

  @Test("NestedRecursive JSON Encoding and Decoding")
  func testNestedRecursiveJSONEncodingAndDecoding() throws {
    let nodeC = DummyNode(name: "C")
    let nodeB = DummyNode(name: "B", next: nodeC)
    let nodeA = DummyNode(name: "A", next: nodeB)

    let recursive = Recursive(value: nodeA)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(recursive)

    let jsonString = String(data: data, encoding: .utf8)
    #expect(jsonString == #"{"name":"A","next":{"name":"B","next":{"name":"C"}}}"#)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Recursive<DummyNode>.self, from: data)

    #expect(decoded == recursive)
    #expect(decoded.value == nodeA)
    #expect(decoded.value.next?.value == nodeB)
    #expect(decoded.value.next?.value.next?.value == nodeC)
  }
}
