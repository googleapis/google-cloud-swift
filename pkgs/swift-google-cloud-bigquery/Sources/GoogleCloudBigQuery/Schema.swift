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

/// The schema of a table or query result.
public struct Schema: Sendable, Hashable, ExpressibleByArrayLiteral {
  /// The top-level columns, in order.
  public var fields: [Field] {
    didSet {
      self.rebuildIndex()
    }
  }

  private var exactIndex: [String: Int] = [:]
  private var lowercaseIndex: [String: Int] = [:]
  private(set) var childSchemas: [Schema?] = []

  /// Creates a schema with `fields`.
  public init(_ fields: [Field]) {
    self.fields = fields
    self.rebuildIndex()
  }

  public init(arrayLiteral elements: Field...) {
    self.init(elements)
  }

  private mutating func rebuildIndex() {
    var exact: [String: Int] = [:]
    var lower: [String: Int] = [:]
    var children: [Schema?] = []
    exact.reserveCapacity(self.fields.count)
    lower.reserveCapacity(self.fields.count)
    children.reserveCapacity(self.fields.count)
    for (index, field) in self.fields.enumerated() {
      if exact[field.name] == nil {
        exact[field.name] = index
      }
      let lowerName = field.name.lowercased()
      if lower[lowerName] == nil {
        lower[lowerName] = index
      }
      children.append(field.fields.isEmpty ? nil : Schema(field.fields))
    }
    self.exactIndex = exact
    self.lowercaseIndex = lower
    self.childSchemas = children
  }

  /// The position of the column named `name`, or `nil` if there is none.
  ///
  /// Names are matched exactly first, then case-insensitively, because BigQuery column names are
  /// case-insensitive.
  public func index(of name: String) -> Int? {
    if let index = self.exactIndex[name] { return index }
    return self.lowercaseIndex[name.lowercased()]
  }

  /// The column named `name`, or `nil` if there is none.
  public subscript(name: String) -> Field? {
    self.index(of: name).map { self.fields[$0] }
  }

  public static func == (lhs: Schema, rhs: Schema) -> Bool {
    lhs.fields == rhs.fields
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.fields)
  }
}

/// A column in a ``Schema``, or a subfield of a `STRUCT` column.
public struct Field: Sendable, Hashable {
  /// The column name.
  public var name: String

  /// The column type.
  public var type: FieldType

  /// The column mode, or `nil` for the service default (``Mode-swift.struct/nullable``).
  public var mode: Mode?

  /// The subfields of a `STRUCT` column.
  public var fields: [Field]

  /// The column description.
  public var description: String?

  /// The maximum length of a `STRING` or `BYTES` column.
  public var maxLength: Int64?

  /// The precision of a `NUMERIC` or `BIGNUMERIC` column.
  public var precision: Int64?

  /// The scale of a `NUMERIC` or `BIGNUMERIC` column.
  public var scale: Int64?

  /// The fractional-second digits of a `TIMESTAMP` column: `6` (the default) or `12`
  /// (picoseconds). The service validates the value.
  public var timestampPrecision: Int64?

  /// How values are rounded when written to a `NUMERIC` or `BIGNUMERIC` column.
  public var roundingMode: RoundingMode?

  /// The collation of a `STRING` column, for example `und:ci`.
  public var collation: String?

  /// A SQL expression that provides the default value of the column.
  public var defaultValueExpression: String?

  /// The element type of a `RANGE` column: `DATE`, `DATETIME`, or `TIMESTAMP`.
  public var rangeElementType: FieldType?

  /// The resource names of the policy tags attached to the column.
  public var policyTags: [String]?

  /// Creates a field.
  public init(
    _ name: String,
    _ type: FieldType,
    mode: Mode? = nil,
    fields: [Field] = [],
    description: String? = nil
  ) {
    self.name = name
    self.type = type
    self.mode = mode
    self.fields = fields
    self.description = description
  }

  /// The mode of a column.
  public struct Mode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// The column may contain `NULL`.
    public static let nullable = Mode(rawValue: "NULLABLE")
    /// The column must have a value.
    public static let required = Mode(rawValue: "REQUIRED")
    /// The column is an array.
    public static let repeated = Mode(rawValue: "REPEATED")

    public var description: String { self.rawValue }
  }

  /// How values are rounded when written to a `NUMERIC` or `BIGNUMERIC` column.
  public struct RoundingMode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Round halfway cases away from zero.
    public static let roundHalfAwayFromZero = RoundingMode(rawValue: "ROUND_HALF_AWAY_FROM_ZERO")
    /// Round halfway cases towards the nearest even digit.
    public static let roundHalfEven = RoundingMode(rawValue: "ROUND_HALF_EVEN")

    public var description: String { self.rawValue }
  }
}

/// The type of a column or query parameter, using GoogleSQL type names.
///
/// The service sometimes reports legacy names, such as `INTEGER` or `RECORD`. The client converts
/// them to their GoogleSQL equivalents, such as ``int64`` and ``struct``.
public struct FieldType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  /// Creates a type, converting legacy names to their GoogleSQL equivalents.
  public init(rawValue: String) {
    let upper = rawValue.uppercased()
    self.rawValue = Self.legacyNames[upper] ?? upper
  }

  public static let string = FieldType(rawValue: "STRING")
  public static let bytes = FieldType(rawValue: "BYTES")
  public static let int64 = FieldType(rawValue: "INT64")
  public static let float64 = FieldType(rawValue: "FLOAT64")
  public static let numeric = FieldType(rawValue: "NUMERIC")
  public static let bigNumeric = FieldType(rawValue: "BIGNUMERIC")
  public static let bool = FieldType(rawValue: "BOOL")
  public static let timestamp = FieldType(rawValue: "TIMESTAMP")
  public static let date = FieldType(rawValue: "DATE")
  public static let time = FieldType(rawValue: "TIME")
  public static let dateTime = FieldType(rawValue: "DATETIME")
  public static let geography = FieldType(rawValue: "GEOGRAPHY")
  public static let json = FieldType(rawValue: "JSON")
  public static let interval = FieldType(rawValue: "INTERVAL")
  public static let range = FieldType(rawValue: "RANGE")
  public static let `struct` = FieldType(rawValue: "STRUCT")

  public var description: String { self.rawValue }

  static let legacyNames = [
    "INTEGER": "INT64",
    "FLOAT": "FLOAT64",
    "BOOLEAN": "BOOL",
    "RECORD": "STRUCT",
    "DECIMAL": "NUMERIC",
    "BIGDECIMAL": "BIGNUMERIC",
  ]
}
