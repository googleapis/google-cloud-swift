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

/// A GoogleSQL data type, used by routine arguments and return types and by model columns.
///
/// ```swift
/// StandardSQLDataType(.int64)
/// StandardSQLDataType.array(of: StandardSQLDataType(.string))
/// StandardSQLDataType.struct([StandardSQLField("x", type: StandardSQLDataType(.float64))])
/// ```
public struct StandardSQLDataType: Sendable, Hashable {
  /// The top-level kind of a GoogleSQL data type.
  public struct TypeKind: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The type kind as sent to the service.
    public var rawValue: String

    /// Creates a type kind from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// `INT64`.
    public static let int64 = TypeKind(rawValue: "INT64")
    /// `BOOL`.
    public static let bool = TypeKind(rawValue: "BOOL")
    /// `FLOAT64`.
    public static let float64 = TypeKind(rawValue: "FLOAT64")
    /// `STRING`.
    public static let string = TypeKind(rawValue: "STRING")
    /// `BYTES`.
    public static let bytes = TypeKind(rawValue: "BYTES")
    /// `TIMESTAMP`.
    public static let timestamp = TypeKind(rawValue: "TIMESTAMP")
    /// `DATE`.
    public static let date = TypeKind(rawValue: "DATE")
    /// `TIME`.
    public static let time = TypeKind(rawValue: "TIME")
    /// `DATETIME`.
    public static let dateTime = TypeKind(rawValue: "DATETIME")
    /// `INTERVAL`.
    public static let interval = TypeKind(rawValue: "INTERVAL")
    /// `GEOGRAPHY`.
    public static let geography = TypeKind(rawValue: "GEOGRAPHY")
    /// `NUMERIC`.
    public static let numeric = TypeKind(rawValue: "NUMERIC")
    /// `BIGNUMERIC`.
    public static let bigNumeric = TypeKind(rawValue: "BIGNUMERIC")
    /// `JSON`.
    public static let json = TypeKind(rawValue: "JSON")
    /// `ARRAY`; see ``StandardSQLDataType/arrayElementType``.
    public static let array = TypeKind(rawValue: "ARRAY")
    /// `STRUCT`; see ``StandardSQLDataType/structType``.
    public static let `struct` = TypeKind(rawValue: "STRUCT")
    /// `RANGE`; see ``StandardSQLDataType/rangeElementType``.
    public static let range = TypeKind(rawValue: "RANGE")

    /// The type kind name.
    public var description: String { self.rawValue }
  }

  indirect enum SubType: Sendable, Hashable {
    case array(StandardSQLDataType)
    case `struct`(StandardSQLStructType)
    case range(StandardSQLDataType)
  }

  /// The top-level kind of the type.
  public let typeKind: TypeKind

  let subType: SubType?

  init(typeKind: TypeKind, subType: SubType?) {
    self.typeKind = typeKind
    self.subType = subType
  }

  /// Creates a type without element or field types, such as `INT64` or `STRING`.
  public init(_ typeKind: TypeKind) {
    self.init(typeKind: typeKind, subType: nil)
  }

  /// Returns an `ARRAY` type with the given element type.
  public static func array(of elementType: StandardSQLDataType) -> StandardSQLDataType {
    StandardSQLDataType(typeKind: .array, subType: .array(elementType))
  }

  /// Returns a `STRUCT` type with the given fields, in order.
  public static func `struct`(_ fields: [StandardSQLField]) -> StandardSQLDataType {
    StandardSQLDataType(typeKind: .struct, subType: .struct(StandardSQLStructType(fields: fields)))
  }

  /// Returns a `RANGE` type with the given element type (`DATE`, `DATETIME`, or `TIMESTAMP`).
  public static func range(of elementType: StandardSQLDataType) -> StandardSQLDataType {
    StandardSQLDataType(typeKind: .range, subType: .range(elementType))
  }

  /// The element type of an `ARRAY`, otherwise `nil`.
  public var arrayElementType: StandardSQLDataType? {
    if case .array(let type) = self.subType { return type }
    return nil
  }

  /// The fields of a `STRUCT`, otherwise `nil`.
  public var structType: StandardSQLStructType? {
    if case .struct(let type) = self.subType { return type }
    return nil
  }

  /// The element type of a `RANGE`, otherwise `nil`.
  public var rangeElementType: StandardSQLDataType? {
    if case .range(let type) = self.subType { return type }
    return nil
  }
}

/// A named field of a GoogleSQL `STRUCT` or table type.
public struct StandardSQLField: Sendable, Hashable {
  /// The field name, or `nil` for an unnamed struct field.
  public var name: String?

  /// The field type, or `nil` when the service does not report it (for example a templated
  /// routine argument).
  public var type: StandardSQLDataType?

  /// Creates a field.
  public init(_ name: String?, type: StandardSQLDataType?) {
    self.name = name
    self.type = type
  }
}

/// The fields of a GoogleSQL `STRUCT` type.
public struct StandardSQLStructType: Sendable, Hashable {
  /// The fields, in order.
  public var fields: [StandardSQLField]

  /// Creates a struct type.
  public init(fields: [StandardSQLField]) {
    self.fields = fields
  }
}

/// The columns of a table returned by a table-valued function.
public struct StandardSQLTableType: Sendable, Hashable {
  /// The columns, in order.
  public var columns: [StandardSQLField]

  /// Creates a table type.
  public init(columns: [StandardSQLField]) {
    self.columns = columns
  }
}
