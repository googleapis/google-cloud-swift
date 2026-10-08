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

private let fullModelJSON = #"""
  {
    "etag": "etag-1",
    "modelReference": {"projectId": "p", "datasetId": "d", "modelId": "m"},
    "creationTime": "1700000000000", "lastModifiedTime": "1700000001000",
    "description": "Description", "friendlyName": "Friendly", "labels": {"k": "v"},
    "expirationTime": "1800000000000", "location": "US",
    "encryptionConfiguration": {"kmsKeyName": "key"},
    "modelType": "LINEAR_REGRESSION",
    "trainingRuns": [{
      "startTime": "2023-11-14T22:13:20Z",
      "trainingOptions": {"maxIterations": "5", "lossType": "MEAN_SQUARED_LOSS",
        "learnRate": 0.1, "learnRateStrategy": "CONSTANT", "earlyStop": true,
        "dataSplitColumn": "split"}
    }],
    "featureColumns": [{"name": "f", "type": {"typeKind": "FLOAT64"}}],
    "labelColumns": [{"name": "label", "type": {"typeKind": "FLOAT64"}}]
  }
  """#

@Suite struct ModelTests {
  // Baseline: U.ModelInfo.01
  @Test func decodesEveryField() throws {
    let model = Model(
      wire: try WireJSON.decode(fullModelJSON, as: GoogleCloudBigQueryV2.Model.self))
    #expect(model.id == ModelID(projectID: "p", datasetID: "d", modelID: "m"))
    #expect(model.description == "Description")
    #expect(model.friendlyName == "Friendly")
    #expect(model.labels == ["k": "v"])
    #expect(model.expirationTime == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(model.encryptionConfiguration?.kmsKeyName == "key")
    #expect(model.etag == "etag-1")
    #expect(model.location == "US")
    #expect(model.modelType == .linearRegression)
    #expect(model.creationTime == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(model.lastModifiedTime == Date(timeIntervalSince1970: 1_700_000_001))
    #expect(
      model.trainingRuns == [
        Model.TrainingRun(
          startTime: Date(timeIntervalSince1970: 1_700_000_000),
          trainingOptions: Model.TrainingOptions(
            maxIterations: 5, lossType: .meanSquaredLoss, learnRate: 0.1,
            learnRateStrategy: .constant, earlyStop: true, dataSplitColumn: "split"))
      ])
    #expect(model.featureColumns == [StandardSQLField("f", type: .init(.float64))])
    #expect(model.labelColumns == [StandardSQLField("label", type: .init(.float64))])
  }

  // Baseline: U.ModelInfo.01
  @Test func requestBodyHasOnlyMutableFields() throws {
    let model = Model(
      wire: try WireJSON.decode(fullModelJSON, as: GoogleCloudBigQueryV2.Model.self))
    let body = try RequestBody.json(model.wire, omitting: model.omittedWireDefaults)
    #expect(
      try WireJSON.object(String(decoding: body, as: UTF8.self))
        == WireJSON.object(
          #"""
          {"modelReference": {"projectId": "p", "datasetId": "d", "modelId": "m"},
           "description": "Description", "friendlyName": "Friendly", "labels": {"k": "v"},
           "expirationTime": "1800000000000", "encryptionConfiguration": {"kmsKeyName": "key"}}
          """#))
    let minimal = Model(id: ModelID(projectID: "p", datasetID: "d", modelID: "m"))
    #expect(
      try WireJSON.object(
        String(
          decoding: try RequestBody.json(minimal.wire, omitting: minimal.omittedWireDefaults),
          as: UTF8.self))
        == WireJSON.object(
          #"{"modelReference": {"projectId": "p", "datasetId": "d", "modelId": "m"}}"#))
  }

  // Baseline: U.ModelInfo.01
  @Test func unsetTrainingOptionsAreNil() {
    let options = Model.TrainingOptions(wire: .init())
    #expect(options == Model.TrainingOptions())
  }
}

/// The model methods of `BigQueryClient`, against a scripted transport.
@Suite struct BigQueryClientModelTests {
  let fake = FakeHTTPTransport()
  let modelJSON =
    #"{"modelReference": {"projectId": "test-project", "datasetId": "d", "modelId": "m"}}"#
  let id = ModelID(datasetID: "d", modelID: "m")
  let path = "/bigquery/v2/projects/test-project/datasets/d/models/m"

  // Baseline: U.BigQueryImpl.24, U.Model.02
  @Test func getUsesClientProjectAndSelectedFields() async throws {
    self.fake.enqueue(json: self.modelJSON)
    let model = try await self.fake.client().getModel(self.id, selectedFields: ["labels"])
    let request = try #require(self.fake.requests.first)
    #expect(request.method == .get)
    #expect(request.path == self.path)
    #expect(request.queryValue("fields") == "modelReference,labels")
    #expect(model?.id == ModelID(projectID: "test-project", datasetID: "d", modelID: "m"))
  }

  // Baseline: U.BigQueryImpl.06 (models), U.Model.02
  @Test func getReturnsNilOnNotFound() async throws {
    self.fake.enqueueError(status: 404, reasons: ["notFound"])
    #expect(try await self.fake.client().getModel(self.id) == nil)
  }

  // Baseline: U.BigQueryImpl.24, U.ModelInfo.02, U.Model.02
  @Test func updatePatchesWithClientProject() async throws {
    self.fake.enqueue(json: self.modelJSON)
    _ = try await self.fake.client().updateModel(
      Model(id: self.id, description: "new", labels: ["a": "1"]),
      clearing: [.expirationTime, .label("b")])
    let request = try #require(self.fake.requests.first)
    #expect(request.method == .patch)
    #expect(request.path == self.path)
    #expect(request.headers["If-Match"] == nil)
    let body = try request.jsonBody()
    #expect(
      body["modelReference"] as? NSDictionary == [
        "projectId": "test-project", "datasetId": "d", "modelId": "m",
      ])
    #expect(body["description"] as? String == "new")
    #expect(body["expirationTime"] is NSNull)
    #expect((body["labels"] as? [String: Any])?["a"] as? String == "1")
    #expect((body["labels"] as? [String: Any])?["b"] is NSNull)
    #expect(body["friendlyName"] == nil)
  }

  // Baseline: U.BigQueryImpl.24, U.Model.02
  @Test func deleteReturnsTrueOrFalseOnNotFound() async throws {
    let client = self.fake.client()
    self.fake.enqueue(status: 204, json: "")
    self.fake.enqueueError(status: 404, reasons: ["notFound"])
    #expect(try await client.deleteModel(self.id))
    #expect(try await client.deleteModel(self.id) == false)
    #expect(self.fake.requests.map(\.method) == [.delete, .delete])
    #expect(self.fake.requests.map(\.path) == [self.path, self.path])
  }

  // Baseline: U.BigQueryImpl.25
  @Test func listFollowsPageTokens() async throws {
    self.fake.enqueue(
      json: #"""
        {"models": [{"modelReference": {"projectId": "test-project", "datasetId": "d", "modelId": "a"}}],
         "nextPageToken": "t2"}
        """#)
    self.fake.enqueue(
      json: #"""
        {"models": [{"modelReference": {"projectId": "test-project", "datasetId": "d", "modelId": "b"}}]}
        """#)
    var names: [String] = []
    for try await model in self.fake.client().listModels(in: DatasetID(datasetID: "d")) {
      names.append(model.id.modelID)
    }
    #expect(names == ["a", "b"])
    #expect(
      self.fake.requests.map(\.path)
        == Array(
          repeating: "/bigquery/v2/projects/test-project/datasets/d/models", count: 2))
    #expect(self.fake.requests.map { $0.queryValue("pageToken") } == [nil, "t2"])
  }

  // Baseline: U.BigQueryImpl.25
  @Test func listWithExplicitProjectAndOptions() async throws {
    self.fake.enqueue(json: "{}")
    for try await _ in self.fake.client().listModels(
      in: DatasetID(projectID: "o", datasetID: "d"), pageSize: 3, pageToken: "t1")
    {}
    let request = try #require(self.fake.requests.first)
    #expect(request.path == "/bigquery/v2/projects/o/datasets/d/models")
    #expect(request.queryValue("maxResults") == "3")
    #expect(request.queryValue("pageToken") == "t1")
  }

  // Design: §5.2
  @Test func updateIsRetriedOnlyWithIfMatch() async throws {
    let client = self.fake.client()
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    await #expect(throws: BigQueryError.self) {
      try await client.updateModel(Model(id: self.id))
    }
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    self.fake.enqueue(json: self.modelJSON)
    _ = try await client.updateModel(Model(id: self.id), ifMatch: "e1")
    #expect(self.fake.requests.count == 3)
    #expect(self.fake.requests[2].headers["If-Match"] == "e1")
  }
}
