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

/// A `DATE` value: a calendar date with no time zone, in the proleptic Gregorian calendar.
///
/// ```swift
/// let date = BigQueryDate(year: 2024, month: 2, day: 29)
/// print(date)  // 2024-02-29
/// ```
public struct BigQueryDate: Sendable, Hashable, Comparable, Codable, LosslessStringConvertible {
  /// The year, 1 through 9999 for values BigQuery accepts.
  public var year: Int
  /// The month, 1 through 12.
  public var month: Int
  /// The day of the month, starting at 1.
  public var day: Int

  /// Creates a date. The components are not validated.
  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// Parses BigQuery's canonical form, `YYYY-[M]M-[D]D`, for example `"2024-02-29"`.
  ///
  /// Returns `nil` if the text is not a valid date.
  public init?(_ description: String) {
    var scanner = TextScanner(description)
    guard let date = scanner.date(), scanner.isAtEnd else { return nil }
    self = date
  }

  /// The date of `date` in `timeZone`.
  public init(_ date: Date, in timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
    let seconds =
      Int(date.timeIntervalSince1970.rounded(.down)) + timeZone.secondsFromGMT(for: date)
    self.init(daysSinceEpoch: seconds.floorDivided(by: 86_400))
  }

  /// The number of days between 1970-01-01 and this date.
  var daysSinceEpoch: Int {
    // Howard Hinnant's days_from_civil algorithm.
    let y = self.month <= 2 ? self.year - 1 : self.year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * ((self.month + 9) % 12) + 2) / 5 + self.day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  /// Creates the date `days` after 1970-01-01.
  init(daysSinceEpoch days: Int) {
    // Howard Hinnant's civil_from_days algorithm.
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra =
      (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let mp = (5 * dayOfYear + 2) / 153
    let month = mp < 10 ? mp + 3 : mp - 9
    self.init(
      year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month,
      day: dayOfYear - (153 * mp + 2) / 5 + 1)
  }

  /// `true` if the components denote a real calendar date.
  var isValid: Bool {
    (1...12).contains(self.month)
      && (1...Self.days(inMonth: self.month, year: self.year))
        .contains(self.day)
  }

  static func days(inMonth month: Int, year: Int) -> Int {
    switch month {
    case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }

  /// The date in BigQuery's canonical form, `YYYY-MM-DD`.
  public var description: String {
    "\(pad(self.year, 4))-\(pad(self.month, 2))-\(pad(self.day, 2))"
  }

  public static func < (lhs: BigQueryDate, rhs: BigQueryDate) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  /// Decodes a date from its canonical form.
  public init(from decoder: any Decoder) throws {
    self = try decodeLosslessString(Self.self, from: decoder, typeName: "DATE")
  }

  /// Encodes the date in its canonical form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.description)
  }
}

/// A `TIME` value: a time of day with no date and no time zone.
///
/// BigQuery stores microseconds; ``nanosecond`` can hold finer values, but the service
/// truncates them.
public struct BigQueryTime: Sendable, Hashable, Comparable, Codable, LosslessStringConvertible {
  /// The hour, 0 through 23.
  public var hour: Int
  /// The minute, 0 through 59.
  public var minute: Int
  /// The second, 0 through 59.
  public var second: Int
  /// The fraction of the second, in nanoseconds.
  public var nanosecond: Int

  /// Creates a time of day. The components are not validated.
  public init(hour: Int, minute: Int, second: Int, nanosecond: Int = 0) {
    self.hour = hour
    self.minute = minute
    self.second = second
    self.nanosecond = nanosecond
  }

  /// Parses BigQuery's canonical form, `[H]H:[M]M:[S]S[.F]`, for example `"12:41:35.220000"`.
  ///
  /// Returns `nil` if the text is not a valid time. Up to nine fractional digits are accepted.
  public init?(_ description: String) {
    var scanner = TextScanner(description)
    guard let time = scanner.time(), scanner.isAtEnd else { return nil }
    self = time
  }

  /// The time in BigQuery's canonical form: `HH:MM:SS`, followed by six fractional digits when
  /// the fraction is not zero (nine if it is not a whole number of microseconds).
  public var description: String {
    "\(pad(self.hour, 2)):\(pad(self.minute, 2)):\(pad(self.second, 2))"
      + fractionText(nanoseconds: self.nanosecond)
  }

  public static func < (lhs: BigQueryTime, rhs: BigQueryTime) -> Bool {
    (lhs.hour, lhs.minute, lhs.second, lhs.nanosecond)
      < (rhs.hour, rhs.minute, rhs.second, rhs.nanosecond)
  }

  /// Decodes a time from its canonical form.
  public init(from decoder: any Decoder) throws {
    self = try decodeLosslessString(Self.self, from: decoder, typeName: "TIME")
  }

  /// Encodes the time in its canonical form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.description)
  }
}

/// A `DATETIME` value: a date and time of day with no time zone.
public struct BigQueryDateTime: Sendable, Hashable, Comparable, Codable,
  LosslessStringConvertible
{
  /// The date part.
  public var date: BigQueryDate
  /// The time part.
  public var time: BigQueryTime

  /// Creates a date and time.
  public init(date: BigQueryDate, time: BigQueryTime) {
    self.date = date
    self.time = time
  }

  /// Parses `YYYY-[M]M-[D]D( |T)[H]H:[M]M:[S]S[.F]`, for example `"2014-08-19 05:41:35.220000"`
  /// or `"2014-08-19T05:41:35.220000"`, the form BigQuery returns in rows.
  ///
  /// Returns `nil` if the text is not a valid date and time.
  public init?(_ description: String) {
    var scanner = TextScanner(description)
    guard let date = scanner.date(), scanner.skip(" ") || scanner.skip("T"),
      let time = scanner.time(), scanner.isAtEnd
    else { return nil }
    self.init(date: date, time: time)
  }

  /// The value in BigQuery's canonical form, `YYYY-MM-DD HH:MM:SS[.FFFFFF]`.
  public var description: String {
    "\(self.date) \(self.time)"
  }

  public static func < (lhs: BigQueryDateTime, rhs: BigQueryDateTime) -> Bool {
    (lhs.date, lhs.time) < (rhs.date, rhs.time)
  }

  /// Decodes a value from its canonical form.
  public init(from decoder: any Decoder) throws {
    self = try decodeLosslessString(Self.self, from: decoder, typeName: "DATETIME")
  }

  /// Encodes the value in its canonical form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.description)
  }
}

/// Decodes a single string and parses it with `LosslessStringConvertible`.
func decodeLosslessString<T: LosslessStringConvertible>(
  _ type: T.Type, from decoder: any Decoder, typeName: String
) throws -> T {
  let container = try decoder.singleValueContainer()
  let text = try container.decode(String.self)
  guard let value = T(text) else {
    throw DecodingError.dataCorruptedError(
      in: container, debugDescription: "\"\(text)\" is not a valid \(typeName) value")
  }
  return value
}

// MARK: - Timestamps

/// Timestamp conversions. BigQuery timestamps are microseconds since the Unix epoch, in UTC.
enum Timestamp {
  /// The microseconds since the epoch nearest to `date`.
  static func micros(from date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
  }

  /// The date `micros` microseconds after the epoch.
  static func date(fromMicros micros: Int64) -> Date {
    let seconds = micros.floorDivided(by: 1_000_000)
    let fraction = micros - seconds * 1_000_000
    return Date(timeIntervalSince1970: Double(seconds) + Double(fraction) / 1_000_000)
  }

  /// Formats `micros` as `YYYY-MM-DD<separator>HH:MM:SS.FFFFFF<suffix>` in UTC.
  static func format(micros: Int64, separator: String, suffix: String) -> String {
    let seconds = micros.floorDivided(by: 1_000_000)
    let fraction = Int(micros - seconds * 1_000_000)
    let days = Int(seconds.floorDivided(by: 86_400))
    let secondOfDay = Int(seconds - Int64(days) * 86_400)
    let date = BigQueryDate(daysSinceEpoch: days)
    return "\(date)\(separator)\(pad(secondOfDay / 3600, 2)):\(pad(secondOfDay / 60 % 60, 2)):"
      + "\(pad(secondOfDay % 60, 2)).\(pad(fraction, 6))\(suffix)"
  }

  /// `true` if `text` is a timestamp literal BigQuery accepts as a query parameter:
  /// `YYYY-[M]M-[D]D [H]H:[M]M[:[S]S[.F]][zone]`, with up to 12 fractional digits and an
  /// optional `Z`, `UTC`, `+HH`, `+HHMM`, or `+HH:MM` zone.
  static func isValidParameterText(_ text: String) -> Bool {
    var scanner = TextScanner(text)
    guard scanner.date() != nil, scanner.skip(" "),
      let hour = scanner.integer(digits: 1...2), hour < 24, scanner.skip(":"),
      let minute = scanner.integer(digits: 1...2), minute < 60
    else { return false }
    if scanner.skip(":") {
      guard let second = scanner.integer(digits: 1...2), second < 60 else { return false }
      if scanner.skip(".") {
        guard scanner.digits(1...12) != nil else { return false }
      }
    }
    if scanner.skip("Z") || scanner.skip(" UTC") || scanner.skip("UTC") {
      return scanner.isAtEnd
    }
    if scanner.skip("+") || scanner.skip("-") {
      // `HH`, `HHMM`, or `HH:MM`.
      guard let zone = scanner.digits(2...4), zone.count != 3,
        zone[0] * 10 + zone[1] < 24
      else { return false }
      if zone.count == 4 {
        return zone[2] < 6 && scanner.isAtEnd
      }
      if scanner.skip(":") {
        guard let minutes = scanner.integer(digits: 2...2), minutes < 60 else { return false }
      }
    }
    return scanner.isAtEnd
  }
}

// MARK: - Helpers

/// Formats `value` with at least `width` digits, padding with zeros. Negative values keep
/// their sign in front.
func pad(_ value: Int, _ width: Int) -> String {
  let digits = String(value.magnitude)
  let padding = String(repeating: "0", count: max(0, width - digits.count))
  return (value < 0 ? "-" : "") + padding + digits
}

/// `""` for a zero fraction, otherwise `.FFFFFF` (or `.FFFFFFFFF` below a microsecond).
func fractionText(nanoseconds: Int) -> String {
  guard nanoseconds != 0 else { return "" }
  return nanoseconds % 1000 == 0 ? "." + pad(nanoseconds / 1000, 6) : "." + pad(nanoseconds, 9)
}

extension BinaryInteger {
  /// Division rounding toward negative infinity.
  func floorDivided(by divisor: Self) -> Self {
    let quotient = self / divisor
    return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? quotient - 1 : quotient
  }
}

/// A minimal scanner over ASCII text, for parsing BigQuery's literal formats.
struct TextScanner {
  private var bytes: ArraySlice<UInt8>

  init(_ text: some StringProtocol) {
    self.bytes = Array(text.utf8)[...]
  }

  var isAtEnd: Bool { self.bytes.isEmpty }

  /// Consumes `literal` if the remaining text starts with it.
  mutating func skip(_ literal: String) -> Bool {
    let literal = Array(literal.utf8)
    guard self.bytes.starts(with: literal) else { return false }
    self.bytes = self.bytes.dropFirst(literal.count)
    return true
  }

  /// Consumes a run of decimal digits whose length is in `count`, and returns them.
  mutating func digits(_ count: ClosedRange<Int>) -> [UInt8]? {
    let run = self.bytes.prefix { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    guard count.contains(run.count) else { return nil }
    self.bytes = self.bytes.dropFirst(run.count)
    return run.map { $0 - UInt8(ascii: "0") }
  }

  /// Consumes a non-negative integer of `digits` digits.
  mutating func integer(digits count: ClosedRange<Int>) -> Int? {
    self.digits(count)?.reduce(0) { $0 * 10 + Int($1) }
  }

  /// Consumes `YYYY-[M]M-[D]D` and validates it.
  mutating func date() -> BigQueryDate? {
    guard let year = self.integer(digits: 4...4), self.skip("-"),
      let month = self.integer(digits: 1...2), self.skip("-"),
      let day = self.integer(digits: 1...2)
    else { return nil }
    let date = BigQueryDate(year: year, month: month, day: day)
    return date.isValid ? date : nil
  }

  /// Consumes `[H]H:[M]M:[S]S[.F]` (up to nine fractional digits) and validates it.
  mutating func time() -> BigQueryTime? {
    guard let hour = self.integer(digits: 1...2), hour < 24, self.skip(":"),
      let minute = self.integer(digits: 1...2), minute < 60, self.skip(":"),
      let second = self.integer(digits: 1...2), second < 60
    else { return nil }
    var nanosecond = 0
    if self.skip(".") {
      guard let fraction = self.digits(1...9) else { return nil }
      nanosecond = (fraction + [UInt8](repeating: 0, count: 9 - fraction.count))
        .reduce(0) { $0 * 10 + Int($1) }
    }
    return BigQueryTime(hour: hour, minute: minute, second: second, nanosecond: nanosecond)
  }
}
