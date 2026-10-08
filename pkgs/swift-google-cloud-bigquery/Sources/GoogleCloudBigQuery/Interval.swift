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

/// An `INTERVAL` value: a number of months, a number of days, and a time duration.
///
/// The three parts are independent, as in BigQuery: one month is not a fixed number of days,
/// and one day is not always 24 hours.
///
/// ```swift
/// let interval = Interval(years: 1, months: 2, days: -3, hours: 4)
/// print(interval)  // 1-2 -3 4:0:0
/// ```
public struct Interval: Sendable, Hashable, Codable, LosslessStringConvertible {
  /// The number of months, including whole years (`years × 12 + months`).
  public var months: Int
  /// The number of days.
  public var days: Int
  /// The time part.
  public var time: Duration

  /// Creates an interval from its three parts.
  public init(months: Int, days: Int, time: Duration) {
    self.months = months
    self.days = days
    self.time = time
  }

  /// Creates an interval from calendar and clock components. Components may be negative.
  public init(
    years: Int = 0, months: Int = 0, days: Int = 0, hours: Int64 = 0, minutes: Int64 = 0,
    seconds: Int64 = 0, nanoseconds: Int64 = 0
  ) {
    self.init(
      months: years * 12 + months, days: days,
      time: .seconds(hours * 3600 + minutes * 60 + seconds) + .nanoseconds(nanoseconds))
  }

  /// Parses an interval in BigQuery's canonical form, `[-]Y-M [-]D [-]H:M:S[.F]` (for example
  /// `"1-2 -3 4:05:06.789"`), or in ISO 8601 duration form (for example `"P1Y2M-3DT4H5M6.789S"`).
  ///
  /// Returns `nil` if the text is in neither form.
  public init?(_ description: String) {
    guard let value = Self.parseCanonical(description) ?? Self.parseISO8601(description) else {
      return nil
    }
    self = value
  }

  /// The interval in BigQuery's canonical form, `[-]Y-M [-]D [-]H:M:S[.F]`.
  ///
  /// The year-month part is normalized, so `Interval(months: 14)` prints as `1-2 0 0:0:0`.
  public var description: String {
    let monthSign = self.months < 0 ? "-" : ""
    let negativeTime = self.time < .zero
    let magnitude = negativeTime ? .zero - self.time : self.time
    let (seconds, attoseconds) = magnitude.components
    let nanoseconds = Int(attoseconds / 1_000_000_000)
    return "\(monthSign)\(self.months.magnitude / 12)-\(self.months.magnitude % 12) \(self.days) "
      + "\(negativeTime ? "-" : "")\(seconds / 3600):\(seconds / 60 % 60):\(seconds % 60)"
      + fractionText(nanoseconds: nanoseconds)
  }

  /// Decodes an interval from its canonical or ISO 8601 form.
  public init(from decoder: any Decoder) throws {
    self = try decodeLosslessString(Self.self, from: decoder, typeName: "INTERVAL")
  }

  /// Encodes the interval in its canonical form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.description)
  }

  /// Parses `[sign]Y-M [sign]D [sign]H:M:S[.F]`.
  private static func parseCanonical(_ text: String) -> Interval? {
    var scanner = TextScanner(text)
    let yearMonthSign = scanner.sign()
    guard let years = scanner.integer(digits: 1...9), scanner.skip("-"),
      let months = scanner.integer(digits: 1...9), scanner.skip(" ")
    else { return nil }
    let daySign = scanner.sign()
    guard let days = scanner.integer(digits: 1...9), scanner.skip(" ") else { return nil }
    let timeSign = Int64(scanner.sign())
    guard let hours = scanner.integer(digits: 1...12), scanner.skip(":"),
      let minutes = scanner.integer(digits: 1...12), scanner.skip(":"),
      let seconds = scanner.integer(digits: 1...12)
    else { return nil }
    var nanoseconds: Int64 = 0
    if scanner.skip(".") {
      guard let fraction = scanner.nanoseconds() else { return nil }
      nanoseconds = fraction
    }
    guard scanner.isAtEnd else { return nil }
    return Interval(
      years: yearMonthSign * years, months: yearMonthSign * months, days: daySign * days,
      hours: timeSign * Int64(hours), minutes: timeSign * Int64(minutes),
      seconds: timeSign * Int64(seconds), nanoseconds: timeSign * nanoseconds)
  }

  /// Parses `[-]P[nY][nM][nW][nD][T[nH][nM][n[.f]S]]`, where each `n` may carry its own sign.
  private static func parseISO8601(_ text: String) -> Interval? {
    var scanner = TextScanner(text)
    let overall = scanner.sign()
    guard scanner.skip("P") else { return nil }
    var result = Interval(months: 0, days: 0, time: .zero)
    var inTime = false
    var sawComponent = false
    while !scanner.isAtEnd {
      if !inTime, scanner.skip("T") {
        inTime = true
        continue
      }
      let sign = scanner.sign()
      guard let value = scanner.integer(digits: 1...12) else { return nil }
      var nanoseconds: Int64 = 0
      if inTime, scanner.skip(".") {
        guard let fraction = scanner.nanoseconds(), scanner.skip("S") else { return nil }
        nanoseconds = fraction
        result.time += .seconds(Int64(sign * value)) + .nanoseconds(Int64(sign) * nanoseconds)
      } else if !inTime, scanner.skip("Y") {
        result.months += sign * value * 12
      } else if !inTime, scanner.skip("M") {
        result.months += sign * value
      } else if !inTime, scanner.skip("W") {
        result.days += sign * value * 7
      } else if !inTime, scanner.skip("D") {
        result.days += sign * value
      } else if inTime, scanner.skip("H") {
        result.time += .seconds(Int64(sign * value) * 3600)
      } else if inTime, scanner.skip("M") {
        result.time += .seconds(Int64(sign * value) * 60)
      } else if inTime, scanner.skip("S") {
        result.time += .seconds(Int64(sign * value))
      } else {
        return nil
      }
      sawComponent = true
    }
    guard sawComponent else { return nil }
    if overall < 0 {
      result = Interval(months: -result.months, days: -result.days, time: .zero - result.time)
    }
    return result
  }
}

extension TextScanner {
  /// Consumes an optional `+` or `-` and returns `1` or `-1`.
  fileprivate mutating func sign() -> Int {
    if self.skip("-") { return -1 }
    _ = self.skip("+")
    return 1
  }

  /// Consumes 1 to 9 fractional digits and returns them as nanoseconds.
  fileprivate mutating func nanoseconds() -> Int64? {
    guard let fraction = self.digits(1...9) else { return nil }
    return (fraction + [UInt8](repeating: 0, count: 9 - fraction.count))
      .reduce(Int64(0)) { $0 * 10 + Int64($1) }
  }
}
