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

@testable import GoogleCloudBigQuery

/// Live tests of table IAM. The table is created with DDL through the raw transport, so these
/// tests do not depend on the table API.
@Suite(.enabled(if: integrationTestsEnabled()))
struct IAMIntegrationTests {
  let client: BigQueryClient

  init() throws {
    self.client = try IntegrationTest.makeClient()
  }

  // Baseline: IT-038
  @Test func tableIAMPolicyLifecycle() async throws {
    try await IntegrationTest.withTemporaryDataset(self.client, slice: "resources") { dataset in
      let table = TableID(datasetID: dataset.datasetID, tableID: "iam_table")
      try await ResourceQuery.run(
        self.client, "CREATE TABLE `\(dataset.datasetID).iam_table` (a STRING)")

      let permissions = ["bigquery.tables.get", "bigquery.tables.getIamPolicy"]
      #expect(
        Set(try await self.client.testIAMPermissions(permissions, for: table)) == Set(permissions))

      let policy = try await self.client.getIAMPolicy(for: table, requestedPolicyVersion: 1)
      let etag = try #require(policy.etag)

      let member = "serviceAccount:\(try await self.client.getServiceAccount())"
      var change = policy
      change.bindings.append(.init(role: "roles/bigquery.dataViewer", members: [member]))
      let stored = try await self.client.setIAMPolicy(change, for: table)
      #expect(
        stored.bindings.contains {
          $0.role == "roles/bigquery.dataViewer" && $0.members == [member]
        })
      #expect(stored.etag != etag)

      // The original etag is stale now; BigQuery reports the conflict as HTTP 400.
      let error = await #expect(throws: BigQueryError.self) {
        try await self.client.setIAMPolicy(policy, for: table)
      }
      #expect(error?.httpStatusCode == 400)

      let reread = try await self.client.getIAMPolicy(for: table)
      #expect(reread.bindings == stored.bindings)
    }
  }
}
