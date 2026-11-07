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

import DatastoreV1Stub
import Foundation
import GoogleAuth
import GoogleGax
import Synchronization
import Testing

@testable import GoogleCloudDatastore

final class MockDatastoreStub: DatastoreRPCStub, Sendable {
  struct State: Sendable {
    var allocateIdsCalls: [(DatastoreV1Stub.AllocateIdsRequest, GoogleGax.RequestOptions)] = []
    var reserveIdsCalls: [(DatastoreV1Stub.ReserveIdsRequest, GoogleGax.RequestOptions)] = []
    var lookupCalls: [(DatastoreV1Stub.LookupRequest, GoogleGax.RequestOptions)] = []
    var commitCalls: [(DatastoreV1Stub.CommitRequest, GoogleGax.RequestOptions)] = []
    var beginTransactionCalls:
      [(DatastoreV1Stub.BeginTransactionRequest, GoogleGax.RequestOptions)] = []
    var rollbackCalls: [(DatastoreV1Stub.RollbackRequest, GoogleGax.RequestOptions)] = []
    var runQueryCalls: [(DatastoreV1Stub.RunQueryRequest, GoogleGax.RequestOptions)] = []
    var runAggregationQueryCalls:
      [(DatastoreV1Stub.RunAggregationQueryRequest, GoogleGax.RequestOptions)] = []

    var allocateIdsHandler:
      (
        @Sendable (DatastoreV1Stub.AllocateIdsRequest) throws -> DatastoreV1Stub.AllocateIdsResponse
      )?
    var reserveIdsHandler:
      (@Sendable (DatastoreV1Stub.ReserveIdsRequest) throws -> DatastoreV1Stub.ReserveIdsResponse)?
    var lookupHandler:
      (@Sendable (DatastoreV1Stub.LookupRequest) throws -> DatastoreV1Stub.LookupResponse)?
    var commitHandler:
      (@Sendable (DatastoreV1Stub.CommitRequest) throws -> DatastoreV1Stub.CommitResponse)?
    var beginTransactionHandler:
      (
        @Sendable (DatastoreV1Stub.BeginTransactionRequest) throws ->
          DatastoreV1Stub.BeginTransactionResponse
      )?
    var rollbackHandler:
      (@Sendable (DatastoreV1Stub.RollbackRequest) throws -> DatastoreV1Stub.RollbackResponse)?
    var runQueryHandler:
      (@Sendable (DatastoreV1Stub.RunQueryRequest) throws -> DatastoreV1Stub.RunQueryResponse)?
    var runAggregationQueryHandler:
      (
        @Sendable (DatastoreV1Stub.RunAggregationQueryRequest) throws ->
          DatastoreV1Stub.RunAggregationQueryResponse
      )?
  }

  let state = Mutex(State())

  func lookup(
    request: DatastoreV1Stub.LookupRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DatastoreV1Stub.LookupResponse {
    let handler = state.withLock { s in
      s.lookupCalls.append((request, options))
      return s.lookupHandler
    }
    return try handler?(request) ?? DatastoreV1Stub.LookupResponse()
  }

  func runQuery(
    request: DatastoreV1Stub.RunQueryRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DatastoreV1Stub.RunQueryResponse {
    let handler = state.withLock { s in
      s.runQueryCalls.append((request, options))
      return s.runQueryHandler
    }
    return try handler?(request) ?? DatastoreV1Stub.RunQueryResponse()
  }

  func runAggregationQuery(
    request: DatastoreV1Stub.RunAggregationQueryRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DatastoreV1Stub.RunAggregationQueryResponse {
    let handler = state.withLock { s in
      s.runAggregationQueryCalls.append((request, options))
      return s.runAggregationQueryHandler
    }
    return try handler?(request) ?? DatastoreV1Stub.RunAggregationQueryResponse()
  }

  func beginTransaction(
    request: DatastoreV1Stub.BeginTransactionRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DatastoreV1Stub.BeginTransactionResponse {
    let handler = state.withLock { s in
      s.beginTransactionCalls.append((request, options))
      return s.beginTransactionHandler
    }
    return try handler?(request) ?? DatastoreV1Stub.BeginTransactionResponse()
  }

  func commit(
    request: DatastoreV1Stub.CommitRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DatastoreV1Stub.CommitResponse {
    let handler = state.withLock { s in
      s.commitCalls.append((request, options))
      return s.commitHandler
    }
    return try handler?(request) ?? DatastoreV1Stub.CommitResponse()
  }

  func rollback(
    request: DatastoreV1Stub.RollbackRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DatastoreV1Stub.RollbackResponse {
    let handler = state.withLock { s in
      s.rollbackCalls.append((request, options))
      return s.rollbackHandler
    }
    return try handler?(request) ?? DatastoreV1Stub.RollbackResponse()
  }

  func allocateIds(
    request: DatastoreV1Stub.AllocateIdsRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DatastoreV1Stub.AllocateIdsResponse {
    let handler = state.withLock { s in
      s.allocateIdsCalls.append((request, options))
      return s.allocateIdsHandler
    }
    return try handler?(request) ?? DatastoreV1Stub.AllocateIdsResponse()
  }

  func reserveIds(
    request: DatastoreV1Stub.ReserveIdsRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DatastoreV1Stub.ReserveIdsResponse {
    let handler = state.withLock { s in
      s.reserveIdsCalls.append((request, options))
      return s.reserveIdsHandler
    }
    return try handler?(request) ?? DatastoreV1Stub.ReserveIdsResponse()
  }
}

@Suite struct KeyAllocationAndRoutingTests {
  @Test func emulatorEnvironmentAutoConfiguration() throws {
    let client = try DatastoreClient(
      DatastoreClientOptions(projectId: "emulated-proj"),
      environment: ["DATASTORE_EMULATOR_HOST": "localhost:8081"]
    )
    #expect(client.options.client.endpoint == "http://localhost:8081")
    #expect(client.options.client.credentials != nil)

    // Explicit caller endpoint takes precedence over DATASTORE_EMULATOR_HOST
    let customClient = try DatastoreClient(
      DatastoreClientOptions(projectId: "emulated-proj").with {
        $0.client.endpoint = "http://127.0.0.1:9090"
      },
      environment: ["DATASTORE_EMULATOR_HOST": "localhost:8081"]
    )
    #expect(customClient.options.client.endpoint == "http://127.0.0.1:9090")
  }

  @Test func routingHeadersDefaultAndNamedDatabase() throws {
    let stub = MockDatastoreStub()
    let defaultDbClient = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "my-proj"),
      stub: stub
    )
    let defaultOpts = defaultDbClient.effectiveRequestOptions(nil)
    #expect(defaultOpts.headers["x-goog-request-params"] == "project_id=my-proj")
    #expect(defaultOpts.headers["google-cloud-resource-prefix"] == "projects/my-proj")

    let namedDbClient = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "my-proj", databaseId: "analytics-db"),
      stub: stub
    )
    let namedOpts = namedDbClient.effectiveRequestOptions(nil)
    #expect(
      namedOpts.headers["x-goog-request-params"] == "project_id=my-proj&database_id=analytics-db")
    #expect(
      namedOpts.headers["google-cloud-resource-prefix"]
        == "projects/my-proj/databases/analytics-db")
  }

  @Test func allocateIdsAndReserveIdsSequential() async throws {
    let stub = MockDatastoreStub()
    stub.state.withLock { s in
      s.allocateIdsHandler = { req in
        DatastoreV1Stub.AllocateIdsResponse().with {
          $0.keys = req.keys.enumerated().map { idx, k in
            var copy = k
            var leaf = copy.path.removeLast()
            leaf.idType = .id(Int64(1000 + idx))
            copy.path.append(leaf)
            return copy
          }
        }
      }
    }

    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p1", databaseId: "db1", namespaceId: "ns1"),
      stub: stub
    )

    let ik1 = IncompleteKey(kind: "Task")
    let ik2 = client.incompleteKey(kind: "Task", parent: client.key(kind: "List", name: "work"))
    let allocated = try await client.allocateIds([ik1, ik2])
    #expect(allocated.count == 2)
    #expect(allocated[0].id == .id(1000))
    #expect(
      allocated[0].partitionId
        == PartitionId(projectId: "p1", databaseId: "db1", namespaceId: "ns1"))
    #expect(allocated[1].id == .id(1001))
    #expect(allocated[1].parent?.id == .name("work"))

    // Verify routing headers were sent on AllocateIds
    let (_, sentOptions) = stub.state.withLock { $0.allocateIdsCalls[0] }
    #expect(sentOptions.headers["x-goog-request-params"] == "project_id=p1&database_id=db1")

    // Test reserveIdsSequential
    let startKey = client.key(kind: "Counter", id: 50)
    try await client.reserveIdsSequential(startingAt: startKey, count: 3)
    let reservedKeys = stub.state.withLock { $0.reserveIdsCalls[0].0.keys }
    #expect(reservedKeys.count == 3)
    #expect(reservedKeys.map { $0.path.last?.idType } == [.id(50), .id(51), .id(52)])

    // Error when key has string name instead of numeric ID
    let namedKey = client.key(kind: "Counter", name: "alpha")
    await #expect(throws: DatastoreError.self) {
      try await client.reserveIdsSequential(startingAt: namedKey, count: 2)
    }
  }
}
