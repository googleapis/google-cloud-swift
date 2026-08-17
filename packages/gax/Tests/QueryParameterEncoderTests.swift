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
@_spi(GoogleCloudInternal) @testable import GoogleCloudGax

@Suite struct QueryParameterEncoderTests {
  @Test func encodeSimpleTypes() throws {
    let encoder = QueryParameterEncoder()

    let stringItems = try encoder.encode("hello", prefix: "field")
    #expect(stringItems == [URLQueryItem(name: "field", value: "hello")])

    let intItems = try encoder.encode(42, prefix: "intField")
    #expect(intItems == [URLQueryItem(name: "intField", value: "42")])

    let boolItems = try encoder.encode(true, prefix: "boolField")
    #expect(boolItems == [URLQueryItem(name: "boolField", value: "true")])
  }

  struct User: Encodable {
    let name: String
    let address: Address
    let roles: [String]
  }

  struct Address: Encodable {
    let city: String
  }

  @Test func encodeRecursiveTypes() throws {
    let encoder = QueryParameterEncoder()
    let user = User(name: "Bob", address: Address(city: "Seattle"), roles: ["admin", "editor"])

    let items = try encoder.encode(user, prefix: "test")

    // Sort items by name, then value for stable testing
    let sortedItems = items.sorted {
      if $0.name != $1.name { return $0.name < $1.name }
      return ($0.value ?? "") < ($1.value ?? "")
    }
    #expect(
      sortedItems == [
        URLQueryItem(name: "test.address.city", value: "Seattle"),
        URLQueryItem(name: "test.name", value: "Bob"),
        URLQueryItem(name: "test.roles", value: "admin"),
        URLQueryItem(name: "test.roles", value: "editor"),
      ])
  }
}
