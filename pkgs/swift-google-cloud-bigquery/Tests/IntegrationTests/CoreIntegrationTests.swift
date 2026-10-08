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
import Testing

@testable import GoogleCloudBigQuery

/// Live checks of the core transport and of the integration test helpers themselves.
@Suite(.enabled(if: integrationTestsEnabled()))
struct CoreIntegrationTests {
  // Design: §9
  @Test func temporaryDatasetIsCreatedAndDeleted() async throws {
    let client = try IntegrationTest.makeClient()
    let id = try await IntegrationTest.withTemporaryDataset(client, slice: "core") { id in
      let dataset = try await client.transport.jsonOrNil(
        HTTPRequest(
          method: .get, path: "/bigquery/v2/projects/\(id.projectID!)/datasets/\(id.datasetID)"),
        as: GoogleCloudBigQueryV2.Dataset.self)
      #expect(dataset?.labels[IntegrationTest.label.key] == IntegrationTest.label.value)
      return id
    }
    #expect(id.datasetID.hasPrefix("swift_bq_it_"))
    let gone = try await client.transport.jsonOrNil(
      HTTPRequest(
        method: .get, path: "/bigquery/v2/projects/\(id.projectID!)/datasets/\(id.datasetID)"),
      as: GoogleCloudBigQueryV2.Dataset.self)
    #expect(gone == nil)
  }

  // Design: §4.3
  @Test func serviceErrorsCarryReasonAndStatus() async throws {
    let client = try IntegrationTest.makeClient()
    let error = await #expect(throws: BigQueryError.self) {
      let _: GoogleCloudBigQueryV2.Dataset = try await client.transport.json(
        HTTPRequest(
          method: .post, path: "/bigquery/v2/projects/\(client.projectID)/datasets",
          body: Data(#"{"datasetReference": {"datasetId": "bad id!"}}"#.utf8)),
        idempotent: false)
    }
    #expect(error?.kind == .service)
    #expect(error?.httpStatusCode == 400)
    #expect(error?.reason == "invalid")
  }

  // Design: §9
  @Test func temporaryBucketRoundTripsObjects() async throws {
    try await IntegrationTest.withTemporaryBucket(slice: "core") { bucket in
      let storage = try CloudStorage()
      try await storage.upload(
        bucket: bucket, name: "dir/a b.csv", data: Data("x,y\n".utf8), contentType: "text/csv")
      #expect(try await storage.listObjects(bucket: bucket, prefix: "dir/") == ["dir/a b.csv"])
      #expect(try await storage.download(bucket: bucket, name: "dir/a b.csv") == Data("x,y\n".utf8))
    }
  }

  // Design: §9
  @Test func janitorOnlyDeletesStaleTestResources() async throws {
    #expect(
      IntegrationTest.isStale(
        "swift_bq_it_20200101_x_1", prefix: "swift_bq_it_", cutoff: "20260101"))
    #expect(
      !IntegrationTest.isStale(
        "swift_bq_it_20990101_x_1", prefix: "swift_bq_it_", cutoff: "20260101"))
    #expect(
      !IntegrationTest.isStale("my_dataset_20200101", prefix: "swift_bq_it_", cutoff: "20260101"))
    #expect(
      !IntegrationTest.isStale("swift_bq_it_core", prefix: "swift_bq_it_", cutoff: "20260101"))
    try await IntegrationTest.cleanUpStaleResources(try IntegrationTest.makeClient())
  }
}
