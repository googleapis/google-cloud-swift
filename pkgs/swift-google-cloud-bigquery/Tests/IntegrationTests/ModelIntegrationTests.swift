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

typealias Model = GoogleCloudBigQuery.Model

/// Live tests of models. Models are created with `CREATE MODEL` through the raw transport, so
/// these tests do not depend on the query API.
@Suite(.enabled(if: integrationTestsEnabled()))
struct ModelIntegrationTests {
  let client: BigQueryClient

  init() throws {
    self.client = try IntegrationTest.makeClient()
  }

  // Baseline: IT-054
  @Test func emptyDatasetHasNoModels() async throws {
    try await IntegrationTest.withTemporaryDataset(self.client, slice: "resources") { dataset in
      var pages = self.client.listModels(in: dataset).pages.makeAsyncIterator()
      let page = try #require(try await pages.next())
      #expect(page.items.isEmpty)
      #expect(page.nextPageToken == nil)
      #expect(try await pages.next() == nil)
    }
  }

  // Baseline: IT-053
  @Test func modelLifecycle() async throws {
    try await IntegrationTest.withTemporaryDataset(self.client, slice: "resources") { dataset in
      let id = ModelID(datasetID: dataset.datasetID, modelID: "resources_model")
      try await ResourceQuery.run(
        self.client,
        """
        CREATE MODEL `\(dataset.datasetID).\(id.modelID)`
        OPTIONS (model_type='linear_reg', max_iterations=1, learn_rate=0.4,
                 learn_rate_strategy='constant')
        AS (SELECT 'a' AS f1, 2.0 AS label UNION ALL SELECT 'b' AS f1, 3.8 AS label)
        """)

      let model = try #require(try await self.client.getModel(id))
      #expect(model.id == self.client.resolve(id))
      #expect(model.modelType == .linearRegression)
      #expect(model.etag != nil)
      #expect(model.creationTime != nil)
      #expect(model.location != nil)
      #expect(model.featureColumns.map(\.name) == ["f1"])
      #expect(model.labelColumns.map(\.name) == ["predicted_label"])
      let options = try #require(model.trainingRuns.first?.trainingOptions)
      #expect(options.maxIterations == 1)
      #expect(options.learnRateStrategy == .constant)
      #expect(options.learnRate == 0.4)

      var listed: [ModelID] = []
      for try await model in self.client.listModels(in: dataset) { listed.append(model.id) }
      #expect(listed == [self.client.resolve(id)])

      let expiration = Date().addingTimeInterval(86_400).millisecondsSinceEpoch
      let updated = try await self.client.updateModel(
        Model(
          id: id, friendlyName: "Resources model", description: "updated",
          labels: ["k": "v"],
          expirationTime: Date(millisecondsSinceEpoch: expiration)),
        ifMatch: model.etag)
      #expect(updated.description == "updated")
      #expect(updated.friendlyName == "Resources model")
      #expect(updated.labels == ["k": "v"])
      #expect(updated.expirationTime?.millisecondsSinceEpoch == expiration)
      #expect(updated.modelType == .linearRegression)

      let cleared = try await self.client.updateModel(
        Model(id: id), clearing: [.description, .expirationTime, .label("k")])
      #expect(cleared.description == nil)
      #expect(cleared.expirationTime == nil)
      #expect(cleared.labels == nil)
      #expect(cleared.friendlyName == "Resources model")

      #expect(try await self.client.deleteModel(id))
      #expect(try await self.client.getModel(id) == nil)
      #expect(try await self.client.deleteModel(id) == false)
    }
  }
}

/// Runs DDL through the raw `jobs.query` endpoint and waits for it to finish.
enum ResourceQuery {
  static func run(_ client: BigQueryClient, _ sql: String) async throws {
    let base = "/bigquery/v2/projects/\(client.projectID)/queries"
    let body = try JSONSerialization.data(withJSONObject: [
      "query": sql, "useLegacySql": false, "timeoutMs": 60_000,
    ])
    var response: GetQueryResultsResponse = try await client.transport.json(
      HTTPRequest(method: .post, path: base, body: body), idempotent: false)
    while response.jobComplete != true {
      let job = try #require(response.jobReference)
      response = try await client.transport.json(
        HTTPRequest(
          method: .get, path: "\(base)/\(job.jobId)",
          query: [
            URLQueryItem(name: "location", value: job.location),
            URLQueryItem(name: "timeoutMs", value: "60000"),
          ]),
        idempotent: true)
    }
    #expect(response.errors.isEmpty)
  }
}
