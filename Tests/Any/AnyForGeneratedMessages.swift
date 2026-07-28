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
import GoogleCloudWkt
import GoogleCloudSecretmanagerV1
import Testing

// Verify `Any` can be used with a struct defined outside the `GoogleCloudWkt`  package.
//
// We use an integration test to avoid a cyclic dependency between the `GoogleCloudWkt` package and the generated library.
// `GoogleCloudSecretmanagerV1` was chosen since it has a simple structure, so it's easy to construct test data for it.

struct WrappedAny: Codable {
  let value: GoogleCloudWkt.`Any`
}

@Test("Any decoding GetSecretRequest")
func testDecodingGetSecretRequestMessage() throws {
  let jsonString =
    #"{"value":{"@type":"type.googleapis.com/google.cloud.secretmanager.v1.GetSecretRequest","name":"projects/test-project/secrets/my-secret"}}"#
  let data = Data(jsonString.utf8)
  let decoder = JSONDecoder()
  let wrapped = try decoder.decode(WrappedAny.self, from: data)
  let any = wrapped.value
  #expect(any.typeUrl == "type.googleapis.com/google.cloud.secretmanager.v1.GetSecretRequest")
  let got = try GetSecretRequest(fromAny: any)
  let want = GetSecretRequest().with { $0.name = "projects/test-project/secrets/my-secret" }
  #expect(got == want)
}

@Test("Any encoding GetSecretRequest")
func testEncodingGetSecretRequestMessage() throws {
  let input = GetSecretRequest().with { $0.name = "projects/test-project/secrets/my-secret" }
  let any = try `Any`(fromMessage: input)
  let wrapped = WrappedAny(value: any)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  let data = try encoder.encode(wrapped)
  let got = String(data: data, encoding: .utf8)!

  let want =
    #"{"value":{"@type":"type.googleapis.com/google.cloud.secretmanager.v1.GetSecretRequest","name":"projects/test-project/secrets/my-secret"}}"#
  #expect(got == want)
}

@Test("Any decoding ListSecretVersionsRequest")
func testDecodingListSecretVersionsRequestMessage() throws {
  let jsonString =
    #"{"value":{"@type":"type.googleapis.com/google.cloud.secretmanager.v1.ListSecretVersionsRequest","filter":"state:ENABLED","pageSize":10,"pageToken":"token123","parent":"projects/test-project/secrets/my-secret"}}"#
  let data = Data(jsonString.utf8)
  let decoder = JSONDecoder()
  let wrapped = try decoder.decode(WrappedAny.self, from: data)
  let any = wrapped.value
  #expect(
    any.typeUrl == "type.googleapis.com/google.cloud.secretmanager.v1.ListSecretVersionsRequest")
  let got = try ListSecretVersionsRequest(fromAny: any)
  let want = ListSecretVersionsRequest().with {
    $0.parent = "projects/test-project/secrets/my-secret"
    $0.pageSize = 10
    $0.pageToken = "token123"
    $0.filter = "state:ENABLED"
  }
  #expect(got == want)
}

@Test("Any encoding ListSecretVersionsRequest")
func testEncodingListSecretVersionsRequestMessage() throws {
  let input = ListSecretVersionsRequest().with {
    $0.parent = "projects/test-project/secrets/my-secret"
    $0.pageSize = 10
    $0.pageToken = "token123"
    $0.filter = "state:ENABLED"
  }
  let any = try `Any`(fromMessage: input)
  let wrapped = WrappedAny(value: any)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  let data = try encoder.encode(wrapped)
  let got = String(data: data, encoding: .utf8)!
  let want =
    #"{"value":{"@type":"type.googleapis.com/google.cloud.secretmanager.v1.ListSecretVersionsRequest","filter":"state:ENABLED","pageSize":10,"pageToken":"token123","parent":"projects/test-project/secrets/my-secret"}}"#
  #expect(got == want)
}
