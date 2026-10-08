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

@Suite struct DatasetIDTests {
  // Baseline: U.DatasetId.01
  @Test func parsesWithAndWithoutProject() throws {
    #expect(try DatasetID("d") == DatasetID(datasetID: "d"))
    #expect(try DatasetID("p.d") == DatasetID(projectID: "p", datasetID: "d"))
    #expect(try DatasetID("p:d") == DatasetID(projectID: "p", datasetID: "d"))
    #expect(
      try DatasetID("example.com:p.d") == DatasetID(projectID: "example.com:p", datasetID: "d"))
    #expect(DatasetID(projectID: "p", datasetID: "d").description == "p.d")
    #expect(DatasetID(datasetID: "d").description == "d")
  }

  // Design: §4.2
  @Test func rejectsMalformedStrings() {
    for bad in ["", ".d", "p.", "p..d"] {
      #expect(throws: BigQueryError.self) { try DatasetID(bad) }
    }
  }

  // Baseline: U.DatasetId.02
  @Test func wireRoundTrip() {
    let id = DatasetID(projectID: "p", datasetID: "d")
    #expect(id.wire.projectId == "p")
    #expect(id.wire.datasetId == "d")
    #expect(DatasetID(wire: id.wire) == id)
    #expect(DatasetID(datasetID: "d").wire.projectId == "")
    #expect(DatasetID(wire: DatasetID(datasetID: "d").wire).projectID == nil)
  }

  // Baseline: U.DatasetId.03
  @Test func clientFillsMissingProject() {
    let client = FakeHTTPTransport().client(projectID: "p")
    #expect(client.resolve(DatasetID(datasetID: "d")) == DatasetID(projectID: "p", datasetID: "d"))
  }
}

@Suite struct TableIDTests {
  // Baseline: U.TableId.01
  @Test func parsesWithAndWithoutProject() throws {
    #expect(try TableID("d.t") == TableID(datasetID: "d", tableID: "t"))
    #expect(try TableID("p.d.t") == TableID(projectID: "p", datasetID: "d", tableID: "t"))
    #expect(try TableID("p:d.t") == TableID(projectID: "p", datasetID: "d", tableID: "t"))
    #expect(
      try TableID("example.com:p.d.t")
        == TableID(projectID: "example.com:p", datasetID: "d", tableID: "t"))
    #expect(try TableID("d.t$20240101").tableID == "t$20240101")
    #expect(TableID(projectID: "p", datasetID: "d", tableID: "t").description == "p.d.t")
    #expect(
      TableID(dataset: DatasetID(projectID: "p", datasetID: "d"), tableID: "t").dataset
        == DatasetID(projectID: "p", datasetID: "d"))
    #expect(throws: BigQueryError.self) { try TableID("t") }
  }

  // Baseline: U.TableId.02
  @Test func wireRoundTrip() {
    let id = TableID(projectID: "p", datasetID: "d", tableID: "t")
    #expect(id.wire.tableId == "t")
    #expect(TableID(wire: id.wire) == id)
  }

  // Baseline: U.TableId.03
  @Test func clientFillsMissingProject() {
    let client = FakeHTTPTransport().client(projectID: "p")
    #expect(client.resolve(TableID(datasetID: "d", tableID: "t")).projectID == "p")
  }
}

@Suite struct RoutineIDTests {
  // Baseline: U.RoutineId.01
  @Test func parsesWithAndWithoutProject() throws {
    #expect(try RoutineID("d.r") == RoutineID(datasetID: "d", routineID: "r"))
    #expect(try RoutineID("p.d.r") == RoutineID(projectID: "p", datasetID: "d", routineID: "r"))
    #expect(RoutineID(projectID: "p", datasetID: "d", routineID: "r").description == "p.d.r")
  }

  // Baseline: U.RoutineId.02
  @Test func wireRoundTrip() {
    let id = RoutineID(projectID: "p", datasetID: "d", routineID: "r")
    #expect(id.wire.routineId == "r")
    #expect(RoutineID(wire: id.wire) == id)
  }

  // Baseline: U.RoutineId.03
  @Test func clientFillsMissingProject() {
    let client = FakeHTTPTransport().client(projectID: "p")
    #expect(client.resolve(RoutineID(datasetID: "d", routineID: "r")).projectID == "p")
  }
}

@Suite struct ModelIDTests {
  // Baseline: U.ModelId.01
  @Test func parsesWithAndWithoutProject() throws {
    #expect(try ModelID("d.m") == ModelID(datasetID: "d", modelID: "m"))
    #expect(try ModelID("p.d.m") == ModelID(projectID: "p", datasetID: "d", modelID: "m"))
    #expect(ModelID(projectID: "p", datasetID: "d", modelID: "m").description == "p.d.m")
  }

  // Baseline: U.ModelId.02
  @Test func wireRoundTrip() {
    let id = ModelID(projectID: "p", datasetID: "d", modelID: "m")
    #expect(id.wire.modelId == "m")
    #expect(ModelID(wire: id.wire) == id)
  }

  // Baseline: U.ModelId.03
  @Test func clientFillsMissingProject() {
    let client = FakeHTTPTransport().client(projectID: "p")
    #expect(client.resolve(ModelID(datasetID: "d", modelID: "m")).projectID == "p")
  }
}

@Suite struct JobIDTests {
  // Design: §4.2
  @Test func randomIDsAreUniqueAndPrefixed() {
    let first = JobID.random(prefix: "load_")
    let second = JobID.random(prefix: "load_")
    #expect(first.jobID.hasPrefix("load_"))
    #expect(first != second)
    #expect(first.projectID == nil)
    #expect(first.location == nil)
  }

  // Design: §4.2
  @Test func descriptionUsesBQToolForm() {
    #expect(JobID(projectID: "p", jobID: "j", location: "EU").description == "p:EU.j")
    #expect(JobID(jobID: "j").description == "j")
  }

  // Design: §4.9
  @Test func wireRoundTripKeepsLocation() {
    let id = JobID(projectID: "p", jobID: "j", location: "EU")
    #expect(id.wire.location == "EU")
    #expect(JobID(wire: id.wire) == id)
  }

  // Design: §4.9
  @Test func clientFillsMissingProjectAndLocation() {
    let client = FakeHTTPTransport().client(projectID: "p", location: "asia-northeast1")
    #expect(
      client.resolve(JobID(jobID: "j"))
        == JobID(projectID: "p", jobID: "j", location: "asia-northeast1"))
  }
}
