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

/// A Swift type that converts to a query parameter of a fixed BigQuery type.
///
/// ``QueryParameterValue/array(_:)`` uses this protocol to type arrays of Swift values, including
/// empty ones. An `Optional` of a conforming type converts `nil` to a typed `NULL`.
public protocol QueryParameterConvertible {
  /// The BigQuery type of every value of this type.
  static var queryParameterType: QueryParameterType { get }

  /// The value as a query parameter.
  var queryParameterValue: QueryParameterValue { get }
}

extension String: QueryParameterConvertible {
  /// `STRING`.
  public static var queryParameterType: QueryParameterType { .string }
  /// The value as a `STRING` parameter.
  public var queryParameterValue: QueryParameterValue { .string(self) }
}

extension Bool: QueryParameterConvertible {
  /// `BOOL`.
  public static var queryParameterType: QueryParameterType { .bool }
  /// The value as a `BOOL` parameter.
  public var queryParameterValue: QueryParameterValue { .bool(self) }
}

extension Int: QueryParameterConvertible {
  /// `INT64`.
  public static var queryParameterType: QueryParameterType { .int64 }
  /// The value as an `INT64` parameter.
  public var queryParameterValue: QueryParameterValue { .int64(Int64(self)) }
}

extension Int64: QueryParameterConvertible {
  /// `INT64`.
  public static var queryParameterType: QueryParameterType { .int64 }
  /// The value as an `INT64` parameter.
  public var queryParameterValue: QueryParameterValue { .int64(self) }
}

extension Int32: QueryParameterConvertible {
  /// `INT64`.
  public static var queryParameterType: QueryParameterType { .int64 }
  /// The value as an `INT64` parameter.
  public var queryParameterValue: QueryParameterValue { .int64(Int64(self)) }
}

extension Double: QueryParameterConvertible {
  /// `FLOAT64`.
  public static var queryParameterType: QueryParameterType { .float64 }
  /// The value as a `FLOAT64` parameter.
  public var queryParameterValue: QueryParameterValue { .float64(self) }
}

extension Float: QueryParameterConvertible {
  /// `FLOAT64`.
  public static var queryParameterType: QueryParameterType { .float64 }
  /// The value as a `FLOAT64` parameter, sent with the `Float`'s shortest decimal form (`1.2`,
  /// not `1.2000000476837158`).
  public var queryParameterValue: QueryParameterValue {
    self.isFinite ? QueryParameterValue(scalar: .float64, String(self)) : .float64(Double(self))
  }
}

extension Decimal: QueryParameterConvertible {
  /// `NUMERIC`.
  public static var queryParameterType: QueryParameterType { .numeric }
  /// The value as a `NUMERIC` parameter.
  public var queryParameterValue: QueryParameterValue { .numeric(self) }
}

extension BigNumeric: QueryParameterConvertible {
  /// `BIGNUMERIC`.
  public static var queryParameterType: QueryParameterType { .bigNumeric }
  /// The value as a `BIGNUMERIC` parameter.
  public var queryParameterValue: QueryParameterValue { .bigNumeric(self) }
}

extension Data: QueryParameterConvertible {
  /// `BYTES`.
  public static var queryParameterType: QueryParameterType { .bytes }
  /// The value as a `BYTES` parameter.
  public var queryParameterValue: QueryParameterValue { .bytes(self) }
}

extension Date: QueryParameterConvertible {
  /// `TIMESTAMP`.
  public static var queryParameterType: QueryParameterType { .timestamp }
  /// The value as a `TIMESTAMP` parameter, with microsecond precision.
  public var queryParameterValue: QueryParameterValue { .timestamp(self) }
}

extension BigQueryTimestamp: QueryParameterConvertible {
  /// `TIMESTAMP`.
  public static var queryParameterType: QueryParameterType { .timestamp }
  /// The value as a `TIMESTAMP` parameter.
  public var queryParameterValue: QueryParameterValue { .timestamp(self) }
}

extension BigQueryDate: QueryParameterConvertible {
  /// `DATE`.
  public static var queryParameterType: QueryParameterType { .date }
  /// The value as a `DATE` parameter.
  public var queryParameterValue: QueryParameterValue { .date(self) }
}

extension BigQueryTime: QueryParameterConvertible {
  /// `TIME`.
  public static var queryParameterType: QueryParameterType { .time }
  /// The value as a `TIME` parameter.
  public var queryParameterValue: QueryParameterValue { .time(self) }
}

extension BigQueryDateTime: QueryParameterConvertible {
  /// `DATETIME`.
  public static var queryParameterType: QueryParameterType { .dateTime }
  /// The value as a `DATETIME` parameter.
  public var queryParameterValue: QueryParameterValue { .dateTime(self) }
}

extension Interval: QueryParameterConvertible {
  /// `INTERVAL`.
  public static var queryParameterType: QueryParameterType { .interval }
  /// The value as an `INTERVAL` parameter.
  public var queryParameterValue: QueryParameterValue { .interval(self) }
}

extension Optional: QueryParameterConvertible where Wrapped: QueryParameterConvertible {
  /// The type of `Wrapped`.
  public static var queryParameterType: QueryParameterType { Wrapped.queryParameterType }
  /// The wrapped value as a parameter, or a `NULL` of the wrapped type.
  public var queryParameterValue: QueryParameterValue {
    self?.queryParameterValue ?? .null(Wrapped.queryParameterType)
  }
}
