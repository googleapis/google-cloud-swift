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
import GoogleCloudWkt
import GoogleCloudSecurityPublicCAV1
@_spi(GoogleCloudInternal) import GoogleCloudGax

struct WellKnown: Encodable {
  let duration: GoogleCloudWkt.Duration?
  let durationMany: [GoogleCloudWkt.Duration]
  let mask: GoogleCloudWkt.FieldMask?
  let maskMany: [GoogleCloudWkt.FieldMask]
}

@Test func wellKnownSerialization() throws {
  let duration = try GoogleCloudWkt.Duration(seconds: 123, nanos: 450_000_000)
  let mask = GoogleCloudWkt.FieldMask(paths: ["user_id", "foo_bar"])
  let value = WellKnown(
    duration: duration,
    durationMany: [duration],
    mask: mask,
    maskMany: [mask]
  )

  let encoder = _QueryParameterEncoder()
  let items = try encoder.encode(value, prefix: "fieldName")
  let sortedItems = items.sorted { $0.name < $1.name }

  #expect(
    sortedItems == [
      URLQueryItem(name: "fieldName.duration", value: "123.450s"),
      URLQueryItem(name: "fieldName.durationMany", value: "123.450s"),
      URLQueryItem(name: "fieldName.mask", value: "userId,fooBar"),
      URLQueryItem(name: "fieldName.maskMany", value: "userId,fooBar"),
    ])
}

@Test func wellKnownDurationOnlySerialization() throws {
  let duration = try GoogleCloudWkt.Duration(seconds: 123, nanos: 450_000_000)
  let value = WellKnown(
    duration: duration,
    durationMany: [],
    mask: nil,
    maskMany: []
  )

  let encoder = _QueryParameterEncoder()
  let items = try encoder.encode(value, prefix: "fieldName")
  #expect(items == [URLQueryItem(name: "fieldName.duration", value: "123.450s")])
}

@Test func wellKnownMaskOnlySerialization() throws {
  let mask = GoogleCloudWkt.FieldMask(paths: ["user_id"])
  let value = WellKnown(
    duration: nil,
    durationMany: [],
    mask: mask,
    maskMany: []
  )

  let encoder = _QueryParameterEncoder()
  let items = try encoder.encode(value, prefix: "fieldName")
  #expect(items == [URLQueryItem(name: "fieldName.mask", value: "userId")])
}

@Test func createExternalAccountKeyRequestSerialization() throws {
  let request = CreateExternalAccountKeyRequest().with {
    $0.parent = "projects/my-project/locations/global"
    $0.externalAccountKey = ExternalAccountKey().with {
      $0.name = "my-key"
      $0.keyId = "my-key-id"
      $0.b64MacKey = Data("abc".utf8)
    }
  }

  let encoder = _QueryParameterEncoder()
  let items = try encoder.encode(request, prefix: "fieldName")
  let sortedItems = items.sorted { $0.name < $1.name }

  #expect(
    sortedItems == [
      URLQueryItem(name: "fieldName.externalAccountKey.b64MacKey", value: "YWJj"),
      URLQueryItem(name: "fieldName.externalAccountKey.keyId", value: "my-key-id"),
      URLQueryItem(name: "fieldName.externalAccountKey.name", value: "my-key"),
      URLQueryItem(name: "fieldName.parent", value: "projects/my-project/locations/global"),
    ])
}

@Test func createExternalAccountKeyRequestNilSerialization() throws {
  let request = CreateExternalAccountKeyRequest().with {
    $0.parent = "projects/my-project/locations/global"
    $0.externalAccountKey = nil
  }

  let encoder = _QueryParameterEncoder()
  let items = try encoder.encode(request, prefix: "fieldName")
  #expect(
    items == [URLQueryItem(name: "fieldName.parent", value: "projects/my-project/locations/global")]
  )
}

@Test func testPrefixSerialization() throws {
  let encoder = _QueryParameterEncoder()
  let duration = try GoogleCloudWkt.Duration(seconds: 123, nanos: 450_000_000)

  let items = try encoder.encode(duration, prefix: "myPrefix")
  #expect(items == [URLQueryItem(name: "myPrefix", value: "123.450s")])

  struct TestMessage: Encodable {
    let name: String
  }
  let message = TestMessage(name: "bar")
  let messageItems = try encoder.encode(message, prefix: "parent")
  #expect(messageItems == [URLQueryItem(name: "parent.name", value: "bar")])
}
