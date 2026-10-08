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

@Suite struct StandardSQLDataTypeTests {
  // Baseline: U.StandardSQLDataType.01
  @Test func roundTripsScalarArrayStructAndRange() throws {
    let json = #"""
      {"typeKind": "STRUCT", "structType": {"fields": [
        {"name": "n", "type": {"typeKind": "INT64"}},
        {"name": "a", "type": {"typeKind": "ARRAY", "arrayElementType": {"typeKind": "STRING"}}},
        {"name": "r", "type": {"typeKind": "RANGE", "rangeElementType": {"typeKind": "DATE"}}}
      ]}}
      """#
    let type = StandardSQLDataType(wire: try WireJSON.decode(json, as: StandardSqlDataType.self))
    #expect(type.typeKind == .struct)
    #expect(
      type
        == .struct([
          StandardSQLField("n", type: .init(.int64)),
          StandardSQLField("a", type: .array(of: .init(.string))),
          StandardSQLField("r", type: .range(of: .init(.date))),
        ]))
    #expect(try WireJSON.object(type.wire) == WireJSON.object(json))
  }

  // Baseline: U.StandardSQLDataType.01
  @Test func accessorsExposeSubTypes() {
    #expect(StandardSQLDataType.array(of: .init(.bool)).arrayElementType == .init(.bool))
    #expect(StandardSQLDataType.array(of: .init(.bool)).typeKind == .array)
    #expect(StandardSQLDataType.range(of: .init(.timestamp)).rangeElementType == .init(.timestamp))
    #expect(StandardSQLDataType.struct([]).structType == StandardSQLStructType(fields: []))
    #expect(StandardSQLDataType(.json).arrayElementType == nil)
    #expect(StandardSQLDataType(.json).structType == nil)
  }
}

@Suite struct StandardSQLFieldTests {
  // Baseline: U.StandardSQLField.01
  @Test func roundTrips() throws {
    let field = StandardSQLField("f", type: .init(.float64))
    #expect(
      try WireJSON.object(field.wire)
        == WireJSON.object(#"{"name": "f", "type": {"typeKind": "FLOAT64"}}"#))
    #expect(StandardSQLField(wire: field.wire) == field)
    #expect(StandardSQLField(wire: StandardSQLField(nil, type: nil).wire).name == nil)
  }
}

@Suite struct StandardSQLStructTypeTests {
  // Baseline: U.StandardSQLStructType.01
  @Test func roundTrips() throws {
    let type = StandardSQLStructType(fields: [
      StandardSQLField("a", type: .init(.int64)), StandardSQLField("b", type: .init(.string)),
    ])
    #expect(StandardSQLStructType(wire: type.wire) == type)
    #expect(type.wire.fields.map(\.name) == ["a", "b"])
  }
}

@Suite struct StandardSQLTableTypeTests {
  // Baseline: U.StandardSQLTableType.01
  @Test func roundTrips() throws {
    let json = #"{"columns": [{"name": "c", "type": {"typeKind": "NUMERIC"}}]}"#
    let type = StandardSQLTableType(wire: try WireJSON.decode(json, as: StandardSqlTableType.self))
    #expect(type == StandardSQLTableType(columns: [StandardSQLField("c", type: .init(.numeric))]))
    #expect(try WireJSON.object(type.wire) == WireJSON.object(json))
  }
}
