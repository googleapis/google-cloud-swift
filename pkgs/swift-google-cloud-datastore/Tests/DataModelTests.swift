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
import GoogleGax
import GoogleType
import GoogleWKT
import Testing

@testable import GoogleCloudDatastore

@Suite struct DataModelTests {
  @Test func keyAndIncompleteKeyHierarchy() throws {
    let client = try DatastoreClient(
      DatastoreClientOptions(projectId: "proj-1", databaseId: "db-1", namespaceId: "ns-1")
    )

    let parentKey = client.key(kind: "Organization", name: "acme")
    #expect(parentKey.partitionId.projectId == "proj-1")
    #expect(parentKey.partitionId.databaseId == "db-1")
    #expect(parentKey.partitionId.namespaceId == "ns-1")
    #expect(parentKey.kind == "Organization")
    #expect(parentKey.id == .name("acme"))
    #expect(parentKey.parent == nil)
    #expect(parentKey.path == [PathElement(kind: "Organization", name: "acme")])

    let incompleteChild = client.incompleteKey(kind: "User", parent: parentKey)
    #expect(incompleteChild.partitionId == parentKey.partitionId)
    #expect(incompleteChild.ancestors == parentKey.path)
    #expect(incompleteChild.kind == "User")

    let completedChild = incompleteChild.completed(id: 42)
    #expect(completedChild.kind == "User")
    #expect(completedChild.id == .id(42))
    #expect(completedChild.parent == parentKey)
    #expect(
      completedChild.path == [
        PathElement(kind: "Organization", name: "acme"),
        PathElement(kind: "User", id: 42),
      ])
  }

  @Test func allElevenValueTypesAndLiterals() throws {
    let key = Key(kind: "Task", id: 100)
    let ts = try GoogleWKT.WKTTimestamp(seconds: 1_700_000_000, nanos: 123_000)
    let geo = GoogleType.LatLng().with {
      $0.latitude = 37.422
      $0.longitude = -122.084
    }

    var entity = Entity(
      key: key,
      properties: [
        "nullProp": nil,
        "boolProp": true,
        "intProp": 12345,
        "doubleProp": 3.14,
        "stringProp": "hello",
        "unindexedText": .unindexed("large text"),
        "bytesProp": PropertyValue(.bytes(Data([1, 2, 3]))),
        "tsProp": PropertyValue(.timestamp(ts)),
        "geoProp": PropertyValue(.geoPoint(geo)),
        "keyProp": PropertyValue(.key(key)),
        "arrayProp": ["a", "b", 1],
        "embeddedProp": ["nested": "value"],
      ]
    )

    #expect(entity[value: "nullProp"] == .null)
    #expect(entity[value: "boolProp"] == .bool(true))
    #expect(entity[value: "intProp"] == .int64(12345))
    #expect(entity[value: "doubleProp"] == .double(3.14))
    #expect(entity[value: "stringProp"] == .string("hello"))
    #expect(entity["unindexedText"]?.excludeFromIndexes == true)

    // Updating value via subscript(value:) preserves excludeFromIndexes
    entity[value: "unindexedText"] = "updated large text"
    #expect(entity["unindexedText"]?.excludeFromIndexes == true)
    #expect(entity[value: "unindexedText"] == .string("updated large text"))

    // Removing via nil
    entity[value: "nullProp"] = nil
    #expect(entity["nullProp"] == nil)
  }

  @Test func projectedTimestampMeaning18() throws {
    let pv = PropertyValue(.int64(1_700_000_000_500_000), excludeFromIndexes: false, meaning: 18)
    let ts = pv.projectedTimestamp
    #expect(ts == (try GoogleWKT.WKTTimestamp(seconds: 1_700_000_000, nanos: 500_000_000)))

    let negativePv = PropertyValue(.int64(-1_500_000), excludeFromIndexes: false, meaning: 18)
    #expect(
      negativePv.projectedTimestamp
        == (try GoogleWKT.WKTTimestamp(seconds: -2, nanos: 500_000_000)))

    let regularInt = PropertyValue(.int64(1_700_000_000_500_000))
    #expect(regularInt.projectedTimestamp == nil)
  }

  @Test func mutationsTransformsAndPendingKeyResolution() throws {
    let incompleteKey = IncompleteKey(kind: "Item")
    let incompleteEntity = IncompleteEntity(key: incompleteKey, properties: ["count": 0])
    let mutation = Mutation.insert(
      incompleteEntity,
      transforms: [
        .setToServerTime("createdAt"),
        .increment("count", by: Int64(1)),
        .maximum("maxScore", 10.5),
        .minimum("minScore", Int64(1)),
        .appendMissingElements("tags", ["new"]),
        .removeAllFromArray("oldTags", ["deprecated"]),
      ]
    )
    #expect(mutation.transforms.count == 6)

    let pendingKey = PendingKey(mutationIndex: 0, incompleteKey: incompleteKey)
    let allocatedKey = incompleteKey.completed(id: 999)
    let commitResult = CommitResult(
      commitTime: try GoogleWKT.WKTTimestamp(seconds: 100, nanos: 0),
      mutationResults: [
        MutationResult(key: allocatedKey, version: 1)
      ]
    )
    #expect(try commitResult.resolveKey(pendingKey) == allocatedKey)
  }
}
