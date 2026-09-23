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

// Verify the generated Discovery enums behave strictly as string-based enums:
// - Deserializes known strings into the matching enum case.
// - Deserializes unknown strings into .unknownStringValue(String).
// - Rejects integer values with DecodingError.
// - Serializes enum cases to their wire string representations.
@Suite struct DiscoveryEnums {
  typealias T = DiscoveryWithEnums
  typealias Status = DiscoveryWithEnums.Status

  @Test(
    arguments: [
      (#"{}"#, T()),
      (#"{"status": null}"#, T()),
      (#"{"status": "ACTIVE"}"#, T().with { $0.status = .active }),
      (#"{"status": "DELETING"}"#, T().with { $0.status = .deleting }),
      (#"{"status": "ERROR"}"#, T().with { $0.status = .error }),
      (#"{"status": "PENDING"}"#, T().with { $0.status = .pending }),
      (
        #"{"status": "CUSTOM_NEW_VALUE"}"#,
        T().with { $0.status = .unknownStringValue("CUSTOM_NEW_VALUE") }
      ),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    arguments: [
      (#"{}"#, T()),
      (#"{"status":"ACTIVE"}"#, T().with { $0.status = .active }),
      (#"{"status":"DELETING"}"#, T().with { $0.status = .deleting }),
      (#"{"status":"ERROR"}"#, T().with { $0.status = .error }),
      (#"{"status":"PENDING"}"#, T().with { $0.status = .pending }),
      (
        #"{"status":"CUSTOM_NEW_VALUE"}"#,
        T().with { $0.status = .unknownStringValue("CUSTOM_NEW_VALUE") }
      ),
    ])
  func roundtrip(want: String, input: T) throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let got = String(data: data, encoding: .utf8)!
    #expect(want == got)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(T.self, from: data)
    #expect(input == roundtrip)
  }

  @Test func integerTypeThrows() throws {
    let decoder = _ProtoJSONDecoder()
    let input = #"{"status": 0}"#
    #expect(throws: DecodingError.self) {
      try decoder.decode(T.self, from: Data(input.utf8))
    }
  }

  @Test func stringValueAndInitializers() {
    #expect(Status.active.stringValue == "ACTIVE")
    #expect(Status.deleting.stringValue == "DELETING")
    #expect(Status.error.stringValue == "ERROR")
    #expect(Status.pending.stringValue == "PENDING")
    #expect(Status.unknownStringValue("OTHER").stringValue == "OTHER")

    #expect(Status(stringValue: "ACTIVE") == .active)
    #expect(Status(stringValue: "DELETING") == .deleting)
    #expect(Status(stringValue: "ERROR") == .error)
    #expect(Status(stringValue: "PENDING") == .pending)
    #expect(Status(stringValue: "OTHER") == .unknownStringValue("OTHER"))
  }
}
