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
import GoogleType
import GoogleWKT
import Synchronization
import Testing

@testable import GoogleCloudDatastore

@Suite struct LookupAndEntityConversionTests {
  @Test func allElevenValueWireConversionsAndMetadataRules() throws {
    let ts = try GoogleWKT.WKTTimestamp(seconds: 1_700_000_000, nanos: 500_000)
    let geo = GoogleType.LatLng().with {
      $0.latitude = 37.7749
      $0.longitude = -122.4194
    }
    let key = Key(
      ancestors: [],
      leaf: PathElement(kind: "Ref", id: 7),
      partitionId: PartitionId(projectId: "p1", databaseId: "db1", namespaceId: "ns1")
    )

    var original = Entity(
      key: key,
      properties: [
        "nullVal": nil,
        "boolVal": true,
        "intVal": PropertyValue(.int64(99), excludeFromIndexes: false, meaning: 14),
        "doubleVal": 2.718,
        "tsVal": PropertyValue(.timestamp(ts)),
        "strVal": .unindexed("unindexed string"),
        "bytesVal": PropertyValue(.bytes(Data([0xAA, 0xBB]))),
        "geoVal": PropertyValue(.geoPoint(geo)),
        "keyVal": PropertyValue(.key(key)),
        "unindexedArr": PropertyValue(.array(["x", "y"]), excludeFromIndexes: true),
        "embedded": PropertyValue(
          .entity(EmbeddedEntity(key: key, properties: ["inner": "val"]))),
      ]
    )

    let wireEntity = try original.toProto(
      defaultProjectId: "p1",
      defaultDatabaseId: "db1",
      defaultNamespaceId: "ns1"
    )

    // Verify Array Indexing Rule: outer arrayValue has excludeFromIndexes == false, elements have true
    let wireArr = try #require(wireEntity.properties["unindexedArr"])
    #expect(wireArr.excludeFromIndexes == false)
    #expect(wireArr.meaning == 0)
    guard case .arrayValue(let arrPayload) = wireArr.valueType else {
      Issue.record("Expected arrayValue on wire")
      return
    }
    #expect(arrPayload.values.count == 2)
    #expect(arrPayload.values.allSatisfy { $0.excludeFromIndexes })

    // Verify meaning preservation on wire
    #expect(wireEntity.properties["intVal"]?.meaning == 14)

    // Decode back via EntityResult
    let entityResult = DatastoreV1Stub.EntityResult().with {
      $0.entity = wireEntity
      $0.version = 42
      $0.createTime = ts
      $0.updateTime = ts
    }
    let decoded = try Entity(fromEntityResult: entityResult)
    #expect(decoded.version == 42)
    #expect(decoded.createTime == ts)
    #expect(decoded.updateTime == ts)
    #expect(decoded["intVal"]?.meaning == 14)
    #expect(decoded["unindexedArr"]?.excludeFromIndexes == true)
    #expect(decoded[value: "strVal"] == .string("unindexed string"))
    #expect(decoded["strVal"]?.excludeFromIndexes == true)
    original.version = 42
    original.createTime = ts
    original.updateTime = ts
    #expect(decoded.key == original.key)

    // Directly nested array is rejected
    let nestedArray = PropertyValue(.array([PropertyValue(.array(["bad"]))]))
    #expect(throws: DatastoreError.self) {
      _ = try nestedArray.toProto()
    }
  }

  @Test func getMultiDeduplicationDeferredLoopAndOrdering() async throws {
    let stub = MockDatastoreStub()
    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p1", databaseId: "db1", namespaceId: "ns1"),
      stub: stub
    )

    let k1 = client.key(kind: "Item", id: 1)
    let k2 = client.key(kind: "Item", id: 2)
    let k3 = client.key(kind: "Item", id: 3)  // missing

    let wireK1 = k1.toProto(
      defaultProjectId: "p1", defaultDatabaseId: "db1", defaultNamespaceId: "ns1")
    let wireK3 = k3.toProto(
      defaultProjectId: "p1", defaultDatabaseId: "db1", defaultNamespaceId: "ns1")

    let e1 = try Entity(key: k1, properties: ["name": "first"]).toProto()
    let e2 = try Entity(key: k2, properties: ["name": "second"]).toProto()

    let callCounter = Mutex(0)
    stub.state.withLock { s in
      s.lookupHandler = { _ in
        let callIndex = callCounter.withLock { count in
          count += 1
          return count
        }
        if callIndex == 1 {
          // First round: k2 is found, k3 is missing, k1 is deferred!
          return DatastoreV1Stub.LookupResponse().with {
            $0.found = [
              DatastoreV1Stub.EntityResult().with {
                $0.entity = e2
                $0.version = 20
              }
            ]
            $0.missing = [
              DatastoreV1Stub.EntityResult().with {
                $0.entity = DatastoreV1Stub.Entity().with { $0.key = wireK3 }
              }
            ]
            $0.deferred = [wireK1]
          }
        } else {
          // Second round: deferred k1 is now found
          return DatastoreV1Stub.LookupResponse().with {
            $0.found = [
              DatastoreV1Stub.EntityResult().with {
                $0.entity = e1
                $0.version = 10
              }
            ]
          }
        }
      }
    }

    // Request with duplicate k1 at the beginning and end: [k1, k2, k3, k1]
    let results = try await client.getMulti(
      [k1, k2, k3, k1],
      options: .consistency(.eventual, propertyMask: ["name"])
    )

    #expect(results.count == 4)
    #expect(results[0]?[value: "name"] == .string("first"))
    #expect(results[0]?.version == 10)
    #expect(results[1]?[value: "name"] == .string("second"))
    #expect(results[1]?.version == 20)
    #expect(results[2] == nil)
    #expect(results[3]?[value: "name"] == .string("first"))

    // Verify deduplication on first LookupRequest (3 unique keys instead of 4) and deferred loop (2 calls)
    let lookupCalls = stub.state.withLock { $0.lookupCalls }
    #expect(lookupCalls.count == 2)
    #expect(lookupCalls[0].0.keys.count == 3)
    #expect(lookupCalls[0].0.readOptions?.consistencyType == .readConsistency(.eventual))
    #expect(lookupCalls[0].0.propertyMask?.paths == ["name"])
    #expect(lookupCalls[1].0.keys == [wireK1])
  }
}
