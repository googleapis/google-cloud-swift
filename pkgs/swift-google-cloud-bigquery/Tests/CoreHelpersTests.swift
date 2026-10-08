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
import GoogleCloudBigQueryV2
import GoogleWKT
import Testing

@testable import GoogleCloudBigQuery

@Suite struct RequestBodyTests {
  private let dataset = GoogleCloudBigQueryV2.Dataset().with {
    $0.datasetReference = DatasetID(projectID: "p", datasetID: "d").wire
    $0.labels = ["keep": "1"]
  }

  private func parse(_ data: Data) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: data) as? NSDictionary ?? [:]
  }

  // Design: §5.4
  @Test func omitsUnsetFields() throws {
    let body = try self.parse(try RequestBody.json(self.dataset, omitting: ["location"]))
    #expect(body["description"] == nil)
    #expect(body["location"] == nil)
    #expect((body["labels"] as? NSDictionary)?["keep"] as? String == "1")
  }

  // Design: §5.4
  @Test func writesExplicitNullsAtNestedPaths() throws {
    let data = try RequestBody.json(
      self.dataset,
      setting: ["description": .null, "labels.gone": .null, "a.b.c": .value(.string(""))])
    let body = try self.parse(data)
    #expect(body["description"] is NSNull)
    let labels = try #require(body["labels"] as? NSDictionary)
    #expect(labels["gone"] is NSNull)
    #expect(labels["keep"] as? String == "1")
    let a = try #require(body["a"] as? NSDictionary)
    #expect((a["b"] as? NSDictionary)?["c"] as? String == "")
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(#""description":null"#))
  }
}

@Suite struct ProjectDiscoveryTests {
  // Design: §4.9
  @Test func prefersExplicitThenEnvironment() throws {
    let environment = ["GOOGLE_CLOUD_PROJECT": "env-1", "GCLOUD_PROJECT": "env-2"]
    #expect(
      try ProjectDiscovery.resolve(explicit: "explicit", environment: environment) == "explicit")
    #expect(try ProjectDiscovery.resolve(explicit: nil, environment: environment) == "env-1")
    #expect(
      try ProjectDiscovery.resolve(explicit: "", environment: ["GCLOUD_PROJECT": "env-2"])
        == "env-2")
  }

  // Design: §4.9
  @Test func readsProjectFromCredentialsFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "bq-creds-\(UUID().uuidString).json")
    try Data(#"{"type": "service_account", "project_id": "from-file"}"#.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(
      try ProjectDiscovery.resolve(
        explicit: nil, environment: ["GOOGLE_APPLICATION_CREDENTIALS": url.path]) == "from-file")
  }

  // Design: §4.9
  @Test func throwsInvalidArgumentWithoutProject() {
    let error = #expect(throws: BigQueryError.self) {
      try ProjectDiscovery.resolve(
        explicit: nil, environment: ["GOOGLE_APPLICATION_CREDENTIALS": "/does/not/exist"])
    }
    #expect(error?.kind == .invalidArgument)
  }
}

@Suite struct SharedConfigurationsTests {
  // Baseline: U.TimePartitioning.01, U.TimePartitioning.02
  @Test func timePartitioningWireRoundTrip() throws {
    let wire: GoogleCloudBigQueryV2.TimePartitioning = try WireJSON.decode(
      #"{"type": "HOUR", "expirationMs": "1500", "field": "ts"}"#)
    let partitioning = TimePartitioning(wire: wire)
    #expect(partitioning.type == .hour)
    #expect(partitioning.field == "ts")
    #expect(partitioning.expiration == .milliseconds(1500))
    #expect(try WireJSON.object(partitioning.wire) == WireJSON.object(wire))
    for type in [TimePartitioning.PartitionType.day, .hour, .month, .year] {
      #expect(TimePartitioning(wire: TimePartitioning(type: type).wire).type == type)
    }
    #expect(TimePartitioning(type: .day).wire.expirationMs == nil)
  }

  // Baseline: U.BigQueryImpl.18
  @Test func timePartitioningWithoutTypeIsDay() throws {
    let wire: GoogleCloudBigQueryV2.TimePartitioning = try WireJSON.decode(#"{"field": "ts"}"#)
    #expect(TimePartitioning(wire: wire).type == .day)
  }

  // Design: §4.6
  @Test func rangePartitioningWireRoundTrip() throws {
    let wire: GoogleCloudBigQueryV2.RangePartitioning = try WireJSON.decode(
      #"{"field": "n", "range": {"start": "-10", "end": "100", "interval": "5"}}"#)
    let partitioning = RangePartitioning(wire: wire)
    #expect(partitioning.range == .init(start: -10, end: 100, interval: 5))
    #expect(try WireJSON.object(partitioning.wire) == WireJSON.object(wire))
  }

  // Design: §4.6
  @Test func clusteringAndEncryptionWireRoundTrip() {
    let clustering = Clustering(fields: ["a", "b"])
    #expect(Clustering(wire: clustering.wire) == clustering)
    let encryption = EncryptionConfiguration(kmsKeyName: "projects/p/keys/k")
    #expect(EncryptionConfiguration(wire: encryption.wire) == encryption)
  }

  // Baseline: U.UserDefinedFunction.01
  @Test func userDefinedFunctionWireRoundTrip() throws {
    #expect(UserDefinedFunction(wire: UserDefinedFunction.inline("code").wire) == .inline("code"))
    #expect(
      UserDefinedFunction(wire: UserDefinedFunction.fromURI("gs://b/f.js").wire)
        == .fromURI("gs://b/f.js"))
    #expect(
      try WireJSON.object(UserDefinedFunction.fromURI("gs://b/f.js").wire)
        == WireJSON.object(#"{"resourceUri": "gs://b/f.js"}"#))
    #expect(UserDefinedFunction(wire: GoogleCloudBigQueryV2.UserDefinedFunctionResource()) == nil)
  }

  // Design: §4.6
  @Test func durationWholeMilliseconds() {
    #expect(Duration.seconds(2).wholeMilliseconds == 2000)
    #expect(Duration.milliseconds(1500).wholeMilliseconds == 1500)
    #expect(Duration.microseconds(1999).wholeMilliseconds == 1)
  }

  // Design: §3
  @Test func millisecondsSinceEpochConversions() {
    #expect(Date(millisecondsSinceEpoch: 0) == nil)
    let date = Date(millisecondsSinceEpoch: 1_700_000_000_123)
    #expect(date?.millisecondsSinceEpoch == 1_700_000_000_123)
    #expect(Date(millisecondsSinceEpoch: -1500)?.millisecondsSinceEpoch == -1500)
  }

  // Design: §3
  @Test func timestampConversions() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000.250_001)
    let timestamp = try WKTTimestamp(date: date)
    #expect(timestamp.seconds == 1_700_000_000)
    #expect(timestamp.nanos == 250_001_000)
    #expect(abs(Date(wire: timestamp).timeIntervalSince(date)) < 0.000_001)
    let before = try WKTTimestamp(date: Date(timeIntervalSince1970: -1.5))
    #expect(before.seconds == -2)
    #expect(before.nanos == 500_000_000)
  }
}
