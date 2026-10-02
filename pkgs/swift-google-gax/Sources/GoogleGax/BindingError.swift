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

/// A failure to bind a request to an HTTP URI path template.
public struct BindingError: Sendable, Equatable, Error, CustomStringConvertible {
  /// All candidate paths considered, and why the binding failed for each.
  public let paths: [PathMismatch]

  /// Creates a new `BindingError`.
  ///
  /// - Parameter paths: The candidate paths considered, and why the binding failed for each.
  ///   Defaults to an empty array for convenience in tests and mock clients.
  public init(paths: [PathMismatch] = []) {
    self.paths = paths
  }

  /// Creates a new `BindingError` for an invalid single-segment field value.
  ///
  /// - Parameters:
  ///   - fieldName: The name of the field that failed validation.
  ///   - invalidValue: The invalid value provided for the field.
  public init(fieldName: String, invalidValue: String) {
    self.init(paths: [
      PathMismatch(substitutions: [
        SubstitutionMismatch(fieldName: fieldName, problem: .invalidValue(actual: invalidValue))
      ])
    ])
  }

  /// Creates a new `BindingError` for an invalid multi-segment field value containing relative segments.
  ///
  /// - Parameters:
  ///   - fieldName: The name of the field that failed validation.
  ///   - invalidSegments: The value containing invalid segments (such as `.` or `..`).
  public init(fieldName: String, invalidSegments: String) {
    self.init(paths: [
      PathMismatch(substitutions: [
        SubstitutionMismatch(
          fieldName: fieldName, problem: .invalidSegments(actual: invalidSegments))
      ])
    ])
  }

  public var description: String {
    if paths.isEmpty {
      return "no matching URL path"
    }
    if paths.count == 1 {
      return paths[0].description
    }
    var result = "at least one of the conditions must be met: "
    for (i, path) in paths.enumerated() {
      if i > 0 {
        result += " OR "
      }
      result += "(\(i + 1)) \(path)"
    }
    return result
  }
}

extension BindingError: CustomDebugStringConvertible {
  public var debugDescription: String {
    "BindingError(paths: \(String(reflecting: paths)))"
  }
}

extension BindingError: LocalizedError {
  public var errorDescription: String? {
    description
  }

  public var failureReason: String? {
    "The request failed to match any valid URL path template."
  }

  public var recoverySuggestion: String? {
    "Verify that all required fields in the request (such as 'name' or 'parent') are set and correctly formatted."
  }
}

/// A failure to bind to a specific candidate URI path template.
public struct PathMismatch: Sendable, Equatable, CustomStringConvertible {
  /// All missing or misformatted fields needed to bind to this path.
  public let substitutions: [SubstitutionMismatch]

  /// Creates a new `PathMismatch`.
  ///
  /// - Parameter substitutions: All missing or misformatted fields needed to bind to this path.
  ///   Defaults to an empty array for convenience in tests and mock clients.
  public init(substitutions: [SubstitutionMismatch] = []) {
    self.substitutions = substitutions
  }

  public var description: String {
    substitutions.map(\.description).joined(separator: " AND ")
  }
}

extension PathMismatch: CustomDebugStringConvertible {
  public var debugDescription: String {
    "PathMismatch(substitutions: \(String(reflecting: substitutions)))"
  }
}

/// Details of why a specific field substitution failed.
public struct SubstitutionMismatch: Sendable, Equatable, CustomStringConvertible {
  public let fieldName: String
  public let problem: SubstitutionFail

  public init(fieldName: String, problem: SubstitutionFail) {
    self.fieldName = fieldName
    self.problem = problem
  }

  public var description: String {
    switch problem {
    case .unset:
      return "field '\(fieldName)' needs to be set"
    case .unsetExpecting(let expected):
      return "field '\(fieldName)' needs to be set and match the template: '\(expected)'"
    case .mismatchExpecting(let actual, let expected):
      return "field '\(fieldName)' should match the template: '\(expected)'; found: '\(actual)'"
    case .invalidValue(let actual):
      return "Invalid value \(actual) for \(fieldName)"
    case .invalidSegments:
      return "Value for \(fieldName) must not contain segments that are exactly . or .."
    }
  }
}

extension SubstitutionMismatch: CustomDebugStringConvertible {
  public var debugDescription: String {
    "SubstitutionMismatch(fieldName: \(String(reflecting: fieldName)), problem: \(String(reflecting: problem)))"
  }
}

/// Categories of substitution failure.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum SubstitutionFail: Sendable, Equatable {
  case unset
  case unsetExpecting(String)
  case mismatchExpecting(actual: String, expected: String)
  case invalidValue(actual: String)
  case invalidSegments(actual: String)
}

extension SubstitutionFail: CustomStringConvertible {
  public var description: String {
    switch self {
    case .unset:
      return "unset"
    case .unsetExpecting(let expected):
      return "unset (expecting \(expected))"
    case .mismatchExpecting(let actual, let expected):
      return "mismatch (actual: \(actual), expecting: \(expected))"
    case .invalidValue(let actual):
      return "invalidValue (\(actual))"
    case .invalidSegments(let actual):
      return "invalidSegments (\(actual))"
    }
  }
}

extension SubstitutionFail: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .unset:
      return "SubstitutionFail.unset"
    case .unsetExpecting(let expected):
      return "SubstitutionFail.unsetExpecting(\(String(reflecting: expected)))"
    case .mismatchExpecting(let actual, let expected):
      return
        "SubstitutionFail.mismatchExpecting(actual: \(String(reflecting: actual)), expected: \(String(reflecting: expected)))"
    case .invalidValue(let actual):
      return "SubstitutionFail.invalidValue(\(String(reflecting: actual)))"
    case .invalidSegments(let actual):
      return "SubstitutionFail.invalidSegments(\(String(reflecting: actual)))"
    }
  }
}

/// Helper builder for accumulating path substitution errors in generated transport code.
@_spi(GoogleCloudInternal)
public struct _PathMismatchBuilder: Sendable {
  private var substitutions: [SubstitutionMismatch] = []

  public init() {}

  public mutating func maybeAdd(
    _ value: String?,
    matching: [_RoutingSegment],
    fieldName: String,
    expecting: String
  ) {
    guard let value, !value.isEmpty else {
      substitutions.append(
        SubstitutionMismatch(fieldName: fieldName, problem: .unsetExpecting(expecting))
      )
      return
    }
    if _RoutingMatcher.value(value, matching: matching) == nil {
      substitutions.append(
        SubstitutionMismatch(
          fieldName: fieldName,
          problem: .mismatchExpecting(actual: value, expected: expecting)
        )
      )
    }
  }

  public mutating func maybeAdd(
    _ value: String?,
    fieldName: String
  ) {
    guard let value, !value.isEmpty else {
      substitutions.append(SubstitutionMismatch(fieldName: fieldName, problem: .unset))
      return
    }
  }

  public mutating func maybeAdd<T>(
    _ value: T?,
    fieldName: String
  ) {
    if value == nil {
      substitutions.append(SubstitutionMismatch(fieldName: fieldName, problem: .unset))
    }
  }

  public func build() -> PathMismatch {
    PathMismatch(substitutions: substitutions)
  }
}
