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

extension AnyTests {
  struct BasicMessage: Codable, Equatable, Sendable {
    let field0: String
    let field1: String
  }

  @Test func decodeBasicMessage() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/test.BasicMessage","field0":"0","field1":"1"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/test.BasicMessage")

    let inner = try BasicMessage(fromAny: any)
    #expect(inner == BasicMessage(field0: "0", field1: "1"))
  }

  @Test func decodeBasicMessageMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","field0":"0","field1":"1"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) {
      let _ = try BasicMessage(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test func decodeBasicMessageMissing() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/test.BasicMessage","field0":"0"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/test.BasicMessage")

    let inner = try BasicMessage(fromAny: any)
    #expect(inner == BasicMessage(field0: "0", field1: ""))
  }
}

extension AnyTests.BasicMessage: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/test.BasicMessage"
  }

  public init(fromAny any: `Any`) throws {
    self = try GoogleCloudWKT._slowAnyDeserialize(Self.self, from: any)
  }

  public func _pack() throws -> Struct {
    return try GoogleCloudWKT._slowAnySerialize(message: self)
  }
}
