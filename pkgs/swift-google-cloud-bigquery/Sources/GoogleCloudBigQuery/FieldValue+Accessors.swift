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

public import Foundation

/// Typed access to cell values.
///
/// Every accessor returns `nil` for `NULL`. The accessors that only unwrap a shape
/// (``stringValue``, ``jsonValue``, ``geographyValue``, ``arrayValue``, ``recordValue``) never
/// throw; they also return `nil` when the value has another shape. The accessors that parse
/// the cell text throw `DecodingError` if it cannot be read as the requested type, for example
/// `int64Value` on `"abc"` or on an array:
///
/// ```swift
/// let name = row["name"]?.stringValue
/// let id = try row["id"]?.int64Value
/// let tags = row["tags"]?.arrayValue?.compactMap(\.stringValue)
/// ```
///
/// Accessors read the cell text; they do not check the column type. Use the accessor that
/// matches the column type in the schema.
extension FieldValue {
  /// `true` if the value is `NULL`.
  public var isNull: Bool { self == .null }

  /// The text of a scalar value. Works for every scalar type, including `DATE`, `TIME`,
  /// `DATETIME`, `GEOGRAPHY` (as WKT), `JSON` (as JSON text), and `INTERVAL`.
  ///
  /// `nil` for `NULL`, an array, or a struct.
  public var stringValue: String? {
    if case .scalar(let text) = self { text } else { nil }
  }

  /// An `INT64` value.
  public var int64Value: Int64? {
    get throws { try self.parse("INT64") { Int64($0) } }
  }

  /// A `FLOAT64` value. `NaN`, `Infinity`, and `-Infinity` are accepted.
  public var doubleValue: Double? {
    get throws { try self.parse("FLOAT64") { Double($0) } }
  }

  /// A `BOOL` value. `true` and `false` are accepted in any case.
  public var boolValue: Bool? {
    get throws {
      try self.parse("BOOL") { text in
        switch text.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
      }
    }
  }

  /// A `BYTES` value, decoded from base64.
  public var bytesValue: Data? {
    get throws { try self.parse("BYTES") { Data(base64Encoded: $0) } }
  }

  /// A `NUMERIC` value. `Decimal` holds the 38 significant digits of `NUMERIC`; use
  /// ``bigNumericValue`` for `BIGNUMERIC`.
  public var numericValue: Decimal? {
    get throws {
      try self.parse("NUMERIC") { text in
        guard let number = DecimalText(text) else { return nil }
        return Decimal(string: number.plainText, locale: Locale(identifier: "en_US_POSIX"))
      }
    }
  }

  /// A `BIGNUMERIC` (or `NUMERIC`) value, exactly.
  public var bigNumericValue: BigNumeric? {
    get throws { try self.parse("BIGNUMERIC") { BigNumeric($0) } }
  }

  /// A `TIMESTAMP` value in microseconds since the Unix epoch.
  ///
  /// ISO 8601 strings (including picosecond `TIMESTAMP(12)` values) are floored to microseconds;
  /// integer strings are read as microseconds; floating-point seconds (for example
  /// `"1.408452095220E9"`) are rounded half away from zero to the nearest microsecond. Use
  /// ``preciseTimestampValue`` when picoseconds matter.
  public var timestampMicros: Int64? {
    get throws {
      try self.parse("TIMESTAMP") { Timestamp.parseCell($0)?.micros }
    }
  }

  /// A `TIMESTAMP` value.
  ///
  /// `Date` cannot represent picoseconds or every microsecond far from 1970; use
  /// ``preciseTimestampValue`` or ``timestampMicros`` when exact sub-second values matter.
  public var timestampValue: Date? {
    get throws { try self.timestampMicros.map(Timestamp.date(fromMicros:)) }
  }

  /// A `TIMESTAMP` value with picosecond precision (`TIMESTAMP` or `TIMESTAMP(12)`).
  public var preciseTimestampValue: BigQueryTimestamp? {
    get throws {
      try self.parse("TIMESTAMP") { Timestamp.parseCell($0) }
    }
  }

  /// A `DATE` value.
  public var dateValue: BigQueryDate? {
    get throws { try self.parse("DATE") { BigQueryDate($0) } }
  }

  /// A `TIME` value.
  public var timeValue: BigQueryTime? {
    get throws { try self.parse("TIME") { BigQueryTime($0) } }
  }

  /// A `DATETIME` value.
  public var dateTimeValue: BigQueryDateTime? {
    get throws { try self.parse("DATETIME") { BigQueryDateTime($0) } }
  }

  /// An `INTERVAL` value, from its canonical or ISO 8601 form.
  public var intervalValue: Interval? {
    get throws { try self.parse("INTERVAL") { Interval($0) } }
  }

  /// A `RANGE` value. Its ``BigQueryRange/elementType`` is `nil`; see the schema for the type.
  public var rangeValue: BigQueryRange? {
    get throws { try self.parse("RANGE") { BigQueryRange($0) } }
  }

  /// A `JSON` value, as JSON text. `nil` for `NULL`, an array, or a struct.
  public var jsonValue: String? { self.stringValue }

  /// A `GEOGRAPHY` value, as Well-Known Text (WKT). `nil` for `NULL`, an array, or a struct.
  public var geographyValue: String? { self.stringValue }

  /// The elements of an array. Arrays are never `NULL` in BigQuery, so a `REPEATED` column
  /// returns `[]` rather than `nil`; `nil` is returned for `NULL`, a scalar, or a struct.
  public var arrayValue: [FieldValue]? {
    if case .array(let elements) = self { elements } else { nil }
  }

  /// The fields of a `STRUCT` value, as a row with the struct's schema. `nil` for `NULL`, a
  /// scalar, or an array.
  public var recordValue: Row? {
    if case .record(let row) = self { row } else { nil }
  }

  /// The text of a scalar value, or `nil` for `NULL`.
  ///
  /// - Throws: `DecodingError.typeMismatch` naming `type` for an array or a struct.
  func checkedText(as type: Any.Type) throws -> String? {
    switch self {
    case .null: return nil
    case .scalar(let text): return text
    case .array: throw Self.mismatch(type, "an array")
    case .record: throw Self.mismatch(type, "a struct")
    }
  }

  /// The fields of a `STRUCT` value, or `nil` for `NULL`.
  ///
  /// - Throws: `DecodingError.typeMismatch` for a scalar or an array.
  func checkedRecord() throws -> Row? {
    switch self {
    case .null: return nil
    case .record(let row): return row
    case .scalar: throw Self.mismatch(Row.self, "a scalar")
    case .array: throw Self.mismatch(Row.self, "an array")
    }
  }

  /// Converts the text of a scalar value, throwing if it is not a scalar or `convert` fails.
  private func parse<T>(_ typeName: String, _ convert: (String) -> T?) throws -> T? {
    guard let text = try self.checkedText(as: T.self) else { return nil }
    guard let value = convert(text) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [], debugDescription: "cannot read \"\(text)\" as \(typeName)"))
    }
    return value
  }

  private static func mismatch(_ type: Any.Type, _ actual: String) -> DecodingError {
    DecodingError.typeMismatch(
      type, DecodingError.Context(codingPath: [], debugDescription: "the value is \(actual)"))
  }
}
