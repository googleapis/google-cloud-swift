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
@_spi(GoogleCloudInternal) import GoogleCloudGax

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
}
