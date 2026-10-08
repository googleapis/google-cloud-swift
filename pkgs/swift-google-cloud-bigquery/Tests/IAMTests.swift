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
import GoogleGax
import Testing

@testable import GoogleCloudBigQuery

@Suite struct IAMPolicyTests {
  // Baseline: U.PolicyHelper.01
  @Test func convertsPolicyWithBindings() throws {
    let json = #"""
      {"version": 3, "etag": "YWJj", "bindings": [
        {"role": "roles/bigquery.dataViewer", "members": ["user:u@example.com", "group:g@example.com"]},
        {"role": "roles/bigquery.dataEditor", "members": ["serviceAccount:s@example.com"],
         "condition": {"expression": "request.time < timestamp('2100-01-01T00:00:00Z')", "title": "t"}}
      ]}
      """#
    let policy = IAMPolicy(wire: try WireJSON.decode(json))
    #expect(policy.version == 3)
    #expect(policy.etag == Data("abc".utf8))
    #expect(
      policy.bindings == [
        .init(
          role: "roles/bigquery.dataViewer", members: ["user:u@example.com", "group:g@example.com"]),
        .init(
          role: "roles/bigquery.dataEditor", members: ["serviceAccount:s@example.com"],
          condition: Expr("request.time < timestamp('2100-01-01T00:00:00Z')", title: "t")),
      ])
    #expect(IAMPolicy(wire: policy.wire) == policy)
  }

  // Baseline: U.PolicyHelper.01
  @Test func convertsPolicyWithoutBindings() throws {
    let policy = IAMPolicy(wire: try WireJSON.decode(#"{"etag": "YWJj"}"#))
    #expect(policy == IAMPolicy(etag: Data("abc".utf8)))
    #expect(IAMPolicy(wire: IAMPolicy().wire) == IAMPolicy())
  }
}

/// The table IAM and project methods of `BigQueryClient`, against a scripted transport.
@Suite struct BigQueryClientIAMTests {
  let fake = FakeHTTPTransport()
  let table = TableID(datasetID: "d", tableID: "t")
  let base = "/bigquery/v2/projects/test-project/datasets/d/tables/t"
  let policyJSON =
    #"{"version": 1, "etag": "YWJj", "bindings": [{"role": "roles/owner", "members": ["user:u@example.com"]}]}"#

  // Baseline: U.BigQueryImpl.69
  @Test func getPostsRequestedPolicyVersion() async throws {
    let client = self.fake.client()
    self.fake.enqueue(json: self.policyJSON)
    self.fake.enqueue(json: self.policyJSON)
    let policy = try await client.getIAMPolicy(for: self.table, requestedPolicyVersion: 3)
    _ = try await client.getIAMPolicy(for: self.table)
    #expect(self.fake.requests.map(\.method) == [.post, .post])
    #expect(
      self.fake.requests.map(\.path) == Array(repeating: "\(self.base):getIamPolicy", count: 2))
    #expect(
      try self.fake.requests[0].jsonBody() as NSDictionary == [
        "options": ["requestedPolicyVersion": 3]
      ])
    #expect(try self.fake.requests[1].jsonBody().isEmpty)
    #expect(policy.version == 1)
    #expect(policy.bindings == [.init(role: "roles/owner", members: ["user:u@example.com"])])
  }

  // Baseline: U.BigQueryImpl.69
  @Test func setPostsPolicy() async throws {
    self.fake.enqueue(json: self.policyJSON)
    let policy = IAMPolicy(
      bindings: [.init(role: "roles/bigquery.dataViewer", members: ["group:g@example.com"])])
    _ = try await self.fake.client().setIAMPolicy(policy, for: self.table)
    let request = try #require(self.fake.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "\(self.base):setIamPolicy")
    #expect(
      try request.jsonBody() as NSDictionary
        == WireJSON.object(
          #"{"policy": {"bindings": [{"role": "roles/bigquery.dataViewer", "members": ["group:g@example.com"]}]}}"#
        ))
  }

  // Baseline: U.BigQueryImpl.69
  @Test func testPermissionsPostsAndReturnsGranted() async throws {
    self.fake.enqueue(json: #"{"permissions": ["bigquery.tables.get"]}"#)
    let granted = try await self.fake.client().testIAMPermissions(
      ["bigquery.tables.get", "bigquery.tables.delete"], for: self.table)
    let request = try #require(self.fake.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "\(self.base):testIamPermissions")
    #expect(
      try request.jsonBody() as NSDictionary == [
        "permissions": ["bigquery.tables.get", "bigquery.tables.delete"]
      ])
    #expect(granted == ["bigquery.tables.get"])
  }

  // Baseline: U.BigQueryImpl.70
  @Test func testPermissionsWithNoneGrantedIsEmpty() async throws {
    self.fake.enqueue(json: "{}")
    #expect(
      try await self.fake.client().testIAMPermissions(["bigquery.tables.get"], for: self.table)
        == [])
  }

  // Design: §5.2
  @Test func setIsRetriedOnlyWithEtag() async throws {
    let client = self.fake.client()
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    await #expect(throws: BigQueryError.self) {
      try await client.setIAMPolicy(IAMPolicy(), for: self.table)
    }
    #expect(self.fake.requests.count == 1)
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    self.fake.enqueue(json: self.policyJSON)
    _ = try await client.setIAMPolicy(IAMPolicy(etag: Data("abc".utf8)), for: self.table)
    #expect(self.fake.requests.count == 3)
    #expect(try self.fake.requests[2].jsonBody() as NSDictionary == ["policy": ["etag": "YWJj"]])
  }

  // Design: §5.2
  @Test func getAndTestAreRetried() async throws {
    let client = self.fake.client()
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    self.fake.enqueue(json: self.policyJSON)
    _ = try await client.getIAMPolicy(for: self.table)
    self.fake.enqueueError(status: 500)
    self.fake.enqueue(json: "{}")
    _ = try await client.testIAMPermissions(["p"], for: self.table)
    #expect(self.fake.requests.count == 4)
  }

  // Baseline: U.BigQueryImpl.08, U.HttpBigQueryRpc.02
  @Test func listProjectsMapsEntries() async throws {
    self.fake.enqueue(
      json: #"""
        {"projects": [{"id": "p1", "numericId": "123", "projectReference": {"projectId": "p1"},
                       "friendlyName": "Project One"},
                      {"id": "p2", "numericId": "456", "projectReference": {"projectId": "p2"}}],
         "nextPageToken": "t2"}
        """#)
    self.fake.enqueue(json: #"{"totalItems": 2}"#)
    var projects: [Project] = []
    for try await project in self.fake.client().listProjects(pageSize: 2) {
      projects.append(project)
    }
    #expect(
      projects == [
        Project(projectID: "p1", numericID: 123, friendlyName: "Project One"),
        Project(projectID: "p2", numericID: 456),
      ])
    #expect(self.fake.requests.map(\.method) == [.get, .get])
    #expect(self.fake.requests.map(\.path) == ["/bigquery/v2/projects", "/bigquery/v2/projects"])
    #expect(self.fake.requests.map { $0.queryValue("maxResults") } == ["2", "2"])
    #expect(self.fake.requests.map { $0.queryValue("pageToken") } == [nil, "t2"])
  }

  // Baseline: U.BigQueryImpl.08
  @Test func listProjectsEmpty() async throws {
    self.fake.enqueue(json: "{}")
    var count = 0
    for try await _ in self.fake.client().listProjects() { count += 1 }
    #expect(count == 0)
  }

  // Design: §4.7
  @Test func getServiceAccountReturnsEmail() async throws {
    let client = self.fake.client()
    self.fake.enqueue(json: #"{"kind": "bigquery#getServiceAccountResponse", "email": "a@b.com"}"#)
    self.fake.enqueue(json: #"{"email": "c@d.com"}"#)
    #expect(try await client.getServiceAccount() == "a@b.com")
    #expect(try await client.getServiceAccount(projectID: "other") == "c@d.com")
    #expect(
      self.fake.requests.map(\.path) == [
        "/bigquery/v2/projects/test-project/serviceAccount",
        "/bigquery/v2/projects/other/serviceAccount",
      ])
  }
}

/// The HTTP method and path of every slice 1 RPC.
@Suite struct ResourceRouteTests {
  typealias Call = @Sendable (BigQueryClient) async throws -> Void

  static let dataset = DatasetID(projectID: "p", datasetID: "d")
  static let routine = RoutineID(projectID: "p", datasetID: "d", routineID: "r")
  static let model = ModelID(projectID: "p", datasetID: "d", modelID: "m")
  static let table = TableID(projectID: "p", datasetID: "d", tableID: "t")

  static let routes: [(String, HTTPMethod, String, Call)] = [
    (
      "datasets.insert", .post, "/projects/p/datasets",
      { _ = try await $0.createDataset(Dataset(id: dataset)) }
    ),
    ("datasets.get", .get, "/projects/p/datasets/d", { _ = try await $0.getDataset(dataset) }),
    (
      "datasets.list", .get, "/projects/p/datasets",
      { for try await _ in $0.listDatasets(projectID: "p") {} }
    ),
    (
      "datasets.patch", .patch, "/projects/p/datasets/d",
      { _ = try await $0.updateDataset(Dataset(id: dataset)) }
    ),
    (
      "datasets.delete", .delete, "/projects/p/datasets/d",
      { _ = try await $0.deleteDataset(dataset) }
    ),
    (
      "routines.insert", .post, "/projects/p/datasets/d/routines",
      { _ = try await $0.createRoutine(Routine(id: routine)) }
    ),
    (
      "routines.get", .get, "/projects/p/datasets/d/routines/r",
      { _ = try await $0.getRoutine(routine) }
    ),
    (
      "routines.list", .get, "/projects/p/datasets/d/routines",
      { for try await _ in $0.listRoutines(in: dataset) {} }
    ),
    (
      "routines.update", .put, "/projects/p/datasets/d/routines/r",
      { _ = try await $0.updateRoutine(Routine(id: routine)) }
    ),
    (
      "routines.delete", .delete, "/projects/p/datasets/d/routines/r",
      { _ = try await $0.deleteRoutine(routine) }
    ),
    ("models.get", .get, "/projects/p/datasets/d/models/m", { _ = try await $0.getModel(model) }),
    (
      "models.list", .get, "/projects/p/datasets/d/models",
      { for try await _ in $0.listModels(in: dataset) {} }
    ),
    (
      "models.patch", .patch, "/projects/p/datasets/d/models/m",
      { _ = try await $0.updateModel(Model(id: model)) }
    ),
    (
      "models.delete", .delete, "/projects/p/datasets/d/models/m",
      { _ = try await $0.deleteModel(model) }
    ),
    (
      "tables.getIamPolicy", .post, "/projects/p/datasets/d/tables/t:getIamPolicy",
      { _ = try await $0.getIAMPolicy(for: table) }
    ),
    (
      "tables.setIamPolicy", .post, "/projects/p/datasets/d/tables/t:setIamPolicy",
      { _ = try await $0.setIAMPolicy(IAMPolicy(), for: table) }
    ),
    (
      "tables.testIamPermissions", .post, "/projects/p/datasets/d/tables/t:testIamPermissions",
      { _ = try await $0.testIAMPermissions([], for: table) }
    ),
    ("projects.list", .get, "/projects", { for try await _ in $0.listProjects() {} }),
    (
      "projects.getServiceAccount", .get, "/projects/p/serviceAccount",
      { _ = try await $0.getServiceAccount(projectID: "p") }
    ),
  ]

  // Baseline: U.HttpBigQueryRpc.03
  @Test(arguments: 0..<Self.routes.count)
  func routesToMethodAndPath(index: Int) async throws {
    let (name, method, path, call) = Self.routes[index]
    let fake = FakeHTTPTransport()
    fake.enqueue(json: #"{"email": "e"}"#)
    try await call(fake.client())
    let request = try #require(fake.requests.first, "\(name)")
    #expect(request.method == method, "\(name)")
    #expect(request.path == "/bigquery/v2" + path, "\(name)")
  }
}
