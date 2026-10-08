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
import GoogleCloudBigQueryV2
import GoogleWKT

extension QueryParameterValue {
  /// A `NUMERIC` value.
  public static func numeric(_ value: Decimal) -> QueryParameterValue {
    QueryParameterValue(scalar: .numeric, value.description)
  }

  /// A `BIGNUMERIC` value, sent exactly as its decimal text.
  public static func bigNumeric(_ value: BigNumeric) -> QueryParameterValue {
    QueryParameterValue(scalar: .bigNumeric, value.description)
  }

  /// A `BYTES` value, sent in base64.
  public static func bytes(_ value: Data) -> QueryParameterValue {
    QueryParameterValue(scalar: .bytes, value.base64EncodedString())
  }

  /// A `GEOGRAPHY` value in Well-Known Text (WKT), for example `"POINT(-122.35 47.65)"`.
  public static func geography(_ wkt: String) -> QueryParameterValue {
    QueryParameterValue(scalar: .geography, wkt)
  }

  /// A `JSON` value from JSON text, for example `#"{"a": 1}"#`.
  public static func json(_ text: String) -> QueryParameterValue {
    QueryParameterValue(scalar: .json, text)
  }

  /// A `TIMESTAMP` value, sent with microsecond precision as `YYYY-MM-DD HH:MM:SS.FFFFFF+00:00`.
  public static func timestamp(_ value: Date) -> QueryParameterValue {
    .timestamp(micros: Timestamp.micros(from: value))
  }

  /// A `TIMESTAMP` value from microseconds since the Unix epoch.
  public static func timestamp(micros: Int64) -> QueryParameterValue {
    QueryParameterValue(
      scalar: .timestamp, Timestamp.format(micros: micros, separator: " ", suffix: "+00:00"))
  }

  /// A `TIMESTAMP` value.
  ///
  /// > Note: BigQuery truncates `TIMESTAMP` query parameters to microseconds on the server. When
  /// > comparing against a `TIMESTAMP(12)` column, either cast the parameter in SQL with
  /// > `CAST(@param AS TIMESTAMP(12))` (which preserves microseconds) or pass `value.description`
  /// > as a `.string(...)` parameter with `CAST(@param AS TIMESTAMP(12))` to preserve picoseconds.
  public static func timestamp(_ value: BigQueryTimestamp) -> QueryParameterValue {
    QueryParameterValue(scalar: .timestamp, value.format(separator: " ", suffix: "+00:00"))
  }

  /// A `TIMESTAMP` value from a timestamp literal, sent unchanged.
  ///
  /// The text must have the form `YYYY-MM-DD HH:MM[:SS[.F]][zone]`, with up to 12 fractional
  /// digits and an optional `Z`, `UTC`, `+HH`, `+HHMM`, or `+HH:MM` zone, for example
  /// `"2014-08-19 12:41:35.220000+00:00"`. The `T` separator is not accepted.
  ///
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/invalidArgument``
  ///   if the text is not a valid timestamp.
  public static func timestamp(_ text: String) throws -> QueryParameterValue {
    guard Timestamp.isValidParameterText(text) else {
      throw BigQueryError.invalidArgument("\"\(text)\" is not a valid TIMESTAMP value")
    }
    return QueryParameterValue(scalar: .timestamp, text)
  }

  /// A `DATE` value.
  public static func date(_ value: BigQueryDate) -> QueryParameterValue {
    QueryParameterValue(scalar: .date, value.description)
  }

  /// A `DATE` value from text in the form `YYYY-MM-DD`, sent unchanged.
  ///
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/invalidArgument``
  ///   if the text is not a valid date.
  public static func date(_ text: String) throws -> QueryParameterValue {
    guard BigQueryDate(text) != nil else {
      throw BigQueryError.invalidArgument("\"\(text)\" is not a valid DATE value")
    }
    return QueryParameterValue(scalar: .date, text)
  }

  /// A `TIME` value.
  public static func time(_ value: BigQueryTime) -> QueryParameterValue {
    QueryParameterValue(scalar: .time, value.description)
  }

  /// A `TIME` value from text in the form `HH:MM:SS[.FFFFFF]`, sent unchanged.
  ///
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/invalidArgument``
  ///   if the text is not a valid time.
  public static func time(_ text: String) throws -> QueryParameterValue {
    guard BigQueryTime(text) != nil else {
      throw BigQueryError.invalidArgument("\"\(text)\" is not a valid TIME value")
    }
    return QueryParameterValue(scalar: .time, text)
  }

  /// A `DATETIME` value.
  public static func dateTime(_ value: BigQueryDateTime) -> QueryParameterValue {
    QueryParameterValue(scalar: .dateTime, value.description)
  }

  /// A `DATETIME` value from text in the form `YYYY-MM-DD HH:MM:SS[.FFFFFF]`, sent unchanged.
  ///
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/invalidArgument``
  ///   if the text is not a valid date and time.
  public static func dateTime(_ text: String) throws -> QueryParameterValue {
    guard BigQueryDateTime(text) != nil else {
      throw BigQueryError.invalidArgument("\"\(text)\" is not a valid DATETIME value")
    }
    return QueryParameterValue(scalar: .dateTime, text)
  }

  /// An `INTERVAL` value, sent in canonical form.
  public static func interval(_ value: Interval) -> QueryParameterValue {
    QueryParameterValue(scalar: .interval, value.description)
  }

  /// An `INTERVAL` value from text in canonical form (`"123-7 -19 0:24:12.000006"`) or ISO 8601
  /// form (`"P123Y7M-19DT0H24M12.000006S"`), sent unchanged.
  ///
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/invalidArgument``
  ///   if the text is not a valid interval.
  public static func interval(_ text: String) throws -> QueryParameterValue {
    guard Interval(text) != nil else {
      throw BigQueryError.invalidArgument("\"\(text)\" is not a valid INTERVAL value")
    }
    return QueryParameterValue(scalar: .interval, text)
  }

  /// A `RANGE` value. Set ``BigQueryRange/elementType``; the service requires it.
  public static func range(_ value: BigQueryRange) -> QueryParameterValue {
    func bound(_ text: String?) -> WKTRecursive<GoogleCloudBigQueryV2.QueryParameterValue>? {
      text.map { text in WKTRecursive(value: .init().with { $0.value = text }) }
    }
    var type = GoogleCloudBigQueryV2.QueryParameterType().with { $0.type = "RANGE" }
    if let element = value.elementType {
      type = QueryParameterType.range(element).wire
    }
    return QueryParameterValue(
      type: type,
      value: GoogleCloudBigQueryV2.QueryParameterValue().with {
        $0.rangeValue = WKTRecursive(
          value: GoogleCloudBigQueryV2.RangeValue().with {
            $0.start = bound(value.start)
            $0.end = bound(value.end)
          })
      })
  }

  /// An `ARRAY` value whose elements have type `elementType`.
  ///
  /// The element type is explicit so that empty arrays and arrays of structs are typed
  /// correctly:
  ///
  /// ```swift
  /// let people = QueryParameterValue.array(
  ///   [.struct(["name": .string("Ana")]), .struct(["name": .string("Bo")])],
  ///   of: .struct([.init("name", .string)]))
  /// ```
  public static func array(
    _ elements: [QueryParameterValue], of elementType: QueryParameterType
  ) -> QueryParameterValue {
    QueryParameterValue(
      type: QueryParameterType.array(elementType).wire,
      value: GoogleCloudBigQueryV2.QueryParameterValue().with {
        $0.arrayValues = elements.map(\.value)
      })
  }

  /// An `ARRAY` value of Swift values, for example `.array([1, 2, 3] as [Int64])` or
  /// `.array(["a", "b"])`.
  public static func array<Element: QueryParameterConvertible>(
    _ elements: [Element]
  ) -> QueryParameterValue {
    .array(elements.map(\.queryParameterValue), of: Element.queryParameterType)
  }

  /// A `STRUCT` value. The field order is kept:
  ///
  /// ```swift
  /// let person = QueryParameterValue.struct(["name": .string("Ana"), "age": .int64(31)])
  /// ```
  public static func `struct`(
    _ fields: KeyValuePairs<String, QueryParameterValue>
  ) -> QueryParameterValue {
    .struct(fields.map { (name: $0.key, value: $0.value) })
  }

  /// A `STRUCT` value from fields in order.
  public static func `struct`(
    _ fields: [(name: String, value: QueryParameterValue)]
  ) -> QueryParameterValue {
    let type = QueryParameterType.struct(
      fields.map { QueryParameterType.StructField($0.name, $0.value.parameterType) })
    var values: [String: GoogleCloudBigQueryV2.QueryParameterValue] = [:]
    for field in fields {
      values[field.name] = field.value.value
    }
    return QueryParameterValue(
      type: type.wire,
      value: GoogleCloudBigQueryV2.QueryParameterValue().with { $0.structValues = values })
  }

  /// A `NULL` value of `type`.
  ///
  /// BigQuery has no `NULL` arrays: a `NULL` of an `ARRAY` type is an empty array.
  public static func null(_ type: QueryParameterType) -> QueryParameterValue {
    QueryParameterValue(type: type.wire, value: .init())
  }
}
