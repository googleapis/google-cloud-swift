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

import ArgumentParser
import Foundation

/// Helper to parse human-readable size strings (e.g. "128KiB", "1MiB", "10MB", "0") into byte counts.
enum SizeParser {
  /// Parses size strings such as "128KiB", "1MiB", "10MB", "1024", "0" into bytes.
  static func parse(_ input: String) throws -> Int {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw ValidationError("Size cannot be empty")
    }

    if let direct = Int(trimmed) {
      guard direct >= 0 else {
        throw ValidationError("Size cannot be negative: \(input)")
      }
      return direct
    }

    let units: [(suffix: String, multiplier: Int)] = [
      ("tib", 1024 * 1024 * 1024 * 1024),
      ("tb", 1000 * 1000 * 1000 * 1000),
      ("gib", 1024 * 1024 * 1024),
      ("gb", 1000 * 1000 * 1000),
      ("g", 1024 * 1024 * 1024),
      ("mib", 1024 * 1024),
      ("mb", 1000 * 1000),
      ("m", 1024 * 1024),
      ("kib", 1024),
      ("kb", 1000),
      ("k", 1024),
      ("b", 1),
    ]

    let lower = trimmed.lowercased()
    for unit in units {
      if lower.hasSuffix(unit.suffix) {
        let numericPart = String(trimmed.dropLast(unit.suffix.count))
          .trimmingCharacters(in: .whitespaces)
        if let value = Double(numericPart) {
          guard value >= 0 else {
            throw ValidationError("Size cannot be negative: \(input)")
          }
          return Int(value * Double(unit.multiplier))
        }
      }
    }

    throw ValidationError(
      "Invalid size format: '\(input)'. Expected values like '128KiB', '1MiB', '10MB', etc.")
  }
}
