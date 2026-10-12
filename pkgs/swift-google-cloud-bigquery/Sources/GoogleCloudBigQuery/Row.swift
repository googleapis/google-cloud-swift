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
import GoogleGax
@_spi(GoogleCloudInternal) import GoogleWKT

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
struct WireRow: _RawJSONDecodable, Sendable, Equatable {
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
struct WireCell: _RawJSONDecodable, Sendable, Equatable {
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
    if (try? container.decodeNil(forKey: .v)) != false {
      self.v = .null
    } else if let text = try? container.decode(String.self, forKey: .v) {
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

/// Single-pass UTF-8 JSON parser for BigQuery `tabledata.list`, `jobs.query`, and
/// `jobs.getQueryResults` row payloads.
///
/// Parses `"rows": [{"f": [{"v": ...}]}]` directly from the raw UTF-8 response buffer into
/// `[Row]` without building a `Foundation.JSONDecoder` token tape or intermediate `[WireRow]`
/// and `[WireCell]` arrays.
struct RowJSONScanner {
  private let bytes: [UInt8]
  private var index: Int = 0

  private init(bytes: [UInt8]) {
    self.bytes = bytes
  }

  private init(data: Data) {
    self.bytes = Array(data)
  }

  /// Decodes a `tabledata.list` or `jobs.getQueryResults` page directly into a ``Page`` of
  /// ``Row`` values in a single UTF-8 pass.
  static func decodePage(from data: Data, schema: Schema) throws -> (
    totalRows: UInt64?, page: Page<Row>
  ) {
    if data.isEmpty {
      return (nil, Page(items: []))
    }
    return try Self.decodePage(from: Array(data), schema: schema)
  }

  /// Decodes a `tabledata.list` or `jobs.getQueryResults` page from a `[UInt8]` buffer in a
  /// single UTF-8 pass.
  static func decodePage(from bytes: [UInt8], schema: Schema) throws -> (
    totalRows: UInt64?, page: Page<Row>
  ) {
    if bytes.isEmpty {
      return (nil, Page(items: []))
    }
    var scanner = RowJSONScanner(bytes: bytes)
    return try scanner.scanPage(schema: schema)
  }

  /// Decodes only the `"rows"` field of a `jobs.query` or `jobs.getQueryResults` JSON response
  /// directly into `[Row]` in a single UTF-8 pass.
  static func decodeRows(from data: Data, schema: Schema) throws -> [Row] {
    if data.isEmpty { return [] }
    var scanner = RowJSONScanner(data: data)
    return try scanner.scanRowsOnly(schema: schema)
  }

  /// Decodes a single row JSON object `{"f": [{"v": ...}]}` directly into a ``Row``.
  static func decodeRow(from data: Data, schema: Schema) throws -> Row {
    var scanner = RowJSONScanner(data: data)
    return try scanner.parseRow(schema: schema)
  }

  /// Peeks the top-level `"pageToken"` from a `tabledata.list` or `jobs.getQueryResults` JSON
  /// payload before decoding its rows.
  static func peekPageToken(from bytes: [UInt8]) -> String? {
    if bytes.isEmpty { return nil }
    var scanner = RowJSONScanner(bytes: bytes)
    return try? scanner.scanPageTokenOnly()
  }

  private mutating func scanPage(schema: Schema) throws -> (totalRows: UInt64?, page: Page<Row>) {
    try self.expectByte(0x7B)  // '{'
    if self.peekByte() == 0x7D {
      self.index += 1
      return (nil, Page(items: []))
    }
    var totalRows: UInt64?
    var pageToken: String?
    var rows: [Row] = []
    while true {
      let key = try self.parseString()
      try self.expectByte(0x3A)  // ':'
      switch key {
      case "totalRows":
        if self.peekByte() == 0x6E {
          try self.consumeNull()
        } else if self.peekByte() == 0x22 {
          totalRows = UInt64(try self.parseString())
        } else {
          totalRows = UInt64(try self.parseNumberToken())
        }
      case "pageToken":
        if self.peekByte() == 0x6E {
          try self.consumeNull()
        } else {
          let token = try self.parseString()
          if !token.isEmpty { pageToken = token }
        }
      case "rows":
        rows = try self.parseRowsArray(schema: schema)
      default:
        try self.skipValue()
      }
      let next = self.peekByte()
      if next == 0x2C {  // ','
        self.index += 1
        continue
      }
      if next == 0x7D {  // '}'
        self.index += 1
        break
      }
      throw malformedRow("expected ',' or '}' in page object")
    }
    return (totalRows, Page(items: rows, nextPageToken: pageToken))
  }

  private mutating func scanRowsOnly(schema: Schema) throws -> [Row] {
    try self.expectByte(0x7B)  // '{'
    if self.peekByte() == 0x7D {
      self.index += 1
      return []
    }
    while true {
      let key = try self.parseString()
      try self.expectByte(0x3A)  // ':'
      if key == "rows" {
        return try self.parseRowsArray(schema: schema)
      }
      try self.skipValue()
      let next = self.peekByte()
      if next == 0x2C {
        self.index += 1
        continue
      }
      if next == 0x7D {
        self.index += 1
        break
      }
      throw malformedRow("expected ',' or '}' in query response")
    }
    return []
  }

  private mutating func scanPageTokenOnly() throws -> String? {
    try self.expectByte(0x7B)  // '{'
    if self.peekByte() == 0x7D { return nil }
    while true {
      let key = try self.parseString()
      try self.expectByte(0x3A)  // ':'
      if key == "pageToken" {
        if self.peekByte() == 0x6E {
          return nil
        }
        let token = try self.parseString()
        return token.isEmpty ? nil : token
      }
      try self.skipValue()
      let next = self.peekByte()
      if next == 0x2C {
        self.index += 1
        continue
      }
      return nil
    }
  }

  private mutating func parseRowsArray(schema: Schema) throws -> [Row] {
    if self.peekByte() == 0x6E {
      try self.consumeNull()
      return []
    }
    try self.expectByte(0x5B)  // '['
    if self.peekByte() == 0x5D {
      self.index += 1
      return []
    }
    var rows: [Row] = []
    while true {
      rows.append(try self.parseRow(schema: schema))
      let next = self.peekByte()
      if next == 0x2C {  // ','
        self.index += 1
        continue
      }
      if next == 0x5D {  // ']'
        self.index += 1
        break
      }
      throw malformedRow("expected ',' or ']' in rows array")
    }
    return rows
  }

  private mutating func parseRow(schema: Schema) throws -> Row {
    guard self.peekByte() == 0x7B else {
      throw malformedRow("row is not an object")
    }
    self.index += 1
    if self.peekByte() == 0x7D {
      self.index += 1
      guard schema.fields.isEmpty else {
        throw malformedRow("row has 0 cells but the schema has \(schema.fields.count)")
      }
      return Row(schema: schema, values: [])
    }
    var values: [FieldValue]?
    while true {
      let key = try self.parseString()
      try self.expectByte(0x3A)  // ':'
      if key == "f" {
        if self.peekByte() == 0x6E {
          try self.consumeNull()
          values = []
        } else if self.peekByte() == 0x5B {
          values = try self.parseCells(schema: schema)
        } else {
          throw malformedRow("row without an \"f\" array")
        }
      } else {
        try self.skipValue()
      }
      let next = self.peekByte()
      if next == 0x2C {
        self.index += 1
        continue
      }
      if next == 0x7D {
        self.index += 1
        break
      }
      throw malformedRow("expected ',' or '}' in row object")
    }
    let resolved = values ?? []
    guard resolved.count == schema.fields.count else {
      throw malformedRow(
        "row has \(resolved.count) cells but the schema has \(schema.fields.count)")
    }
    return Row(schema: schema, values: resolved)
  }

  private mutating func parseCells(schema: Schema) throws -> [FieldValue] {
    try self.expectByte(0x5B)  // '['
    let fieldCount = schema.fields.count
    var values: [FieldValue] = []
    values.reserveCapacity(fieldCount)
    if self.peekByte() == 0x5D {
      self.index += 1
      guard fieldCount == 0 else {
        throw malformedRow("row has 0 cells but the schema has \(fieldCount)")
      }
      return values
    }
    var cellIndex = 0
    while true {
      if cellIndex < fieldCount {
        values.append(
          try self.parseCellObject(
            field: schema.fields[cellIndex],
            childSchema: schema.childSchemas[cellIndex]))
      } else {
        try self.skipValue()
      }
      cellIndex += 1
      let next = self.peekByte()
      if next == 0x2C {
        self.index += 1
        continue
      }
      if next == 0x5D {
        self.index += 1
        break
      }
      throw malformedRow("expected ',' or ']' in \"f\" array")
    }
    guard cellIndex == fieldCount else {
      throw malformedRow("row has \(cellIndex) cells but the schema has \(fieldCount)")
    }
    return values
  }

  private mutating func parseCellObject(field: Field, childSchema: Schema?) throws -> FieldValue {
    guard self.peekByte() == 0x7B else {
      throw malformedRow("cell for \"\(field.name)\" is not an object")
    }
    self.index += 1
    if self.peekByte() == 0x7D {
      self.index += 1
      return field.mode == .repeated ? .array([]) : .null
    }
    var cellValue: FieldValue?
    while true {
      let key = try self.parseString()
      try self.expectByte(0x3A)  // ':'
      if key == "v" {
        cellValue = try self.parseCellValue(field: field, childSchema: childSchema)
      } else {
        try self.skipValue()
      }
      let next = self.peekByte()
      if next == 0x2C {
        self.index += 1
        continue
      }
      if next == 0x7D {
        self.index += 1
        break
      }
      throw malformedRow("expected ',' or '}' in cell object")
    }
    return cellValue ?? (field.mode == .repeated ? .array([]) : .null)
  }

  private mutating func parseCellValue(field: Field, childSchema: Schema?) throws -> FieldValue {
    guard let b = self.peekByte() else {
      throw malformedRow("unexpected end of JSON in cell for \"\(field.name)\"")
    }
    if field.mode == .repeated {
      if b == 0x6E {  // 'null'
        try self.consumeNull()
        return .array([])
      }
      guard b == 0x5B else {  // '['
        throw malformedRow("value of repeated field \"\(field.name)\" is not an array")
      }
      self.index += 1
      if self.peekByte() == 0x5D {
        self.index += 1
        return .array([])
      }
      var elementField = field
      elementField.mode = .nullable
      let nestedSchema = childSchema ?? (field.fields.isEmpty ? nil : Schema(field.fields))
      var elements: [FieldValue] = []
      while true {
        guard self.peekByte() == 0x7B else {
          throw malformedRow("array element of \"\(field.name)\" is not an object")
        }
        elements.append(
          try self.parseCellObject(field: elementField, childSchema: nestedSchema))
        let next = self.peekByte()
        if next == 0x2C {
          self.index += 1
          continue
        }
        if next == 0x5D {
          self.index += 1
          break
        }
        throw malformedRow("expected ',' or ']' in repeated cell array")
      }
      return .array(elements)
    }

    switch b {
    case 0x22:  // '"'
      return .scalar(try self.parseString())
    case 0x6E:  // 'null'
      try self.consumeNull()
      return .null
    case 0x7B:  // '{'
      guard field.type == .struct else {
        throw malformedRow("value of \"\(field.name)\" is an object but its type is \(field.type)")
      }
      return .record(try self.parseRow(schema: childSchema ?? Schema(field.fields)))
    case 0x5B:  // '['
      throw malformedRow("value of non-repeated field \"\(field.name)\" is an array")
    case 0x74:  // 'true'
      try self.consumeLiteral(0x74, 0x72, 0x75, 0x65)
      return .scalar("true")
    case 0x66:  // 'false'
      try self.consumeLiteral(0x66, 0x61, 0x6C, 0x73, 0x65)
      return .scalar("false")
    case 0x2D, 0x30...0x39:
      let token = try self.parseNumberToken()
      guard let number = Double(token) else {
        throw malformedRow("invalid number in cell for \"\(field.name)\"")
      }
      return .scalar(String(number))
    default:
      throw malformedRow("unexpected JSON token in cell for \"\(field.name)\"")
    }
  }

  private mutating func skipWhitespace() {
    while self.index < self.bytes.count {
      switch self.bytes[self.index] {
      case 0x20, 0x09, 0x0A, 0x0D:
        self.index += 1
      default:
        return
      }
    }
  }

  private mutating func peekByte() -> UInt8? {
    self.skipWhitespace()
    guard self.index < self.bytes.count else { return nil }
    return self.bytes[self.index]
  }

  private mutating func expectByte(_ expected: UInt8) throws {
    self.skipWhitespace()
    guard self.index < self.bytes.count, self.bytes[self.index] == expected else {
      throw malformedRow("unexpected JSON token at byte \(self.index)")
    }
    self.index += 1
  }

  private mutating func consumeNull() throws {
    try self.consumeLiteral(0x6E, 0x75, 0x6C, 0x6C)
  }

  private mutating func consumeLiteral(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) throws {
    guard self.index + 4 <= self.bytes.count,
      self.bytes[self.index] == b0,
      self.bytes[self.index + 1] == b1,
      self.bytes[self.index + 2] == b2,
      self.bytes[self.index + 3] == b3
    else {
      throw malformedRow("invalid JSON literal at byte \(self.index)")
    }
    self.index += 4
  }

  private mutating func consumeLiteral(
    _ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8, _ b4: UInt8
  ) throws {
    guard self.index + 5 <= self.bytes.count,
      self.bytes[self.index] == b0,
      self.bytes[self.index + 1] == b1,
      self.bytes[self.index + 2] == b2,
      self.bytes[self.index + 3] == b3,
      self.bytes[self.index + 4] == b4
    else {
      throw malformedRow("invalid JSON literal at byte \(self.index)")
    }
    self.index += 5
  }

  private mutating func parseNumberToken() throws -> String {
    self.skipWhitespace()
    let start = self.index
    while self.index < self.bytes.count {
      switch self.bytes[self.index] {
      case 0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x7D, 0x5D:
        return String(decoding: self.bytes[start..<self.index], as: UTF8.self)
      default:
        self.index += 1
      }
    }
    return String(decoding: self.bytes[start..<self.index], as: UTF8.self)
  }

  private mutating func parseString() throws -> String {
    try self.expectByte(0x22)  // '"'
    let start = self.index
    while self.index < self.bytes.count {
      let b = self.bytes[self.index]
      if b == 0x22 {
        let result = String(decoding: self.bytes[start..<self.index], as: UTF8.self)
        self.index += 1
        return result
      }
      if b == 0x5C {
        return try self.parseEscapedString(from: start)
      }
      self.index += 1
    }
    throw malformedRow("unterminated JSON string")
  }

  private mutating func parseEscapedString(from start: Int) throws -> String {
    let quoteStart = start - 1
    var out: [UInt8] = []
    out.reserveCapacity((self.index - start) + 16)
    if self.index > start {
      out.append(contentsOf: self.bytes[start..<self.index])
    }
    var hasUnicodeEscape = false
    while self.index < self.bytes.count {
      let b = self.bytes[self.index]
      self.index += 1
      if b == 0x22 {
        if hasUnicodeEscape {
          return try JSONDecoder().decode(
            String.self, from: Data(self.bytes[quoteStart..<self.index]))
        }
        return String(decoding: out, as: UTF8.self)
      }
      if b == 0x5C {
        guard self.index < self.bytes.count else {
          throw malformedRow("unterminated JSON escape")
        }
        let esc = self.bytes[self.index]
        self.index += 1
        switch esc {
        case 0x22: out.append(0x22)
        case 0x5C: out.append(0x5C)
        case 0x2F: out.append(0x2F)
        case 0x62: out.append(0x08)
        case 0x66: out.append(0x0C)
        case 0x6E: out.append(0x0A)
        case 0x72: out.append(0x0D)
        case 0x74: out.append(0x09)
        case 0x75: hasUnicodeEscape = true
        default: throw malformedRow("invalid JSON escape")
        }
      } else if !hasUnicodeEscape {
        out.append(b)
      }
    }
    throw malformedRow("unterminated JSON string")
  }

  private mutating func skipStringBody() throws {
    while self.index < self.bytes.count {
      let b = self.bytes[self.index]
      self.index += 1
      if b == 0x22 { return }
      if b == 0x5C {
        guard self.index < self.bytes.count else {
          throw malformedRow("unterminated JSON escape")
        }
        self.index += 1
      }
    }
    throw malformedRow("unterminated JSON string")
  }

  private mutating func skipValue() throws {
    guard let b = self.peekByte() else {
      throw malformedRow("unexpected end of JSON")
    }
    if b == 0x22 {
      self.index += 1
      try self.skipStringBody()
      return
    }
    if b == 0x7B || b == 0x5B {
      self.index += 1
      var depth = 1
      while self.index < self.bytes.count && depth > 0 {
        let cur = self.bytes[self.index]
        self.index += 1
        if cur == 0x22 {
          try self.skipStringBody()
        } else if cur == 0x7B || cur == 0x5B {
          depth += 1
        } else if cur == 0x7D || cur == 0x5D {
          depth -= 1
        }
      }
      guard depth == 0 else {
        throw malformedRow("unterminated JSON container")
      }
      return
    }
    while self.index < self.bytes.count {
      switch self.bytes[self.index] {
      case 0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x7D, 0x5D:
        return
      default:
        self.index += 1
      }
    }
  }
}
