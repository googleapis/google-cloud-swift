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

@Suite struct RowDecoderTests {
  private static var rangeField: Field {
    var field = Field("periods", .range, mode: .repeated)
    field.rangeElementType = .date
    return field
  }

  private let schema: Schema = [
    Field("name", .string),
    Field("age", .int64),
    Field("score", .float64),
    Field("active", .bool),
    Field("joined", .timestamp),
    Field("photo", .bytes),
    Field("price", .numeric),
    Field("big", .bigNumeric),
    Field("birthday", .date),
    Field("alarm", .time),
    Field("meeting", .dateTime),
    Field("wait", .interval),
    Field("tags", .string, mode: .repeated),
    Field("address", .struct, fields: [Field("city", .string), Field("zip", .string)]),
    Field(
      "visits", .struct, mode: .repeated,
      fields: [Field("Day", .date), Field("count", .int64)]),
    Self.rangeField,
    Field("nickname", .string),
  ]

  private func row(_ json: String) throws -> Row {
    try Row(wire: try WireJSON.decode(json, as: WKTStruct.self), schema: self.schema)
  }

  private var sample: Row {
    get throws {
      try self.row(
        #"""
        {"f": [{"v": "Ada"}, {"v": "36"}, {"v": "9.5"}, {"v": "true"}, {"v": "1408452095220000"},
               {"v": "AQM="}, {"v": "3.14"}, {"v": "1e-38"}, {"v": "1815-12-10"},
               {"v": "05:41:35"}, {"v": "2014-08-19T05:41:35.220000"}, {"v": "1-2 3 4:5:6"},
               {"v": [{"v": "a"}, {"v": "b"}]},
               {"v": {"f": [{"v": "London"}, {"v": null}]}},
               {"v": [{"v": {"f": [{"v": "2024-01-01"}, {"v": "3"}]}},
                      {"v": {"f": [{"v": "2024-01-02"}, {"v": "4"}]}}]},
               {"v": [{"v": "[2024-01-01, 2024-02-01)"}, {"v": "[2024-03-01, UNBOUNDED)"}]},
               {"v": null}]}
        """#)
    }
  }

  struct Address: Decodable, Equatable {
    var city: String
    var zip: String?
  }

  struct Visit: Decodable, Equatable {
    var day: BigQueryDate
    var count: Int
  }

  struct Person: Decodable {
    var name: String
    var age: Int64
    var score: Double
    var active: Bool
    var joined: Date
    var photo: Data
    var price: Decimal
    var big: BigNumeric
    var birthday: BigQueryDate
    var alarm: BigQueryTime
    var meeting: BigQueryDateTime
    var wait: Interval
    var tags: [String]
    var address: Address
    var visits: [Visit]
    var periods: [BigQueryRange]
    var nickname: String?
    var missing: String?
  }

  // Baseline: U.FieldValueList.01, U.FieldValueList.02
  @Test func decodesEveryColumnType() throws {
    let person = try self.sample.decode(Person.self)
    #expect(person.name == "Ada")
    #expect(person.age == 36)
    #expect(person.score == 9.5)
    #expect(person.active)
    #expect(person.joined == Date(timeIntervalSince1970: 1_408_452_095.22))
    #expect(person.photo == Data([1, 3]))
    #expect(person.price == Decimal(string: "3.14"))
    #expect(person.big == BigNumeric("1e-38"))
    #expect(person.birthday == BigQueryDate(year: 1815, month: 12, day: 10))
    #expect(person.alarm == BigQueryTime(hour: 5, minute: 41, second: 35))
    #expect(person.meeting.description == "2014-08-19 05:41:35.220000")
    #expect(person.wait == Interval(years: 1, months: 2, days: 3, hours: 4, minutes: 5, seconds: 6))
    #expect(person.tags == ["a", "b"])
    #expect(person.address == Address(city: "London", zip: nil))
    #expect(person.nickname == nil)
    #expect(person.missing == nil)
  }

  // Design: §4.5
  @Test func decodesPicosecondAndISOTimestamps() throws {
    struct Event: Decodable, Equatable {
      var ts: BigQueryTimestamp
      var when: Date
    }
    let row = Row(
      schema: [Field("ts", .timestamp), Field("when", .timestamp)],
      values: [
        .scalar("2025-01-01T12:34:56.123456789123Z"),
        .scalar("2014-08-19T12:41:35.220000Z"),
      ])
    let event = try row.decode(Event.self)
    #expect(event.ts == BigQueryTimestamp("2025-01-01T12:34:56.123456789123Z"))
    #expect(event.when == Date(timeIntervalSince1970: 1_408_452_095.22))
  }

  // Design: §4.5
  @Test func arrayOfStructElementsDecodeByFieldName() throws {
    // Java parses REPEATED cells without a schema, so name access fails on ARRAY<STRUCT>.
    let person = try self.sample.decode(Person.self)
    #expect(
      person.visits == [
        Visit(day: BigQueryDate(year: 2024, month: 1, day: 1), count: 3),
        Visit(day: BigQueryDate(year: 2024, month: 1, day: 2), count: 4),
      ])
  }

  // Design: §4.5
  @Test func arrayOfRangeElementsKeepElementType() throws {
    // Java returns ARRAY<RANGE> elements as plain strings.
    let person = try self.sample.decode(Person.self)
    #expect(
      person.periods == [
        BigQueryRange(start: "2024-01-01", end: "2024-02-01", elementType: .date),
        BigQueryRange(start: "2024-03-01", end: nil, elementType: .date),
      ])
  }

  // Baseline: U.FieldValueList.02
  @Test func keysMatchColumnsCaseInsensitively() throws {
    struct Names: Decodable {
      var name: String
      var age: Int
      enum CodingKeys: String, CodingKey {
        case name = "NAME"
        case age = "Age"
      }
    }
    let names = try self.sample.decode(Names.self)
    #expect(names.name == "Ada")
    #expect(names.age == 36)
  }

  // Design: §4.5
  @Test func fieldValueAndRowPropertiesAreNotConverted() throws {
    struct Raw: Decodable {
      var tags: FieldValue
      var address: Row
    }
    let raw = try self.sample.decode(Raw.self)
    #expect(raw.tags == .array([.scalar("a"), .scalar("b")]))
    #expect(raw.address["city"] == .scalar("London"))
  }

  // Baseline: U.FieldValueList.03
  @Test func missingColumnThrowsKeyNotFound() throws {
    struct Missing: Decodable { var unknown: String }
    #expect {
      try self.sample.decode(Missing.self)
    } throws: { error in
      guard case DecodingError.keyNotFound(let key, _) = error else { return false }
      return key.stringValue == "unknown"
    }
  }

  // Design: §4.5
  @Test func nullForNonOptionalThrowsValueNotFound() throws {
    struct NonOptional: Decodable { var nickname: String }
    #expect {
      try self.sample.decode(NonOptional.self)
    } throws: { error in
      guard case DecodingError.valueNotFound = error else { return false }
      return true
    }
  }

  // Design: §4.5
  @Test func conversionErrorsCarryTheCodingPath() throws {
    struct BadVisit: Decodable { var day: Int }
    struct Bad: Decodable { var visits: [BadVisit] }
    #expect {
      try self.sample.decode(Bad.self)
    } throws: { error in
      guard case DecodingError.dataCorrupted(let context) = error else { return false }
      return context.codingPath.map(\.stringValue) == ["visits", "Index 0", "day"]
    }
  }

  // Design: §4.5, §8
  @Test func rowSequenceDecodesLazily() async throws {
    struct Name: Decodable { var name: String }
    let schema: Schema = [Field("name", .string)]
    let rows = RowSequence(
      schema: schema,
      rows: [
        Row(schema: schema, values: [.scalar("a")]),
        Row(schema: schema, values: [.scalar("b")]),
      ])
    // The decoded sequence is Sendable, so it can cross into a task.
    let decoded = rows.decode(Name.self)
    let names = try await Task {
      var names: [String] = []
      for try await item in decoded {
        names.append(item.name)
      }
      return names
    }.value
    #expect(names == ["a", "b"])
  }
}
