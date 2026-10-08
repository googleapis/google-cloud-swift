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

typealias Dataset = GoogleCloudBigQuery.Dataset

/// A complete `datasets.get` response.
private let fullDatasetJSON = #"""
  {
    "kind": "bigquery#dataset", "etag": "etag-1", "id": "p:d",
    "selfLink": "https://bigquery.googleapis.com/bigquery/v2/projects/p/datasets/d",
    "datasetReference": {"projectId": "p", "datasetId": "d"},
    "friendlyName": "Friendly", "description": "Description", "location": "EU",
    "labels": {"env": "prod"},
    "defaultTableExpirationMs": "3600000", "defaultPartitionExpirationMs": "7200000",
    "access": [
      {"role": "OWNER", "specialGroup": "projectOwners"},
      {"role": "READER", "userByEmail": "u@example.com"},
      {"view": {"projectId": "p", "datasetId": "d2", "tableId": "v"}}
    ],
    "defaultEncryptionConfiguration": {"kmsKeyName": "projects/p/locations/eu/keyRings/r/cryptoKeys/k"},
    "defaultCollation": "und:ci", "maxTimeTravelHours": "120",
    "storageBillingModel": "PHYSICAL", "isCaseInsensitive": true,
    "resourceTags": {"123/env": "prod"},
    "externalDatasetReference": {
      "externalSource": "aws-glue://arn:aws:glue:us-east-1:1:database/db",
      "connection": "projects/p/locations/aws-us-east-1/connections/c"
    },
    "creationTime": "1700000000000", "lastModifiedTime": "1700000001000"
  }
  """#

@Suite struct DatasetTests {
  func fullDataset() throws -> Dataset {
    Dataset(wire: try WireJSON.decode(fullDatasetJSON, as: GoogleCloudBigQueryV2.Dataset.self))
  }

  // Baseline: U.DatasetInfo.01, U.Dataset.04
  @Test func decodesEveryField() throws {
    let dataset = try self.fullDataset()
    #expect(dataset.id == DatasetID(projectID: "p", datasetID: "d"))
    #expect(dataset.friendlyName == "Friendly")
    #expect(dataset.description == "Description")
    #expect(dataset.location == "EU")
    #expect(dataset.labels == ["env": "prod"])
    #expect(dataset.defaultTableExpiration == .seconds(3600))
    #expect(dataset.defaultPartitionExpiration == .seconds(7200))
    #expect(
      dataset.access == [
        Acl(.projectOwners, role: .owner), Acl(.user("u@example.com"), role: .reader),
        Acl(.view(TableID(projectID: "p", datasetID: "d2", tableID: "v"))),
      ])
    #expect(
      dataset.defaultEncryptionConfiguration?.kmsKeyName
        == "projects/p/locations/eu/keyRings/r/cryptoKeys/k")
    #expect(dataset.defaultCollation == "und:ci")
    #expect(dataset.maxTimeTravelHours == 120)
    #expect(dataset.storageBillingModel == .physical)
    #expect(dataset.isCaseInsensitive == true)
    #expect(dataset.resourceTags == ["123/env": "prod"])
    #expect(
      dataset.externalDatasetReference
        == ExternalDatasetReference(
          externalSource: "aws-glue://arn:aws:glue:us-east-1:1:database/db",
          connection: "projects/p/locations/aws-us-east-1/connections/c"))
    #expect(dataset.etag == "etag-1")
    #expect(dataset.generatedID == "p:d")
    #expect(dataset.selfLink?.hasSuffix("/datasets/d") == true)
    #expect(dataset.creationTime == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(dataset.lastModifiedTime == Date(timeIntervalSince1970: 1_700_000_001))
  }

  // Baseline: U.DatasetInfo.01, U.Dataset.04
  @Test func roundTripsThroughRequestBody() throws {
    let dataset = try self.fullDataset()
    let body = try RequestBody.json(dataset.wire, omitting: dataset.omittedWireDefaults)
    let decoded = Dataset(
      wire: try WireJSON.decode(
        String(decoding: body, as: UTF8.self), as: GoogleCloudBigQueryV2.Dataset.self))
    var expected = dataset
    expected.etag = nil
    expected.generatedID = nil
    expected.selfLink = nil
    expected.creationTime = nil
    expected.lastModifiedTime = nil
    #expect(decoded == expected)

    let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
    for key in ["kind", "etag", "id", "selfLink", "creationTime", "lastModifiedTime", "type"] {
      #expect(object[key] == nil, "\(key) is output only")
    }
  }

  // Design: §5.4
  @Test func minimalDatasetSendsOnlyItsReference() throws {
    let dataset = Dataset(id: DatasetID(projectID: "p", datasetID: "d"))
    let body = try RequestBody.json(dataset.wire, omitting: dataset.omittedWireDefaults)
    #expect(
      try WireJSON.object(String(decoding: body, as: UTF8.self))
        == WireJSON.object(#"{"datasetReference": {"projectId": "p", "datasetId": "d"}}"#))
  }

  // Baseline: U.DatasetInfo.02
  @Test func resolvingFillsProjectInIDAndAccessEntries() {
    let client = FakeHTTPTransport().client(projectID: "client-project")
    let dataset = Dataset(
      id: DatasetID(datasetID: "d"),
      access: [
        Acl(.view(TableID(datasetID: "d2", tableID: "v"))),
        Acl(.routine(RoutineID(datasetID: "d2", routineID: "r"))),
        Acl(.view(TableID(projectID: "other", datasetID: "d3", tableID: "v"))),
        Acl(.user("u@example.com"), role: .reader),
      ])
    let resolved = dataset.resolved(by: client)
    #expect(resolved.id == DatasetID(projectID: "client-project", datasetID: "d"))
    #expect(
      resolved.access == [
        Acl(.view(TableID(projectID: "client-project", datasetID: "d2", tableID: "v"))),
        Acl(.routine(RoutineID(projectID: "client-project", datasetID: "d2", routineID: "r"))),
        Acl(.view(TableID(projectID: "other", datasetID: "d3", tableID: "v"))),
        Acl(.user("u@example.com"), role: .reader),
      ])
  }

  // Baseline: U.DatasetInfo.03
  @Test func serializesMaxTimeTravelHours() throws {
    let dataset = Dataset(id: DatasetID(projectID: "p", datasetID: "d"), maxTimeTravelHours: 120)
    let body = try RequestBody.json(dataset.wire, omitting: dataset.omittedWireDefaults)
    let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
    #expect(object["maxTimeTravelHours"] as? String == "120")
    let decoded = try WireJSON.decode(
      String(decoding: body, as: UTF8.self), as: GoogleCloudBigQueryV2.Dataset.self)
    #expect(Dataset(wire: decoded) == dataset)
  }

  // Baseline: U.ExternalDatasetReference.01
  @Test func roundTripsExternalDatasetReference() throws {
    let reference = ExternalDatasetReference(
      externalSource: "aws-glue://arn", connection: "projects/p/locations/l/connections/c")
    #expect(
      try WireJSON.object(reference.wire)
        == WireJSON.object(
          #"{"externalSource": "aws-glue://arn", "connection": "projects/p/locations/l/connections/c"}"#
        ))
    #expect(ExternalDatasetReference(wire: reference.wire) == reference)
  }

  // Baseline: U.HttpBigQueryRpc.01
  @Test func listItemKeepsReferenceNameLabelsAndLocation() throws {
    let item = try WireJSON.decode(
      #"""
      {"kind": "bigquery#dataset", "id": "p:d", "friendlyName": "F",
       "datasetReference": {"projectId": "p", "datasetId": "d"},
       "labels": {"k": "v"}, "location": "US"}
      """#, as: ListFormatDataset.self)
    let dataset = Dataset(wire: item)
    #expect(dataset.id == DatasetID(projectID: "p", datasetID: "d"))
    #expect(dataset.generatedID == "p:d")
    #expect(dataset.friendlyName == "F")
    #expect(dataset.labels == ["k": "v"])
    #expect(dataset.location == "US")
    #expect(dataset.description == nil)
  }
}

@Suite struct AclTests {
  static let entities: [(Acl.Entity, String)] = [
    (
      .dataset(DatasetID(projectID: "p", datasetID: "d"), targetTypes: [.views]),
      #"{"dataset": {"dataset": {"projectId": "p", "datasetId": "d"}, "targetTypes": ["VIEWS"]}}"#
    ),
    (.domain("example.com"), #"{"domain": "example.com"}"#),
    (.group("g@example.com"), #"{"groupByEmail": "g@example.com"}"#),
    (.projectReaders, #"{"specialGroup": "projectReaders"}"#),
    (.user("u@example.com"), #"{"userByEmail": "u@example.com"}"#),
    (
      .view(TableID(projectID: "p", datasetID: "d", tableID: "v")),
      #"{"view": {"projectId": "p", "datasetId": "d", "tableId": "v"}}"#
    ),
    (
      .routine(RoutineID(projectID: "p", datasetID: "d", routineID: "r")),
      #"{"routine": {"projectId": "p", "datasetId": "d", "routineId": "r"}}"#
    ),
    (.iamMember("allUsers"), #"{"iamMember": "allUsers"}"#),
  ]

  // Baseline: U.Acl.01
  @Test(arguments: 0..<Self.entities.count)
  func entityMapsToAndFromJSON(index: Int) throws {
    let (entity, json) = Self.entities[index]
    let decoded = Acl(wire: try WireJSON.decode(json, as: Access.self))
    #expect(decoded == Acl(entity))
    #expect(Acl(wire: Acl(entity).wire) == Acl(entity))
    let encoded = try WireJSON.object(Acl(entity).wire)
    for (key, value) in try WireJSON.object(json) {
      #expect(encoded[key] as? NSObject == value as? NSObject)
    }
  }

  // Baseline: U.Acl.01
  @Test func entityAccessorsReturnTheirValue() {
    #expect(Acl.Entity.user("u").user == "u")
    #expect(Acl.Entity.user("u").group == nil)
    #expect(Acl.Entity.group("g").group == "g")
    #expect(Acl.Entity.domain("d").domain == "d")
    #expect(Acl.Entity.allAuthenticatedUsers.specialGroup == "allAuthenticatedUsers")
    #expect(Acl.Entity.iamMember("m").iamMember == "m")
    let table = TableID(projectID: "p", datasetID: "d", tableID: "t")
    #expect(Acl.Entity.view(table).view == table)
    let routine = RoutineID(projectID: "p", datasetID: "d", routineID: "r")
    #expect(Acl.Entity.routine(routine).routine == routine)
    let dataset = DatasetID(projectID: "p", datasetID: "d")
    #expect(Acl.Entity.dataset(dataset, targetTypes: [.routines]).dataset == dataset)
    #expect(Acl.Entity.dataset(dataset, targetTypes: [.routines]).targetTypes == [.routines])
  }

  // Baseline: U.Acl.02
  @Test func roleAndConditionRoundTrip() throws {
    let acl = Acl(
      .user("u@example.com"), role: .writer,
      condition: Expr("request.time < timestamp('2100-01-01')", title: "t", description: "d"))
    let wire = acl.wire
    #expect(wire.role == "WRITER")
    let condition = try WireJSON.object(wire)["condition"] as? NSDictionary
    #expect(condition?["expression"] as? String == "request.time < timestamp('2100-01-01')")
    #expect(condition?["title"] as? String == "t")
    #expect(condition?["description"] as? String == "d")
    #expect(Acl(wire: wire) == acl)
    #expect(Acl(wire: Acl(.user("u")).wire).role == nil)
    #expect(Acl(wire: Acl(.user("u")).wire).condition == nil)
  }
}
