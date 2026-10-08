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

/// Live checks of insertAll, query parameters, and row decoding (slice 2).
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

  private static let addressFields: [Field] = [
    Field("city", .string),
    Field("zip", .string),
  ]

  private static func rangeField(_ name: String, _ elementType: FieldType) -> Field {
    var field = Field(name, .range)
    field.rangeElementType = elementType
    return field
  }

  private static let recordSchema = Schema([
    Field("name", .string, mode: .required),
    Field("age", .int64),
    Field("score", .float64),
    Field("active", .bool),
    Field("joined", .timestamp),
    Field("photo", .bytes),
    Field("price", .numeric),
    Field("exact", .bigNumeric),
    Field("birthday", .date),
    Field("alarm", .time),
    Field("meeting", .dateTime),
    Field("wait", .interval),
    Field("place", .geography),
    Field("payload", .json),
    rangeField("period", .date),
    Field("tags", .string, mode: .repeated),
    Field("address", .struct, fields: addressFields),
    Field("visits", .struct, mode: .repeated, fields: addressFields),
  ])

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

  // Baseline: IT-048, IT-123, IT-013 (partial), IT-014 (partial), IT-015 (partial), U.FieldValueList.02
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
      #expect(rows[0]["visits"]?.arrayValue?[0].recordValue?["city"]?.stringValue == "Oslo")

      let bo = rows[1]
      #expect(try bo["age"]?.int64Value == 1 << 60)
      #expect(try bo["score"]?.doubleValue == .infinity)
      #expect(try bo["joined"]?.timestampMicros == -1_500_000)
      #expect(try bo["price"]?.numericValue == Decimal(string: "-0.000000001"))
      #expect(try bo["exact"]?.bigNumericValue == BigNumeric("1e-38"))
      #expect(try bo["alarm"]?.timeValue?.nanosecond == 999_999_000)
      #expect(try bo["wait"]?.intervalValue == Interval(days: 1))
      #expect(try bo["period"]?.rangeValue == BigQueryRange(start: nil, end: "2024-02-01"))
      #expect(bo["tags"]?.arrayValue == [])
      #expect(bo["visits"]?.arrayValue == [])
      #expect(bo["address"]?.recordValue?["zip"]?.isNull == true)

      // An ARRAY<STRUCT> parameter filters the table data.
      let people = QueryParameterValue.array(
        [.struct(["name": .string("Bo")]), .struct(["name": .string("Cy")])],
        of: .struct([.init("name", .string)]))
      let filtered = try await Self.query(
        client,
        "SELECT r.name FROM `\(dataset.projectID!).\(dataset.datasetID).records` AS r,"
          + " UNNEST(@people) AS p WHERE r.name = p.name",
        parameters: .named(["people": people]))
      #expect(filtered.map { $0["name"]?.stringValue } == ["Bo"])
    }
  }

  // Baseline: IT-049
  @Test func insertAllWithTemplateSuffixCreatesTable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: "values") { dataset in
      let table = try await Self.createTable(
        client, dataset, "template", schema: Schema([Field("name", .string)]))
      let response = try await client.insertAll(
        [InsertRow(["name": "a"]), InsertRow(["name": "b"])], into: table, templateSuffix: "_suffix"
      )
      #expect(!response.hasErrors)
      let suffixed = TableID(
        projectID: dataset.projectID, datasetID: dataset.datasetID, tableID: "template_suffix")
      var created: Table? = nil
      for _ in 0..<30 {
        created = try await client.getTable(suffixed)
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
        schema: Schema([
          Field("name", .string, mode: .required),
          Field("n", .int64),
        ])
      )
      let rows = [
        InsertRow(["name": "ok", "n": 1]),
        InsertRow(["name": "bad", "n": "not a number"]),
        InsertRow(["name": "unknown", "extra": true]),
        InsertRow(["n": 2]),
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

  // Baseline: IT-013, IT-014 (partial), IT-015
  @Test func jsonIntervalAndRangeColumns() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: "values") { dataset in
      let table = try await Self.createTable(
        client, dataset, "typed",
        schema: Schema([
          Field("name", .string),
          Field("j", .json),
          Field("iv", .interval),
          Self.rangeField("d", .date),
          Self.rangeField("dt", .dateTime),
          Self.rangeField("ts", .timestamp),
        ]))
      let dates = BigQueryRange.date(
        from: BigQueryDate(year: 2020, month: 1, day: 1),
        to: BigQueryDate(year: 2020, month: 12, day: 31))
      let dateTimes = BigQueryRange.dateTime(
        from: BigQueryDateTime("2020-01-01 12:00:00"), to: BigQueryDateTime("2020-12-31 12:00:00"))
      let timestamps = BigQueryRange.timestamp(
        from: Date(timeIntervalSince1970: 1_577_880_000),
        to: Date(timeIntervalSince1970: 1_609_416_000.5))
      let response = try await client.insertAll(
        [
          InsertRow([
            "name": "bounded", "j": #"{"class": "student"}"#, "iv": "123-7 -19 0:24:12.000006",
            "d": .range(dates), "dt": .range(dateTimes), "ts": .range(timestamps),
          ]),
          InsertRow([
            "name": "unbounded", "iv": "P123Y7M-19DT0H24M12.000006S",
            "d": .range(BigQueryRange(start: nil, end: nil)),
            "dt": .range(BigQueryRange(start: nil, end: nil)),
            "ts": .range(BigQueryRange(start: "2020-01-01 00:00:00", end: nil)),
          ]),
        ], into: table)
      try #require(response.rowErrors == [:], "\(response.rowErrors)")

      let bad = try await client.insertAll(
        [InsertRow(["name": "bad", "j": #"{"class": "#])], into: table)
      #expect(bad.rowErrors[0]?.first?.reason == "invalid")

      let fqn = "`\(dataset.projectID!).\(dataset.datasetID).typed`"
      struct Typed: Decodable {
        var name: String
        var j: String?
        var iv: Interval
        var d: BigQueryRange
        var dt: BigQueryRange
        var ts: BigQueryRange
      }
      let rows = try await Self.query(client, "SELECT * FROM \(fqn) ORDER BY name").map {
        try $0.decode(Typed.self)
      }
      try #require(rows.count == 2)
      let interval = Interval(
        years: 123, months: 7, days: -19, minutes: 24, seconds: 12, nanoseconds: 6000)
      #expect(rows[0].j == #"{"class":"student"}"#)
      #expect(rows[0].iv == interval)
      #expect(rows[0].d == dates)
      #expect(
        rows[0].dt
          == BigQueryRange(
            start: "2020-01-01T12:00:00", end: "2020-12-31T12:00:00", elementType: .dateTime))
      #expect(rows[0].ts.elementType == .timestamp)
      #expect(
        try rows[0].ts.startValue.timestampValue == Date(timeIntervalSince1970: 1_577_880_000))
      #expect(
        try rows[0].ts.endValue.timestampValue == Date(timeIntervalSince1970: 1_609_416_000.5))
      #expect(rows[1].j == nil)
      #expect(rows[1].iv == interval)
      #expect(rows[1].d == BigQueryRange(start: nil, end: nil, elementType: .date))
      #expect(try rows[1].ts.startValue.timestampMicros == 1_577_836_800_000_000)
      #expect(rows[1].ts.end == nil)

      // RANGE, INTERVAL and JSON parameters filter the table.
      let filtered = try await Self.query(
        client,
        "SELECT name, JSON_VALUE(j, '$.class') AS class FROM \(fqn)"
          + " WHERE d = @d AND dt = @dt AND ts = @ts AND iv = @iv"
          + " AND JSON_VALUE(j, '$.class') = JSON_VALUE(@j, '$.class')",
        parameters: .named([
          "d": .range(dates), "dt": .range(dateTimes), "ts": .range(timestamps),
          "iv": try .interval("P123Y7M-19DT0H24M12.000006S"), "j": .json(#"{"class": "student"}"#),
        ]))
      #expect(filtered.map { $0["class"]?.stringValue } == ["student"])

      await #expect {
        _ = try await Self.query(
          client, "SELECT ? AS j", parameters: .positional([.json(#"{"class" : {"student" : [}"#)]))
      } throws: { error in
        (error as? BigQueryError)?.reason == "invalidQuery"
      }
    }
  }

  // Baseline: IT-001, IT-066
  @Test func timestampsAreLossless() async throws {
    let client = try IntegrationTest.makeClient()
    let rows = try await Self.query(
      client,
      "SELECT TIMESTAMP '9999-12-31 23:59:59.999999 UTC' AS max,"
        + " TIMESTAMP '2024-01-02 03:04:05.123456 UTC' AS t, TIMESTAMP '1900-01-01 00:00:00.000001 UTC' AS old"
    )
    let row = try #require(rows.first)
    #expect(row["max"]?.stringValue == "9999-12-31T23:59:59.999999Z")
    #expect(try row["max"]?.timestampMicros == 253_402_300_799_999_999)
    #expect(
      try row["max"]?.preciseTimestampValue == BigQueryTimestamp("9999-12-31T23:59:59.999999Z"))
    #expect(try row["t"]?.timestampMicros == 1_704_164_645_123_456)
    #expect(try row["t"]?.timestampValue == Date(timeIntervalSince1970: 1_704_164_645.123456))
    #expect(try row["old"]?.timestampMicros == -2_208_988_799_999_999)
  }

  // Baseline: IT-194, IT-195, IT-196, IT-197, IT-198, IT-199, IT-200, IT-201
  @Test func highPrecisionTimestamps() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: "values") { dataset in
      var field = Field("timestampHighPrecisionField", .timestamp)
      field.timestampPrecision = 12
      let table = try await Self.createTable(client, dataset, "picos", schema: Schema([field]))
      let fqn = "`\(dataset.projectID!).\(dataset.datasetID).picos`"

      let ts1 = "2025-01-01T12:34:56.123456789123Z"
      let ts2 = "1970-01-01T12:34:56.123456789123Z"
      let ts3 = "2000-01-01T12:34:56.123456789123Z"
      struct PicoRow: Codable, Equatable {
        var timestampHighPrecisionField: BigQueryTimestamp
      }
      let seed = try await client.insertAll(
        [ts1, ts2, ts3].map { PicoRow(timestampHighPrecisionField: BigQueryTimestamp($0)!) },
        into: table)
      try #require(!seed.hasErrors, "\(seed.rowErrors)")

      // IT-194: Querying a TIMESTAMP(12) column returns all 12 fractional digits.
      let allRows = try await Self.query(
        client, "SELECT timestampHighPrecisionField FROM \(fqn) ORDER BY 1")
      #expect(
        allRows.compactMap { $0["timestampHighPrecisionField"]?.stringValue } == [ts2, ts3, ts1])
      #expect(
        try allRows.map { try $0.decode(PicoRow.self).timestampHighPrecisionField }
          == [BigQueryTimestamp(ts2)!, BigQueryTimestamp(ts3)!, BigQueryTimestamp(ts1)!])

      // IT-195: Streaming insert of a valid 12-digit ISO-8601 string into a second table succeeds.
      let extraTable = try await Self.createTable(
        client, dataset, "picos_valid", schema: Schema([field]))
      let validInsert = try await client.insertAll(
        [InsertRow(["timestampHighPrecisionField": .string(ts1)])], into: extraTable)
      #expect(!validInsert.hasErrors)

      // IT-196: Numeric or numeric-string formats are rejected for TIMESTAMP(12) columns.
      for badValue: InsertValue in [
        .int64(123_456), .string("123456"), .int64(-123_456), .float64(1000.0),
      ] {
        let bad = try await client.insertAll(
          [InsertRow(["timestampHighPrecisionField": badValue])], into: extraTable)
        #expect(bad.hasErrors)
      }

      // IT-197: Named TIMESTAMP parameter with CAST(@timestampParam AS TIMESTAMP(12)).
      // BigQuery truncates TIMESTAMP query parameters to microseconds on the server, so
      // 2000-01-01 12:34:56.123456000000Z < ts3 and only ts2 matches.
      let namedCastSQL =
        "SELECT timestampHighPrecisionField FROM \(fqn)"
        + " WHERE timestampHighPrecisionField < CAST(@timestampParam AS TIMESTAMP(12))"
      let namedHigh = try await Self.query(
        client, namedCastSQL,
        parameters: .named([
          "timestampParam": .timestamp(
            BigQueryTimestamp("2000-01-01 12:34:56.123456789123Z")!)
        ]))
      #expect(namedHigh.compactMap { $0[0].stringValue } == [ts2])

      // IT-198: Positional TIMESTAMP parameter with CAST(? AS TIMESTAMP(12)).
      let posHigh = try await Self.query(
        client,
        "SELECT timestampHighPrecisionField FROM \(fqn)"
          + " WHERE timestampHighPrecisionField < CAST(? AS TIMESTAMP(12))",
        parameters: .positional([
          .timestamp(BigQueryTimestamp("2000-01-01 12:34:56.123456789123Z")!)
        ]))
      #expect(posHigh.compactMap { $0[0].stringValue } == [ts2])

      // IT-199: Named TIMESTAMP parameter constructed from microseconds (946_730_096_123_456).
      let namedMicros = try await Self.query(
        client, namedCastSQL,
        parameters: .named(["timestampParam": .timestamp(micros: 946_730_096_123_456)]))
      #expect(namedMicros.compactMap { $0[0].stringValue } == [ts2])

      // IT-200: Named TIMESTAMP parameter constructed from a microsecond string.
      let namedString = try await Self.query(
        client, namedCastSQL,
        parameters: .named([
          "timestampParam": try .timestamp("2000-01-01 12:34:56.123456Z")
        ]))
      #expect(namedString.compactMap { $0[0].stringValue } == [ts2])

      // IT-201: Comparing TIMESTAMP(12) directly against a TIMESTAMP parameter without CAST fails.
      await #expect {
        _ = try await Self.query(
          client,
          "SELECT timestampHighPrecisionField FROM \(fqn)"
            + " WHERE timestampHighPrecisionField < @timestampParam",
          parameters: .named([
            "timestampParam": .timestamp(
              BigQueryTimestamp("2000-01-01 12:34:56.123456789123Z")!)
          ]))
      } throws: { error in
        guard let bqError = error as? BigQueryError else { return false }
        return bqError.message.contains("Invalid argument type passed to a function")
      }
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
    #expect(row["c0"]?.stringValue == "s")
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
    #expect(row["c13"]?.geographyValue == "POINT(-122.35022 47.649154)")
    #expect(row["c14"]?.jsonValue == #"{"a":1}"#)
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

  private static func createTable(
    _ client: BigQueryClient, _ dataset: DatasetID, _ name: String, schema: Schema
  ) async throws -> TableID {
    let id = TableID(projectID: dataset.projectID, datasetID: dataset.datasetID, tableID: name)
    _ = try await client.createTable(Table(id: id, schema: schema))
    return id
  }

  private static func query(
    _ client: BigQueryClient, _ sql: String, parameters: QueryParameters? = nil
  ) async throws -> [Row] {
    try await client.query(sql, parameters: parameters).rows.collect()
  }
}
