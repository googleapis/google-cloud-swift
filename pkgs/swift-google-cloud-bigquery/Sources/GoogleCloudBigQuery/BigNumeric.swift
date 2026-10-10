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

/// A `BIGNUMERIC` value: a decimal number with up to 76.76 digits of precision.
///
/// Foundation's `Decimal` holds 38 significant digits, which is enough for `NUMERIC` but not
/// for `BIGNUMERIC`. `BigNumeric` keeps the exact decimal text instead:
///
/// ```swift
/// let value = BigNumeric("578960446186580977117854925043439539266.34992332820282019728792003956564819967")
/// let parameter = QueryParameterValue.bigNumeric(value!)
/// ```
///
/// Two values are equal when they denote the same number, so `BigNumeric("1.50")` equals
/// `BigNumeric("1.5")`. ``description`` returns the text the value was created from.
public struct BigNumeric: Sendable, Hashable, Codable, LosslessStringConvertible {
  /// The decimal text, for example `"-12.345"` or `"1E-38"`.
  public let description: String

  private let number: DecimalText

  /// Creates a value from decimal text, such as `"123.456"`, `"-0.5"`, or `"1e-38"`.
  ///
  /// Returns `nil` if `description` is not a decimal number. The range of `BIGNUMERIC` is
  /// checked by the service, not here.
  public init?(_ description: String) {
    guard let number = DecimalText(description) else { return nil }
    self.description = description
    self.number = number
  }

  /// Creates a value from an integer.
  public init(_ value: some BinaryInteger) {
    self.init(String(value))!
  }

  /// Creates a value from a `Decimal`.
  ///
  /// - Precondition: `value` is not NaN.
  public init(_ value: Decimal) {
    precondition(!value.isNaN, "BigNumeric cannot represent NaN")
    self.init(value.description)!
  }

  /// The value as a `Decimal`, rounded to the 38 significant digits that `Decimal` can hold.
  public var decimalValue: Decimal {
    Decimal(string: self.number.plainText, locale: DecimalText.posixLocale) ?? 0
  }

  public static func == (lhs: BigNumeric, rhs: BigNumeric) -> Bool {
    lhs.number == rhs.number
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.number)
  }

  /// Decodes a value from its decimal text.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let value = BigNumeric(text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "\"\(text)\" is not a BIGNUMERIC value")
    }
    self = value
  }

  /// Encodes the value as its decimal text.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.description)
  }
}

/// A decimal number parsed from text, normalized so that equal numbers compare equal.
///
/// The value is `(negative ? -1 : 1) × digits × 10^exponent`. `digits` has no leading or
/// trailing zeros; zero has no digits, `exponent == 0`, and `negative == false`.
struct DecimalText: Hashable {
  static let posixLocale = Locale(identifier: "en_US_POSIX")

  var negative: Bool
  var digits: [UInt8]
  var exponent: Int

  /// Parses `[+-]digits[.digits][(e|E)[+-]digits]`. At least one mantissa digit is required.
  init?(_ text: some StringProtocol) {
    var bytes = Array(text.utf8)[...]
    var negative = false
    if let sign = bytes.first, sign == UInt8(ascii: "-") || sign == UInt8(ascii: "+") {
      negative = sign == UInt8(ascii: "-")
      bytes = bytes.dropFirst()
    }
    var digits: [UInt8] = []
    var exponent = 0
    var sawDigit = false
    var sawPoint = false
    while let byte = bytes.first {
      if let digit = Self.digit(byte) {
        sawDigit = true
        if !(digits.isEmpty && digit == 0) { digits.append(digit) }
        if sawPoint { exponent -= 1 }
      } else if byte == UInt8(ascii: "."), !sawPoint {
        sawPoint = true
      } else {
        break
      }
      bytes = bytes.dropFirst()
    }
    guard sawDigit else { return nil }
    if let marker = bytes.first, marker == UInt8(ascii: "e") || marker == UInt8(ascii: "E") {
      bytes = bytes.dropFirst()
      var exponentNegative = false
      if let sign = bytes.first, sign == UInt8(ascii: "-") || sign == UInt8(ascii: "+") {
        exponentNegative = sign == UInt8(ascii: "-")
        bytes = bytes.dropFirst()
      }
      guard !bytes.isEmpty, bytes.count <= 9 else { return nil }
      var value = 0
      for byte in bytes {
        guard let digit = Self.digit(byte) else { return nil }
        value = value * 10 + Int(digit)
      }
      exponent += exponentNegative ? -value : value
      bytes = bytes[bytes.endIndex...]
    }
    guard bytes.isEmpty else { return nil }
    while digits.last == 0 {
      digits.removeLast()
      exponent += 1
    }
    if digits.isEmpty {
      negative = false
      exponent = 0
    }
    self.negative = negative
    self.digits = digits
    self.exponent = exponent
  }

  /// The number as plain decimal text, without an exponent.
  var plainText: String {
    guard !self.digits.isEmpty else { return "0" }
    var text = self.negative ? "-" : ""
    let digitText = String(decoding: self.digits.map { $0 + UInt8(ascii: "0") }, as: UTF8.self)
    if self.exponent >= 0 {
      text += digitText + String(repeating: "0", count: self.exponent)
    } else if -self.exponent >= self.digits.count {
      text += "0." + String(repeating: "0", count: -self.exponent - self.digits.count) + digitText
    } else {
      let split = digitText.index(digitText.endIndex, offsetBy: self.exponent)
      text += digitText[..<split] + "." + digitText[split...]
    }
    return text
  }

  /// The number multiplied by `10^shift` and rounded half away from zero to an integer, or `nil`
  /// if the result does not fit in `Int64`.
  func roundedInteger(shiftedBy shift: Int) -> Int64? {
    let exponent = self.exponent + shift
    var digits = self.digits
    var roundUp = false
    if exponent < 0 {
      let keep = digits.count + exponent
      if keep < 0 {
        digits = []
      } else {
        roundUp = keep < digits.count && digits[keep] >= 5
        digits = Array(digits[..<keep])
      }
    } else {
      digits += [UInt8](repeating: 0, count: exponent)
    }
    var magnitude: UInt64 = 0
    for digit in digits {
      let (shifted, overflow1) = magnitude.multipliedReportingOverflow(by: 10)
      let (sum, overflow2) = shifted.addingReportingOverflow(UInt64(digit))
      guard !overflow1, !overflow2 else { return nil }
      magnitude = sum
    }
    if roundUp {
      let (sum, overflow) = magnitude.addingReportingOverflow(1)
      guard !overflow else { return nil }
      magnitude = sum
    }
    if self.negative {
      guard magnitude <= UInt64(Int64.max) + 1 else { return nil }
      return magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude)
    }
    guard magnitude <= UInt64(Int64.max) else { return nil }
    return Int64(magnitude)
  }

  private static func digit(_ byte: UInt8) -> UInt8? {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) ? byte - UInt8(ascii: "0") : nil
  }
}
