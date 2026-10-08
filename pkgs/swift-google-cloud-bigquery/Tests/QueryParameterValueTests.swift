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

// The generated module declares types with the same names.
private typealias QueryParameterValue = GoogleCloudBigQuery.QueryParameterValue
private typealias QueryParameterType = GoogleCloudBigQuery.QueryParameterType

@Suite struct QueryParameterValueTests {
  private func expectScalar(
    _ value: QueryParameterValue, _ type: QueryParameterType, _ text: String?,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(value.parameterType == type, sourceLocation: sourceLocation)
    #expect(value.scalarValue == text, sourceLocation: sourceLocation)
    #expect(value.arrayValues == nil, sourceLocation: sourceLocation)
    #expect(value.structValues == nil, sourceLocation: sourceLocation)
    #expect(value.rangeValue == nil, sourceLocation: sourceLocation)
  }

  // Baseline: U.QueryParameterValue.02
  @Test func scalarFactoriesSetTypeAndText() {
    self.expectScalar(.bool(true), .bool, "true")
    self.expectScalar(.int64(Int64.max), .int64, "9223372036854775807")
    self.expectScalar(Int32.max.queryParameterValue, .int64, "2147483647")
    self.expectScalar(.float64(1.2), .float64, "1.2")
    self.expectScalar(Float(1.2).queryParameterValue, .float64, "1.2")
    self.expectScalar(.float64(Double.nan), .float64, "NaN")
    self.expectScalar(.float64(-Double.infinity), .float64, "-Infinity")
    self.expectScalar(.numeric(Decimal(string: "3.14")!), .numeric, "3.14")
    self.expectScalar(.string("foo"), .string, "foo")
    self.expectScalar(
      .geography("POINT(-122.350220 47.649154)"), .geography, "POINT(-122.350220 47.649154)")
    self.expectScalar(.bytes(Data([1, 3])), .bytes, "AQM=")
  }

  // Baseline: U.QueryParameterValue.03
  @Test func bigNumericSendsTextVerbatim() throws {
    // Java formats through BigDecimal.toString ("5.00…E-9"); Swift keeps the caller's text.
    for text in [
      "0.33333333333333333333333333333333333333",
      "0.00000000500000000000000000000000000000",
      "-578960446186580977117854925043439539266.34992332820282019728792003956564819968",
      "1e-38",
    ] {
      self.expectScalar(.bigNumeric(try #require(BigNumeric(text))), .bigNumeric, text)
    }
  }

  // Baseline: U.QueryParameterValue.04
  @Test func jsonSendsText() {
    let text = #"{"class" : {"students" : [{"name" : "Jane"}]}}"#
    self.expectScalar(.json(text), .json, text)
  }

  // Baseline: U.QueryParameterValue.05
  @Test func intervalFromTextOrValue() throws {
    self.expectScalar(
      try .interval("123-7 -19 0:24:12.000006"), .interval, "123-7 -19 0:24:12.000006")
    self.expectScalar(
      try .interval("P123Y7M-19DT0H24M12.000006S"), .interval, "P123Y7M-19DT0H24M12.000006S")
    self.expectScalar(
      .interval(Interval(years: 1, months: 2, days: 25, hours: 8)), .interval, "1-2 25 8:0:0")
    #expect(throws: BigQueryError.self) { try QueryParameterValue.interval("soon") }
  }

  // Baseline: U.QueryParameterValue.06
  @Test func arraysOfSwiftValuesInferTheElementType() {
    func expectArray(
      _ value: QueryParameterValue, _ element: QueryParameterType, _ texts: [String?],
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      #expect(value.parameterType == .array(element), sourceLocation: sourceLocation)
      #expect(value.scalarValue == nil, sourceLocation: sourceLocation)
      #expect(value.arrayValues?.map(\.scalarValue) == texts, sourceLocation: sourceLocation)
      #expect(
        value.arrayValues?.allSatisfy { $0.parameterType == element } == true,
        sourceLocation: sourceLocation)
    }
    expectArray(.array([true, false]), .bool, ["true", "false"])
    expectArray(.array([2, 5] as [Int64]), .int64, ["2", "5"])
    expectArray(.array([2, 5] as [Int]), .int64, ["2", "5"])
    expectArray(.array([2.6, 5.4] as [Double]), .float64, ["2.6", "5.4"])
    expectArray(.array([2.6, 5.4] as [Float]), .float64, ["2.6", "5.4"])
    expectArray(
      .array([Decimal(string: "3.14")!, Decimal(string: "1.59")!]), .numeric, ["3.14", "1.59"])
    expectArray(.array(["Ana", "Marv"]), .string, ["Ana", "Marv"])
    expectArray(.array([] as [Int64]), .int64, [])
  }

  // Baseline: U.QueryParameterValue.06
  @Test func emptyArrayFromServerKeepsElementType() throws {
    // The service omits the value of an empty array.
    let parameters = try QueryParameters(
      wire: [
        try WireJSON.decode(
          #"{"name": "a", "parameterType": {"type": "ARRAY", "arrayType": {"type": "INT64"}}}"#)
      ],
      mode: "NAMED")
    guard case .named(let named) = parameters, let value = named["a"] else {
      Issue.record("expected a named parameter")
      return
    }
    #expect(value.parameterType == .array(.int64))
    #expect(value.arrayValues == [])
  }

  // Baseline: U.QueryParameterValue.07
  @Test func timestampFromMicrosAndDateUsesCanonicalFormat() throws {
    self.expectScalar(
      .timestamp(micros: 1_408_452_095_220_000), .timestamp, "2014-08-19 12:41:35.220000+00:00")
    self.expectScalar(
      .timestamp(micros: 1_571_068_536_842_123), .timestamp, "2019-10-14 15:55:36.842123+00:00")
    self.expectScalar(
      .timestamp(Date(timeIntervalSince1970: 1_408_452_095.22)), .timestamp,
      "2014-08-19 12:41:35.220000+00:00")
    self.expectScalar(.timestamp(micros: -1), .timestamp, "1969-12-31 23:59:59.999999+00:00")
    let picos = try #require(BigQueryTimestamp("2025-12-08T12:34:56.123456789123Z"))
    self.expectScalar(.timestamp(picos), .timestamp, "2025-12-08 12:34:56.123456789123+00:00")
    self.expectScalar(
      picos.queryParameterValue, .timestamp, "2025-12-08 12:34:56.123456789123+00:00")
  }

  // Baseline: U.QueryParameterValue.07
  @Test(
    arguments: [
      "2014-08-19 12:41:35.220000+00:00",
      "2025-08-19 12:34:56.123456789+00:00",
      "2025-12-08 12:34:56.1234567890+00:00",
      "2025-12-08 12:34:56.123456789123+00:00",
      "2019-02-14 12:34:45.938993Z",
      "2019-02-14 12:34:45.938993+0000",
      "2019-02-14 12:34:45.102+00:00",
    ])
  func timestampFromValidTextIsSentUnchanged(text: String) throws {
    self.expectScalar(try .timestamp(text), .timestamp, text)
  }

  // Baseline: U.QueryParameterValue.08
  @Test(
    arguments: [
      "abc",
      "2014-08-19",
      "2014-08-19 12",
      "2014-08-19T12",
      "2014-08-19T12:34:00.123456",
      "2014-08-19 12:34:00.123456789abc+00:00",
      "2014-08-19 12:34:00.123456abc789+00:00",
      "2025-12-08 12:34:56.1234567891234+00:00",
      "2025-12-08 12:34:56.123456789123456789123456789+00:00",
    ])
  func timestampFromInvalidTextThrows(text: String) {
    #expect(throws: BigQueryError.self) { try QueryParameterValue.timestamp(text) }
  }

  // Baseline: U.QueryParameterValue.09
  @Test func civilFactoriesValidateText() throws {
    self.expectScalar(try .date("2014-08-19"), .date, "2014-08-19")
    self.expectScalar(
      .date(BigQueryDate(Date(timeIntervalSince1970: 1_474_156_800))), .date, "2016-09-18")
    self.expectScalar(try .time("05:41:35.220000"), .time, "05:41:35.220000")
    self.expectScalar(
      try .dateTime("2014-08-19 05:41:35.220000"), .dateTime, "2014-08-19 05:41:35.220000")
    self.expectScalar(
      .dateTime(
        BigQueryDateTime(
          date: BigQueryDate(year: 2014, month: 8, day: 19),
          time: BigQueryTime(hour: 5, minute: 41, second: 35))),
      .dateTime, "2014-08-19 05:41:35")
    #expect(throws: BigQueryError.self) {
      try QueryParameterValue.date("2014-08-19 12:41:35.220000")
    }
    #expect(throws: BigQueryError.self) {
      try QueryParameterValue.time("2014-08-19 12:41:35.220000")
    }
    #expect(throws: BigQueryError.self) { try QueryParameterValue.dateTime("2014-08-19") }
  }

  // Baseline: U.QueryParameterValue.10
  @Test func timestampArrays() throws {
    let fromMicros = QueryParameterValue.array(
      [.timestamp(micros: 1_408_452_095_220_000), .timestamp(micros: 1_481_041_545_110_000)],
      of: .timestamp)
    #expect(fromMicros.parameterType == .array(.timestamp))
    #expect(
      fromMicros.arrayValues?.map(\.scalarValue)
        == ["2014-08-19 12:41:35.220000+00:00", "2016-12-06 16:25:45.110000+00:00"])
    let texts = [
      "2019-02-14 12:34:45.938993Z", "2019-02-14 12:34:45.938993+0000",
      "2019-02-14 12:34:45.102+00:00",
    ]
    let fromText = QueryParameterValue.array(
      try texts.map { try QueryParameterValue.timestamp($0) }, of: .timestamp)
    #expect(fromText.arrayValues?.map(\.scalarValue) == texts.map { Optional($0) })
    let fromDates = QueryParameterValue.array([Date(timeIntervalSince1970: 0)])
    #expect(fromDates.arrayValues?.map(\.scalarValue) == ["1970-01-01 00:00:00.000000+00:00"])
  }

  // Baseline: U.QueryParameterValue.11
  @Test func structKeepsFieldOrderAndRoundTrips() throws {
    let record = QueryParameterValue.struct([
      "booleanField": .bool(true), "integerField": .int64(15),
      "stringField": .string("test-string"),
    ])
    #expect(
      record.parameterType
        == .struct([
          .init("booleanField", .bool), .init("integerField", .int64),
          .init("stringField", .string),
        ]))
    #expect(
      record.parameterType.description
        == "STRUCT<booleanField BOOL, integerField INT64, stringField STRING>")
    #expect(record.scalarValue == nil)
    #expect(
      record.structValues?.map { $0.name } == ["booleanField", "integerField", "stringField"])
    #expect(
      record.structValues?.map { $0.value } == [.bool(true), .int64(15), .string("test-string")])
    #expect(try self.roundTrip(record) == record)

    let wire = try WireJSON.object(record.value)
    #expect(
      wire
        == (try WireJSON.object(
          #"{"structValues": {"booleanField": {"value": "true"}, "integerField": {"value": "15"}, "stringField": {"value": "test-string"}}}"#
        )))
  }

  // Baseline: U.QueryParameterValue.11
  @Test func nestedStructRoundTrips() throws {
    let inner = QueryParameterValue.struct(["bool": .bool(true), "int": .int64(15)])
    let outer = QueryParameterValue.struct(["string": .string("s"), "struct": inner])
    #expect(
      outer.parameterType.description
        == "STRUCT<string STRING, struct STRUCT<bool BOOL, int INT64>>")
    #expect(outer.structValues?.last?.value == inner)
    #expect(try self.roundTrip(outer) == outer)
  }

  // Baseline: U.QueryParameterValue.11
  @Test func arrayOfStructsRoundTrips() throws {
    let elementType = QueryParameterType.struct([
      .init("b", .bool), .init("i", .int64), .init("s", .string),
    ])
    let values = QueryParameterValue.array(
      [
        .struct(["b": .bool(true), "i": .int64(15), "s": .string("test-string")]),
        .struct(["b": .bool(false), "i": .int64(20), "s": .string("test-string2")]),
      ], of: elementType)
    #expect(values.parameterType == .array(elementType))
    #expect(values.parameterType.description == "ARRAY<STRUCT<b BOOL, i INT64, s STRING>>")
    let decoded = try self.roundTrip(values)
    #expect(decoded.arrayValues?.count == 2)
    let second = try #require(decoded.arrayValues?[1].structValues).map { $0.value }
    #expect(second == [.bool(false), .int64(20), .string("test-string2")])
  }

  // Baseline: U.QueryParameterValue.12
  @Test(
    arguments: [
      (FieldType.date, "1970-01-02", "1971-02-03"),
      (.dateTime, "2014-08-19 05:41:35.220000", "2015-09-20 06:41:35.220000"),
      (.timestamp, "2014-08-19 12:41:35.220000+00:00", "2015-09-20 13:41:35.220000+01:00"),
    ])
  func rangeRoundTripsWithEveryBoundCombination(type: FieldType, start: String, end: String) throws
  {
    for (lower, upper) in [(nil, nil), (nil, end), (start, nil), (start, end)]
      as [(String?, String?)]
    {
      let value = QueryParameterValue.range(
        BigQueryRange(start: lower, end: upper, elementType: type))
      let decoded = try self.roundTrip(value)
      #expect(decoded.parameterType == .range(type))
      #expect(decoded.rangeValue == BigQueryRange(start: lower, end: upper, elementType: type))
      #expect(decoded.scalarValue == nil)
      #expect(decoded.arrayValues == nil)
      #expect(decoded.structValues == nil)
    }
  }

  // Design: §4.5
  @Test func nullParametersAreTyped() {
    let null = QueryParameterValue.null(.string)
    #expect(null.parameterType == .string)
    #expect(null.scalarValue == nil)
    let missing: Int64? = nil
    #expect(missing.queryParameterValue == .null(.int64))
    #expect(
      QueryParameterValue.array([1, nil] as [Int64?]).arrayValues == [.int64(1), .null(.int64)])
  }

  // Design: §4.5
  @Test func namedParametersSerializeSortedByName() throws {
    let parameters = QueryParameters.named(["b": .int64(1), "a": .string("x")])
    #expect(parameters.wireMode == "NAMED")
    #expect(parameters.wire.map(\.name) == ["a", "b"])
    #expect(try QueryParameters(wire: parameters.wire, mode: "NAMED") == parameters)
    let positional = QueryParameters.positional([.int64(1), .array(["x"])])
    #expect(positional.wireMode == "POSITIONAL")
    #expect(try QueryParameters(wire: positional.wire, mode: "POSITIONAL") == positional)
  }

  // Design: §4.5
  @Test func parametersWithoutTypeOrNameAreRejected() throws {
    let untyped: GoogleCloudBigQueryV2.QueryParameter = try WireJSON.decode(#"{"name": "a"}"#)
    #expect(throws: DecodingError.self) { try QueryParameters(wire: [untyped], mode: nil) }
    let unnamed: GoogleCloudBigQueryV2.QueryParameter = try WireJSON.decode(
      #"{"parameterType": {"type": "INT64"}, "parameterValue": {"value": "1"}}"#)
    #expect(throws: DecodingError.self) { try QueryParameters(wire: [unnamed], mode: "NAMED") }
    #expect(try QueryParameters(wire: [unnamed], mode: "POSITIONAL") == .positional([.int64(1)]))
  }

  /// Sends `value` through its wire form and back, as a query job configuration does.
  private func roundTrip(_ value: QueryParameterValue) throws -> QueryParameterValue {
    let wire = QueryParameters.positional([value]).wire
    let json = try JSONSerialization.data(withJSONObject: try WireJSON.object(wire[0]))
    let decoded: GoogleCloudBigQueryV2.QueryParameter = try WireJSON.decode(
      String(decoding: json, as: UTF8.self))
    guard case .positional(let values) = try QueryParameters(wire: [decoded], mode: "POSITIONAL")
    else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not positional"))
    }
    return values[0]
  }
}
