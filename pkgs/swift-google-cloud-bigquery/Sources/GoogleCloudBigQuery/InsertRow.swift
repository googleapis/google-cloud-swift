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
import GoogleWKT

/// One row to stream into a table with ``BigQueryClient/insertAll(_:into:skipInvalidRows:ignoreUnknownValues:templateSuffix:insertIDs:options:)``.
///
/// Create a row from any `Encodable` value whose properties match the column names, or from a
/// dictionary of ``InsertValue``s:
///
/// ```swift
/// struct Person: Encodable { var name: String; var age: Int?; var joined: Date }
/// let rows = [
///   try InsertRow(Person(name: "Ana", age: 31, joined: .now)),
///   InsertRow(["name": "Bo", "tags": ["a", "b"], "address": ["city": "Paris"]]),
/// ]
/// ```
///
/// Values are converted to JSON as follows:
///
/// | Swift value | JSON |
/// | ----------- | ---- |
/// | `Date`, ``BigQueryTimestamp`` | an RFC 3339 UTC string with microsecond or picosecond precision |
/// | `Data` | base64 |
/// | `Decimal`, ``BigNumeric`` | an exact decimal string |
/// | Integers | a number when the magnitude is at most 2^53, otherwise a decimal string |
/// | `Double`, `Float` | a number; `NaN` and infinities become `"NaN"`, `"Infinity"`, `"-Infinity"` |
/// | `Bool` | a boolean |
/// | ``BigQueryDate``, ``BigQueryTime``, ``BigQueryDateTime``, ``Interval`` | the canonical string |
/// | ``BigQueryRange`` | an object with the bounds that are set (`{"start": "2024-01-01"}`) |
/// | Nested `Encodable` values and dictionaries | an object (`STRUCT`) |
/// | Arrays | an array (`REPEATED`) |
/// | `nil` | the key is omitted |
public struct InsertRow: Sendable, Equatable {
  /// The ID BigQuery uses to drop duplicate rows on a best-effort basis.
  ///
  /// When `nil`, ``BigQueryClient/insertAll(_:into:skipInvalidRows:ignoreUnknownValues:templateSuffix:insertIDs:options:)``
  /// generates one unless called with ``InsertIDPolicy/none``.
  public var insertID: String?

  /// The row content as a JSON object.
  var json: WKTStruct

  /// Creates a row by encoding `value`, which must encode to a keyed container (an object).
  ///
  /// - Parameters:
  ///   - value: the row content.
  ///   - insertID: the ID used to drop duplicate rows.
  /// - Throws: `EncodingError` if `value` does not encode to an object, or any error thrown by
  ///   its `encode(to:)` method.
  @_disfavoredOverload
  public init<T: Encodable>(_ value: T, insertID: String? = nil) throws {
    guard case .object(let json) = try InsertRowEncoder.encode(value) else {
      throw EncodingError.invalidValue(
        value,
        EncodingError.Context(
          codingPath: [], debugDescription: "An InsertRow must encode to a keyed container."))
    }
    self.json = json
    self.insertID = insertID
  }

  /// Creates a row from column values. `nil` values are omitted.
  ///
  /// - Parameters:
  ///   - values: the value of each column, keyed by column name.
  ///   - insertID: the ID used to drop duplicate rows.
  public init(_ values: [String: InsertValue], insertID: String? = nil) {
    self.json = InsertValue.record(values).json.objectValue
    self.insertID = insertID
  }
}

/// A column value of an ``InsertRow``.
///
/// Literals and the static factory methods create values:
///
/// ```swift
/// let values: [String: InsertValue] = [
///   "name": "Ana", "age": 31, "score": 9.5, "active": true,
///   "joined": .timestamp(.now), "photo": .bytes(data), "tags": ["a", "b"],
///   "address": ["city": "Paris"], "nickname": nil,
/// ]
/// ```
public struct InsertValue: Sendable, Equatable {
  var json: WKTValue

  init(json: WKTValue) {
    self.json = json
  }

  /// A `STRING`, `GEOGRAPHY` (as WKT), or `JSON` (as JSON text) value.
  public static func string(_ value: String) -> InsertValue { InsertValue(json: .string(value)) }

  /// An `INT64` value. Values with a magnitude above 2^53 are sent as decimal strings.
  public static func int64(_ value: Int64) -> InsertValue {
    InsertValue(json: InsertJSON.integer(value))
  }

  /// A `FLOAT64` value. `NaN` and infinities are sent as `"NaN"`, `"Infinity"`, `"-Infinity"`.
  public static func float64(_ value: Double) -> InsertValue {
    InsertValue(json: InsertJSON.double(value))
  }

  /// A `BOOL` value.
  public static func bool(_ value: Bool) -> InsertValue { InsertValue(json: .bool(value)) }

  /// A `BYTES` value, sent in base64.
  public static func bytes(_ value: Data) -> InsertValue {
    InsertValue(json: .string(value.base64EncodedString()))
  }

  /// A `NUMERIC` value, sent as an exact decimal string.
  public static func numeric(_ value: Decimal) -> InsertValue {
    InsertValue(json: .string(value.description))
  }

  /// A `BIGNUMERIC` value, sent as an exact decimal string.
  public static func bigNumeric(_ value: BigNumeric) -> InsertValue {
    InsertValue(json: .string(value.description))
  }

  /// A `TIMESTAMP` value, sent as an RFC 3339 UTC string with microseconds.
  public static func timestamp(_ value: Date) -> InsertValue {
    InsertValue(json: .string(InsertJSON.timestamp(value)))
  }

  /// A `TIMESTAMP` or `TIMESTAMP(12)` value, sent as an RFC 3339 UTC string.
  public static func timestamp(_ value: BigQueryTimestamp) -> InsertValue {
    InsertValue(json: .string(value.description))
  }

  /// A `DATE` value.
  public static func date(_ value: BigQueryDate) -> InsertValue {
    InsertValue(json: .string(value.description))
  }

  /// A `TIME` value.
  public static func time(_ value: BigQueryTime) -> InsertValue {
    InsertValue(json: .string(value.description))
  }

  /// A `DATETIME` value.
  public static func dateTime(_ value: BigQueryDateTime) -> InsertValue {
    InsertValue(json: .string(value.description))
  }

  /// An `INTERVAL` value.
  public static func interval(_ value: Interval) -> InsertValue {
    InsertValue(json: .string(value.description))
  }

  /// A `RANGE` value, sent as an object with the bounds that are set.
  public static func range(_ value: BigQueryRange) -> InsertValue {
    InsertValue(json: InsertJSON.range(value))
  }

  /// A `REPEATED` value.
  public static func array(_ elements: [InsertValue]) -> InsertValue {
    InsertValue(json: .array(elements.map(\.json)))
  }

  /// A `RECORD` (`STRUCT`) value. `nil` fields are omitted.
  public static func record(_ fields: [String: InsertValue]) -> InsertValue {
    InsertValue(json: .object(fields.filter { !$0.value.isNull }.mapValues(\.json)))
  }

  /// No value. In a row or record the column is omitted.
  public static let null = InsertValue(json: .null(WKTNullValue()))

  var isNull: Bool {
    if case .null = self.json { return true }
    return false
  }
}

extension InsertValue: ExpressibleByStringLiteral {
  /// Creates a `STRING` value.
  public init(stringLiteral value: String) { self = .string(value) }
}

extension InsertValue: ExpressibleByIntegerLiteral {
  /// Creates an `INT64` value.
  public init(integerLiteral value: Int64) { self = .int64(value) }
}

extension InsertValue: ExpressibleByFloatLiteral {
  /// Creates a `FLOAT64` value.
  public init(floatLiteral value: Double) { self = .float64(value) }
}

extension InsertValue: ExpressibleByBooleanLiteral {
  /// Creates a `BOOL` value.
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension InsertValue: ExpressibleByArrayLiteral {
  /// Creates a `REPEATED` value.
  public init(arrayLiteral elements: InsertValue...) { self = .array(elements) }
}

extension InsertValue: ExpressibleByDictionaryLiteral {
  /// Creates a `RECORD` value. Later duplicate keys replace earlier ones.
  public init(dictionaryLiteral elements: (String, InsertValue)...) {
    self = .record(Dictionary(elements, uniquingKeysWith: { _, last in last }))
  }
}

extension InsertValue: ExpressibleByNilLiteral {
  /// Creates ``null``.
  public init(nilLiteral: ()) { self = .null }
}

extension WKTValue {
  /// The members of an object, or empty for other values.
  fileprivate var objectValue: WKTStruct {
    if case .object(let object) = self { return object }
    return [:]
  }
}

/// Whether ``BigQueryClient/insertAll(_:into:skipInvalidRows:ignoreUnknownValues:templateSuffix:insertIDs:options:)``
/// generates insert IDs.
///
/// Insert IDs let BigQuery drop duplicate rows on a best-effort basis, which makes retrying a
/// failed request safe. A request is retried only if every row has an insert ID.
public struct InsertIDPolicy: RawRepresentable, Sendable, Hashable {
  /// The policy name.
  public var rawValue: String

  /// Creates a policy from its name.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Generate a random UUID for each row without an ``InsertRow/insertID``. The default.
  public static let generateMissing = InsertIDPolicy(rawValue: "generateMissing")

  /// Send only the insert IDs set on the rows. Unless every row has one, the request is not
  /// retried, because a retry could insert duplicate rows.
  public static let none = InsertIDPolicy(rawValue: "none")
}
