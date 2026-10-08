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
import GoogleGax
import GoogleWKT
import Testing

@testable import GoogleCloudBigQuery

@Suite struct RowTests {
  private let schema: Schema = [
    Field("name", .string),
    Field("age", .int64),
    Field("tags", .string, mode: .repeated),
    Field(
      "address", .struct,
      fields: [Field("city", .string), Field("zip", .string)]),
    Field(
      "visits", .struct, mode: .repeated,
      fields: [Field("Day", .date), Field("count", .int64)]),
  ]

  private func row(_ json: String) throws -> Row {
    try Row(wire: try WireJSON.decode(json, as: WKTStruct.self), schema: self.schema)
  }

  // Baseline: U.FieldValueList.01
  @Test func parsesRowAgainstSchema() throws {
    let row = try self.row(
      #"""
      {"f": [{"v": "Ada"}, {"v": "36"}, {"v": [{"v": "a"}, {"v": null}]},
             {"v": {"f": [{"v": "London"}, {"v": null}]}},
             {"v": [{"v": {"f": [{"v": "2024-01-01"}, {"v": "3"}]}}]}]}
      """#)
    #expect(row[0] == .scalar("Ada"))
    #expect(row[1] == .scalar("36"))
    #expect(row[2] == .array([.scalar("a"), .null]))
    guard case .record(let address) = row[3] else {
      Issue.record("address is not a record")
      return
    }
    #expect(address["city"] == .scalar("London"))
    #expect(address["zip"] == .null)
  }

  // Design: §4.5
  @Test func repeatedStructElementsUseTheFieldSchema() throws {
    let row = try self.row(
      #"""
      {"f": [{"v": null}, {"v": null}, {"v": null}, {"v": null},
             {"v": [{"v": {"f": [{"v": "2024-01-01"}, {"v": "3"}]}}]}]}
      """#)
    guard case .array(let visits) = row["visits"], case .record(let visit) = visits.first else {
      Issue.record("visits is not an array of records")
      return
    }
    #expect(visit["day"] == .scalar("2024-01-01"))
    #expect(visit["count"] == .scalar("3"))
  }

  // Design: §4.5
  @Test func nullRepeatedFieldIsEmptyArray() throws {
    let row = try self.row(
      #"{"f": [{"v": null}, {"v": null}, {"v": null}, {"v": null}, {"v": null}]}"#)
    #expect(row["tags"] == .array([]))
    #expect(row["visits"] == .array([]))
    #expect(row["name"] == .null)
    #expect(row["address"] == .null)
  }

  // Baseline: U.FieldValueList.02
  @Test func accessByIndexAndName() throws {
    let row = Row(
      schema: [Field("a", .string), Field("B", .int64)], values: [.scalar("x"), .null])
    #expect(row[0] == .scalar("x"))
    #expect(row["a"] == .scalar("x"))
    #expect(row["b"] == .null)
    #expect(row["B"] == .null)
  }

  // Baseline: U.FieldValueList.03
  @Test func unknownNameIsNil() throws {
    let row = Row(schema: [Field("a", .string)], values: [.scalar("x")])
    #expect(row["missing"] == nil)
    #expect(Row(schema: [], values: [.scalar("x")])["a"] == nil)
  }

  // Design: §4.5
  @Test func rejectsMalformedRows() throws {
    #expect(throws: RequestError.self) { try self.row(#"{"f": "x"}"#) }
    // Fewer cells than columns means the caller passed an unprojected schema.
    #expect(throws: RequestError.self) { try self.row(#"{"f": [{"v": "a"}]}"#) }
    #expect(throws: RequestError.self) {
      try self.row(
        #"{"f": [{"v": "a"}, {"v": "b"}, {"v": "c"}, {"v": "d"}, {"v": "e"}, {"v": "f"}]}"#)
    }
    #expect(throws: RequestError.self) {
      try self.row(#"{"f": [{"v": ["a"]}, {"v": null}, {"v": null}, {"v": null}, {"v": null}]}"#)
    }
  }

  // Design: §4.5
  @Test func convertsAPage() throws {
    let rows = try Row.rows(
      from: [
        try WireJSON.decode(#"{"f": [{"v": "1"}]}"#), try WireJSON.decode(#"{"f": [{"v": "2"}]}"#),
      ],
      schema: [Field("n", .int64)])
    #expect(rows.map { $0[0] } == [.scalar("1"), .scalar("2")])
  }
}

@Suite struct SchemaTests {
  // Baseline: U.FieldList.01
  @Test func lookupByNameIsCaseInsensitiveAfterExactMatch() {
    let schema: Schema = [Field("Name", .string), Field("name", .int64), Field("Other", .bool)]
    #expect(schema.index(of: "name") == 1)
    #expect(schema.index(of: "Name") == 0)
    #expect(schema.index(of: "OTHER") == 2)
    #expect(schema["other"]?.type == .bool)
    #expect(schema["missing"] == nil)
  }

  // Baseline: U.FieldList.02
  @Test func lookupByIndex() {
    let schema: Schema = [Field("a", .string), Field("b", .int64)]
    #expect(schema.fields[1].name == "b")
  }

  // Baseline: U.FieldList.03
  @Test func nestedRecordSchema() {
    let schema: Schema = [Field("r", .struct, fields: [Field("x", .int64)])]
    #expect(schema["r"]?.fields.first?.name == "x")
  }

  // Baseline: U.Schema.01, U.FieldList.04, U.Field.01, U.Field.02, U.FieldElementType.01, U.PolicyTags.01
  @Test func wireRoundTripPreservesEveryField() throws {
    let json = #"""
      {"fields": [
        {"name": "id", "type": "INT64", "mode": "REQUIRED", "description": "key"},
        {"name": "price", "type": "NUMERIC", "mode": "NULLABLE", "precision": "10", "scale": "2",
         "roundingMode": "ROUND_HALF_EVEN"},
        {"name": "code", "type": "STRING", "maxLength": "5", "collation": "und:ci",
         "defaultValueExpression": "'x'", "policyTags": {"names": ["projects/p/tag"]}},
        {"name": "span", "type": "RANGE", "rangeElementType": {"type": "DATE"}},
        {"name": "rec", "type": "RECORD", "mode": "REPEATED",
         "fields": [{"name": "leaf", "type": "BOOLEAN"}]},
        {"name": "ts", "type": "TIMESTAMP", "timestampPrecision": "12"}
      ]}
      """#
    let wire: GoogleCloudBigQueryV2.TableSchema = try WireJSON.decode(json)
    let schema = Schema(wire: wire)
    #expect(schema.fields.count == 6)
    let id = schema.fields[0]
    #expect(id.mode == .required)
    #expect(id.description == "key")
    #expect(id.timestampPrecision == nil)
    let price = schema.fields[1]
    #expect(price.precision == 10)
    #expect(price.scale == 2)
    #expect(price.roundingMode == .roundHalfEven)
    let code = schema.fields[2]
    #expect(code.mode == nil)
    #expect(code.maxLength == 5)
    #expect(code.collation == "und:ci")
    #expect(code.defaultValueExpression == "'x'")
    #expect(code.policyTags == ["projects/p/tag"])
    #expect(code.precision == nil)
    #expect(code.roundingMode == nil)
    #expect(schema.fields[3].rangeElementType == .date)
    let rec = schema.fields[4]
    #expect(rec.type == .struct)
    #expect(rec.fields.first?.type == .bool)
    #expect(schema.fields[5].timestampPrecision == 12)
    #expect(Schema(wire: schema.wire) == schema)
  }

  // Baseline: U.Schema.02
  @Test func emptySchemaHasNoFields() throws {
    #expect(Schema(wire: try WireJSON.decode("{}")).fields.isEmpty)
  }

  // Baseline: U.PolicyTags.02
  @Test func policyTagsWithoutNamesAreEmpty() throws {
    let wire: GoogleCloudBigQueryV2.TableFieldSchema = try WireJSON.decode(
      #"{"name": "a", "type": "STRING", "policyTags": {}}"#)
    #expect(Field(wire: wire).policyTags == [])
    let none: GoogleCloudBigQueryV2.TableFieldSchema = try WireJSON.decode(
      #"{"name": "a", "type": "STRING"}"#)
    #expect(Field(wire: none).policyTags == nil)
  }

  // Design: §4.5
  @Test(arguments: [
    ("INTEGER", "INT64"), ("FLOAT", "FLOAT64"), ("BOOLEAN", "BOOL"), ("RECORD", "STRUCT"),
    ("DECIMAL", "NUMERIC"), ("BIGDECIMAL", "BIGNUMERIC"), ("string", "STRING"),
    ("Geography", "GEOGRAPHY"),
  ])
  func fieldTypeNormalizesLegacyNames(legacy: String, standard: String) {
    #expect(FieldType(rawValue: legacy).rawValue == standard)
    #expect(FieldType(rawValue: legacy) == FieldType(rawValue: standard))
  }
}
