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

/// A user-defined function, table-valued function, or stored procedure.
///
/// ```swift
/// let routine = Routine(
///   id: RoutineID(datasetID: "udfs", routineID: "triple"),
///   type: .scalarFunction,
///   language: .sql,
///   arguments: [Routine.Argument(name: "x", dataType: StandardSQLDataType(.int64))],
///   body: "x * 3")
/// try await client.createRoutine(routine)
/// ```
///
/// ``BigQueryClient/updateRoutine(_:ifMatch:options:)`` replaces the whole routine, so pass
/// every property you want to keep. The output-only properties (``etag``, ``creationTime``,
/// and ``lastModifiedTime``) are ignored on create and update.
public struct Routine: Sendable, Hashable {
  /// The routine ID. A `nil` project means the client's project.
  public var id: RoutineID

  /// The kind of routine. Required on create.
  public var type: RoutineType?

  /// The language of ``body``. The service default is ``Language/sql``.
  public var language: Language?

  /// The arguments, in order.
  public var arguments: [Argument]?

  /// The return type of a function. Optional for SQL functions, where it is inferred.
  public var returnType: StandardSQLDataType?

  /// The columns returned by a table-valued function. Inferred when `nil`.
  public var returnTableType: StandardSQLTableType?

  /// Cloud Storage URIs of JavaScript libraries the routine imports.
  public var importedLibraries: [String]?

  /// The routine body: an expression for SQL functions, a statement block for procedures, or
  /// the code of a JavaScript function.
  public var body: String?

  /// A user-friendly description.
  public var description: String?

  /// Whether a JavaScript function always returns the same result for the same arguments.
  public var determinismLevel: DeterminismLevel?

  /// The options of a remote function.
  public var remoteFunctionOptions: RemoteFunctionOptions?

  /// Marks the routine for use in data masking rules.
  public var dataGovernanceType: DataGovernanceType?

  /// Output only. The version tag of the routine.
  public var etag: String?

  /// Output only. When the routine was created.
  public var creationTime: Date?

  /// Output only. When the routine was last modified.
  public var lastModifiedTime: Date?

  /// Creates a routine description.
  public init(
    id: RoutineID,
    type: RoutineType? = nil,
    language: Language? = nil,
    arguments: [Argument]? = nil,
    returnType: StandardSQLDataType? = nil,
    returnTableType: StandardSQLTableType? = nil,
    importedLibraries: [String]? = nil,
    body: String? = nil,
    description: String? = nil,
    determinismLevel: DeterminismLevel? = nil,
    remoteFunctionOptions: RemoteFunctionOptions? = nil,
    dataGovernanceType: DataGovernanceType? = nil
  ) {
    self.id = id
    self.type = type
    self.language = language
    self.arguments = arguments
    self.returnType = returnType
    self.returnTableType = returnTableType
    self.importedLibraries = importedLibraries
    self.body = body
    self.description = description
    self.determinismLevel = determinismLevel
    self.remoteFunctionOptions = remoteFunctionOptions
    self.dataGovernanceType = dataGovernanceType
  }

  /// An argument of a routine.
  public struct Argument: Sendable, Hashable {
    /// The argument name. Required except for a function's return value.
    public var name: String?

    /// Whether the argument has a fixed type or accepts any type.
    public var kind: Kind?

    /// Whether a procedure argument is input, output, or both.
    public var mode: Mode?

    /// The argument type. Required when ``kind`` is ``Kind/fixedType`` or `nil`.
    public var dataType: StandardSQLDataType?

    /// Creates an argument.
    public init(
      name: String? = nil, kind: Kind? = nil, mode: Mode? = nil,
      dataType: StandardSQLDataType? = nil
    ) {
      self.name = name
      self.kind = kind
      self.mode = mode
      self.dataType = dataType
    }

    /// Whether an argument has a fixed type.
    public struct Kind: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
      /// The kind as sent to the service.
      public var rawValue: String

      /// Creates a kind from its service name.
      public init(rawValue: String) {
        self.rawValue = rawValue
      }

      /// The argument has the type given by ``Argument/dataType``.
      public static let fixedType = Kind(rawValue: "FIXED_TYPE")
      /// A templated argument that accepts any type.
      public static let anyType = Kind(rawValue: "ANY_TYPE")

      /// The kind name.
      public var description: String { self.rawValue }
    }

    /// The direction of a procedure argument.
    public struct Mode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
      /// The mode as sent to the service.
      public var rawValue: String

      /// Creates a mode from its service name.
      public init(rawValue: String) {
        self.rawValue = rawValue
      }

      /// An input argument.
      public static let `in` = Mode(rawValue: "IN")
      /// An output argument.
      public static let out = Mode(rawValue: "OUT")
      /// An input and output argument.
      public static let `inout` = Mode(rawValue: "INOUT")

      /// The mode name.
      public var description: String { self.rawValue }
    }
  }

  /// The options of a remote function, which calls an HTTP endpoint through a connection.
  public struct RemoteFunctionOptions: Sendable, Hashable {
    /// The endpoint to call, for example a Cloud Functions or Cloud Run URL.
    public var endpoint: String?

    /// The connection used to call the endpoint, in the form
    /// `projects/{project}/locations/{location}/connections/{connection}`.
    public var connection: String?

    /// Key-value pairs sent with every request to the endpoint.
    public var userDefinedContext: [String: String]?

    /// The maximum number of rows in each request, or `nil` for no limit.
    public var maxBatchingRows: Int64?

    /// Creates remote function options.
    public init(
      endpoint: String? = nil, connection: String? = nil,
      userDefinedContext: [String: String]? = nil, maxBatchingRows: Int64? = nil
    ) {
      self.endpoint = endpoint
      self.connection = connection
      self.userDefinedContext = userDefinedContext
      self.maxBatchingRows = maxBatchingRows
    }
  }

  /// The kind of a routine.
  public struct RoutineType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The routine type as sent to the service.
    public var rawValue: String

    /// Creates a routine type from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// A function that returns a value.
    public static let scalarFunction = RoutineType(rawValue: "SCALAR_FUNCTION")
    /// A stored procedure.
    public static let procedure = RoutineType(rawValue: "PROCEDURE")
    /// A function that returns a table.
    public static let tableValuedFunction = RoutineType(rawValue: "TABLE_VALUED_FUNCTION")
    /// An aggregate function.
    public static let aggregateFunction = RoutineType(rawValue: "AGGREGATE_FUNCTION")

    /// The routine type name.
    public var description: String { self.rawValue }
  }

  /// The language of a routine body.
  public struct Language: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The language as sent to the service.
    public var rawValue: String

    /// Creates a language from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// GoogleSQL.
    public static let sql = Language(rawValue: "SQL")
    /// JavaScript.
    public static let javaScript = Language(rawValue: "JAVASCRIPT")
    /// Python.
    public static let python = Language(rawValue: "PYTHON")
    /// Java.
    public static let java = Language(rawValue: "JAVA")
    /// Scala.
    public static let scala = Language(rawValue: "SCALA")

    /// The language name.
    public var description: String { self.rawValue }
  }

  /// Whether a function is deterministic.
  public struct DeterminismLevel: RawRepresentable, Sendable, Hashable,
    CustomStringConvertible
  {
    /// The determinism level as sent to the service.
    public var rawValue: String

    /// Creates a determinism level from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// The function always returns the same result for the same arguments.
    public static let deterministic = DeterminismLevel(rawValue: "DETERMINISTIC")
    /// The function may return different results for the same arguments.
    public static let notDeterministic = DeterminismLevel(rawValue: "NOT_DETERMINISTIC")

    /// The determinism level name.
    public var description: String { self.rawValue }
  }

  /// How a routine is used in data governance.
  public struct DataGovernanceType: RawRepresentable, Sendable, Hashable,
    CustomStringConvertible
  {
    /// The data governance type as sent to the service.
    public var rawValue: String

    /// Creates a data governance type from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// The routine can be used as a data masking rule.
    public static let dataMasking = DataGovernanceType(rawValue: "DATA_MASKING")

    /// The data governance type name.
    public var description: String { self.rawValue }
  }
}
