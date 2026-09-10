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

let secondsPerDay: Int64 = 86_400
let secondsPerHour: Int64 = 3_600
let secondsPerMinute: Int64 = 60
let daysFrom0000To1970: Int64 = 719_527
let daysFrom0000Mar01To1970Jan01: Int64 = 719_468
let daysIn400Years: Int64 = 146_097
let daysIn100Years: Int64 = 36_524
let daysIn4Years: Int64 = 1_460
let daysInYear: Int64 = 365
let yearsIn400Cycle: Int64 = 400
let daysIn5MonthCycle: Int64 = 153  // both March-July and August-December
let monthsInCycle: Int64 = 5
let rfc3339DateTimeLength = 19

/// The Google APIs representation for a point in time.
///
/// A Timestamp represents a point in time independent of any time zone or local
/// calendar, encoded as a count of seconds and fractions of seconds at
/// nanosecond resolution. The count is relative to an epoch at UTC midnight on
/// January 1, 1970, in the proleptic Gregorian calendar which extends the
/// Gregorian calendar backwards to year one.
///
/// All minutes are 60 seconds long. Leap seconds are "smeared" so that no leap
/// second table is needed for interpretation, using a [24-hour linear
/// smear](https://developers.google.com/time/smear).
///
/// The range is from 0001-01-01T00:00:00Z to 9999-12-31T23:59:59.999999999Z. By
/// restricting to that range, we ensure that we can convert to and from
/// [RFC 3339](https://www.ietf.org/rfc/rfc3339.txt) date strings.
///
/// # JSON Mapping
///
/// In JSON format, the Timestamp type is encoded as a string in the
/// [RFC 3339](https://www.ietf.org/rfc/rfc3339.txt) format. That is, the
/// format is "{year}-{month}-{day}T{hour}:{min}:{sec}[.{frac_sec}]Z"
/// where {year} is always expressed using four digits while {month}, {day},
/// {hour}, {min}, and {sec} are zero-padded to two digits each. The fractional
/// seconds, which can go up to 9 digits (i.e. up to 1 nanosecond resolution),
/// are optional. The "Z" suffix indicates the timezone ("UTC"); the timezone
/// is required. A ProtoJSON serializer should always use UTC (as indicated by
/// "Z") when printing the Timestamp type and a ProtoJSON parser should be
/// able to accept both UTC and other timezones (as indicated by an offset).
///
/// For example, "2017-01-15T01:30:15.01Z" encodes 15.01 seconds past 01:30 UTC on January 15, 2017.
public struct Timestamp: Codable, Equatable, Sendable {
  /// The maximum value for the `seconds` component.
  ///
  /// Corresponds to 0001-01-01T00:00:00Z
  static public let minSeconds: Int64 = -62_135_596_800

  /// The minimum value for the `seconds` component, approximately  years.
  ///
  /// Corresponds to 9999-12-31T23:59:59Z
  static public let maxSeconds: Int64 = 253_402_300_799

  /// The maximum value for the `nanos` component.
  static public let maxNanos: Int64 = nanosPerSecond - 1

  /// The minimum value for the `nanos` component.
  static public let minNanos: Int64 = 0

  /// Represents seconds of UTC time since Unix epoch 1970-01-01T00:00:00Z. Must
  /// be between -62135596800 and 253402300799 inclusive (which corresponds to
  /// 0001-01-01T00:00:00Z to 9999-12-31T23:59:59Z).
  public let seconds: Int64

  /// Non-negative fractions of a second at nanosecond resolution. This field is
  /// the nanosecond portion of the duration, not an alternative to seconds.
  /// Negative second values with fractions must still have non-negative nanos
  /// values that count forward in time. Must be between 0 and 999,999,999
  /// inclusive.
  public let nanos: Int64

  /// Create a new instance, validating the inputs.
  ///
  /// - Parameters:
  ///   - seconds: the number of seconds from the epoch.
  ///   - nanos: the number of nanoseconds counting forward in time. Must be >= 0.
  ///
  /// - Throws: `TimestampError.outOfRange` if the seconds are outside the
  ///   [`minSeconds`, `maxSeconds`] range **or** the nanoseconds are
  ///   outside the [`minNanoseconds`, `maxNanoseconds`] range.
  public init(seconds: Int64, nanos: Int64) throws {
    if seconds < Self.minSeconds || seconds > Self.maxSeconds {
      throw TimestampError.outOfRange
    }
    if nanos < Self.minNanos || nanos > Self.maxNanos {
      throw TimestampError.outOfRange
    }
    self.seconds = seconds
    self.nanos = nanos
  }

  public init(from encoder: any Decoder) throws {
    let rfc3339 = try String(from: encoder)
    self = try Self.init(fromString: rfc3339)
  }

  public func encode(to encoder: any Encoder) throws {
    let formatted = toString()
    try formatted.encode(to: encoder)
  }

  init(fromString: String) throws {
    // RFC 3339 format: {year}-{month}-{day}T{hour}:{min}:{sec}[.{frac_sec}](Z|+HH:MM|-HH:MM)
    // Example: 2017-01-15T01:30:15.01Z

    // Fixed layout for the date/time part is YYYY-MM-DDTHH:MM:SS (19 characters)
    guard fromString.count >= rfc3339DateTimeLength,
      fromString[fromString.index(fromString.startIndex, offsetBy: 10)] == "T"
    else { throw TimestampError.invalidFormat }

    let dateStr = fromString.prefix(10)
    let timeStartIndex = fromString.index(fromString.startIndex, offsetBy: 11)
    let timeEndIndex = fromString.index(timeStartIndex, offsetBy: 8)
    let timeStr = fromString[timeStartIndex..<timeEndIndex]

    let daysInSeconds = try Self.parseDateSegment(dateStr)
    let timeInSeconds = try Self.parseTimeSegment(timeStr)
    var baseSeconds = daysInSeconds + timeInSeconds

    var pos = fromString.index(fromString.startIndex, offsetBy: rfc3339DateTimeLength)
    let nanos = Self.parseNanosSegment(fromString, at: &pos)
    let offsetSeconds = try Self.parseTimezoneOffset(fromString, at: pos)

    baseSeconds -= offsetSeconds

    try self.init(seconds: baseSeconds, nanos: nanos)
  }

  private static func parseDateSegment(_ segment: Substring) throws -> Int64 {
    // segment is YYYY-MM-DD
    guard segment.count == 10,
      segment[segment.index(segment.startIndex, offsetBy: 4)] == "-",
      segment[segment.index(segment.startIndex, offsetBy: 7)] == "-"
    else { throw TimestampError.invalidFormat }
    let yearStr = segment[segment.startIndex..<segment.index(segment.startIndex, offsetBy: 4)]
    let monthStr = segment[
      segment.index(
        segment.startIndex, offsetBy: 5)..<segment.index(
          segment.startIndex, offsetBy: 7)]
    let dayStr = segment[
      segment.index(
        segment.startIndex, offsetBy: 8)..<segment.index(
          segment.startIndex, offsetBy: 10)]

    guard let year = Int(yearStr),
      let month = Int(monthStr),
      let day = Int(dayStr)
    else {
      throw TimestampError.invalidFormat
    }

    // Basic range validation
    guard month >= 1 && month <= 12 else {
      throw TimestampError.invalidFormat
    }
    let isleap = (year % 400 == 0) || ((year % 100 != 0) && (year % 4 == 0))
    let daysInMonth: [Int] = [0, 31, isleap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard day >= 1 && day <= daysInMonth[month] else {
      throw TimestampError.invalidFormat
    }

    // Epoch calculation using the mathematical approach (inspired by SwiftProtobuf)
    // Days in months for a non-leap year
    let mdayStart: [Int] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    var yday = Int64(mdayStart[month - 1])
    if isleap && (month > 2) { yday += 1 }
    yday += Int64(day - 1)

    var daysSinceEpoch = yday
    // Leap years are every 4 years. Multiples of 100 are not leap years. Multiples of 400 are.
    daysSinceEpoch += Int64(365 * year)
    daysSinceEpoch += Int64((year - 1) / 4)
    daysSinceEpoch -= Int64((year - 1) / 100)
    daysSinceEpoch += Int64((year - 1) / 400)
    // Subtract days from 0000-01-01 to 1970-01-01
    daysSinceEpoch -= daysFrom0000To1970

    return daysSinceEpoch * secondsPerDay
  }

  private static func parseTimeSegment(_ segment: Substring) throws -> Int64 {
    // segment is HH:MM:SS
    guard segment.count == 8,
      segment[segment.index(segment.startIndex, offsetBy: 2)] == ":",
      segment[segment.index(segment.startIndex, offsetBy: 5)] == ":"
    else { throw TimestampError.invalidFormat }
    let hourStr = segment[segment.startIndex..<segment.index(segment.startIndex, offsetBy: 2)]
    let minuteStr = segment[
      segment.index(
        segment.startIndex, offsetBy: 3)..<segment.index(
          segment.startIndex, offsetBy: 5)]
    let secondStr = segment[
      segment.index(
        segment.startIndex, offsetBy: 6)..<segment.index(
          segment.startIndex, offsetBy: 8)]

    guard let hour = Int(hourStr),
      let minute = Int(minuteStr),
      let second = Int(secondStr)
    else {
      throw TimestampError.invalidFormat
    }

    // Basic range validation
    guard hour >= 0 && hour <= 23,
      minute >= 0 && minute <= 59,
      second >= 0 && second <= 61
    else {  // Allow leap seconds (60, 61)
      throw TimestampError.invalidFormat
    }

    return Int64(hour) * secondsPerHour + Int64(minute) * secondsPerMinute + Int64(second)
  }

  private static func parseNanosSegment(_ rfc3339: String, at pos: inout String.Index) -> Int64 {
    guard pos < rfc3339.endIndex && rfc3339[pos] == "." else {
      return 0
    }
    pos = rfc3339.index(after: pos)
    let fracStart = pos
    while pos < rfc3339.endIndex && rfc3339[pos].isNumber {
      pos = rfc3339.index(after: pos)
    }
    let fracStr = String(rfc3339[fracStart..<pos])
    if fracStr.isEmpty {
      return 0
    }
    let paddedFrac = fracStr.padding(toLength: 9, withPad: "0", startingAt: 0).prefix(9)
    return Int64(paddedFrac) ?? 0
  }

  private static func parseTimezoneOffset(_ rfc3339: String, at pos: String.Index) throws -> Int64 {
    guard pos < rfc3339.endIndex else {
      // RFC 3339 requires a timezone suffix.
      throw TimestampError.invalidFormat
    }
    let suffix = rfc3339[pos..<rfc3339.endIndex]
    if suffix == "Z" {
      return 0
    }

    if suffix.hasPrefix("+") || suffix.hasPrefix("-") {
      let isNegative = suffix.hasPrefix("-")
      let offsetPart = suffix.dropFirst()
      // Formats can be HH:MM or HHMM
      let hhmm = offsetPart.replacingOccurrences(of: ":", with: "")
      guard (hhmm.count == 4 || hhmm.count == 2),
        let offsetH = Int(hhmm.prefix(2)),
        offsetH < 24
      else {
        throw TimestampError.invalidFormat
      }
      let offsetM = hhmm.count == 4 ? (Int(hhmm.suffix(2)) ?? 0) : 0
      guard offsetM < 60 else {
        throw TimestampError.invalidFormat
      }

      let totalOffsetSeconds = Int64(offsetH) * secondsPerHour + Int64(offsetM) * secondsPerMinute
      return isNegative ? -totalOffsetSeconds : totalOffsetSeconds
    }

    throw TimestampError.invalidFormat
  }

  func toString() -> String {
    var seconds = self.seconds
    var days = seconds / secondsPerDay
    seconds %= secondsPerDay
    if seconds < 0 {
      seconds += secondsPerDay
      days -= 1
    }

    // Convert days since 1970-01-01 to YMD
    // Using algorithm from https://howardhinnant.github.io/date_algorithms.html
    let z = days + daysFrom0000Mar01To1970Jan01
    let era = (z >= 0 ? z : z - (daysIn400Years - 1)) / daysIn400Years
    let doe = z - era * daysIn400Years
    let yoe =
      (doe - doe / daysIn4Years + doe / daysIn100Years - doe / (daysIn400Years - 1)) / daysInYear
    let y = yoe + era * yearsIn400Cycle
    let doy = doe - (daysInYear * yoe + yoe / 4 - yoe / 100)
    let mp = (monthsInCycle * doy + 2) / daysIn5MonthCycle
    let d = doy - (daysIn5MonthCycle * mp + 2) / monthsInCycle + 1
    let m = mp < 10 ? mp + 3 : mp - 9

    let year = Int(y + (m <= 2 ? 1 : 0))
    let month = Int(m)
    let day = Int(d)

    let hour = Int(seconds / secondsPerHour)
    let minute = Int((seconds % secondsPerHour) / secondsPerMinute)
    let second = Int(seconds % secondsPerMinute)

    let formatted = String(
      format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
    if self.nanos == 0 {
      return "\(formatted)Z"
    }
    let frac = formatNanos(nanos: self.nanos)
    return "\(formatted).\(frac)Z"
  }
}

// Makes `Timestamp` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `Any`.
extension Timestamp: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Timestamp"
  }

  public init(fromAny any: `Any`) throws {
    if Self._anyTypeUrl != any._type {
      throw AnyError.mismatchedTypeUrl
    }
    guard case let .string(v)? = any.fields[`Any`.valueField] else {
      throw AnyError.invalidValueField
    }
    self = try Self(fromString: v)
  }

  public func _pack() throws -> Struct {
    return [`Any`.valueField: Value(string: self.toString())]
  }
}

/// An error type for the `Timestamp` initializer.
public enum TimestampError: Error {
  /// The seconds or nanosecond components are out of range.
  case outOfRange
  /// Invalid format when parsing a timestamp from a string.
  case invalidFormat
}
