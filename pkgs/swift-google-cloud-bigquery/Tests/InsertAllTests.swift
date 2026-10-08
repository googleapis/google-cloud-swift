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
import GoogleWKT
import Testing

@testable import GoogleCloudBigQuery

/// The JSON text of a row's content, with sorted keys.
private func jsonText(_ row: InsertRow) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return String(decoding: try encoder.encode(row.json), as: UTF8.self)
}

@Suite struct InsertRowTests {
  struct Address: Encodable {
    var city: String
    var zip: String?
  }

  struct Person: Encodable {
    var name: String
    var age: Int?
    var big: Int64
    var score: Double
    var ratio: Float
    var active: Bool
    var joined: Date
    var photo: Data
    var price: Decimal
    var exact: BigNumeric
    var birthday: BigQueryDate
    var alarm: BigQueryTime
    var meeting: BigQueryDateTime
    var wait: Interval
    var tags: [String]
    var address: Address
    var link: URL
    var period: BigQueryRange
  }

  // Design: §4.7
  @Test func encodableFollowsInsertAllRules() throws {
    let person = Person(
      name: "Ana", age: nil, big: 1 << 53 + 1, score: .nan, ratio: 1.2, active: true,
      joined: Date(timeIntervalSince1970: 1_704_164_645.123456), photo: Data([1, 3]),
      price: Decimal(string: "3.14")!, exact: BigNumeric("1e-38")!,
      birthday: BigQueryDate(year: 2024, month: 1, day: 2),
      alarm: BigQueryTime(hour: 3, minute: 4, second: 5),
      meeting: BigQueryDateTime(
        date: BigQueryDate(year: 2024, month: 1, day: 2),
        time: BigQueryTime(hour: 3, minute: 4, second: 5)),
      wait: Interval(years: 1, days: 2), tags: ["a", "b"],
      address: Address(city: "Paris", zip: nil),
      link: URL(string: "https://example.com/a")!,
      period: BigQueryRange(start: nil, end: "2024-02-01", elementType: .date))
    let row = try InsertRow(person, insertID: "id-1")
    #expect(row.insertID == "id-1")
    #expect(
      try jsonText(row)
        == #"{"active":true,"address":{"city":"Paris"},"alarm":"03:04:05","big":"9007199254740993","#
        + #""birthday":"2024-01-02","exact":"1e-38","joined":"2024-01-02T03:04:05.123456Z","#
        + #""link":"https://example.com/a","meeting":"2024-01-02 03:04:05","name":"Ana","#
        + #""period":{"end":"2024-02-01"},"photo":"AQM=","price":"3.14","ratio":1.2,"score":"NaN","tags":["a","b"],"wait":"1-0 2 0:0:0"}"#
    )
  }

  // Design: §4.7
  @Test func integersUpToTwoToThe53AreNumbers() throws {
    let row = try InsertRow(
      ["small": 1 << 53, "negative": -(1 << 53), "large": Int64.min] as [String: Int64])
    #expect(
      try jsonText(row)
        == #"{"large":"-9223372036854775808","negative":-9007199254740992,"small":9007199254740992}"#
    )
  }

  // Design: §4.7
  @Test func infinitiesBecomeStrings() throws {
    let row = try InsertRow(["a": .infinity, "b": -.infinity, "c": 0.5] as [String: Double])
    #expect(try jsonText(row) == #"{"a":"Infinity","b":"-Infinity","c":0.5}"#)
  }

  // Baseline: U.InsertAllRequest.02
  @Test func nilValuesAreAcceptedAndOmitted() throws {
    struct Explicit: Encodable {
      var foo: String?
      func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.foo, forKey: .foo)
      }
      enum CodingKeys: CodingKey { case foo }
    }
    #expect(try jsonText(try InsertRow(Explicit(foo: nil))) == "{}")
    #expect(try jsonText(InsertRow(["foo": nil])) == "{}")
    #expect(try jsonText(InsertRow(["foo": nil, "bar": ["baz": nil]])) == #"{"bar":{}}"#)
  }

  // Design: §4.7
  @Test func nonObjectValuesAreRejected() {
    #expect(throws: EncodingError.self) { try InsertRow([1, 2, 3]) }
    #expect(throws: EncodingError.self) { try InsertRow("text") }
  }

  // Baseline: U.InsertAllRequest.01
  @Test func valueLiteralsAndFactories() throws {
    let row = InsertRow(
      [
        "string": "s", "int": 42, "double": 1.5, "bool": false, "array": [1, 2],
        "record": ["nested": "n"], "bytes": .bytes(Data([1, 3])),
        "timestamp": .timestamp(Date(timeIntervalSince1970: 0.000001)),
        "numeric": .numeric(Decimal(string: "1.25")!),
        "bigNumeric": .bigNumeric(BigNumeric("2.5")!),
        "date": .date(BigQueryDate(year: 2024, month: 1, day: 2)),
        "time": .time(BigQueryTime(hour: 1, minute: 2, second: 3)),
        "dateTime": .dateTime(
          BigQueryDateTime(
            date: BigQueryDate(year: 2024, month: 1, day: 2),
            time: BigQueryTime(hour: 1, minute: 2, second: 3))),
        "interval": .interval(Interval(months: 1, days: 0, time: .zero)),
        "range": .range(.date(from: BigQueryDate(year: 2024, month: 1, day: 1), to: nil)),
        "nan": .float64(.nan),
      ])
    #expect(row.insertID == nil)
    #expect(
      try jsonText(row)
        == #"{"array":[1,2],"bigNumeric":"2.5","bool":false,"bytes":"AQM=","date":"2024-01-02","#
        + #""dateTime":"2024-01-02 01:02:03","double":1.5,"int":42,"interval":"0-1 0 0:0:0","nan":"NaN","#
        + #""numeric":"1.25","range":{"start":"2024-01-01"},"record":{"nested":"n"},"string":"s","#
        + #""time":"01:02:03","timestamp":"1970-01-01T00:00:00.000001Z"}"#)
  }
}

@Suite struct InsertAllResponseTests {
  // Baseline: U.InsertAllResponse.01
  @Test func errorsAreKeyedByRowIndex() {
    let empty = InsertAllResponse()
    #expect(!empty.hasErrors)
    #expect(empty.rowErrors[0] == nil)
    let errors = [BigQueryError.Detail(reason: "invalid", message: "bad")]
    let response = InsertAllResponse(rowErrors: [1: errors])
    #expect(response.hasErrors)
    #expect(response.rowErrors[1] == errors)
    #expect(response.rowErrors[0] == nil)
  }

  // Baseline: U.InsertAllResponse.02
  @Test func decodesInsertErrors() throws {
    let wire: InsertAllWireResponse = try WireJSON.decode(
      #"""
      {"insertErrors": [
        {"index": 0, "errors": [{"reason": "invalid", "location": "age", "message": "bad age"}]},
        {"index": 2, "errors": [{"reason": "stopped"}, {"reason": "timeout"}]}]}
      """#)
    let response = InsertAllResponse(wire: wire)
    #expect(
      response.rowErrors == [
        0: [BigQueryError.Detail(reason: "invalid", location: "age", message: "bad age")],
        2: [BigQueryError.Detail(reason: "stopped"), BigQueryError.Detail(reason: "timeout")],
      ])
    #expect(InsertAllResponse(wire: try WireJSON.decode("{}")) == InsertAllResponse())
  }
}

@Suite struct BigQueryClientInsertAllTests {
  private let table = TableID(datasetID: "dataset", tableID: "table")

  // Baseline: U.BigQueryImpl.28, U.InsertAllRequest.01
  @Test func sendsRowsAndOptionsToTheTableProject() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "{}")
    let client = fake.client()
    let response = try await client.insertAll(
      [InsertRow(["name": "a"], insertID: "id-1"), InsertRow(["name": "b"], insertID: "id-2")],
      into: TableID(projectID: "other-project", datasetID: "dataset", tableID: "table$20240101"),
      skipInvalidRows: true, ignoreUnknownValues: true, templateSuffix: "_suffix")
    #expect(!response.hasErrors)
    let request = try #require(fake.requests.first)
    #expect(request.method == .post)
    #expect(
      request.path
        == "/bigquery/v2/projects/other-project/datasets/dataset/tables/table%2420240101/insertAll")
    #expect(
      try WireJSON.object(String(decoding: try #require(request.body), as: UTF8.self))
        == (try WireJSON.object(
          #"""
          {"rows": [{"insertId": "id-1", "json": {"name": "a"}}, {"insertId": "id-2", "json": {"name": "b"}}],
           "skipInvalidRows": true, "ignoreUnknownValues": true, "templateSuffix": "_suffix"}
          """#)))
  }

  // Baseline: U.BigQueryImpl.28
  @Test func usesTheClientProjectAndDefaultOptions() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "{}")
    _ = try await fake.client(projectID: "client-project").insertAll(
      [InsertRow(["name": "a"], insertID: "id-1")], into: self.table)
    let request = try #require(fake.requests.first)
    #expect(
      request.path == "/bigquery/v2/projects/client-project/datasets/dataset/tables/table/insertAll"
    )
    let body = try request.jsonBody()
    #expect(body["skipInvalidRows"] as? Bool == false)
    #expect(body["ignoreUnknownValues"] as? Bool == false)
    #expect(body["templateSuffix"] == nil)
  }

  // Design: §1 #8-Q2
  @Test func generatesMissingInsertIDsThatSurviveRetries() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 500, reasons: ["backendError"])
    fake.enqueue(json: "{}")
    _ = try await fake.client().insertAll(
      [InsertRow(["name": "a"]), InsertRow(["name": "b"], insertID: "mine")], into: self.table)
    #expect(fake.requests.count == 2)
    let ids = try fake.requests.map { request in
      try (request.jsonBody()["rows"] as? [[String: Any]] ?? []).map { $0["insertId"] as? String }
    }
    #expect(ids[0][1] == "mine")
    let generated = try #require(ids[0][0])
    #expect(UUID(uuidString: generated) != nil)
    #expect(ids[1] == ids[0])
  }

  // Baseline: U.BigQueryImpl.26
  @Test func rowsWithInsertIDsAreRetriedAndErrorsMappedByIndex() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 500, reasons: ["backendError"])
    fake.enqueue(
      json:
        #"{"insertErrors": [{"index": 1, "errors": [{"reason": "invalid", "message": "bad"}]}]}"#)
    let response = try await fake.client().insertAll(
      [InsertRow(["a": 1], insertID: "1"), InsertRow(["a": "x"], insertID: "2")], into: self.table,
      insertIDs: .none)
    #expect(fake.requests.count == 2)
    #expect(response.rowErrors == [1: [BigQueryError.Detail(reason: "invalid", message: "bad")]])
  }

  // Baseline: U.BigQueryImpl.27
  @Test func rowsWithoutInsertIDsAreNotRetried() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 500, reasons: ["backendError"])
    fake.enqueue(json: "{}")
    await #expect(throws: BigQueryError.self) {
      try await fake.client().insertAll(
        [InsertRow(["a": 1], insertID: "1"), InsertRow(["a": 2])], into: self.table,
        insertIDs: .none)
    }
    #expect(fake.requests.count == 1)
    let rows = try fake.requests[0].jsonBody()["rows"] as? [[String: Any]] ?? []
    #expect(rows.count == 2)
    #expect(rows[1]["insertId"] == nil)
  }

  // Design: §4.7
  @Test func encodableValuesAreSentAsRowsWithGeneratedInsertIDs() async throws {
    struct Person: Encodable {
      var name: String
      var age: Int?
    }
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "{}")
    _ = try await fake.client().insertAll(
      [Person(name: "Ana", age: 31), Person(name: "Bo", age: nil)], into: self.table,
      skipInvalidRows: true)
    let body = try #require(fake.requests.first).jsonBody()
    #expect(body["skipInvalidRows"] as? Bool == true)
    let rows = try #require(body["rows"] as? [[String: Any]])
    #expect(rows.count == 2)
    let first = try #require(rows[0]["json"] as? [String: Any])
    #expect(first["name"] as? String == "Ana")
    #expect(first["age"] as? Int == 31)
    let second = try #require(rows[1]["json"] as? [String: Any])
    #expect(second["name"] as? String == "Bo")
    #expect(second["age"] == nil)
    #expect(rows.allSatisfy { UUID(uuidString: $0["insertId"] as? String ?? "") != nil })
  }

  // Design: §4.7
  @Test func encodableValuesThatAreNotObjectsFailBeforeSending() async throws {
    let fake = FakeHTTPTransport()
    await #expect(throws: EncodingError.self) {
      try await fake.client().insertAll(["not an object"], into: self.table)
    }
    #expect(fake.requests.isEmpty)
  }
}
