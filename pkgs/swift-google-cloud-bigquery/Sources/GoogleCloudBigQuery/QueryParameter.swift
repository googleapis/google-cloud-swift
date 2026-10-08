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
/// Create values with the static factory methods, for example `.int64(42)` or `.string("x")`.
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
}
