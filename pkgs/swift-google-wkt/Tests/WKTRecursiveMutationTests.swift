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

@_spi(GoogleCloudInternal) import GoogleWKT

/// Demonstrates the behavior requested in
/// https://github.com/googleapis/google-cloud-swift/issues/1087
@Suite struct WKTRecursiveMutationTests {
  /// A stand-in for `GoogleCloudAIPlatformV1.Schema`: a struct with a
  /// recursive field, a recursive optional field, and a repeated recursive
  /// field. Note that the type is a `struct` and it (indirectly) contains
  /// itself; this only compiles because `WKTRecursive` is pointer-sized.
  struct Schema: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case unspecified, string, array, object }

    var type: Kind = .unspecified
    var title: String = ""
    var items: WKTRecursive<Schema>? = nil
    var additionalProperties: WKTRecursive<Schema>? = nil
    var anyOf: [Schema] = []

    func with(_ populate: (inout Self) -> Void) -> Self {
      var copy = self
      populate(&copy)
      return copy
    }
  }

  @Test("The expression from the issue compiles and mutates in place")
  func testInPlaceMutation() {
    var schema = Schema()
    schema.type = .array
    schema.items = WKTRecursive(value: Schema())

    // This is the expression that does not compile today.
    schema.items?.value.type = .string
    schema.items?.value.title = "element"

    #expect(schema.items?.value.type == .string)
    #expect(schema.items?.value.title == "element")
  }

  @Test("Mutation works at arbitrary depth without rebuilding the wrappers")
  func testDeepMutation() {
    var schema = Schema().with {
      $0.type = .array
      $0.items = WKTRecursive(
        value: Schema().with {
          $0.type = .object
          $0.additionalProperties = WKTRecursive(value: Schema())
        })
    }

    schema.items?.value.additionalProperties?.value.type = .string
    schema.items?.value.anyOf.append(Schema().with { $0.type = .string })

    #expect(schema.items?.value.additionalProperties?.value.type == .string)
    #expect(schema.items?.value.anyOf.count == 1)
  }

  @Test("Copies have value semantics: mutating one does not affect the other")
  func testValueSemantics() {
    let original = Schema().with {
      $0.items = WKTRecursive(value: Schema().with { $0.title = "original" })
    }

    var copy = original
    copy.items?.value.title = "mutated"

    #expect(original.items?.value.title == "original")
    #expect(copy.items?.value.title == "mutated")
    #expect(original != copy)
  }

  @Test("Equality still compares the wrapped values, not identities")
  func testEquality() {
    let lhs = WKTRecursive(value: Schema().with { $0.title = "a" })
    let rhs = WKTRecursive(value: Schema().with { $0.title = "a" })
    #expect(lhs == rhs)
  }

  @Test("Encoding remains transparent after the change")
  func testEncodingIsUnchanged() throws {
    let schema = Schema().with {
      $0.type = .array
      $0.items = WKTRecursive(value: Schema().with { $0.type = .string })
    }

    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(schema)
    #expect(
      String(data: data, encoding: .utf8)
        == #"{"anyOf":[],"items":{"anyOf":[],"title":"","type":"string"},"title":"","type":"array"}"#
    )

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(Schema.self, from: data)
    #expect(roundtrip == schema)
  }

  @Test("The wrapper is the size of a single pointer")
  func testSize() {
    // Use `AnyObject` (a single class reference pointer) rather than `UnsafeRawPointer` so the
    // assertion is memory-safe under `-strict-memory-safety` across both Swift 6.3 and Swift 6.4.
    #expect(MemoryLayout<WKTRecursive<Schema>>.size == MemoryLayout<AnyObject>.size)
    // Optionals of the wrapper do not need extra storage either.
    #expect(MemoryLayout<WKTRecursive<Schema>?>.size == MemoryLayout<AnyObject>.size)
  }
}
