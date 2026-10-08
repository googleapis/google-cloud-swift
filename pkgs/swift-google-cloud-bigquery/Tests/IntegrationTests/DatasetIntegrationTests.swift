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

/// Live tests of datasets, dataset access lists, projects, and the service account.
@Suite(.enabled(if: integrationTestsEnabled()))
struct DatasetIntegrationTests {
  let client: BigQueryClient

  init() throws {
    self.client = try IntegrationTest.makeClient()
  }

  /// Creates a labeled dataset from `dataset`, runs `body`, and deletes the dataset.
  func withDataset<Result>(
    _ dataset: Dataset, accessPolicyVersion: Int32? = nil,
    _ body: (Dataset) async throws -> Result
  ) async throws -> Result {
    var dataset = dataset
    dataset.labels = (dataset.labels ?? [:]).merging(
      [IntegrationTest.label.key: IntegrationTest.label.value]) { a, _ in a }
    let created = try await self.client.createDataset(
      dataset, accessPolicyVersion: accessPolicyVersion)
    do {
      let result = try await body(created)
      try await IntegrationTest.deleteDataset(self.client, created.id)
      return result
    } catch {
      try? await IntegrationTest.deleteDataset(self.client, created.id)
      throw error
    }
  }

  func newID() -> DatasetID {
    DatasetID(datasetID: IntegrationTest.uniqueName("resources"))
  }

  /// A principal that can be granted dataset access: the project's BigQuery service agent.
  func principal() async throws -> String {
    try await self.client.getServiceAccount()
  }

  // Baseline: IT-002
  @Test func listsDatasetsOfAnotherProject() async throws {
    var datasets: [Dataset] = []
    for try await dataset in self.client.listDatasets(projectID: "bigquery-public-data") {
      datasets.append(dataset)
      if datasets.count >= 5 { break }
    }
    #expect(datasets.count == 5)
    for dataset in datasets {
      #expect(dataset.id.projectID == "bigquery-public-data")
      #expect(dataset.location != nil)
    }
  }

  // Baseline: IT-003
  @Test func listsDatasetsWithLabelFilter() async throws {
    let id = self.newID()
    try await self.withDataset(Dataset(id: id, labels: ["resources-filter": id.datasetID])) { _ in
      var found: [DatasetID] = []
      for try await dataset in self.client.listDatasets(
        filter: "labels.resources-filter:\(id.datasetID)")
      {
        found.append(dataset.id)
      }
      #expect(found == [self.client.resolve(id)])
    }
  }

  // Baseline: IT-004
  @Test func getsDatasetFields() async throws {
    let id = self.newID()
    try await self.withDataset(
      Dataset(id: id, description: "resources dataset", location: "US", labels: ["k": "v"])
    ) { _ in
      let dataset = try #require(try await self.client.getDataset(id))
      #expect(dataset.id == self.client.resolve(id))
      #expect(dataset.description == "resources dataset")
      #expect(dataset.labels?["k"] == "v")
      #expect(dataset.location == "US")
      #expect(dataset.etag != nil)
      #expect(dataset.generatedID == "\(self.client.projectID):\(id.datasetID)")
      #expect(dataset.selfLink != nil)
      let created = try #require(dataset.creationTime)
      #expect(abs(created.timeIntervalSinceNow) < 3600)
      #expect(dataset.lastModifiedTime != nil)
      #expect(dataset.defaultTableExpiration == nil)
    }
  }

  // Baseline: IT-005
  @Test func updatesAccessList() async throws {
    let principal = try await self.principal()
    try await self.withDataset(Dataset(id: self.newID())) { created in
      var access = try #require(created.access)
      access.append(Acl(.user(principal), role: .reader))
      access.append(Acl(.iamMember("serviceAccount:\(principal)"), role: .writer))
      let updated = try await self.client.updateDataset(Dataset(id: created.id, access: access))
      let entries = try #require(updated.access)
      #expect(entries.contains(Acl(.user(principal), role: .reader)))
      #expect(
        entries.contains {
          $0.role == .writer && ($0.entity.iamMember != nil || $0.entity.user == principal)
        })
    }
  }

  // Baseline: IT-006
  @Test func getsDatasetWithSelectedFields() async throws {
    let id = self.newID()
    try await self.withDataset(Dataset(id: id, description: "d", labels: ["k": "v"])) { _ in
      let dataset = try #require(
        try await self.client.getDataset(id, selectedFields: ["creationTime"]))
      #expect(dataset.id == self.client.resolve(id))
      #expect(dataset.creationTime != nil)
      #expect(dataset.description == nil)
      #expect(dataset.labels == nil)
      #expect(dataset.etag == nil)
      #expect(dataset.location == nil)
    }
  }

  // Baseline: IT-007, IT-021
  @Test func createsAndGetsConditionalAccessWithPolicyVersion3() async throws {
    let principal = try await self.principal()
    let condition = Expr(
      "request.time < timestamp('2100-01-01T00:00:00Z')", title: "until 2100",
      description: "resources IT")
    let acl = Acl(.user(principal), role: .reader, condition: condition)
    let dataset = Dataset(
      id: self.newID(),
      access: [Acl(.projectOwners, role: .owner), acl])
    try await self.withDataset(dataset, accessPolicyVersion: 3) { created in
      #expect(created.access?.contains(acl) == true)
      let v3 = try #require(try await self.client.getDataset(created.id, accessPolicyVersion: 3))
      #expect(v3.access?.contains(acl) == true)
      // Earlier policy versions return the entry with a synthetic role and no condition.
      let v1 = try #require(try await self.client.getDataset(created.id, accessPolicyVersion: 1))
      #expect(v1.access?.contains(acl) == false)
      #expect(v1.access?.contains { $0.entity.user == principal && $0.condition == nil } == true)
    }
  }

  // Baseline: IT-008
  @Test func patchesDatasetAndClearsLabels() async throws {
    try await self.withDataset(
      Dataset(id: self.newID(), description: "before", labels: ["a": "1", "b": "2"])
    ) { created in
      var change = Dataset(
        id: created.id, description: "after", labels: ["c": "3"], maxTimeTravelHours: 120,
        storageBillingModel: .logical)
      change.friendlyName = "friendly"
      let updated = try await self.client.updateDataset(change, clearing: [.label("a")])
      #expect(updated.description == "after")
      #expect(updated.friendlyName == "friendly")
      #expect(updated.labels?["a"] == nil)
      #expect(updated.labels?["b"] == "2")
      #expect(updated.labels?["c"] == "3")
      #expect(updated.maxTimeTravelHours == 120)
      #expect(updated.storageBillingModel == .logical)

      let cleared = try await self.client.updateDataset(
        Dataset(id: created.id), clearing: [.labels, .description, .friendlyName])
      #expect(cleared.labels == nil)
      #expect(cleared.description == nil)
      #expect(cleared.friendlyName == nil)
      #expect(cleared.maxTimeTravelHours == 120)
    }
  }

  // Baseline: IT-009
  @Test func patchesDatasetWithSelectedFields() async throws {
    try await self.withDataset(Dataset(id: self.newID(), labels: ["k": "v"])) { created in
      let updated = try await self.client.updateDataset(
        Dataset(id: created.id, description: "selected"), selectedFields: ["description"])
      #expect(updated.id == created.id)
      #expect(updated.description == "selected")
      #expect(updated.labels == nil)
      #expect(updated.etag == nil)
    }
  }

  // Baseline: IT-010
  @Test func patchesConditionalAccessWithPolicyVersion3() async throws {
    let principal = try await self.principal()
    try await self.withDataset(Dataset(id: self.newID())) { created in
      let acl = Acl(
        .user(principal), role: .reader,
        condition: Expr("request.time < timestamp('2100-01-01T00:00:00Z')", title: "t"))
      var access = try #require(created.access)
      access.append(acl)
      let updated = try await self.client.updateDataset(
        Dataset(id: created.id, access: access), accessPolicyVersion: 3)
      #expect(updated.access?.contains(acl) == true)
    }
  }

  // Design: §5.4
  @Test func etagGuardsUpdates() async throws {
    try await self.withDataset(Dataset(id: self.newID())) { created in
      let etag = try #require(created.etag)
      let updated = try await self.client.updateDataset(
        Dataset(id: created.id, description: "v1"), ifMatch: etag)
      #expect(updated.etag != etag)
      let error = await #expect(throws: BigQueryError.self) {
        try await self.client.updateDataset(
          Dataset(id: created.id, description: "v2"), ifMatch: etag)
      }
      #expect(error?.httpStatusCode == 412)
    }
  }

  // Baseline: IT-017
  @Test func createsDatasetWithStorageBillingModel() async throws {
    try await self.withDataset(Dataset(id: self.newID(), storageBillingModel: .logical)) {
      #expect($0.storageBillingModel == .logical)
    }
  }

  // Baseline: IT-018
  @Test func createsDatasetWithMaxTimeTravelHours() async throws {
    try await self.withDataset(Dataset(id: self.newID(), maxTimeTravelHours: 120)) {
      #expect($0.maxTimeTravelHours == 120)
    }
  }

  // Baseline: IT-019
  @Test func createsDatasetWithDefaultMaxTimeTravelHours() async throws {
    try await self.withDataset(Dataset(id: self.newID())) { created in
      let fetched = try await self.client.getDataset(created.id)
      #expect(fetched?.maxTimeTravelHours == 168)
    }
  }

  // Baseline: IT-020
  @Test func createsDatasetWithDefaultCollation() async throws {
    try await self.withDataset(Dataset(id: self.newID(), defaultCollation: "und:ci")) {
      #expect($0.defaultCollation == "und:ci")
    }
  }

  // Baseline: IT-022
  @Test func rejectsInvalidAccessPolicyVersion() async throws {
    let id = self.newID()
    let error = await #expect(throws: BigQueryError.self) {
      try await self.withDataset(Dataset(id: id), accessPolicyVersion: 4) { _ in }
    }
    #expect(error?.httpStatusCode == 400)
    #expect(try await self.client.getDataset(id) == nil)
  }

  // Baseline: IT-062
  @Test func authorizesDataset() async throws {
    try await self.withDataset(Dataset(id: self.newID())) { source in
      try await self.withDataset(Dataset(id: self.newID())) { authorized in
        let acl = Acl(.dataset(authorized.id, targetTypes: [.views]))
        var access = try #require(source.access)
        access.append(acl)
        let updated = try await self.client.updateDataset(Dataset(id: source.id, access: access))
        #expect(updated.access?.contains(acl) == true)
      }
    }
  }

  // Design: §5.3
  @Test func missingDatasetIsNilAndDeleteReturnsFalse() async throws {
    let id = self.newID()
    #expect(try await self.client.getDataset(id) == nil)
    #expect(try await self.client.deleteDataset(id) == false)
  }

  // Design: §4.7
  @Test func deletesDatasetWithContents() async throws {
    let created = try await self.client.createDataset(
      Dataset(
        id: self.newID(), labels: [IntegrationTest.label.key: IntegrationTest.label.value]))
    do {
      _ = try await self.client.createRoutine(
        Routine(
          id: RoutineID(datasetID: created.id.datasetID, routineID: "f"), type: .scalarFunction,
          language: .sql, body: "1"))
      let error = await #expect(throws: BigQueryError.self) {
        try await self.client.deleteDataset(created.id)
      }
      #expect(error?.httpStatusCode == 400)
      #expect(try await self.client.deleteDataset(created.id, deleteContents: true))
    } catch {
      try? await IntegrationTest.deleteDataset(self.client, created.id)
      throw error
    }
  }

  // Design: §11
  @Test func listsProjects() async throws {
    // The caller may see many projects; check the first page only.
    var pages = self.client.listProjects(pageSize: 10).pages.makeAsyncIterator()
    let page = try #require(try await pages.next())
    #expect(!page.items.isEmpty)
    for project in page.items {
      #expect(!project.projectID.isEmpty)
      #expect(project.numericID != nil)
    }
  }

  // Design: §4.7
  @Test func getsServiceAccount() async throws {
    let email = try await self.client.getServiceAccount()
    #expect(email.hasSuffix(".iam.gserviceaccount.com"))
  }
}
