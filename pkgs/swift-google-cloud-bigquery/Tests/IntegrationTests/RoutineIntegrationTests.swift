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

/// Live tests of routines and authorized routines.
@Suite(.enabled(if: integrationTestsEnabled()))
struct RoutineIntegrationTests {
  let client: BigQueryClient

  init() throws {
    self.client = try IntegrationTest.makeClient()
  }

  func withDataset(_ body: (DatasetID) async throws -> Void) async throws {
    try await IntegrationTest.withTemporaryDataset(self.client, slice: "resources", body)
  }

  // Baseline: IT-055
  @Test func emptyDatasetHasNoRoutines() async throws {
    try await self.withDataset { dataset in
      var pages = self.client.listRoutines(in: dataset).pages.makeAsyncIterator()
      let page = try #require(try await pages.next())
      #expect(page.items.isEmpty)
      #expect(page.nextPageToken == nil)
    }
  }

  // Baseline: IT-056
  @Test func routineLifecycle() async throws {
    try await self.withDataset { dataset in
      let id = RoutineID(datasetID: dataset.datasetID, routineID: "add_one")
      try await ResourceQuery.run(
        self.client,
        "CREATE FUNCTION `\(dataset.datasetID).add_one`(x INT64) AS (x + 1)")

      let routine = try #require(try await self.client.getRoutine(id))
      #expect(routine.type == .scalarFunction)
      #expect(routine.language == .sql)
      #expect(routine.body == "x + 1")
      #expect(routine.arguments == [Routine.Argument(name: "x", dataType: .init(.int64))])
      #expect(routine.etag != nil)

      var listed: [RoutineID] = []
      for try await routine in self.client.listRoutines(in: dataset) { listed.append(routine.id) }
      #expect(listed == [self.client.resolve(id)])

      var change = routine
      change.body = "x + 2"
      change.description = "adds two"
      let updated = try await self.client.updateRoutine(change, ifMatch: routine.etag)
      #expect(updated.body == "x + 2")
      #expect(updated.description == "adds two")

      // PUT is a full replacement: an omitted description is removed.
      change.description = nil
      let replaced = try await self.client.updateRoutine(change)
      #expect(replaced.description == nil)

      #expect(try await self.client.deleteRoutine(id))
      #expect(try await self.client.getRoutine(id) == nil)
      #expect(try await self.client.deleteRoutine(id) == false)
    }
  }

  // Baseline: IT-057
  @Test func createsSQLScalarFunction() async throws {
    try await self.withDataset { dataset in
      let routine = try await self.client.createRoutine(
        Routine(
          id: RoutineID(datasetID: dataset.datasetID, routineID: "times_two"),
          type: .scalarFunction, language: .sql,
          arguments: [Routine.Argument(name: "x", dataType: .init(.int64))],
          returnType: .init(.int64), body: "x * 2"))
      #expect(routine.type == .scalarFunction)
      #expect(routine.returnType == .init(.int64))
      #expect(routine.arguments?.first?.name == "x")
      #expect(routine.body == "x * 2")
      #expect(routine.creationTime != nil)
    }
  }

  // Baseline: IT-058
  @Test func createsJavaScriptFunction() async throws {
    try await self.withDataset { dataset in
      let routine = try await self.client.createRoutine(
        Routine(
          id: RoutineID(datasetID: dataset.datasetID, routineID: "js_split"),
          type: .scalarFunction, language: .javaScript,
          arguments: [
            Routine.Argument(
              name: "s", kind: .fixedType, dataType: .init(.string))
          ],
          returnType: .array(of: .init(.string)),
          body: "return s.split(',');",
          determinismLevel: .notDeterministic))
      #expect(routine.language == .javaScript)
      #expect(routine.returnType == .array(of: .init(.string)))
      #expect(routine.determinismLevel == .notDeterministic)
      #expect(routine.arguments?.first?.dataType == .init(.string))
    }
  }

  // Baseline: IT-059
  @Test func createsTableValuedFunction() async throws {
    try await self.withDataset { dataset in
      let returnTableType = StandardSQLTableType(columns: [
        StandardSQLField("x", type: .init(.int64)),
        StandardSQLField("label", type: .init(.string)),
      ])
      let routine = try await self.client.createRoutine(
        Routine(
          id: RoutineID(datasetID: dataset.datasetID, routineID: "tvf"),
          type: .tableValuedFunction, language: .sql,
          arguments: [Routine.Argument(name: "n", dataType: .init(.int64))],
          returnTableType: returnTableType,
          body: "SELECT x, CAST(x AS STRING) AS label FROM UNNEST(GENERATE_ARRAY(1, n)) AS x"))
      #expect(routine.type == .tableValuedFunction)
      #expect(routine.returnTableType == returnTableType)
    }
  }

  // Baseline: IT-060
  @Test func createsDataMaskingFunction() async throws {
    try await self.withDataset { dataset in
      let routine = try await self.client.createRoutine(
        Routine(
          id: RoutineID(datasetID: dataset.datasetID, routineID: "mask"),
          type: .scalarFunction, language: .sql,
          arguments: [Routine.Argument(name: "s", dataType: .init(.string))],
          returnType: .init(.string), body: "SAFE.REGEXP_REPLACE(s, '[0-9]', 'X')",
          dataGovernanceType: .dataMasking))
      #expect(routine.dataGovernanceType == .dataMasking)
    }
  }

  // Baseline: IT-061
  @Test func authorizesRoutine() async throws {
    try await self.withDataset { routines in
      let routine = try await self.client.createRoutine(
        Routine(
          id: RoutineID(datasetID: routines.datasetID, routineID: "authorized"),
          type: .tableValuedFunction, language: .sql, body: "SELECT 1 AS x"))
      try await self.withDataset { shared in
        let current = try #require(try await self.client.getDataset(shared))
        var access = try #require(current.access)
        access.append(Acl(.routine(routine.id)))
        let updated = try await self.client.updateDataset(Dataset(id: shared, access: access))
        #expect(updated.access?.contains(Acl(.routine(routine.id))) == true)
      }
    }
  }

  // Baseline: IT-214
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["BIGQUERY_TEST_CONNECTION_ID"] != nil))
  func createsRemoteFunction() async throws {
    // `location.connection`, as in the table integration tests. Remote functions need the
    // connection's resource name.
    let connectionID = try #require(
      ProcessInfo.processInfo.environment["BIGQUERY_TEST_CONNECTION_ID"])
    let parts = connectionID.split(separator: ".", maxSplits: 1)
    try #require(parts.count == 2)
    let connection =
      "projects/\(self.client.projectID)/locations/\(parts[0])/connections/\(parts[1])"
    try await self.withDataset { dataset in
      let options = Routine.RemoteFunctionOptions(
        endpoint: "https://aaabbbccc-uc.a.run.app", connection: connection,
        userDefinedContext: ["key": "value"], maxBatchingRows: 20)
      let routine = try await self.client.createRoutine(
        Routine(
          id: RoutineID(datasetID: dataset.datasetID, routineID: "remote"),
          type: .scalarFunction,
          arguments: [Routine.Argument(name: "x", dataType: .init(.string))],
          returnType: .init(.string), remoteFunctionOptions: options))
      #expect(routine.remoteFunctionOptions?.endpoint == options.endpoint)
      #expect(routine.remoteFunctionOptions?.userDefinedContext == options.userDefinedContext)
      #expect(routine.remoteFunctionOptions?.maxBatchingRows == 20)
    }
  }
}
