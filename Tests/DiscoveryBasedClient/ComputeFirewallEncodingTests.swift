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
@testable import GoogleCloudComputeV1
@_spi(GoogleCloudInternal) import GoogleWKT

@Suite struct ComputeFirewallEncodingTests {
  @Test func encodeEmptyFirewallOmitsEmptyCollections() throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let firewall = Firewall()
    let data = try encoder.encode(firewall)
    let jsonString = try #require(String(data: data, encoding: .utf8))

    #expect(jsonString == "{}")
  }

  @Test func encodeFirewallAllowedOmitsDenied() throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    var firewall = Firewall()
    firewall.name = "allow-ssh"
    firewall.allowed = [
      Firewall.Allowed().with {
        $0.ipprotocol = "tcp"
        $0.ports = ["22"]
      }
    ]

    let data = try encoder.encode(firewall)
    let jsonString = try #require(String(data: data, encoding: .utf8))

    #expect(
      jsonString
        == #"{"allowed":[{"IPProtocol":"tcp","ports":["22"]}],"name":"allow-ssh"}"#
    )
    #expect(!jsonString.contains("denied"))
    #expect(!jsonString.contains("sourceRanges"))
  }

  @Test func encodeFirewallPatchOmitsUnmodifiedCollections() throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    var firewall = Firewall()
    firewall.description = "updated description"

    let data = try encoder.encode(firewall)
    let jsonString = try #require(String(data: data, encoding: .utf8))

    #expect(jsonString == #"{"description":"updated description"}"#)
    #expect(!jsonString.contains("allowed"))
    #expect(!jsonString.contains("denied"))
    #expect(!jsonString.contains("sourceRanges"))
    #expect(!jsonString.contains("sourceTags"))
  }
}
