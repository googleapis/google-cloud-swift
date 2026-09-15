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

/// Represents a segment in a routing parameter path template per AIP-4222.
@_spi(GoogleCloudInternal)
public enum _RoutingSegment: Sendable, Equatable {
  /// A literal string, matches its exact prefix value.
  case literal(String)
  /// Matches any value satisfying `[^/]+` (up to the next `/` or end of string).
  case singleWildcard
  /// Matches any value, including empty strings.
  case multiWildcard
  /// Matches any value satisfying `([:/].*)?` or empty string.
  case trailingMultiWildcard

  func matchLength(in haystack: Substring) -> Int? {
    switch self {
    case .literal(let lit):
      return haystack.hasPrefix(lit) ? lit.count : nil
    case .singleWildcard:
      if haystack.isEmpty || haystack.hasPrefix("/") {
        return nil
      }
      if let slashIndex = haystack.firstIndex(of: "/") {
        return haystack.distance(from: haystack.startIndex, to: slashIndex)
      }
      return haystack.count
    case .multiWildcard:
      return haystack.count
    case .trailingMultiWildcard:
      if haystack.isEmpty {
        return 0
      }
      if haystack.hasPrefix("/") || haystack.hasPrefix(":") {
        return haystack.count
      }
      return nil
    }
  }
}

/// Helper for extracting and formatting AIP-4222 gRPC routing metadata parameters.
@_spi(GoogleCloudInternal)
public enum _RoutingMatcher {
  /// The RFC 6570 Section 1.5 unreserved character set: `ALPHA / DIGIT / - / . / _ / ~`.
  private static let unreservedCharacterSet = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
  )

  /// Percent-encodes a string according to RFC 6570 Section 3.2.2.
  public static func encode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: unreservedCharacterSet) ?? value
  }

  /// Formats a single key and value into a percent-encoded `key=value` string.
  public static func format(key: String, value: String) -> String {
    "\(encode(key))=\(encode(value))"
  }

  /// Formats a list of key-value pairs into an array of percent-encoded `key=value` strings.
  public static func format(_ matches: [(key: String, value: String?)]) -> [String] {
    matches.compactMap { key, value in
      guard let value, !value.isEmpty else { return nil }
      return format(key: key, value: value)
    }
  }

  /// Extracts a routing parameter value from `haystack` using decomposed template segments.
  ///
  /// - Parameters:
  ///   - haystack: The input string to match against.
  ///   - prefix: Initial template segments that must match, not included in the result.
  ///   - matching: Template segments that must match, included in the result.
  ///   - suffix: Trailing template segments that must match, not included in the result.
  /// - Returns: The extracted segment string if matched, or `nil`.
  public static func value(
    _ haystack: String?,
    prefix: [_RoutingSegment] = [],
    matching: [_RoutingSegment],
    suffix: [_RoutingSegment] = []
  ) -> String? {
    guard let haystack, !haystack.isEmpty else { return nil }

    var remains = Substring(haystack)
    var startOffset = 0
    var endOffset = 0

    for needle in prefix {
      guard let count = needle.matchLength(in: remains) else { return nil }
      startOffset += count
      endOffset += count
      remains = remains.dropFirst(count)
    }

    for needle in matching {
      guard let count = needle.matchLength(in: remains) else { return nil }
      endOffset += count
      remains = remains.dropFirst(count)
    }

    for needle in suffix {
      guard let count = needle.matchLength(in: remains) else { return nil }
      remains = remains.dropFirst(count)
    }

    guard remains.isEmpty, startOffset < endOffset else { return nil }

    let start = haystack.index(haystack.startIndex, offsetBy: startOffset)
    let end = haystack.index(haystack.startIndex, offsetBy: endOffset)
    return String(haystack[start..<end])
  }

  /// The character set allowed in REST URI path templates per go/client-libraries:rest-special-uri-chars: `[-_.~/0-9a-zA-Z]`.
  static let restUriAllowedCharacterSet = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/"
  )

  /// Percent-encodes a REST URI path component according to security guidelines.
  public static func encodePath(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: restUriAllowedCharacterSet) ?? value
  }

  /// Validates that a single-segment variable value does not equal `.` or `..`.
  public static func validateSingleSegment(value: String, fieldName: String) throws {
    if value == "." || value == ".." {
      throw RequestError.binding(BindingError(fieldName: fieldName, invalidValue: value))
    }
  }

  /// Validates that a multi-segment variable value does not contain path segments that are `.` or `..`.
  public static func validateMultiSegment(value: String, fieldName: String) throws {
    if value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) {
      throw RequestError.binding(BindingError(fieldName: fieldName, invalidSegments: value))
    }
  }

  /// Extracts, validates, and percent-encodes a REST URI path parameter from `haystack`
  /// using decomposed template segments per security guidelines (go/client-libraries:rest-special-uri-chars).
  ///
  /// - Parameters:
  ///   - haystack: The field value from the request.
  ///   - matching: Template segments that must match the field value.
  ///   - fieldName: The name of the field being bound.
  /// - Returns: The percent-encoded path string if matched and valid, or `nil` if `haystack` does not match the template structure.
  /// - Throws: `RequestError.binding` if any `*` segment is `.` or `..`, or if any `**` segment contains `.` or `..`.
  public static func pathValue(
    _ haystack: String?,
    matching: [_RoutingSegment],
    fieldName: String
  ) throws -> String? {
    guard let haystack, !haystack.isEmpty else { return nil }

    var remains = Substring(haystack)

    for (index, needle) in matching.enumerated() {
      switch needle {
      case .literal(let lit):
        guard remains.hasPrefix(lit) else { return nil }
        remains = remains.dropFirst(lit.count)

      case .singleWildcard:
        if remains.isEmpty || remains.hasPrefix("/") {
          return nil
        }
        let matchLength: Int
        if let slashIndex = remains.firstIndex(of: "/") {
          matchLength = remains.distance(from: remains.startIndex, to: slashIndex)
        } else {
          matchLength = remains.count
        }
        let segment = String(remains.prefix(matchLength))
        try validateSingleSegment(value: segment, fieldName: fieldName)
        remains = remains.dropFirst(matchLength)

      case .multiWildcard, .trailingMultiWildcard:
        if index == matching.count - 1 {
          if remains.isEmpty && needle == .multiWildcard {
            return nil
          }
          try validateMultiSegment(value: String(remains), fieldName: fieldName)
          remains = remains.dropFirst(remains.count)
        } else {
          let followingSegments = Array(matching[(index + 1)...])
          var foundLength: Int?
          for len in stride(from: remains.count, through: 0, by: -1) {
            let candidateSuffix = remains.dropFirst(len)
            var testRemains = candidateSuffix
            var allMatched = true
            for suffixNeedle in followingSegments {
              guard let count = suffixNeedle.matchLength(in: testRemains) else {
                allMatched = false
                break
              }
              testRemains = testRemains.dropFirst(count)
            }
            if allMatched && testRemains.isEmpty {
              foundLength = len
              break
            }
          }
          guard let matchLen = foundLength else { return nil }
          if matchLen == 0 && needle == .multiWildcard { return nil }
          let segment = String(remains.prefix(matchLen))
          try validateMultiSegment(value: segment, fieldName: fieldName)
          remains = remains.dropFirst(matchLen)
        }
      }
    }

    guard remains.isEmpty else { return nil }
    return encodePath(haystack)
  }
}
