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
import GoogleAuth
import GoogleGax
import Testing

@testable import GoogleCloudBigQuery

@Suite struct BigQueryClientTests {
  // Design: §4.9
  @Test func internalInitKeepsProjectAndLocation() {
    let client = FakeHTTPTransport().client(projectID: "my-project", location: "EU")
    #expect(client.projectID == "my-project")
    #expect(client.location == "EU")
    #expect(BigQueryClient.defaultEndpoint == "https://bigquery.googleapis.com")
  }

  // Design: §4.9
  @Test func publicInitUsesExplicitProject() throws {
    let client = try BigQueryClient(
      BigQueryClientOptions().with {
        $0.projectID = "explicit-project"
        $0.client.credentials = try! Credentials(configuration: .anonymous)
      })
    #expect(client.projectID == "explicit-project")
  }

  // Design: §4.1
  @Test func optionsDefaultAttemptTimeoutIsSixtySeconds() {
    #expect(BigQueryClientOptions().client.attemptTimeout == .seconds(60))
  }

  // Design: §4.9
  @Test func resolveFillsMissingProjectAndLocation() {
    let client = FakeHTTPTransport().client(projectID: "p", location: "US")
    #expect(client.resolve(DatasetID(datasetID: "d")).projectID == "p")
    #expect(client.resolve(DatasetID(projectID: "other", datasetID: "d")).projectID == "other")
    #expect(client.resolve(TableID(datasetID: "d", tableID: "t")).projectID == "p")
    #expect(client.resolve(RoutineID(datasetID: "d", routineID: "r")).projectID == "p")
    #expect(client.resolve(ModelID(datasetID: "d", modelID: "m")).projectID == "p")
    let job = client.resolve(JobID(jobID: "j"))
    #expect(job.projectID == "p")
    #expect(job.location == "US")
    #expect(client.resolve(JobID(jobID: "j", location: "EU")).location == "EU")
  }
}
