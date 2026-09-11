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

import Foundation

/// A failure to bind a request to an HTTP URI path template.
public struct BindingError: Sendable, Equatable, Error, CustomStringConvertible,
  ExpressibleByStringInterpolation
{
  /// All candidate paths considered, and why the binding failed for each.
  public var paths: [PathMismatch]
  /// An optional unstructured error message for non-template binding errors.
  public var message: String?

  public init(paths: [PathMismatch]) {
    self.paths = paths
    self.message = nil
  }

  public init(_ message: String) {
    self.paths = []
    self.message = message
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  public init(stringInterpolation: DefaultStringInterpolation) {
    self.init(String(stringInterpolation: stringInterpolation))
  }

  public var description: String {
    if let message {
      return message
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

/// A failure to bind to a specific candidate URI path template.
public struct PathMismatch: Sendable, Equatable, CustomStringConvertible {
  /// All missing or misformatted fields needed to bind to this path.
  public var substitutions: [SubstitutionMismatch]

  public init(substitutions: [SubstitutionMismatch] = []) {
    self.substitutions = substitutions
  }

  public var description: String {
    substitutions.map(\.description).joined(separator: " AND ")
  }
}

/// Details of why a specific field substitution failed.
public struct SubstitutionMismatch: Sendable, Equatable, CustomStringConvertible {
  public var fieldName: String
  public var problem: SubstitutionFail

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
    }
  }
}

/// Categories of substitution failure.
public enum SubstitutionFail: Sendable, Equatable {
  case unset
  case unsetExpecting(String)
  case mismatchExpecting(actual: String, expected: String)
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
