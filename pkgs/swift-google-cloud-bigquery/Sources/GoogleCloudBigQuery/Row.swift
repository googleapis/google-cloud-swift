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

import GoogleGax
import GoogleWKT

/// One row of a table or query result.
///
/// Access cells by position or by column name:
///
/// ```swift
/// let name = try row["name"]?.stringValue
/// let first = row[0]
/// ```
public struct Row: Sendable, Equatable {
  /// The schema of this row. For a `STRUCT` value, the schema of the struct's fields.
  public let schema: Schema

  /// The cells of this row, in schema order.
  public let values: [FieldValue]

  /// Creates a row.
  ///
  /// `values` should contain one value per field of `schema`.
  public init(schema: Schema, values: [FieldValue]) {
    self.schema = schema
    self.values = values
  }

  /// The cell at `index`.
  ///
  /// - Precondition: `index` is less than `values.count`.
  public subscript(index: Int) -> FieldValue {
    self.values[index]
  }

  /// The cell of the column named `name`, or `nil` if there is no such column.
  ///
  /// Column names are matched exactly first, then case-insensitively, because BigQuery column
  /// names are case-insensitive.
  public subscript(name: String) -> FieldValue? {
    guard let index = self.schema.index(of: name), index < self.values.count else { return nil }
    return self.values[index]
  }
}

/// The value of one cell, exactly as BigQuery returned it.
///
/// BigQuery returns every scalar as a string. Typed accessors such as `int64Value` convert the
/// string according to the column type.
///
/// This enumeration is closed: it models the four shapes of the BigQuery row format and will not
/// gain cases.
public enum FieldValue: Sendable, Equatable {
  /// A `NULL` value.
  case null

  /// A scalar value in its BigQuery string form, for example `"42"`, `"true"`, or a timestamp in
  /// microseconds since the epoch.
  case scalar(String)

  /// The elements of a `REPEATED` (array) column. A `NULL` array is reported as empty.
  case array([FieldValue])

  /// The value of a `STRUCT` column.
  case record(Row)
}

/// One row in the BigQuery REST `{"f": [{"v": ...}]}` format.
struct WireRow: Decodable, Sendable, Equatable {
  var f: [WireCell] = []

  private enum CodingKeys: String, CodingKey {
    case f
  }

  init(f: [WireCell] = []) {
    self.f = f
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.f = try container.decodeIfPresent([WireCell].self, forKey: .f) ?? []
  }
}

/// One cell `{"v": ...}` in a ``WireRow``.
struct WireCell: Decodable, Sendable, Equatable {
  enum Value: Sendable, Equatable {
    case null
    case scalar(String)
    case array([WireCell])
    case record(WireRow)
  }

  var v: Value

  private enum CodingKeys: String, CodingKey {
    case v
  }

  init(v: Value = .null) {
    self.v = v
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard container.contains(.v), !(try container.decodeNil(forKey: .v)) else {
      self.v = .null
      return
    }
    if let text = try? container.decode(String.self, forKey: .v) {
      self.v = .scalar(text)
    } else if let elements = try? container.decode([WireCell].self, forKey: .v) {
      self.v = .array(elements)
    } else if let row = try? container.decode(WireRow.self, forKey: .v) {
      self.v = .record(row)
    } else if let bool = try? container.decode(Bool.self, forKey: .v) {
      self.v = .scalar(bool ? "true" : "false")
    } else if let number = try? container.decode(Double.self, forKey: .v) {
      self.v = .scalar(String(number))
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .v, in: container, debugDescription: "unexpected BigQuery cell value")
    }
  }
}

extension Row {
  /// Converts rows in the BigQuery `{"f": [{"v": ...}]}` format.
  static func rows(from wire: [WireRow], schema: Schema) throws -> [Row] {
    try wire.map { try Row(wire: $0, schema: schema) }
  }

  /// Converts one row in the BigQuery `{"f": [{"v": ...}]}` format.
  init(wire: WireRow, schema: Schema) throws {
    let cells = wire.f
    guard cells.count == schema.fields.count else {
      throw malformedRow("row has \(cells.count) cells but the schema has \(schema.fields.count)")
    }
    var values: [FieldValue] = []
    values.reserveCapacity(cells.count)
    for index in cells.indices {
      values.append(
        try FieldValue(
          wire: cells[index].v,
          field: schema.fields[index],
          childSchema: schema.childSchemas[index]))
    }
    self.init(schema: schema, values: values)
  }

  /// Converts one row in the BigQuery `{"f": [{"v": ...}]}` format.
  ///
  /// `schema` must describe exactly the returned columns, in order. When a request selects a
  /// subset of the columns (`selectedFields`), pass the schema projected to that subset.
  init(wire: WKTStruct, schema: Schema) throws {
    guard case .array(let cells) = wire["f"] ?? .array([]) else {
      throw malformedRow("row without an \"f\" array")
    }
    guard cells.count == schema.fields.count else {
      throw malformedRow("row has \(cells.count) cells but the schema has \(schema.fields.count)")
    }
    var values: [FieldValue] = []
    values.reserveCapacity(cells.count)
    for index in cells.indices {
      let cell = cells[index]
      let field = schema.fields[index]
      guard case .object(let object) = cell else {
        throw malformedRow("cell for \"\(field.name)\" is not an object")
      }
      values.append(
        try FieldValue(
          wire: object["v"] ?? .null(WKTNullValue()),
          field: field,
          childSchema: schema.childSchemas[index]))
    }
    self.init(schema: schema, values: values)
  }
}

extension FieldValue {
  /// Converts the `v` member of a ``WireCell``, using `field` to interpret arrays and structs.
  init(wire: WireCell.Value, field: Field, childSchema: Schema? = nil) throws {
    if field.mode == .repeated {
      switch wire {
      case .null:
        // BigQuery represents a NULL array as an empty array.
        self = .array([])
      case .array(let elements):
        var element = field
        element.mode = .nullable
        let nestedSchema = childSchema ?? (field.fields.isEmpty ? nil : Schema(field.fields))
        self = .array(
          try elements.map { item in
            try FieldValue(wire: item.v, field: element, childSchema: nestedSchema)
          })
      default:
        throw malformedRow("value of repeated field \"\(field.name)\" is not an array")
      }
      return
    }
    switch wire {
    case .null:
      self = .null
    case .scalar(let value):
      self = .scalar(value)
    case .record(let object):
      guard field.type == .struct else {
        throw malformedRow("value of \"\(field.name)\" is an object but its type is \(field.type)")
      }
      self = .record(
        try Row(wire: object, schema: childSchema ?? Schema(field.fields)))
    case .array:
      throw malformedRow("value of non-repeated field \"\(field.name)\" is an array")
    }
  }

  /// Converts the `v` member of a cell, using `field` to interpret arrays and structs.
  init(wire: WKTValue, field: Field, childSchema: Schema? = nil) throws {
    if field.mode == .repeated {
      switch wire {
      case .null:
        // BigQuery represents a NULL array as an empty array.
        self = .array([])
      case .array(let elements):
        var element = field
        element.mode = .nullable
        let nestedSchema = childSchema ?? (field.fields.isEmpty ? nil : Schema(field.fields))
        self = .array(
          try elements.map { item in
            guard case .object(let object) = item else {
              throw malformedRow("array element of \"\(field.name)\" is not an object")
            }
            return try FieldValue(
              wire: object["v"] ?? .null(WKTNullValue()),
              field: element,
              childSchema: nestedSchema)
          })
      default:
        throw malformedRow("value of repeated field \"\(field.name)\" is not an array")
      }
      return
    }
    switch wire {
    case .null:
      self = .null
    case .string(let value):
      self = .scalar(value)
    case .bool(let value):
      self = .scalar(value ? "true" : "false")
    case .number(let value):
      self = .scalar(String(value))
    case .object(let object):
      guard field.type == .struct else {
        throw malformedRow("value of \"\(field.name)\" is an object but its type is \(field.type)")
      }
      self = .record(try Row(wire: object, schema: childSchema ?? Schema(field.fields)))
    case .array:
      throw malformedRow("value of non-repeated field \"\(field.name)\" is an array")
    }
  }
}

/// The error thrown when the service returns rows that do not match the format or schema.
func malformedRow(_ description: String) -> RequestError {
  RequestError.malformedResponse("malformed BigQuery row: " + description)
}
