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

import GoogleCloudDatastore
import GoogleGax
import Testing

@Suite struct DatastoreClientOptionsTests {
  @Test func defaultOptions() throws {
    let options = DatastoreClientOptions(projectId: "my-project")
    #expect(options.projectId == "my-project")
    #expect(options.databaseId == "")
    #expect(options.namespaceId == "")
    #expect(options.maxTransactionAttempts == 5)

    let client = try DatastoreClient(options)
    #expect(client.projectId == "my-project")
    #expect(client.databaseId == "")
    #expect(client.namespaceId == "")
  }

  @Test func customOptionsWithMutator() throws {
    let options = DatastoreClientOptions(projectId: "p1").with {
      $0.databaseId = "db-1"
      $0.namespaceId = "ns-1"
      $0.maxTransactionAttempts = 3
      $0.client.endpoint = "http://localhost:8081"
    }
    #expect(options.projectId == "p1")
    #expect(options.databaseId == "db-1")
    #expect(options.namespaceId == "ns-1")
    #expect(options.maxTransactionAttempts == 3)
    #expect(options.client.endpoint == "http://localhost:8081")
  }

  @Test func emptyProjectIdThrows() {
    #expect(throws: DatastoreError.invalidArgument("projectId must not be empty")) {
      _ = try DatastoreClient(DatastoreClientOptions(projectId: ""))
    }
  }
}
