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

typealias Routine = GoogleCloudBigQuery.Routine

private let fullRoutineJSON = #"""
  {
    "etag": "etag-1",
    "routineReference": {"projectId": "p", "datasetId": "d", "routineId": "r"},
    "routineType": "SCALAR_FUNCTION", "language": "JAVASCRIPT",
    "creationTime": "1700000000000", "lastModifiedTime": "1700000001000",
    "arguments": [
      {"name": "x", "argumentKind": "FIXED_TYPE", "mode": "IN", "dataType": {"typeKind": "INT64"}},
      {"name": "y", "argumentKind": "ANY_TYPE"}
    ],
    "returnType": {"typeKind": "ARRAY", "arrayElementType": {"typeKind": "STRING"}},
    "importedLibraries": ["gs://b/lib.js"],
    "definitionBody": "return [String(x)];",
    "description": "Description",
    "determinismLevel": "DETERMINISTIC",
    "dataGovernanceType": "DATA_MASKING"
  }
  """#

@Suite struct RoutineTests {
  func fullRoutine() throws -> Routine {
    Routine(wire: try WireJSON.decode(fullRoutineJSON, as: GoogleCloudBigQueryV2.Routine.self))
  }

  // Baseline: U.RoutineInfo.01
  @Test func decodesEveryField() throws {
    let routine = try self.fullRoutine()
    #expect(routine.id == RoutineID(projectID: "p", datasetID: "d", routineID: "r"))
    #expect(routine.type == .scalarFunction)
    #expect(routine.language == .javaScript)
    #expect(
      routine.arguments == [
        Routine.Argument(name: "x", kind: .fixedType, mode: .in, dataType: .init(.int64)),
        Routine.Argument(name: "y", kind: .anyType),
      ])
    #expect(routine.returnType == .array(of: .init(.string)))
    #expect(routine.returnTableType == nil)
    #expect(routine.importedLibraries == ["gs://b/lib.js"])
    #expect(routine.body == "return [String(x)];")
    #expect(routine.description == "Description")
    #expect(routine.determinismLevel == .deterministic)
    #expect(routine.dataGovernanceType == .dataMasking)
    #expect(routine.etag == "etag-1")
    #expect(routine.creationTime == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(routine.lastModifiedTime == Date(timeIntervalSince1970: 1_700_000_001))
  }

  // Baseline: U.RoutineInfo.01
  @Test func roundTripsThroughRequestBody() throws {
    var routine = try self.fullRoutine()
    routine.returnType = nil
    routine.returnTableType = StandardSQLTableType(columns: [
      StandardSQLField("a", type: .init(.int64))
    ])
    let body = try RequestBody.json(routine.wire, omitting: routine.omittedWireDefaults)
    let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
    for key in ["etag", "creationTime", "lastModifiedTime", "securityMode"] {
      #expect(object[key] == nil, "\(key) is output only")
    }
    var expected = routine
    expected.etag = nil
    expected.creationTime = nil
    expected.lastModifiedTime = nil
    #expect(Routine(wire: try WireJSON.decode(String(decoding: body, as: UTF8.self))) == expected)
  }

  // Design: §5.4
  @Test func minimalRoutineOmitsUnsetEnumsAndStrings() throws {
    let routine = Routine(id: RoutineID(projectID: "p", datasetID: "d", routineID: "r"))
    let body = try RequestBody.json(routine.wire, omitting: routine.omittedWireDefaults)
    #expect(
      try WireJSON.object(String(decoding: body, as: UTF8.self))
        == WireJSON.object(
          #"{"routineReference": {"projectId": "p", "datasetId": "d", "routineId": "r"}}"#))
  }

  // Baseline: U.RoutineArgument.01
  @Test func argumentRoundTrips() throws {
    let argument = Routine.Argument(
      name: "s", kind: .fixedType, mode: .inout,
      dataType: .struct([StandardSQLField("f", type: .init(.bool))]))
    let json = try WireJSON.object(argument.wire)
    #expect(json["name"] as? String == "s")
    #expect(json["argumentKind"] as? String == "FIXED_TYPE")
    #expect(json["mode"] as? String == "INOUT")
    #expect(Routine.Argument(wire: argument.wire) == argument)
    #expect(Routine.Argument(wire: Routine.Argument().wire) == Routine.Argument())
  }

  // Baseline: U.RemoteFunctionOptions.01
  @Test func remoteFunctionOptionsRoundTrip() throws {
    let options = Routine.RemoteFunctionOptions(
      endpoint: "https://example.com/f", connection: "projects/p/locations/us/connections/c",
      userDefinedContext: ["k": "v"], maxBatchingRows: 10)
    #expect(
      try WireJSON.object(options.wire)
        == WireJSON.object(
          #"""
          {"endpoint": "https://example.com/f", "connection": "projects/p/locations/us/connections/c",
           "userDefinedContext": {"k": "v"}, "maxBatchingRows": "10"}
          """#))
    #expect(Routine.RemoteFunctionOptions(wire: options.wire) == options)
  }
}

/// The routine methods of `BigQueryClient`, against a scripted transport.
@Suite struct BigQueryClientRoutineTests {
  let fake = FakeHTTPTransport()
  let routineJSON =
    #"{"routineReference": {"projectId": "test-project", "datasetId": "d", "routineId": "r"}}"#
  let id = RoutineID(datasetID: "d", routineID: "r")
  let path = "/bigquery/v2/projects/test-project/datasets/d/routines/r"

  // Baseline: U.BigQueryImpl.66, U.RoutineInfo.02
  @Test func createPostsWithClientProject() async throws {
    self.fake.enqueue(json: self.routineJSON)
    let created = try await self.fake.client().createRoutine(
      Routine(id: self.id, type: .scalarFunction, language: .sql, body: "1"))
    let request = try #require(self.fake.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/bigquery/v2/projects/test-project/datasets/d/routines")
    #expect(
      try request.jsonBody() as NSDictionary
        == WireJSON.object(
          #"""
          {"routineReference": {"projectId": "test-project", "datasetId": "d", "routineId": "r"},
           "routineType": "SCALAR_FUNCTION", "language": "SQL", "definitionBody": "1"}
          """#))
    #expect(created.id == RoutineID(projectID: "test-project", datasetID: "d", routineID: "r"))
  }

  // Baseline: U.BigQueryImpl.66, U.Routine.02
  @Test func getUsesClientOrExplicitProject() async throws {
    let client = self.fake.client()
    self.fake.enqueue(json: self.routineJSON)
    self.fake.enqueue(json: self.routineJSON)
    let routine = try await client.getRoutine(self.id, selectedFields: ["etag"])
    _ = try await client.getRoutine(RoutineID(projectID: "o", datasetID: "d", routineID: "r"))
    #expect(routine?.id.projectID == "test-project")
    #expect(
      self.fake.requests.map(\.path) == [
        self.path, "/bigquery/v2/projects/o/datasets/d/routines/r",
      ])
    #expect(self.fake.requests[0].queryValue("fields") == "routineReference,etag")
  }

  // Baseline: U.BigQueryImpl.06 (routines), U.Routine.02
  @Test func getReturnsNilOnNotFound() async throws {
    self.fake.enqueueError(status: 404, reasons: ["notFound"])
    #expect(try await self.fake.client().getRoutine(self.id) == nil)
  }

  // Baseline: U.BigQueryImpl.66, U.Routine.02
  @Test func updatePutsFullRoutine() async throws {
    self.fake.enqueue(json: self.routineJSON)
    _ = try await self.fake.client().updateRoutine(
      Routine(id: self.id, type: .scalarFunction, language: .sql, body: "2"))
    let request = try #require(self.fake.requests.first)
    #expect(request.method == .put)
    #expect(request.path == self.path)
    #expect(request.headers["If-Match"] == nil)
    #expect(try request.jsonBody()["definitionBody"] as? String == "2")
  }

  // Baseline: U.BigQueryImpl.66, U.Routine.02
  @Test func deleteReturnsTrueOrFalseOnNotFound() async throws {
    let client = self.fake.client()
    self.fake.enqueue(status: 204, json: "")
    self.fake.enqueueError(status: 404, reasons: ["notFound"])
    #expect(try await client.deleteRoutine(self.id))
    #expect(try await client.deleteRoutine(self.id) == false)
    #expect(self.fake.requests.map(\.method) == [.delete, .delete])
    #expect(self.fake.requests.map(\.path) == [self.path, self.path])
  }

  // Baseline: U.BigQueryImpl.67
  @Test func listFollowsPageTokens() async throws {
    self.fake.enqueue(
      json: #"""
        {"routines": [{"routineReference": {"projectId": "test-project", "datasetId": "d", "routineId": "a"}}],
         "nextPageToken": "t2"}
        """#)
    self.fake.enqueue(json: "{}")
    var names: [String] = []
    for try await routine in self.fake.client().listRoutines(
      in: DatasetID(datasetID: "d"), pageSize: 5)
    {
      names.append(routine.id.routineID)
    }
    #expect(names == ["a"])
    #expect(
      self.fake.requests.map(\.path)
        == Array(
          repeating: "/bigquery/v2/projects/test-project/datasets/d/routines", count: 2))
    #expect(self.fake.requests.map { $0.queryValue("pageToken") } == [nil, "t2"])
    #expect(self.fake.requests.map { $0.queryValue("maxResults") } == ["5", "5"])
  }

  // Baseline: U.BigQueryImpl.67
  @Test func listWithExplicitProjectAndPageToken() async throws {
    self.fake.enqueue(json: "{}")
    for try await _ in self.fake.client().listRoutines(
      in: DatasetID(projectID: "o", datasetID: "d"), pageToken: "t1")
    {}
    #expect(self.fake.requests.first?.path == "/bigquery/v2/projects/o/datasets/d/routines")
    #expect(self.fake.requests.first?.queryValue("pageToken") == "t1")
  }

  // Design: §5.2
  @Test func createIsNotRetried() async throws {
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    await #expect(throws: BigQueryError.self) {
      try await self.fake.client().createRoutine(Routine(id: self.id))
    }
    #expect(self.fake.requests.count == 1)
  }

  // Design: §5.2
  @Test func updateIsRetriedOnlyWithIfMatch() async throws {
    let client = self.fake.client()
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    await #expect(throws: BigQueryError.self) {
      try await client.updateRoutine(Routine(id: self.id))
    }
    self.fake.enqueueError(status: 503, reasons: ["backendError"])
    self.fake.enqueue(json: self.routineJSON)
    _ = try await client.updateRoutine(Routine(id: self.id), ifMatch: "e1")
    #expect(self.fake.requests.count == 3)
    #expect(self.fake.requests[2].headers["If-Match"] == "e1")
  }
}
