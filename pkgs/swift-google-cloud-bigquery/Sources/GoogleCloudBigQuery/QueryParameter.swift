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

import GoogleCloudBigQueryV2
import GoogleWKT

/// The parameters of a parameterized query.
///
/// A query uses either named parameters (`@name`) or positional parameters (`?`), never both.
///
/// ```swift
/// let result = try await client.query(
///   "SELECT name FROM people WHERE age > @age",
///   parameters: .named(["age": .int64(21)]))
/// ```
///
/// This enumeration is closed and will not gain cases.
public enum QueryParameters: Sendable, Equatable {
  /// Parameters referenced as `@name` in the query.
  case named([String: QueryParameterValue])

  /// Parameters referenced as `?` in the query, in order.
  case positional([QueryParameterValue])
}

/// The type and value of one query parameter.
///
/// Create values with the static factory methods, for example `.int64(42)`, `.string("x")`,
/// `.array([1, 2, 3])`, or `.struct(["name": .string("Ana"), "age": .int64(31)])`.
///
/// Read a value back with ``parameterType`` and ``scalarValue``, ``arrayValues``,
/// ``structValues``, or ``rangeValue``, for example from the configuration of a query job.
public struct QueryParameterValue: Sendable, Equatable {
  /// The wire representation of the parameter type.
  var type: GoogleCloudBigQueryV2.QueryParameterType

  /// The wire representation of the parameter value.
  var value: GoogleCloudBigQueryV2.QueryParameterValue

  init(
    type: GoogleCloudBigQueryV2.QueryParameterType,
    value: GoogleCloudBigQueryV2.QueryParameterValue
  ) {
    self.type = type
    self.value = value
  }

  /// Creates a scalar value of `type` from its BigQuery string form. `nil` means `NULL`.
  init(scalar type: FieldType, _ value: String?) {
    self.init(
      type: GoogleCloudBigQueryV2.QueryParameterType().with { $0.type = type.rawValue },
      value: GoogleCloudBigQueryV2.QueryParameterValue().with { $0.value = value })
  }

  /// A `STRING` value.
  public static func string(_ value: String) -> QueryParameterValue {
    QueryParameterValue(scalar: .string, value)
  }

  /// An `INT64` value.
  public static func int64(_ value: Int64) -> QueryParameterValue {
    QueryParameterValue(scalar: .int64, String(value))
  }

  /// A `BOOL` value.
  public static func bool(_ value: Bool) -> QueryParameterValue {
    QueryParameterValue(scalar: .bool, value ? "true" : "false")
  }

  /// A `FLOAT64` value. Non-finite values are sent as `NaN`, `Infinity`, and `-Infinity`.
  public static func float64(_ value: Double) -> QueryParameterValue {
    let text: String
    if value.isNaN {
      text = "NaN"
    } else if value.isInfinite {
      text = value < 0 ? "-Infinity" : "Infinity"
    } else {
      text = String(value)
    }
    return QueryParameterValue(scalar: .float64, text)
  }

  /// The type of the parameter.
  public var parameterType: QueryParameterType {
    QueryParameterType(wire: self.type)
  }

  /// The value of a scalar parameter in its BigQuery string form, for example `"42"` for
  /// `.int64(42)`. `nil` for `NULL` and for `ARRAY`, `STRUCT`, and `RANGE` parameters.
  public var scalarValue: String? {
    self.parameterType.isScalar ? self.value.value : nil
  }

  /// The elements of an `ARRAY` parameter, or `nil` for other types.
  public var arrayValues: [QueryParameterValue]? {
    guard self.type.type == "ARRAY" else { return nil }
    let elementType = self.type.arrayType?.value ?? .init()
    return self.value.arrayValues.map { QueryParameterValue(type: elementType, value: $0) }
  }

  /// The fields of a `STRUCT` parameter in type order, or `nil` for other types. A field that
  /// has no value is `NULL`.
  public var structValues: [(name: String, value: QueryParameterValue)]? {
    guard self.type.type == "STRUCT" else { return nil }
    return self.type.structTypes.map { field in
      (
        name: field.name,
        value: QueryParameterValue(
          type: field.type?.value ?? .init(), value: self.value.structValues[field.name] ?? .init())
      )
    }
  }

  /// The bounds of a `RANGE` parameter, or `nil` for other types.
  public var rangeValue: BigQueryRange? {
    guard self.type.type == "RANGE" else { return nil }
    return BigQueryRange(
      start: self.value.rangeValue?.value.start?.value.value,
      end: self.value.rangeValue?.value.end?.value.value,
      elementType: self.type.rangeElementType.map { FieldType(rawValue: $0.value.type) })
  }
}

/// The type of a query parameter: a scalar type, or an `ARRAY`, `STRUCT`, or `RANGE` type.
///
/// ```swift
/// let empty = QueryParameterValue.array([], of: .int64)
/// let missing = QueryParameterValue.null(.struct([.init("name", .string)]))
/// ```
public struct QueryParameterType: Sendable, Equatable, CustomStringConvertible {
  var wire: GoogleCloudBigQueryV2.QueryParameterType

  init(wire: GoogleCloudBigQueryV2.QueryParameterType) {
    self.wire = wire
  }

  /// A scalar type, for example `QueryParameterType(.int64)`.
  public init(_ type: FieldType) {
    self.init(wire: GoogleCloudBigQueryV2.QueryParameterType().with { $0.type = type.rawValue })
  }

  /// `STRING`.
  public static let string = QueryParameterType(.string)
  /// `BYTES`.
  public static let bytes = QueryParameterType(.bytes)
  /// `INT64`.
  public static let int64 = QueryParameterType(.int64)
  /// `FLOAT64`.
  public static let float64 = QueryParameterType(.float64)
  /// `NUMERIC`.
  public static let numeric = QueryParameterType(.numeric)
  /// `BIGNUMERIC`.
  public static let bigNumeric = QueryParameterType(.bigNumeric)
  /// `BOOL`.
  public static let bool = QueryParameterType(.bool)
  /// `TIMESTAMP`.
  public static let timestamp = QueryParameterType(.timestamp)
  /// `DATE`.
  public static let date = QueryParameterType(.date)
  /// `TIME`.
  public static let time = QueryParameterType(.time)
  /// `DATETIME`.
  public static let dateTime = QueryParameterType(.dateTime)
  /// `GEOGRAPHY`.
  public static let geography = QueryParameterType(.geography)
  /// `JSON`.
  public static let json = QueryParameterType(.json)
  /// `INTERVAL`.
  public static let interval = QueryParameterType(.interval)

  /// `ARRAY<element>`.
  public static func array(_ element: QueryParameterType) -> QueryParameterType {
    QueryParameterType(
      wire: GoogleCloudBigQueryV2.QueryParameterType().with {
        $0.type = "ARRAY"
        $0.arrayType = WKTRecursive(value: element.wire)
      })
  }

  /// `STRUCT<fields>`, with the fields in order.
  public static func `struct`(_ fields: [StructField]) -> QueryParameterType {
    QueryParameterType(
      wire: GoogleCloudBigQueryV2.QueryParameterType().with {
        $0.type = "STRUCT"
        $0.structTypes = fields.map { field in
          GoogleCloudBigQueryV2.QueryParameterStructType().with {
            $0.name = field.name
            $0.type = WKTRecursive(value: field.type.wire)
          }
        }
      })
  }

  /// `RANGE<element>`, where `element` is `DATE`, `DATETIME`, or `TIMESTAMP`.
  public static func range(_ element: FieldType) -> QueryParameterType {
    QueryParameterType(
      wire: GoogleCloudBigQueryV2.QueryParameterType().with {
        $0.type = "RANGE"
        $0.rangeElementType = WKTRecursive(value: QueryParameterType(element).wire)
      })
  }

  /// The name of the type, for example `"INT64"`, `"ARRAY"`, `"STRUCT"`, or `"RANGE"`.
  public var typeName: String { self.wire.type }

  /// The element type of an `ARRAY` type, or `nil` for other types.
  public var elementType: QueryParameterType? {
    self.wire.arrayType.map { QueryParameterType(wire: $0.value) }
  }

  /// The fields of a `STRUCT` type, or `nil` for other types.
  public var structFields: [StructField]? {
    guard self.wire.type == "STRUCT" else { return nil }
    return self.wire.structTypes.map {
      StructField($0.name, QueryParameterType(wire: $0.type?.value ?? .init()))
    }
  }

  /// The element type of a `RANGE` type, or `nil` for other types.
  public var rangeElementType: FieldType? {
    self.wire.rangeElementType.map { FieldType(rawValue: $0.value.type) }
  }

  /// The type in GoogleSQL syntax, for example `ARRAY<STRUCT<name STRING>>`.
  public var description: String {
    if let element = self.elementType { return "ARRAY<\(element)>" }
    if let fields = self.structFields {
      return "STRUCT<"
        + fields.map { $0.name.isEmpty ? "\($0.type)" : "\($0.name) \($0.type)" }
        .joined(separator: ", ") + ">"
    }
    if let element = self.rangeElementType { return "RANGE<\(element)>" }
    return self.typeName
  }

  /// `true` for types other than `ARRAY`, `STRUCT`, and `RANGE`.
  var isScalar: Bool { !["ARRAY", "STRUCT", "RANGE"].contains(self.wire.type) }

  /// One field of a `STRUCT` type.
  public struct StructField: Sendable, Equatable {
    /// The field name. Empty for an unnamed field.
    public var name: String
    /// The field type.
    public var type: QueryParameterType

    /// Creates a struct field.
    public init(_ name: String, _ type: QueryParameterType) {
      self.name = name
      self.type = type
    }
  }
}

extension QueryParameters {
  /// The parameters in wire form. Named parameters are sorted by name.
  var wire: [GoogleCloudBigQueryV2.QueryParameter] {
    switch self {
    case .named(let parameters):
      return parameters.sorted { $0.key < $1.key }.map { name, value in
        GoogleCloudBigQueryV2.QueryParameter().with {
          $0.name = name
          $0.parameterType = value.type
          $0.parameterValue = value.value
        }
      }
    case .positional(let values):
      return values.map { value in
        GoogleCloudBigQueryV2.QueryParameter().with {
          $0.parameterType = value.type
          $0.parameterValue = value.value
        }
      }
    }
  }

  /// The `parameterMode` of a query using these parameters.
  var wireMode: String {
    switch self {
    case .named: return "NAMED"
    case .positional: return "POSITIONAL"
    }
  }

  /// Converts the parameters of a query configuration read from the service.
  ///
  /// - Parameters:
  ///   - wire: the `queryParameters` of the configuration.
  ///   - mode: the `parameterMode`. `"POSITIONAL"` gives ``positional(_:)``; anything else,
  ///     including `nil`, gives ``named(_:)``.
  /// - Throws: `DecodingError` if a parameter has no type, or a named parameter has no name.
  init(wire: [GoogleCloudBigQueryV2.QueryParameter], mode: String?) throws {
    let values = try wire.map { parameter in
      guard let type = parameter.parameterType, !type.type.isEmpty else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: [], debugDescription: "query parameter \"\(parameter.name)\" has no type"))
      }
      return QueryParameterValue(type: type, value: parameter.parameterValue ?? .init())
    }
    if mode == "POSITIONAL" {
      self = .positional(values)
      return
    }
    var named: [String: QueryParameterValue] = [:]
    for (parameter, value) in zip(wire, values) {
      guard !parameter.name.isEmpty else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: [], debugDescription: "a named query parameter has no name"))
      }
      named[parameter.name] = value
    }
    self = .named(named)
  }
}
