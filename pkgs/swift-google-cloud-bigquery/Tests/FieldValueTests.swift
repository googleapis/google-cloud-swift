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

@Suite struct FieldValueTests {
  // Baseline: U.FieldValue.01
  @Test func scalarAccessorsConvertCellText() throws {
    #expect(try FieldValue.scalar("false").boolValue == false)
    #expect(try FieldValue.scalar("TRUE").boolValue == true)
    #expect(try FieldValue.scalar("1").int64Value == 1)
    #expect(try FieldValue.scalar("1.5").doubleValue == 1.5)
    #expect(
      FieldValue.scalar("POINT(-122.350220 47.649154)").geographyValue
        == "POINT(-122.350220 47.649154)")
    #expect(
      try FieldValue.scalar("123456789.123456789").numericValue
        == Decimal(string: "123456789.123456789"))
    #expect(FieldValue.scalar("string").stringValue == "string")
    #expect(
      try FieldValue.scalar(Data([0xD, 0xE, 0xA, 0xD]).base64EncodedString()).bytesValue
        == Data([0xD, 0xE, 0xA, 0xD]))
    #expect(FieldValue.scalar(#"{"a": 1}"#).jsonValue == #"{"a": 1}"#)
    #expect(try FieldValue.scalar("NaN").doubleValue?.isNaN == true)
    #expect(try FieldValue.scalar("-Infinity").doubleValue == -.infinity)
  }

  // Baseline: U.FieldValue.01
  @Test func integerTimestampTextIsMicroseconds() throws {
    // Java reads "42" as seconds; BigQuery's int64 timestamp output is microseconds.
    #expect(try FieldValue.scalar("42").timestampMicros == 42)
    #expect(try FieldValue.scalar("42").timestampValue == Date(timeIntervalSince1970: 0.000042))
  }

  // Baseline: U.FieldValue.01
  @Test func intervalAccessorParsesBothForms() throws {
    let expected = Interval(
      years: 3, months: 2, days: 1, hours: 12, minutes: 34, seconds: 56, nanoseconds: 789_000_000)
    #expect(try FieldValue.scalar("P3Y2M1DT12H34M56.789S").intervalValue == expected)
    #expect(try FieldValue.scalar("3-2 1 12:34:56.789").intervalValue == expected)
    #expect(FieldValue.scalar("3-2 1 12:34:56.789").stringValue == "3-2 1 12:34:56.789")
  }

  // Baseline: U.FieldValue.01
  @Test func nullReadsAsNilFromEveryAccessor() throws {
    let value = FieldValue.null
    #expect(value.isNull)
    #expect(value.stringValue == nil)
    #expect(try value.int64Value == nil)
    #expect(try value.doubleValue == nil)
    #expect(try value.boolValue == nil)
    #expect(try value.bytesValue == nil)
    #expect(try value.numericValue == nil)
    #expect(try value.bigNumericValue == nil)
    #expect(try value.timestampValue == nil)
    #expect(try value.dateValue == nil)
    #expect(try value.timeValue == nil)
    #expect(try value.dateTimeValue == nil)
    #expect(try value.intervalValue == nil)
    #expect(try value.rangeValue == nil)
    #expect(value.arrayValue == nil)
    #expect(value.recordValue == nil)
  }

  // Baseline: U.FieldValue.01
  @Test func repeatedAndRecordAccessorsReturnNestedValues() throws {
    let repeated = FieldValue.array([.scalar("1"), .scalar("1")])
    #expect(repeated.arrayValue == [.scalar("1"), .scalar("1")])
    let row = Row(
      schema: [Field("f", .float64), Field("t", .timestamp)],
      values: [.scalar("1.5"), .scalar("42")])
    #expect(FieldValue.record(row).recordValue == row)
  }

  // Baseline: U.FieldValue.01, U.Range.01
  @Test func rangeAccessorParsesBounds() throws {
    let range = try #require(try FieldValue.scalar("[2020-01-01, UNBOUNDED)").rangeValue)
    #expect(range.start == "2020-01-01")
    #expect(range.end == nil)
  }

  // Baseline: U.FieldValue.02
  @Test func floatSecondsTimestampConvertsToMicros() throws {
    #expect(
      try FieldValue.scalar("-1.9954383398377106E10").timestampMicros == -19_954_383_398_377_106)
    #expect(try FieldValue.scalar("1408452095.22").timestampMicros == 1_408_452_095_220_000)
  }

  // Baseline: U.FieldValue.03
  @Test func int64TimestampIsLossless() throws {
    let lossy = try FieldValue.scalar("1.9954383398377106E10").timestampMicros
    let lossless = try FieldValue.scalar("19954383398377106").timestampMicros
    #expect(lossy == lossless)
    #expect(lossless == 19_954_383_398_377_106)
    #expect(try FieldValue.scalar("253402300799999999").timestampMicros == 253_402_300_799_999_999)
  }

  // Design: §4.5
  @Test func iso8601AndPicosecondTimestampsParseLosslessly() throws {
    let picos = FieldValue.scalar("2025-01-01T12:34:56.123456789123Z")
    #expect(
      try picos.preciseTimestampValue
        == BigQueryTimestamp(seconds: 1_735_734_896, picoseconds: 123_456_789_123))
    #expect(try picos.timestampMicros == 1_735_734_896_123_456)
    #expect(
      try FieldValue.scalar("9999-12-31T23:59:59.999999Z").timestampMicros
        == 253_402_300_799_999_999)
    #expect(
      try FieldValue.scalar("0001-01-01T00:00:00.000000Z").timestampMicros
        == -62_135_596_800_000_000)
    #expect(
      try FieldValue.scalar("1969-12-31T23:59:59.999999999999Z").timestampMicros == -1)
    #expect(
      try FieldValue.scalar("1969-12-31T23:59:59.000000000001Z").timestampMicros == -1_000_000)
    #expect(try FieldValue.null.preciseTimestampValue == nil)
  }

  // Design: §4.5
  @Test func civilAccessorsParseCanonicalText() throws {
    #expect(
      try FieldValue.scalar("2024-02-29").dateValue == BigQueryDate(year: 2024, month: 2, day: 29))
    #expect(
      try FieldValue.scalar("05:41:35.220000").timeValue
        == BigQueryTime(hour: 5, minute: 41, second: 35, nanosecond: 220_000_000))
    #expect(
      try FieldValue.scalar("2014-08-19T05:41:35.220000").dateTimeValue
        == BigQueryDateTime(
          date: BigQueryDate(year: 2014, month: 8, day: 19),
          time: BigQueryTime(hour: 5, minute: 41, second: 35, nanosecond: 220_000_000)))
    #expect(
      try FieldValue.scalar(
        "578960446186580977117854925043439539266.34992332820282019728792003956564819967"
      )
      .bigNumericValue?.description
        == "578960446186580977117854925043439539266.34992332820282019728792003956564819967")
  }

  // Design: §4.5
  @Test func invalidTextThrowsDataCorrupted() {
    #expect(throws: DecodingError.self) { try FieldValue.scalar("abc").int64Value }
    #expect(throws: DecodingError.self) { try FieldValue.scalar("abc").doubleValue }
    #expect(throws: DecodingError.self) { try FieldValue.scalar("yes").boolValue }
    #expect(throws: DecodingError.self) { try FieldValue.scalar("not base64!").bytesValue }
    #expect(throws: DecodingError.self) { try FieldValue.scalar("1.2.3").numericValue }
    #expect(throws: DecodingError.self) { try FieldValue.scalar("2024-13-01").dateValue }
    #expect(throws: DecodingError.self) { try FieldValue.scalar("later").timestampMicros }
  }

  // Baseline: U.FieldValueList.03
  @Test func wrongShapeThrowsTypeMismatchFromParsingAccessors() {
    let row = Row(schema: [Field("a", .string)], values: [.scalar("x")])
    #expect(throws: DecodingError.self) { try FieldValue.array([]).int64Value }
    #expect(throws: DecodingError.self) { try FieldValue.record(row).timestampMicros }
  }

  // Design: §4.5
  @Test func wrongShapeIsNilFromShapeAccessors() {
    let row = Row(schema: [Field("a", .string)], values: [.scalar("x")])
    #expect(FieldValue.array([]).stringValue == nil)
    #expect(FieldValue.record(row).jsonValue == nil)
    #expect(FieldValue.array([.null]).geographyValue == nil)
    #expect(FieldValue.scalar("1").arrayValue == nil)
    #expect(FieldValue.record(row).arrayValue == nil)
    #expect(FieldValue.scalar("1").recordValue == nil)
    #expect(FieldValue.array([]).recordValue == nil)
  }
}

@Suite struct IntervalTests {
  // Baseline: U.FieldValue.04
  @Test(
    arguments: [
      (
        "125-7 -19 -0:24:12.001",
        Interval(
          years: 125, months: 7, days: -19, minutes: -24, seconds: -12, nanoseconds: -1_000_000)
      ),
      (
        "-15-6 23 23:14:05",
        Interval(years: -15, months: -6, days: 23, hours: 23, minutes: 14, seconds: 5)
      ),
      (
        "06-01 06 01:01:00.123456",
        Interval(years: 6, months: 1, days: 6, hours: 1, minutes: 1, nanoseconds: 123_456_000)
      ),
      ("-0-0 -0 -0:0:0", Interval(months: 0, days: 0, time: .zero)),
      (
        "-99999-99999 9999 999:999:999.999999999",
        Interval(
          years: -99999, months: -99999, days: 9999, hours: 999, minutes: 999, seconds: 999,
          nanoseconds: 999_999_999)
      ),
    ])
  func parsesCanonicalForm(text: String, expected: Interval) {
    #expect(Interval(text) == expected)
  }

  // Baseline: U.QueryParameterValue.05
  @Test func parsesISO8601Form() {
    #expect(
      Interval("P123Y7M-19DT0H24M12.000006S")
        == Interval(years: 123, months: 7, days: -19, minutes: 24, seconds: 12, nanoseconds: 6000))
    #expect(Interval("P1Y2M25DT8H") == Interval(years: 1, months: 2, days: 25, hours: 8))
    #expect(Interval("-P1D") == Interval(days: -1))
    #expect(Interval("P2W") == Interval(days: 14))
  }

  // Design: §4.5
  @Test func descriptionIsNormalizedCanonicalForm() {
    #expect(Interval(years: 1, months: 2, days: -3, hours: 4).description == "1-2 -3 4:0:0")
    #expect(Interval(months: 14, days: 0, time: .zero).description == "1-2 0 0:0:0")
    #expect(
      Interval(months: -1, days: 0, time: .seconds(-1.5)).description == "-0-1 0 -0:0:1.500000")
  }

  // Design: §4.5
  @Test func rejectsMalformedText() {
    #expect(Interval("") == nil)
    #expect(Interval("1-2") == nil)
    #expect(Interval("P") == nil)
    #expect(Interval("1-2 3 4:5") == nil)
  }

  // Design: §4.5
  @Test func codableUsesCanonicalString() throws {
    let interval = Interval(years: 1, days: 2, seconds: 3)
    let data = try JSONEncoder().encode([interval])
    #expect(String(decoding: data, as: UTF8.self) == #"["1-0 2 0:0:3"]"#)
    #expect(try JSONDecoder().decode([Interval].self, from: data) == [interval])
  }
}

@Suite struct BigNumericTests {
  // Baseline: U.QueryParameterValue.03
  @Test func keepsDecimalTextVerbatim() throws {
    for text in [
      "0.33333333333333333333333333333333333333",
      "0.50000000000000000000000000000000000000",
      "0.33333333333333333333333333333333333333888888888888888",
      "578960446186580977117854925043439539266.34992332820282019728792003956564819967",
      "-578960446186580977117854925043439539266.34992332820282019728792003956564819968",
      "1e-38",
    ] {
      #expect(try #require(BigNumeric(text)).description == text)
    }
  }

  // Design: §4.5
  @Test func equalityComparesNumericValue() throws {
    #expect(BigNumeric("1.50") == BigNumeric("1.5"))
    #expect(BigNumeric("1e2") == BigNumeric("100"))
    #expect(BigNumeric("-0") == BigNumeric("0"))
    #expect(BigNumeric("1.5") != BigNumeric("1.4"))
    #expect(Set([BigNumeric("1.0"), BigNumeric("1")]).count == 1)
  }

  // Design: §4.5
  @Test func rejectsNonNumbers() {
    #expect(BigNumeric("") == nil)
    #expect(BigNumeric("abc") == nil)
    #expect(BigNumeric("1.2.3") == nil)
    #expect(BigNumeric("NaN") == nil)
  }

  // Design: §4.5
  @Test func convertsFromAndToSwiftNumbers() {
    #expect(BigNumeric(42).description == "42")
    #expect(BigNumeric(Decimal(string: "3.14")!).description == "3.14")
    #expect(BigNumeric("3.14")?.decimalValue == Decimal(string: "3.14"))
  }
}

@Suite struct CivilTypesTests {
  // Baseline: U.QueryParameterValue.09
  @Test func dateParsesAndPrints() throws {
    let date = try #require(BigQueryDate("2016-09-18"))
    #expect(date == BigQueryDate(year: 2016, month: 9, day: 18))
    #expect(date.description == "2016-09-18")
    #expect(BigQueryDate("2016-9-8")?.description == "2016-09-08")
    #expect(BigQueryDate("2014-08-19 12:41:35.220000") == nil)
    #expect(BigQueryDate("2023-02-29") == nil)
  }

  // Baseline: U.QueryParameterValue.09
  @Test func dateFromFoundationDateUsesTimeZone() throws {
    let instant = Date(timeIntervalSince1970: 1_474_156_800 + 3600)  // 2016-09-18T01:00:00Z
    #expect(BigQueryDate(instant) == BigQueryDate(year: 2016, month: 9, day: 18))
    let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
    #expect(BigQueryDate(instant, in: pacific) == BigQueryDate(year: 2016, month: 9, day: 17))
  }

  // Baseline: U.QueryParameterValue.09
  @Test func timeParsesAndPrints() throws {
    let time = try #require(BigQueryTime("05:41:35.220000"))
    #expect(time == BigQueryTime(hour: 5, minute: 41, second: 35, nanosecond: 220_000_000))
    #expect(time.description == "05:41:35.220000")
    #expect(BigQueryTime(hour: 5, minute: 6, second: 7).description == "05:06:07")
    #expect(
      BigQueryTime(hour: 5, minute: 6, second: 7, nanosecond: 1).description == "05:06:07.000000001"
    )
    #expect(BigQueryTime("2014-08-19 12:41:35.220000") == nil)
    #expect(BigQueryTime("24:00:00") == nil)
  }

  // Baseline: U.QueryParameterValue.09
  @Test func dateTimeParsesAndPrints() throws {
    let dateTime = try #require(BigQueryDateTime("2014-08-19 05:41:35.220000"))
    #expect(dateTime.description == "2014-08-19 05:41:35.220000")
    #expect(BigQueryDateTime("2014-08-19T05:41:35.220000") == dateTime)
    #expect(BigQueryDateTime("2014-08-19") == nil)
  }

  // Design: §4.5
  @Test func codableUsesCanonicalStrings() throws {
    struct Values: Codable, Equatable {
      var date: BigQueryDate
      var time: BigQueryTime
      var dateTime: BigQueryDateTime
    }
    let values = Values(
      date: BigQueryDate(year: 2024, month: 1, day: 2),
      time: BigQueryTime(hour: 3, minute: 4, second: 5),
      dateTime: BigQueryDateTime(
        date: BigQueryDate(year: 2024, month: 1, day: 2),
        time: BigQueryTime(hour: 3, minute: 4, second: 5)))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(values)
    #expect(
      String(decoding: data, as: UTF8.self)
        == #"{"date":"2024-01-02","dateTime":"2024-01-02 03:04:05","time":"03:04:05"}"#)
    #expect(try JSONDecoder().decode(Values.self, from: data) == values)
  }

  // Design: §4.5
  @Test func timestampParsesPrintsAndNormalizesPicoseconds() throws {
    let picos = try #require(BigQueryTimestamp("2025-01-01T12:34:56.123456789123Z"))
    #expect(picos.seconds == 1_735_734_896)
    #expect(picos.picoseconds == 123_456_789_123)
    #expect(picos.micros == 1_735_734_896_123_456)
    #expect(picos.description == "2025-01-01T12:34:56.123456789123Z")

    let microsOnly = try #require(BigQueryTimestamp("2024-01-02 05:04:05.123456+02:00"))
    #expect(microsOnly.description == "2024-01-02T03:04:05.123456Z")
    #expect(BigQueryTimestamp("1774-09-24T00:00:00")?.description == "1774-09-24T00:00:00.000000Z")
    #expect(BigQueryTimestamp("2025-01-01T12:34:56.1234567891234Z") == nil)

    // Negative epochs and out-of-range picoseconds normalize into 0..<10^12.
    let beforeEpoch = BigQueryTimestamp(seconds: 0, picoseconds: -1)
    #expect(beforeEpoch.seconds == -1)
    #expect(beforeEpoch.picoseconds == 999_999_999_999)
    #expect(beforeEpoch.micros == -1)
    #expect(beforeEpoch.description == "1969-12-31T23:59:59.999999999999Z")
    #expect(beforeEpoch == BigQueryTimestamp("1969-12-31T23:59:59.999999999999Z"))
    #expect(
      Set([
        beforeEpoch,
        BigQueryTimestamp(seconds: -2, picoseconds: 1_999_999_999_999),
        BigQueryTimestamp("1969-12-31T23:59:59.999999999999Z")!,
      ]).count == 1)

    let earlier = BigQueryTimestamp(seconds: -1, picoseconds: 1)
    let epoch = BigQueryTimestamp(seconds: 0, picoseconds: 0)
    #expect(earlier < beforeEpoch)
    #expect(beforeEpoch < epoch)
    #expect(earlier.micros == -1_000_000)

    let encoded = try JSONEncoder().encode([picos, microsOnly])
    #expect(
      String(decoding: encoded, as: UTF8.self)
        == #"["2025-01-01T12:34:56.123456789123Z","2024-01-02T03:04:05.123456Z"]"#)
    #expect(
      try JSONDecoder().decode([BigQueryTimestamp].self, from: encoded) == [picos, microsOnly])
  }
}

@Suite struct BigQueryRangeTests {
  // Baseline: U.Range.01
  @Test func parsesBoundsIncludingUnboundedAndNull() throws {
    let both = try #require(BigQueryRange("[2020-01-01, 2020-12-31)"))
    #expect(both.start == "2020-01-01")
    #expect(both.end == "2020-12-31")
    let unbounded = try #require(BigQueryRange("[UNBOUNDED, unbounded)"))
    #expect(unbounded.start == nil)
    #expect(unbounded.end == nil)
    let null = try #require(BigQueryRange("[NULL, 2020-12-31)"))
    #expect(null.start == nil)
    #expect(null.end == "2020-12-31")
    let timestamps = try #require(
      BigQueryRange("[2014-08-19 12:41:35.220000+00:00, 2015-09-20 13:41:35.220000+01:00)"))
    #expect(timestamps.start == "2014-08-19 12:41:35.220000+00:00")
    #expect(timestamps.end == "2015-09-20 13:41:35.220000+01:00")
    #expect(BigQueryRange("2020-01-01, 2020-12-31") == nil)
    #expect(BigQueryRange("[2020-01-01)") == nil)
  }

  // Baseline: U.Range.02
  @Test func boundValuesAreFieldValues() {
    let range = BigQueryRange(start: "1970-01-02", end: nil, elementType: .date)
    #expect(range.startValue == .scalar("1970-01-02"))
    #expect(range.endValue == .null)
    #expect(range.description == "[1970-01-02, UNBOUNDED)")
  }

  // Baseline: U.Range.01
  @Test func typedFactoriesSetElementType() {
    let dates = BigQueryRange.date(from: BigQueryDate(year: 1970, month: 1, day: 2), to: nil)
    #expect(dates == BigQueryRange(start: "1970-01-02", end: nil, elementType: .date))
    let timestamps = BigQueryRange.timestamp(
      from: nil, to: Date(timeIntervalSince1970: 1_408_452_095.22))
    #expect(timestamps.elementType == .timestamp)
    #expect(timestamps.start == nil)
    #expect(timestamps.end == "2014-08-19 12:41:35.220000+00:00")
    let precise = BigQueryRange.timestamp(
      from: BigQueryTimestamp("2025-01-01T12:34:56.123456789123Z"), to: nil)
    #expect(precise.start == "2025-01-01 12:34:56.123456789123+00:00")
  }
}
