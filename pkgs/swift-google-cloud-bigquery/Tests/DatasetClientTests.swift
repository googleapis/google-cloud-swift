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

/// The dataset methods of `BigQueryClient`, against a scripted transport.
@Suite struct BigQueryClientDatasetTests {
  let fake = FakeHTTPTransport()
  let datasetJSON = #"{"datasetReference": {"projectId": "test-project", "datasetId": "d"}}"#

  // Baseline: U.BigQueryImpl.02
  @Test func createPostsToClientProject() async throws {
    self.fake.enqueue(json: self.datasetJSON)
    let created = try await self.fake.client().createDataset(
      Dataset(id: DatasetID(datasetID: "d"), description: "x"))
    let request = try #require(self.fake.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/bigquery/v2/projects/test-project/datasets")
    #expect(
      try request.jsonBody() as NSDictionary
        == WireJSON.object(
          #"{"datasetReference": {"projectId": "test-project", "datasetId": "d"}, "description": "x"}"#
        ))
    #expect(created.id == DatasetID(projectID: "test-project", datasetID: "d"))
  }

  // Baseline: U.BigQueryImpl.02
  @Test func createUsesProjectOfDatasetID() async throws {
    self.fake.enqueue(json: #"{"datasetReference": {"projectId": "other", "datasetId": "d"}}"#)
    _ = try await self.fake.client().createDataset(
      Dataset(id: DatasetID(projectID: "other", datasetID: "d")))
    #expect(self.fake.requests.first?.path == "/bigquery/v2/projects/other/datasets")
  }

  // Baseline: U.BigQueryImpl.03
  @Test func selectedFieldsAlwaysIncludeReference() async throws {
    let client = self.fake.client()
    let id = DatasetID(datasetID: "d")
    for _ in 0..<3 { self.fake.enqueue(json: self.datasetJSON) }
    _ = try await client.createDataset(
      Dataset(id: id), selectedFields: ["access", "etag", "datasetReference"])
    _ = try await client.getDataset(id, selectedFields: ["access", "etag"])
    _ = try await client.updateDataset(Dataset(id: id), selectedFields: ["access", "etag"])
    for request in self.fake.requests {
      #expect(request.queryValue("fields") == "datasetReference,access,etag")
    }
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await client.getDataset(id)
    #expect(self.fake.requests.last?.queryValue("fields") == nil)
  }

  // Baseline: U.BigQueryImpl.04
  @Test func createPassesAccessPolicyVersion() async throws {
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await self.fake.client().createDataset(
      Dataset(id: DatasetID(datasetID: "d")), accessPolicyVersion: 3)
    #expect(self.fake.requests.first?.queryValue("accessPolicyVersion") == "3")
  }

  // Baseline: U.BigQueryImpl.05, U.Dataset.02
  @Test func getFillsMissingProjectAndKeepsExplicitProject() async throws {
    let client = self.fake.client()
    self.fake.enqueue(json: self.datasetJSON)
    self.fake.enqueue(json: #"{"datasetReference": {"projectId": "other", "datasetId": "d"}}"#)
    let dataset = try await client.getDataset(DatasetID(datasetID: "d"))
    let other = try await client.getDataset(DatasetID(projectID: "other", datasetID: "d"))
    #expect(self.fake.requests.map(\.method) == [.get, .get])
    #expect(
      self.fake.requests.map(\.path) == [
        "/bigquery/v2/projects/test-project/datasets/d", "/bigquery/v2/projects/other/datasets/d",
      ])
    #expect(dataset?.id == DatasetID(projectID: "test-project", datasetID: "d"))
    #expect(other?.id == DatasetID(projectID: "other", datasetID: "d"))
  }

  // Design: §4.7
  @Test func getPassesViewAndAccessPolicyVersion() async throws {
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await self.fake.client().getDataset(
      DatasetID(datasetID: "d"), view: .acl, accessPolicyVersion: 3)
    let request = try #require(self.fake.requests.first)
    #expect(request.queryValue("datasetView") == "ACL")
    #expect(request.queryValue("accessPolicyVersion") == "3")
  }

  // Baseline: U.BigQueryImpl.06 (datasets), U.Dataset.02; Design: §5.3
  @Test func getReturnsNilOnNotFound() async throws {
    self.fake.enqueueError(status: 404, reasons: ["notFound"])
    #expect(try await self.fake.client().getDataset(DatasetID(datasetID: "d")) == nil)
  }

  // Design: §5.3
  @Test func getThrowsOtherErrors() async throws {
    self.fake.enqueueError(status: 403, reasons: ["accessDenied"])
    let error = await #expect(throws: BigQueryError.self) {
      try await self.fake.client().getDataset(DatasetID(datasetID: "d"))
    }
    #expect(error?.httpStatusCode == 403)
  }

  // Baseline: U.BigQueryImpl.07
  @Test func listFollowsPageTokens() async throws {
    self.fake.enqueue(
      json: #"""
        {"datasets": [{"datasetReference": {"projectId": "test-project", "datasetId": "a"}}],
         "nextPageToken": "t2"}
        """#)
    self.fake.enqueue(
      json:
        #"{"datasets": [{"datasetReference": {"projectId": "test-project", "datasetId": "b"}}]}"#
    )
    var names: [String] = []
    for try await dataset in self.fake.client().listDatasets() {
      names.append(dataset.id.datasetID)
    }
    #expect(names == ["a", "b"])
    #expect(
      self.fake.requests.map(\.path)
        == Array(
          repeating: "/bigquery/v2/projects/test-project/datasets", count: 2))
    #expect(self.fake.requests.map { $0.queryValue("pageToken") } == [nil, "t2"])
  }

  // Baseline: U.BigQueryImpl.07
  @Test func listPassesProjectAndOptions() async throws {
    self.fake.enqueue(json: #"{"datasets": []}"#)
    let pages = self.fake.client().listDatasets(
      projectID: "other", all: true, filter: "labels.env:prod", pageSize: 42, pageToken: "t1"
    ).pages
    var count = 0
    for try await page in pages {
      #expect(page.items.isEmpty)
      #expect(page.nextPageToken == nil)
      count += 1
    }
    #expect(count == 1)
    let request = try #require(self.fake.requests.first)
    #expect(request.path == "/bigquery/v2/projects/other/datasets")
    #expect(request.queryValue("all") == "true")
    #expect(request.queryValue("filter") == "labels.env:prod")
    #expect(request.queryValue("maxResults") == "42")
    #expect(request.queryValue("pageToken") == "t1")
  }

  // Baseline: U.BigQueryImpl.07
  @Test func listOfEmptyProjectHasNoItems() async throws {
    self.fake.enqueue(json: "{}")
    var count = 0
    for try await _ in self.fake.client().listDatasets() { count += 1 }
    #expect(count == 0)
  }

  // Baseline: U.BigQueryImpl.09, U.Dataset.02
  @Test func deleteReturnsTrue() async throws {
    let client = self.fake.client()
    self.fake.enqueue(status: 204, json: "")
    self.fake.enqueue(status: 204, json: "")
    #expect(try await client.deleteDataset(DatasetID(datasetID: "d")))
    #expect(try await client.deleteDataset(DatasetID(projectID: "other", datasetID: "d")))
    #expect(self.fake.requests.map(\.method) == [.delete, .delete])
    #expect(
      self.fake.requests.map(\.path) == [
        "/bigquery/v2/projects/test-project/datasets/d", "/bigquery/v2/projects/other/datasets/d",
      ])
    #expect(self.fake.requests.first?.queryValue("deleteContents") == nil)
  }

  // Baseline: U.Dataset.02; Design: §5.3
  @Test func deleteReturnsFalseOnNotFound() async throws {
    self.fake.enqueueError(status: 404, reasons: ["notFound"])
    #expect(try await self.fake.client().deleteDataset(DatasetID(datasetID: "d")) == false)
  }

  // Baseline: U.BigQueryImpl.10
  @Test func deletePassesDeleteContents() async throws {
    self.fake.enqueue(status: 204, json: "")
    try await self.fake.client().deleteDataset(DatasetID(datasetID: "d"), deleteContents: true)
    #expect(self.fake.requests.first?.queryValue("deleteContents") == "true")
  }

  // Baseline: U.BigQueryImpl.11, U.Dataset.02
  @Test func updatePatchesWithClientProject() async throws {
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await self.fake.client().updateDataset(
      Dataset(id: DatasetID(datasetID: "d"), friendlyName: "F", labels: ["k": "v"]),
      updateMode: .updateMetadata, accessPolicyVersion: 3)
    let request = try #require(self.fake.requests.first)
    #expect(request.method == .patch)
    #expect(request.path == "/bigquery/v2/projects/test-project/datasets/d")
    #expect(request.queryValue("updateMode") == "UPDATE_METADATA")
    #expect(request.queryValue("accessPolicyVersion") == "3")
    #expect(request.headers["If-Match"] == nil)
    #expect(
      try request.jsonBody() as NSDictionary
        == WireJSON.object(
          #"""
          {"datasetReference": {"projectId": "test-project", "datasetId": "d"},
           "friendlyName": "F", "labels": {"k": "v"}}
          """#))
  }

  // Baseline: U.Annotations.01; Design: §5.4
  @Test func updateClearingSendsJSONNull() async throws {
    let client = self.fake.client()
    self.fake.enqueue(json: self.datasetJSON)
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await client.updateDataset(
      Dataset(id: DatasetID(datasetID: "d"), description: "set", labels: ["a": "1"]),
      clearing: [.label("b"), .friendlyName, .defaultTableExpiration])
    _ = try await client.updateDataset(
      Dataset(id: DatasetID(datasetID: "d"), description: "set"), clearing: [.labels])
    let first = try self.fake.requests[0].jsonBody()
    #expect(first["description"] as? String == "set")
    #expect(first["friendlyName"] is NSNull)
    #expect(first["defaultTableExpirationMs"] is NSNull)
    let labels = try #require(first["labels"] as? [String: Any])
    #expect(labels["a"] as? String == "1")
    #expect(labels["b"] is NSNull)
    #expect(try self.fake.requests[1].jsonBody()["labels"] is NSNull)
  }

  // Baseline: U.Annotations.01
  @Test func updateWithEmptyLabelsOmitsThem() async throws {
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await self.fake.client().updateDataset(
      Dataset(id: DatasetID(datasetID: "d"), labels: [:]))
    #expect(try self.fake.requests[0].jsonBody()["labels"] == nil)
  }

  // Design: §5.2
  @Test func createIsNotRetried() async throws {
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    await #expect(throws: BigQueryError.self) {
      try await self.fake.client().createDataset(Dataset(id: DatasetID(datasetID: "d")))
    }
    #expect(self.fake.requests.count == 1)
  }

  // Design: §5.2
  @Test func updateIsRetriedOnlyWithIfMatch() async throws {
    let client = self.fake.client()
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    await #expect(throws: BigQueryError.self) {
      try await client.updateDataset(Dataset(id: DatasetID(datasetID: "d")))
    }
    #expect(self.fake.requests.count == 1)

    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await client.updateDataset(Dataset(id: DatasetID(datasetID: "d")), ifMatch: "e1")
    #expect(self.fake.requests.count == 3)
    #expect(self.fake.requests[2].headers["If-Match"] == "e1")
  }

  // Design: §5.2
  @Test func getListAndDeleteAreRetried() async throws {
    let client = self.fake.client()
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await client.getDataset(DatasetID(datasetID: "d"))
    self.fake.enqueueError(status: 500)
    self.fake.enqueue(json: "{}")
    for try await _ in client.listDatasets() {}
    self.fake.enqueueError(status: 502)
    self.fake.enqueue(status: 204, json: "")
    #expect(try await client.deleteDataset(DatasetID(datasetID: "d")))
    #expect(self.fake.requests.count == 6)
  }

  // Baseline: U.BigQueryImpl.59
  @Test func getRetries500AndKeepsMessageOf501() async throws {
    let client = self.fake.client()
    self.fake.enqueueError(status: 500, message: "internal")
    self.fake.enqueue(json: self.datasetJSON)
    #expect(try await client.getDataset(DatasetID(datasetID: "d")) != nil)
    #expect(self.fake.requests.count == 2)

    self.fake.enqueueError(status: 501, message: "not implemented")
    let error = await #expect(throws: BigQueryError.self) {
      try await client.getDataset(DatasetID(datasetID: "d"))
    }
    #expect(self.fake.requests.count == 3)
    #expect(error?.httpStatusCode == 501)
    #expect(error?.message == "not implemented")
  }

  // Baseline: U.Dataset.03
  @Test func tableOfDatasetInAnotherProjectUsesThatProject() async throws {
    let dataset = DatasetID(projectID: "other", datasetID: "d")
    self.fake.enqueue(
      json: #"{"tableReference": {"projectId": "other", "datasetId": "d", "tableId": "t"}}"#)
    let table = try await self.fake.client().getTable(
      TableID(projectID: dataset.projectID, datasetID: dataset.datasetID, tableID: "t"))
    #expect(self.fake.requests.first?.path == "/bigquery/v2/projects/other/datasets/d/tables/t")
    #expect(table?.id == TableID(projectID: "other", datasetID: "d", tableID: "t"))
  }

  // Design: §5.4
  @Test func clearingResourceTagKeepsDotsInKey() async throws {
    self.fake.enqueue(json: self.datasetJSON)
    _ = try await self.fake.client().updateDataset(
      Dataset(id: DatasetID(datasetID: "d")),
      clearing: [.resourceTag("example.com:project/env")])
    let tags = try self.fake.requests[0].jsonBody()["resourceTags"] as? [String: Any]
    #expect(tags?["example.com:project/env"] is NSNull)
  }
}
