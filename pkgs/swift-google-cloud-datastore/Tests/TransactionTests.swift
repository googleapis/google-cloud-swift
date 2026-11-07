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
import GoogleGax
import GoogleRpc
import GoogleWKT
import Synchronization
import Testing

@testable import GoogleCloudDatastore

private struct ZeroBackoff: BackoffPolicy {
  func backoffDelay(for state: RetryState) -> Duration { .zero }
}

private enum TestFailure: Error, Equatable {
  case boom
}

@Suite struct TransactionTests {
  @Test func lazyReadInitiationAndTransactionalCommit() async throws {
    let stub = MockDatastoreStub()
    let txId = Data([0xAA, 0xBB, 0xCC])
    stub.state.withLock { s in
      s.lookupHandler = { req in
        return DatastoreV1Stub.LookupResponse().with {
          if case .newTransaction = req.readOptions?.consistencyType {
            $0.transaction = txId
          }
          if let firstKey = req.keys.first {
            $0.found = [
              DatastoreV1Stub.EntityResult().with {
                $0.entity = DatastoreV1Stub.Entity().with {
                  $0.key = firstKey
                  $0.properties = [
                    "balance": DatastoreV1Stub.Value().with { $0.valueType = .integerValue(100) }
                  ]
                }
              }
            ]
          }
        }
      }
      s.commitHandler = { req in
        DatastoreV1Stub.CommitResponse().with {
          $0.mutationResults = req.mutations.map { _ in
            DatastoreV1Stub.MutationResult().with { $0.version = 55 }
          }
        }
      }
    }

    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p-tx"),
      stub: stub
    )

    let k1 = client.key(kind: "Account", name: "a1")
    let k2 = client.key(kind: "Account", name: "a2")

    let (finalBalance, commitResult) = try await client.runInTransaction { tx in
      let e1 = try await tx.get(k1)
      let e2 = try await tx.get(k2)
      let b1: Int64 = if case .int64(let v) = e1?[value: "balance"] { v } else { 0 }
      let b2: Int64 = if case .int64(let v) = e2?[value: "balance"] { v } else { 0 }
      var updated = Entity(key: k1)
      updated[value: "balance"] = .int64(b1 + b2)
      try tx.update(updated)
      return b1 + b2
    }

    #expect(finalBalance == 200)
    #expect(commitResult.mutationResults.count == 1)

    let lookupReqs = stub.state.withLock { $0.lookupCalls.map(\.0) }
    #expect(lookupReqs.count == 2)
    // First read uses new_transaction
    if case .newTransaction(let txOpts) = lookupReqs[0].readOptions?.consistencyType,
      case .readWrite(let rw) = txOpts.mode
    {
      #expect(rw.previousTransaction.isEmpty)
    } else {
      Issue.record(
        "Expected first lookup to carry newTransaction(readWrite), got \(String(describing: lookupReqs[0].readOptions))"
      )
    }
    // Second read reuses transaction ID
    #expect(lookupReqs[1].readOptions?.consistencyType == .transaction(txId))

    // Commit uses transaction ID
    let commitReq = stub.state.withLock { $0.commitCalls[0].0 }
    #expect(commitReq.mode == .transactional)
    #expect(commitReq.transactionSelector == .transaction(txId))
  }

  @Test func writeOnlySingleUseTransactionAndPendingKeyResolution() async throws {
    let stub = MockDatastoreStub()
    stub.state.withLock { s in
      s.commitHandler = { _ in
        DatastoreV1Stub.CommitResponse().with {
          $0.mutationResults = [
            DatastoreV1Stub.MutationResult().with {
              $0.key = DatastoreV1Stub.Key().with {
                $0.partitionId = DatastoreV1Stub.PartitionId().with { $0.projectId = "p-tx" }
                $0.path = [
                  DatastoreV1Stub.Key.PathElement().with {
                    $0.kind = "Task"
                    $0.idType = .id(777)
                  }
                ]
              }
              $0.version = 1
            }
          ]
        }
      }
    }

    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p-tx"),
      stub: stub
    )

    let (pending, commitResult) = try await client.runInTransaction { tx in
      try tx.insert(IncompleteEntity(key: IncompleteKey(kind: "Task"), properties: ["ok": true]))
    }

    let resolved = try commitResult.resolveKey(pending)
    #expect(resolved.id == .id(777))
    #expect(stub.state.withLock { $0.lookupCalls.isEmpty })

    let commitReq = stub.state.withLock { $0.commitCalls[0].0 }
    if case .singleUseTransaction(let txOpts) = commitReq.transactionSelector,
      case .readWrite = txOpts.mode
    {
      // Expected single_use_transaction fast path
    } else {
      Issue.record(
        "Expected singleUseTransaction selector, got \(String(describing: commitReq.transactionSelector))"
      )
    }
  }

  @Test func emptyTransactionAndRollbackBehaviorOnError() async throws {
    let stub = MockDatastoreStub()
    let txId = Data([0x10, 0x20])
    stub.state.withLock { s in
      s.lookupHandler = { _ in
        DatastoreV1Stub.LookupResponse().with { $0.transaction = txId }
      }
    }

    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p-tx"),
      stub: stub
    )

    // 1. Empty transaction sends zero RPCs
    let (val, emptyCommit) = try await client.runInTransaction { _ in 42 }
    #expect(val == 42)
    #expect(emptyCommit.mutationResults.isEmpty)
    #expect(stub.state.withLock { $0.lookupCalls.isEmpty && $0.commitCalls.isEmpty })

    // 2. Error thrown before any read sends zero Rollback RPCs
    await #expect(throws: TestFailure.boom) {
      try await client.runInTransaction { _ in
        throw TestFailure.boom
      }
    }
    #expect(stub.state.withLock { $0.rollbackCalls.isEmpty })

    // 3. Error thrown after a read sends RollbackRequest with acquired transaction ID
    await #expect(throws: TestFailure.boom) {
      try await client.runInTransaction { tx in
        _ = try await tx.get(client.key(kind: "Task", id: 1))
        throw TestFailure.boom
      }
    }
    let rollbacks = stub.state.withLock { $0.rollbackCalls.map(\.0) }
    #expect(rollbacks.count == 1)
    #expect(rollbacks[0].transaction == txId)
  }

  @Test func contentionRetryWithPreviousTransactionAndReadOnlyValidation() async throws {
    let stub = MockDatastoreStub()
    let txIdAttempt1 = Data([0x01])
    let txIdAttempt2 = Data([0x02])
    let attemptCounter = Mutex(0)

    stub.state.withLock { s in
      s.lookupHandler = { _ in
        let attempt = attemptCounter.withLock { count -> Int in
          count += 1
          return count
        }
        return DatastoreV1Stub.LookupResponse().with {
          $0.transaction = (attempt == 1) ? txIdAttempt1 : txIdAttempt2
        }
      }
      s.commitHandler = { req in
        if req.transactionSelector == .transaction(txIdAttempt1) {
          throw RequestError.service(
            ServiceError(code: .aborted, message: "Aborted due to contention", httpStatusCode: 409)
          )
        }
        return DatastoreV1Stub.CommitResponse().with {
          $0.mutationResults = [DatastoreV1Stub.MutationResult().with { $0.version = 9 }]
        }
      }
    }

    let client = try DatastoreClient(
      options: DatastoreClientOptions(
        projectId: "p-tx",
        maxTransactionAttempts: 3,
        transactionBackoffPolicy: ZeroBackoff()
      ),
      stub: stub
    )

    let k = client.key(kind: "Counter", name: "c1")
    let (runs, _) = try await client.runInTransaction { tx in
      _ = try await tx.get(k)
      try tx.upsert(Entity(key: k, properties: ["v": 1]))
      return attemptCounter.withLock { $0 }
    }
    #expect(runs == 2)

    let lookupReqs = stub.state.withLock { $0.lookupCalls.map(\.0) }
    #expect(lookupReqs.count == 2)
    if case .newTransaction(let txOpts2) = lookupReqs[1].readOptions?.consistencyType,
      case .readWrite(let rw2) = txOpts2.mode
    {
      #expect(rw2.previousTransaction == txIdAttempt1)
    } else {
      Issue.record("Expected second attempt to pass previousTransaction = txIdAttempt1")
    }

    // Read-only transaction rejects mutations and sends no Commit RPC
    let snapTime = try GoogleWKT.WKTTimestamp(seconds: 1_700_000_000, nanos: 0)
    await #expect(throws: DatastoreError.readOnlyTransaction) {
      try await client.runInTransaction(options: .readOnly(readTime: snapTime)) { tx in
        try tx.delete(k)
      }
    }
  }
}
