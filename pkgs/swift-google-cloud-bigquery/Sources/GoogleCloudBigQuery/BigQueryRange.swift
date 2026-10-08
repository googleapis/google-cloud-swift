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

/// A `RANGE` value: a half-open interval `[start, end)` of `DATE`, `DATETIME`, or `TIMESTAMP`
/// values.
///
/// The bounds are kept in their BigQuery string form. A `nil` bound is unbounded. Use
/// ``startValue`` and ``endValue`` to read the bounds with the typed accessors of
/// ``FieldValue``:
///
/// ```swift
/// if let range = try row["period"]?.rangeValue {
///   let start = try range.startValue.dateValue
/// }
/// ```
public struct BigQueryRange: Sendable, Hashable, CustomStringConvertible {
  /// The inclusive lower bound, or `nil` if the range is unbounded below.
  public var start: String?
  /// The exclusive upper bound, or `nil` if the range is unbounded above.
  public var end: String?
  /// The type of the bounds: `DATE`, `DATETIME`, or `TIMESTAMP`.
  ///
  /// Query parameters need it. Values read with ``FieldValue/rangeValue`` leave it `nil`
  /// because a cell does not carry its type; ``Row/decode(_:)`` fills it from the schema.
  public var elementType: FieldType?

  /// Creates a range from bounds in their BigQuery string form.
  public init(start: String?, end: String?, elementType: FieldType? = nil) {
    self.start = start
    self.end = end
    self.elementType = elementType
  }

  /// Parses the `[start, end)` form that BigQuery returns, where `UNBOUNDED` or `NULL`
  /// (in any case) marks a missing bound.
  ///
  /// Returns `nil` if `text` is not in that form.
  public init?(_ text: String, elementType: FieldType? = nil) {
    guard text.hasPrefix("["), text.hasSuffix(")"),
      let comma = text.range(of: ", ")
    else { return nil }
    let start = text[text.index(after: text.startIndex)..<comma.lowerBound]
    let end = text[comma.upperBound..<text.index(before: text.endIndex)]
    func bound(_ value: Substring) -> String? {
      let upper = value.uppercased()
      return upper == "UNBOUNDED" || upper == "NULL" ? nil : String(value)
    }
    self.init(start: bound(start), end: bound(end), elementType: elementType)
  }

  /// A range of dates.
  public static func date(from start: BigQueryDate?, to end: BigQueryDate?) -> BigQueryRange {
    BigQueryRange(start: start?.description, end: end?.description, elementType: .date)
  }

  /// A range of civil date-times.
  public static func dateTime(
    from start: BigQueryDateTime?, to end: BigQueryDateTime?
  ) -> BigQueryRange {
    BigQueryRange(start: start?.description, end: end?.description, elementType: .dateTime)
  }

  /// A range of timestamps, with microsecond precision.
  public static func timestamp(from start: Date?, to end: Date?) -> BigQueryRange {
    func text(_ date: Date?) -> String? {
      date.map {
        Timestamp.format(micros: Timestamp.micros(from: $0), separator: " ", suffix: "+00:00")
      }
    }
    return BigQueryRange(start: text(start), end: text(end), elementType: .timestamp)
  }

  /// A range of timestamps.
  @_disfavoredOverload
  public static func timestamp(
    from start: BigQueryTimestamp?, to end: BigQueryTimestamp?
  ) -> BigQueryRange {
    func text(_ timestamp: BigQueryTimestamp?) -> String? {
      timestamp?.format(separator: " ", suffix: "+00:00")
    }
    return BigQueryRange(start: text(start), end: text(end), elementType: .timestamp)
  }

  /// The lower bound as a ``FieldValue``: `.null` if unbounded, otherwise `.scalar`.
  public var startValue: FieldValue { self.start.map(FieldValue.scalar) ?? .null }

  /// The upper bound as a ``FieldValue``: `.null` if unbounded, otherwise `.scalar`.
  public var endValue: FieldValue { self.end.map(FieldValue.scalar) ?? .null }

  /// The range in BigQuery's `[start, end)` form, with `UNBOUNDED` for a missing bound.
  public var description: String {
    "[\(self.start ?? "UNBOUNDED"), \(self.end ?? "UNBOUNDED"))"
  }
}

extension BigQueryRange: Codable {
  /// Decodes a range from its `[start, end)` form. The element type is `nil`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let range = BigQueryRange(text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "\"\(text)\" is not a valid RANGE value")
    }
    self = range
  }

  /// Encodes the range in its `[start, end)` form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.description)
  }
}
