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
import GoogleWKT
import Testing

@testable import GoogleCloudBigQuery

// The generated module declares types with the same names.
private typealias QueryParameterValue = GoogleCloudBigQuery.QueryParameterValue

/// Live checks of insertAll, query parameters, and row decoding (slice 2).
///
/// Tables are created and queried through the raw transport until the tables and jobs slices
/// land.
@Suite(.enabled(if: integrationTestsEnabled()))
struct ValuesIntegrationTests {
  // MARK: - insertAll

  struct Address: Codable, Equatable {
    var city: String
    var zip: String?
  }

  struct Record: Codable, Equatable {
    var name: String
    var age: Int64?
    var score: Double
    var active: Bool
    var joined: Date
    var photo: Data
    var price: Decimal
    var exact: BigNumeric
    var birthday: BigQueryDate
    var alarm: BigQueryTime
    var meeting: BigQueryDateTime
    var wait: Interval
    var place: String
    var payload: String
    var period: BigQueryRange
    var tags: [String]
    var address: Address
    var visits: [Address]
  }

  private static let recordSchema = #"""
    {"fields": [
      {"name": "name", "type": "STRING", "mode": "REQUIRED"},
      {"name": "age", "type": "INT64"},
      {"name": "score", "type": "FLOAT64"},
      {"name": "active", "type": "BOOL"},
      {"name": "joined", "type": "TIMESTAMP"},
      {"name": "photo", "type": "BYTES"},
      {"name": "price", "type": "NUMERIC"},
      {"name": "exact", "type": "BIGNUMERIC"},
      {"name": "birthday", "type": "DATE"},
      {"name": "alarm", "type": "TIME"},
      {"name": "meeting", "type": "DATETIME"},
      {"name": "wait", "type": "INTERVAL"},
      {"name": "place", "type": "GEOGRAPHY"},
      {"name": "payload", "type": "JSON"},
      {"name": "period", "type": "RANGE", "rangeElementType": {"type": "DATE"}},
      {"name": "tags", "type": "STRING", "mode": "REPEATED"},
      {"name": "address", "type": "RECORD", "fields": [
        {"name": "city", "type": "STRING"}, {"name": "zip", "type": "STRING"}]},
      {"name": "visits", "type": "RECORD", "mode": "REPEATED", "fields": [
        {"name": "city", "type": "STRING"}, {"name": "zip", "type": "STRING"}]}
    ]}
    """#

  private static let sample = Record(
    name: "Ana", age: nil, score: 9.5, active: true,
    joined: Date(timeIntervalSince1970: 1_704_164_645.123456), photo: Data([1, 3, 255]),
    price: Decimal(string: "123456789.123456789")!,
    exact: BigNumeric(
      "578960446186580977117854925043439539266.34992332820282019728792003956564819967")!,
    birthday: BigQueryDate(year: 1815, month: 12, day: 10),
    alarm: BigQueryTime(hour: 5, minute: 41, second: 35, nanosecond: 220_000_000),
    meeting: BigQueryDateTime(
      date: BigQueryDate(year: 2014, month: 8, day: 19),
      time: BigQueryTime(hour: 5, minute: 41, second: 35, nanosecond: 123_456_000)),
    wait: Interval(
      years: 1, months: 2, days: -3, hours: 4, minutes: 5, seconds: 6, nanoseconds: 789_000),
    place: "POINT(-122.35022 47.649154)", payload: #"{"a":[1,2]}"#,
    period: .date(from: BigQueryDate(year: 2024, month: 1, day: 1), to: nil),
    tags: ["a", "b"], address: Address(city: "Paris", zip: nil),
    visits: [Address(city: "Oslo", zip: "0150"), Address(city: "Rome", zip: nil)])

  // Baseline: IT-048, IT-123, U.FieldValueList.02
  @Test func insertAllRoundTripsEveryType() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: "values") { dataset in
      let table = try await Self.createTable(client, dataset, "records", schema: Self.recordSchema)
      let fromDictionary = InsertRow([
        "name": "Bo", "age": .int64(1 << 60), "score": .float64(.infinity), "active": false,
        "joined": .timestamp(Date(timeIntervalSince1970: -1.5)), "photo": .bytes(Data()),
        "price": .numeric(Decimal(string: "-0.000000001")!),
        "exact": .bigNumeric(BigNumeric("1e-38")!),
        "birthday": .date(BigQueryDate(year: 1, month: 1, day: 1)),
        "alarm": .time(BigQueryTime(hour: 23, minute: 59, second: 59, nanosecond: 999_999_000)),
        "meeting": .dateTime(Self.sample.meeting), "wait": .interval(Interval(days: 1)),
        "place": "POINT(1 2)", "payload": "[]",
        "period": .range(.date(from: nil, to: BigQueryDate(year: 2024, month: 2, day: 1))),
        "tags": [], "address": ["city": "Lima"], "visits": [],
      ])
      let response = try await client.insertAll(
        [try InsertRow(Self.sample), fromDictionary], into: table)
      try #require(response.rowErrors == [:], "\(response.rowErrors)")

      let rows = try await Self.query(
        client, "SELECT * FROM `\(dataset.projectID!).\(dataset.datasetID).records` ORDER BY name")
      try #require(rows.count == 2)
      let ana = try rows[0].decode(Record.self)
      var expected = Self.sample
      expected.period.elementType = .date
      #expect(ana == expected)
      // NUMERIC and ARRAY<STRUCT> elements read back by name.
      #expect(try rows[0]["visits"]?.arrayValue?[0].recordValue?["city"]?.stringValue == "Oslo")

      let bo = rows[1]
      #expect(try bo["age"]?.int64Value == 1 << 60)
      #expect(try bo["score"]?.doubleValue == .infinity)
      #expect(try bo["joined"]?.timestampMicros == -1_500_000)
      #expect(try bo["price"]?.numericValue == Decimal(string: "-0.000000001"))
      #expect(try bo["exact"]?.bigNumericValue == BigNumeric("1e-38"))
      #expect(try bo["alarm"]?.timeValue?.nanosecond == 999_999_000)
      #expect(try bo["wait"]?.intervalValue == Interval(days: 1))
      #expect(try bo["period"]?.rangeValue == BigQueryRange(start: nil, end: "2024-02-01"))
      #expect(try bo["tags"]?.arrayValue == [])
      #expect(try bo["visits"]?.arrayValue == [])
      #expect(try bo["address"]?.recordValue?["zip"]?.isNull == true)

      // An ARRAY<STRUCT> parameter filters the table data.
      let people = QueryParameterValue.array(
        [.struct(["name": .string("Bo")]), .struct(["name": .string("Cy")])],
        of: .struct([.init("name", .string)]))
      let filtered = try await Self.query(
        client,
        "SELECT r.name FROM `\(dataset.projectID!).\(dataset.datasetID).records` AS r,"
          + " UNNEST(@people) AS p WHERE r.name = p.name",
        parameters: .named(["people": people]))
      #expect(try filtered.map { try $0["name"]?.stringValue } == ["Bo"])
    }
  }

  // Baseline: IT-049
  @Test func insertAllWithTemplateSuffixCreatesTable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: "values") { dataset in
      let table = try await Self.createTable(
        client, dataset, "template", schema: #"{"fields": [{"name": "name", "type": "STRING"}]}"#)
      let response = try await client.insertAll(
        [InsertRow(["name": "a"]), InsertRow(["name": "b"])], into: table, templateSuffix: "_suffix"
      )
      #expect(!response.hasErrors)
      let path =
        "/bigquery/v2/projects/\(dataset.projectID!)/datasets/\(dataset.datasetID)/tables/template_suffix"
      var created: GoogleCloudBigQueryV2.Table? = nil
      for _ in 0..<30 {
        created = try await client.transport.jsonOrNil(
          HTTPRequest(method: .get, path: path), as: GoogleCloudBigQueryV2.Table.self)
        if created != nil { break }
        try await Task.sleep(for: .seconds(2))
      }
      #expect(created?.schema?.fields.map(\.name) == ["name"])
    }
  }

  // Baseline: IT-050
  @Test func insertAllReportsPerRowErrors() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: "values") { dataset in
      let table = try await Self.createTable(
        client, dataset, "errors",
        schema:
          #"{"fields": [{"name": "name", "type": "STRING", "mode": "REQUIRED"}, {"name": "n", "type": "INT64"}]}"#
      )
      let rows = [
        InsertRow(["name": "ok", "n": 1]),
        try InsertRow(["name": "bad", "n": "not a number"]),
        InsertRow(["name": "unknown", "extra": true]),
        try InsertRow(["n": 2]),
      ]
      let strict = try await client.insertAll(rows, into: table)
      #expect(Set(strict.rowErrors.keys) == [0, 1, 2, 3])
      #expect(strict.rowErrors[0]?.first?.reason == "stopped")
      #expect(strict.rowErrors[1]?.first?.reason == "invalid")

      let lenient = try await client.insertAll(
        rows, into: table, skipInvalidRows: true, ignoreUnknownValues: true)
      #expect(Set(lenient.rowErrors.keys) == [1, 3])
      #expect(lenient.rowErrors[3]?.first?.reason == "invalid")
    }
  }

  // MARK: - Query parameters

  // Baseline: IT-116, IT-065, IT-074, IT-127, IT-128
  @Test func positionalParametersOfEveryScalarType() async throws {
    let client = try IntegrationTest.makeClient()
    let instant = Date(timeIntervalSince1970: 1_408_452_095.22)
    let values: [QueryParameterValue] = [
      .string("s"), .int64(Int64.max), .float64(1.5), .bool(true),
      .numeric(Decimal(string: "123456789.123456789")!),
      .bigNumeric(BigNumeric("0.00000000500000000000000000000000000000")!),
      .bigNumeric(BigNumeric("1e-38")!),
      .bytes(Data([1, 3])), .timestamp(instant), try .timestamp("2014-08-19 12:41:35.220000+00:00"),
      .date(BigQueryDate(year: 2014, month: 8, day: 19)),
      .time(BigQueryTime(hour: 5, minute: 41, second: 35, nanosecond: 220_000_000)),
      .dateTime(BigQueryDateTime("2014-08-19 05:41:35.220000")!),
      .geography("POINT(-122.35022 47.649154)"), .json(#"{"a": 1}"#),
      .interval(Interval(years: 1, days: 2, hours: 3)),
    ]
    let select = values.indices.map { "? AS c\($0)" }.joined(separator: ", ")
    let rows = try await Self.query(client, "SELECT \(select)", parameters: .positional(values))
    let row = try #require(rows.first)
    #expect(try row["c0"]?.stringValue == "s")
    #expect(try row["c1"]?.int64Value == Int64.max)
    #expect(try row["c2"]?.doubleValue == 1.5)
    #expect(try row["c3"]?.boolValue == true)
    #expect(try row["c4"]?.numericValue == Decimal(string: "123456789.123456789"))
    #expect(try row["c5"]?.bigNumericValue == BigNumeric("5e-9"))
    #expect(try row["c6"]?.bigNumericValue == BigNumeric("1e-38"))
    #expect(try row["c7"]?.bytesValue == Data([1, 3]))
    #expect(try row["c8"]?.timestampValue == instant)
    #expect(try row["c9"]?.timestampMicros == 1_408_452_095_220_000)
    #expect(try row["c10"]?.dateValue == BigQueryDate(year: 2014, month: 8, day: 19))
    #expect(
      try row["c11"]?.timeValue
        == BigQueryTime(hour: 5, minute: 41, second: 35, nanosecond: 220_000_000))
    #expect(try row["c12"]?.dateTimeValue == BigQueryDateTime("2014-08-19 05:41:35.22"))
    #expect(try row["c13"]?.geographyValue == "POINT(-122.35022 47.649154)")
    #expect(try row["c14"]?.jsonValue == #"{"a":1}"#)
    #expect(try row["c15"]?.intervalValue == Interval(years: 1, days: 2, hours: 3))
  }

  // Baseline: IT-118
  @Test func namedParametersIncludingArrays() async throws {
    let client = try IntegrationTest.makeClient()
    let rows = try await Self.query(
      client,
      "SELECT @name AS name, @n + 1 AS n, ARRAY_LENGTH(@ids) AS count, @ids AS ids, @empty AS empty",
      parameters: .named([
        "name": .string("x"), "n": .int64(41), "ids": .array([1, 2, 3] as [Int64]),
        "empty": .array([] as [String]),
      ]))
    struct Result: Decodable {
      var name: String
      var n: Int
      var count: Int
      var ids: [Int64]
      var empty: [String]
    }
    let result = try #require(rows.first).decode(Result.self)
    #expect(result.name == "x")
    #expect(result.n == 42)
    #expect(result.count == 3)
    #expect(result.ids == [1, 2, 3])
    #expect(result.empty == [])
  }

  // Baseline: IT-120, IT-126, IT-125
  @Test func structParametersRoundTrip() async throws {
    let client = try IntegrationTest.makeClient()
    let inner = QueryParameterValue.struct(["b": .bool(true), "i": .int64(15)])
    let outer = QueryParameterValue.struct(["s": .string("test"), "inner": inner])
    let rows = try await Self.query(
      client, "SELECT @person AS person, @person.inner.i AS i, STRUCT(1 AS a, 'x' AS b) AS literal",
      parameters: .named(["person": outer]))
    struct Inner: Decodable, Equatable {
      var b: Bool
      var i: Int
    }
    struct Outer: Decodable, Equatable {
      var s: String
      var inner: Inner
    }
    struct Literal: Decodable, Equatable {
      var a: Int
      var b: String
    }
    struct Result: Decodable {
      var person: Outer
      var i: Int
      var literal: Literal
    }
    let result = try #require(rows.first).decode(Result.self)
    #expect(result.person == Outer(s: "test", inner: Inner(b: true, i: 15)))
    #expect(result.i == 15)
    #expect(result.literal == Literal(a: 1, b: "x"))
  }

  // Baseline: IT-121, IT-122
  @Test func arrayOfStructParameters() async throws {
    let client = try IntegrationTest.makeClient()
    let elementType = QueryParameterType.struct([.init("name", .string), .init("age", .int64)])
    let people = QueryParameterValue.array(
      [
        .struct(["name": .string("Ana"), "age": .int64(31)]),
        .struct(["name": .string("Bo"), "age": .int64(17)]),
      ], of: elementType)
    let rows = try await Self.query(
      client,
      "SELECT @people AS people, ARRAY(SELECT p.name FROM UNNEST(@people) AS p WHERE p.age >= 18) AS adults",
      parameters: .named(["people": people]))
    struct Person: Decodable, Equatable {
      var name: String
      var age: Int
    }
    struct Result: Decodable {
      var people: [Person]
      var adults: [String]
    }
    let result = try #require(rows.first).decode(Result.self)
    #expect(result.people == [Person(name: "Ana", age: 31), Person(name: "Bo", age: 17)])
    #expect(result.adults == ["Ana"])
  }

  // Baseline: IT-124
  @Test func emptyArrayOfFieldlessStructParameterIsRejected() async throws {
    // Java infers `ARRAY<STRUCT>` with no fields for an empty array; the service rejects it.
    let client = try IntegrationTest.makeClient()
    await #expect(throws: BigQueryError.self) {
      _ = try await Self.query(
        client,
        "SELECT * FROM (SELECT STRUCT(false AS boolField) AS repeatedRecord)"
          + " WHERE repeatedRecord IN UNNEST(@repeatedRecordField)",
        parameters: .named(["repeatedRecordField": .array([], of: .struct([]))]))
    }
  }

  // Baseline: U.QueryParameterValue.12
  @Test func rangeParametersRoundTrip() async throws {
    let client = try IntegrationTest.makeClient()
    let dates = BigQueryRange.date(from: BigQueryDate(year: 2024, month: 1, day: 1), to: nil)
    let timestamps = BigQueryRange(
      start: "2014-08-19 12:41:35.220000+00:00", end: "2015-09-20 13:41:35.220000+01:00",
      elementType: .timestamp)
    let rows = try await Self.query(
      client, "SELECT @dates AS dates, @timestamps AS timestamps, [@dates, @dates] AS many",
      parameters: .named(["dates": .range(dates), "timestamps": .range(timestamps)]))
    struct Result: Decodable {
      var dates: BigQueryRange
      var timestamps: BigQueryRange
      var many: [BigQueryRange]
    }
    let row = try #require(rows.first)
    let result = try row.decode(Result.self)
    #expect(result.dates == dates)
    #expect(result.many == [dates, dates])
    #expect(result.timestamps.elementType == .timestamp)
    let range = try #require(try row["timestamps"]?.rangeValue)
    #expect(try range.startValue.timestampMicros == 1_408_452_095_220_000)
    #expect(try range.endValue.timestampMicros == 1_442_752_895_220_000)
  }

  // MARK: - Helpers

  /// Creates a table from a schema in JSON form.
  private static func createTable(
    _ client: BigQueryClient, _ dataset: DatasetID, _ name: String, schema: String
  ) async throws -> TableID {
    let id = TableID(projectID: dataset.projectID, datasetID: dataset.datasetID, tableID: name)
    let body =
      #"{"tableReference": {"projectId": "\#(id.projectID!)", "datasetId": "\#(id.datasetID)", "tableId": "\#(name)"}, "schema": \#(schema)}"#
    let _: GoogleCloudBigQueryV2.Table = try await client.transport.json(
      HTTPRequest(
        method: .post,
        path: "/bigquery/v2/projects/\(id.projectID!)/datasets/\(id.datasetID)/tables",
        body: Data(body.utf8)),
      idempotent: false)
    return id
  }

  /// Runs a query with `jobs.query` and returns its rows. The query must finish within the
  /// request timeout.
  private static func query(
    _ client: BigQueryClient, _ sql: String, parameters: QueryParameters? = nil
  ) async throws -> [Row] {
    let request = GoogleCloudBigQueryV2.QueryRequest().with {
      $0.query = sql
      $0.useLegacySql = WKTBoolValue(false)
      $0.timeoutMs = WKTUInt32Value(60_000)
      $0.formatOptions = GoogleCloudBigQueryV2.DataFormatOptions().with {
        $0.useInt64Timestamp = true
      }
      if let parameters {
        $0.parameterMode = parameters.wireMode
        $0.queryParameters = parameters.wire
      }
    }
    let response: GoogleCloudBigQueryV2.QueryResponse = try await client.transport.json(
      HTTPRequest(
        method: .post, path: "/bigquery/v2/projects/\(client.projectID)/queries",
        body: try RequestBody.json(request)),
      idempotent: false)
    guard response.jobComplete == true, let schema = response.schema else {
      throw BigQueryError.invalidArgument("the query did not finish in time")
    }
    return try Row.rows(from: response.rows, schema: Schema(wire: schema))
  }
}
