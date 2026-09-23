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

/// A time duration type for Google APIs.
///
/// A `WKTDuration` represents a signed, fixed-length span of time represented
/// as a count of seconds and fractions of seconds at nanosecond
/// resolution. It is independent of any calendar and concepts like "day"
/// or "month". It is related to ``WKTTimestamp`` in that the
/// difference between two `WKTTimestamp` values is a `WKTDuration` and it can be added
/// or subtracted from a `WKTTimestamp`. Range is approximately +-10,000 years.
///
/// # JSON Mapping
///
/// In JSON format, the Duration type is encoded as a string rather than an
/// object, where the string ends in the suffix "s" (indicating seconds) and
/// is preceded by the number of seconds, with nanoseconds expressed as
/// fractional seconds. For example, 3 seconds with 0 nanoseconds should be
/// encoded in JSON format as "3s", while 3 seconds and 1 nanosecond should
/// be expressed in JSON format as "3.000000001s", and 3 seconds and 1
/// microsecond should be expressed in JSON format as "3.000001s".
public struct WKTDuration: Codable, Equatable, Sendable {
  /// The maximum value for the `seconds` component, approximately 10,000 years.
  public static let maxSeconds: Int64 = 315_576_000_000

  /// The minimum value for the `seconds` component, approximately -10,000 years.
  public static let minSeconds: Int64 = -maxSeconds

  /// The maximum value for the `nanos` component.
  public static let maxNanos: Int64 = nanosPerSecond - 1

  /// The minimum value for the `nanos` component.
  public static let minNanos: Int64 = -maxNanos

  public let seconds: Int64
  public let nanos: Int64

  /// Create a new instance, validating the inputs.
  ///
  /// - Parameters:
  ///   - seconds: the number of seconds in the span of time.
  ///   - nanos: the number of nanoseconds in the span of time. The sign must
  ///     match the sign in the seconds.
  ///
  /// - Throws: `WKTDurationError.mismatchedSigns` if the seconds and nanoseconds
  ///     do not have matching signs.
  /// - Throws: `WKTDurationError.outOfRange` if the seconds are outside the
  ///   [`minSeconds`, `maxSeconds`] range **or** the nanoseconds are
  ///   outside the [`minNanoseconds`, `maxNanoseconds`] range.
  public init(seconds: Int64, nanos: Int64) throws {
    if (seconds < 0 && nanos > 0) || (seconds > 0 && nanos < 0) {
      throw WKTDurationError.mismatchedSigns
    }
    if seconds < Self.minSeconds || seconds > Self.maxSeconds {
      throw WKTDurationError.outOfRange
    }
    if nanos < Self.minNanos || nanos > Self.maxNanos {
      throw WKTDurationError.outOfRange
    }
    self.seconds = seconds
    self.nanos = nanos
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    self = try WKTDuration.fromString(string: string)
  }

  public func encode(to encoder: any Encoder) throws {
    try toString().encode(to: encoder)
  }

  func toString() throws -> String {
    if nanos == 0 {
      return String("\(seconds)s")
    }
    if seconds < 0 || (seconds == 0 && nanos < 0) {
      let nanosStr = formatNanos(nanos: abs(nanos))
      return "-\(abs(seconds)).\(nanosStr)s"
    }
    let nanosStr = formatNanos(nanos: nanos)
    return "\(seconds).\(nanosStr)s"
  }

  static func fromString(string: String) throws -> Self {
    guard string.hasSuffix("s") else {
      throw WKTDurationError.invalidFormat
    }
    let withoutSuffix = string.dropLast()

    let isNegative = withoutSuffix.hasPrefix("-")
    let unsignedStr = isNegative ? withoutSuffix.dropFirst() : withoutSuffix

    if unsignedStr.isEmpty {
      throw WKTDurationError.invalidFormat
    }

    let parts = unsignedStr.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2 else {
      throw WKTDurationError.invalidFormat
    }

    let secondsStr = parts[0].isEmpty ? "0" : String(parts[0])
    guard let seconds = Int64(secondsStr) else {
      throw WKTDurationError.invalidFormat
    }

    var nanos: Int64 = 0
    if parts.count == 2 {
      let nanosStr = String(parts[1]).padding(toLength: 9, withPad: "0", startingAt: 0)
      guard let pNanos = Int64(nanosStr) else {
        throw WKTDurationError.invalidFormat
      }
      nanos = pNanos
    }

    return try self.init(
      seconds: isNegative ? -seconds : seconds, nanos: isNegative ? -nanos : nanos)
  }
}

private let nanosFormatStyle = IntegerFormatStyle<Int64>(locale: Locale(identifier: "en_US_POSIX"))
  .grouping(.never)
  .precision(.integerLength(9))

func formatNanos(nanos: Int64) -> String {
  var result = nanos.formatted(nanosFormatStyle)
  // ProtoJSON requires either millisecond, microsecond, or nanosecond precision.
  if result.hasSuffix("000") {
    result.removeLast(3)
  }
  if result.hasSuffix("000") {
    result.removeLast(3)
  }
  return result
}

// Makes `WKTDuration` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `WKTAny`.
extension WKTDuration: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Duration"
  }

  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeUrl
    }
    guard case let .string(v)? = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.invalidValueField
    }
    self = try Self.fromString(string: v)
  }

  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: WKTValue(string: try self.toString())]
  }
}

/// An error type for the `WKTDuration` initializer.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum WKTDurationError: Error {
  /// The seconds and nanosecond signs did no match.
  case mismatchedSigns
  /// The seconds or nanosecond components are out of range.
  case outOfRange
  /// Invalid format when parsing a duration from a string.
  case invalidFormat
}

/// The number of nanoseconds in a second.
let nanosPerSecond: Int64 = 1_000_000_000
