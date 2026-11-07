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
import GoogleWKT
import Synchronization
import Testing

@testable import GoogleCloudDatastore

@Suite struct MutationTests {
  @Test func nonTransactionalInsertUpsertUpdateDeleteAndKeyNormalization() async throws {
    let stub = MockDatastoreStub()
    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p1", databaseId: "db1", namespaceId: "ns1"),
      stub: stub
    )

    stub.state.withLock { s in
      s.commitHandler = { req in
        #expect(req.mode == .nonTransactional)
        return DatastoreV1Stub.CommitResponse().with {
          $0.mutationResults = req.mutations.map { mut in
            DatastoreV1Stub.MutationResult().with {
              $0.version = 101
              // Simulate Datastore: only return a key when the input key was incomplete!
              if case .insert(let ent) = mut.operation, ent.key?.path.last?.idType == nil {
                var allocated = ent.key ?? DatastoreV1Stub.Key()
                var leaf = allocated.path.removeLast()
                leaf.idType = .id(777)
                allocated.path.append(leaf)
                $0.key = allocated
              }
            }
          }
        }
      }
    }

    // 1. Insert with incomplete key returns server-allocated complete Key
    let incomplete = IncompleteEntity(
      key: client.incompleteKey(kind: "Task"),
      properties: ["title": "New"]
    )
    let allocatedKey = try await client.insert(incomplete)
    #expect(allocatedKey.id == .id(777))
    #expect(allocatedKey.kind == "Task")

    // 2. Insert/Upsert with complete key normalizes and returns input Key even when wire MutationResult.key is nil
    let completeKey = client.key(kind: "Task", name: "existing")
    let returnedKey = try await client.upsert(Entity(key: completeKey, properties: ["done": true]))
    #expect(returnedKey == completeKey)

    try await client.update(Entity(key: completeKey, properties: ["done": false]))
    try await client.delete(completeKey)

    let commitCalls = stub.state.withLock { $0.commitCalls }
    #expect(commitCalls.count == 4)
  }

  @Test func propertyTransformsPropertyMaskBaseVersionAndDuplicateDeleteDedup() async throws {
    let stub = MockDatastoreStub()
    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p1", databaseId: "db1", namespaceId: "ns1"),
      stub: stub
    )

    let ts = try GoogleWKT.WKTTimestamp(seconds: 1_700_000_000, nanos: 0)
    stub.state.withLock { s in
      s.commitHandler = { req in
        DatastoreV1Stub.CommitResponse().with {
          $0.mutationResults = req.mutations.map { mut in
            DatastoreV1Stub.MutationResult().with {
              $0.version = 500
              if !mut.propertyTransforms.isEmpty {
                $0.transformResults = [
                  DatastoreV1Stub.Value().with { $0.valueType = .timestampValue(ts) },
                  DatastoreV1Stub.Value().with { $0.valueType = .integerValue(11) },
                ]
              }
            }
          }
        }
      }
    }

    let k1 = client.key(kind: "Counter", id: 1)
    let k2 = client.key(kind: "Trash", id: 99)

    // Batch with:
    // [0] transform-only mutation (empty PropertyMask + 6 transforms)
    // [1] delete(k2)
    // [2] duplicate delete(k2) -> should be coalesced on the wire, then fanned back out!
    let results = try await client.mutate([
      .transform(
        key: k1,
        baseVersion: 499,
        transforms: [
          .setToServerTime("updatedAt"),
          .increment("count", by: Int64(1)),
          .maximum("maxVal", Int64(100)),
          .minimum("minVal", 0.5),
          .appendMissingElements("tags", ["a"]),
          .removeAllFromArray("oldTags", ["b"]),
        ]
      ),
      .delete(k2),
      .delete(k2),
    ])

    // Caller receives 3 MutationResults matching the 3 input mutations
    #expect(results.count == 3)
    #expect(results[0].key == k1)
    #expect(results[0].version == 500)
    #expect(results[0].transformResults.count == 2)
    #expect(results[0].transformResults[0].value == .timestamp(ts))
    #expect(results[0].transformResults[1].value == .int64(11))
    #expect(results[1].version == 500)
    #expect(results[2].version == 500)

    // Wire CommitRequest had only 2 mutations because duplicate delete(k2) was coalesced!
    let sentRequest = stub.state.withLock { $0.commitCalls[0].0 }
    #expect(sentRequest.mutations.count == 2)
    let transformMut = sentRequest.mutations[0]
    #expect(transformMut.propertyMask?.paths == [])
    #expect(transformMut.conflictDetectionStrategy == .baseVersion(499))
    #expect(transformMut.propertyTransforms.count == 6)
  }
}
