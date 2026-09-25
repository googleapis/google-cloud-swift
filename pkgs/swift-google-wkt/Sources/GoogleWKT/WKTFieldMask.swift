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

/// A field mask represents a set of symbolic field paths, for example:
///
///     paths: ["user.display_name", "photo"]
///
/// In JSON representation, a field mask is a string where paths are separated
/// by a comma. Each path in the string is converted to camelCase.
///
/// For example, the `WKTFieldMask` `paths: ["user.display_name", "photo"]` is
/// represented in JSON as `"user.displayName,photo"`.
public struct WKTFieldMask: Codable, Equatable, Sendable {
  /// The set of field mask paths.
  public var paths: [String] = []

  /// Initialize a new instance of `WKTFieldMask`.
  public init(paths: [String] = []) {
    self.paths = paths
  }

  public func encode(to encoder: any Encoder) throws {
    let joined = self.toString()
    try joined.encode(to: encoder)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    self.paths = try Self.pathsFromString(string: string)
  }

  func toString() -> String {
    let camelCasePaths = paths.map { convertPathToCamelCase($0) }
    return camelCasePaths.joined(separator: ",")
  }

  static func pathsFromString(string: String) throws -> [String] {
    if string.isEmpty {
      return []
    }
    let camelCasePaths = string.split(separator: ",", omittingEmptySubsequences: false)
    return camelCasePaths.map { convertPathToSnakeCase(String($0)) }
  }
}

// Makes `WKTFieldMask` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `WKTAny`.
extension WKTFieldMask: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.FieldMask"
  }

  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeUrl
    }
    guard case let .string(v)? = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.invalidValueField
    }
    self.paths = try Self.pathsFromString(string: v)
  }

  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: WKTValue(string: toString())]
  }
}

private func snakeToCamel(_ s: String) -> String {
  let components = s.split(separator: "_")
  guard let first = components.first else { return s }
  var result = String(first)
  for component in components.dropFirst() {
    if let firstChar = component.first {
      result += String(firstChar).uppercased() + component.dropFirst()
    }
  }
  return result
}

private func camelToSnake(_ s: String) -> String {
  var result = ""
  for char in s {
    if char.isUppercase {
      result.append("_")
      result.append(char.lowercased())
    } else {
      result.append(char)
    }
  }
  return result
}

private func convertPathToCamelCase(_ path: String) -> String {
  return path.split(separator: ".", omittingEmptySubsequences: false)
    .map { snakeToCamel(String($0)) }
    .joined(separator: ".")
}

private func convertPathToSnakeCase(_ path: String) -> String {
  return path.split(separator: ".", omittingEmptySubsequences: false)
    .map { camelToSnake(String($0)) }
    .joined(separator: ".")
}
