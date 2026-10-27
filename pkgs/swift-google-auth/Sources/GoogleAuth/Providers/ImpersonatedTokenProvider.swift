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

/// A `TokenProvider` that exchanges a source credential's authentication headers for a short-lived
/// OAuth 2.0 access token impersonating a target Google Cloud service account.
///
/// Calls the IAM Service Account Credentials API endpoint:
/// `POST https://iamcredentials.{universeDomain}/v1/projects/-/serviceAccounts/{targetPrincipal}:generateAccessToken`
///
/// - SeeAlso: [AIP-4110: Application Default Credentials](https://google.aip.dev/auth/4110)
/// - SeeAlso: [Method: projects.serviceAccounts.generateAccessToken](https://cloud.google.com/iam/docs/reference/credentials/rest/v1/projects.serviceAccounts/generateAccessToken)
struct ImpersonatedTokenProvider: TokenProvider, Sendable {
  /// The underlying source credentials used to authenticate the IAM `:generateAccessToken` request.
  let sourceCredentials: any CredentialsProvider

  /// The full IAM Credentials `:generateAccessToken` endpoint URL.
  let iamEndpointURL: URL

  /// The OAuth 2.0 scopes requested for the impersonated access token.
  let scopes: [String]

  /// Normalized service account resource names (`projects/-/serviceAccounts/{email}`) in the delegation chain.
  let delegates: [String]

  /// Desired lifetime of the impersonated access token formatted as a ProtoJSON duration string (e.g. `"3600s"`).
  let lifetime: String

  /// Retry policy configuration for transient IAM API errors.
  let retryConfiguration: RetryConfiguration

  /// HTTP client used to execute the `:generateAccessToken` request.
  let httpClient: AuthHTTPClient

  @concurrent
  func fetchToken() async throws -> Token {
    let sourceAuthHeaders: AuthHeaders
    do {
      sourceAuthHeaders = try await sourceCredentials.headers()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: "Could not obtain source credentials token for service account impersonation.",
        underlyingError: error
      )
    }

    var headersDict: [String: String] = [:]
    for (name, value) in sourceAuthHeaders {
      headersDict[name] = value
    }
    let requestHeaders = headersDict

    let requestBody = IAMGenerateAccessTokenRequest(
      scope: scopes,
      delegates: delegates.isEmpty ? nil : delegates,
      lifetime: lifetime
    )

    let response: IAMGenerateAccessTokenResponse
    do {
      response = try await RetryEngine.retry(
        configuration: retryConfiguration,
        isRetryable: AuthHTTPError.isRetryable
      ) {
        try await httpClient.post(
          url: iamEndpointURL,
          body: requestBody,
          headers: requestHeaders
        )
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: "Could not generate impersonated service account access token.",
        underlyingError: error
      )
    }

    guard let expirationDate = Self.parseRFC3339Date(response.expireTime) else {
      throw CredentialsError.cannotFetchToken(
        message: "Could not generate impersonated service account access token.",
        underlyingError: AuthHTTPError.decodingError(
          error: CredentialsError.parseError(
            "Invalid expireTime RFC 3339 timestamp in IAM generateAccessToken response: '\(response.expireTime)'"
          )
        )
      )
    }

    return Token(
      accessToken: response.accessToken,
      tokenType: "Bearer",
      expirationDate: expirationDate
    )
  }

  /// Parses an RFC 3339 timestamp string (with or without fractional seconds) into a `Date`.
  static func parseRFC3339Date(_ string: String) -> Date? {
    // Fixed layout for the date/time part is YYYY-MM-DDTHH:MM:SS (19 characters).
    let bytes = Array(string.utf8)
    guard bytes.count >= 20,
      bytes[4] == UInt8(ascii: "-"),
      bytes[7] == UInt8(ascii: "-"),
      bytes[10] == UInt8(ascii: "T") || bytes[10] == UInt8(ascii: "t"),
      bytes[13] == UInt8(ascii: ":"),
      bytes[16] == UInt8(ascii: ":")
    else {
      return nil
    }

    guard let year = parseDigits(bytes, range: 0..<4),
      let month = parseDigits(bytes, range: 5..<7),
      let day = parseDigits(bytes, range: 8..<10),
      let hour = parseDigits(bytes, range: 11..<13),
      let minute = parseDigits(bytes, range: 14..<16),
      let second = parseDigits(bytes, range: 17..<19)
    else {
      return nil
    }

    guard year >= 1970,
      (1...12).contains(month),
      (0...23).contains(hour),
      (0...59).contains(minute),
      (0...60).contains(second)
    else {
      return nil
    }

    let isLeap = (year % 400 == 0) || ((year % 100 != 0) && (year % 4 == 0))
    let daysInMonths = [0, 31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard (1...daysInMonths[month]).contains(day) else {
      return nil
    }

    var idx = 19
    var fractionalSeconds: Double = 0
    if idx < bytes.count && bytes[idx] == UInt8(ascii: ".") {
      idx += 1
      let fracStart = idx
      while idx < bytes.count && bytes[idx] >= UInt8(ascii: "0") && bytes[idx] <= UInt8(ascii: "9")
      {
        idx += 1
      }
      let fracCount = idx - fracStart
      guard fracCount >= 1 else {
        return nil
      }
      var fracValue: Int64 = 0
      var divisor: Double = 1
      let parseEnd = min(idx, fracStart + 9)
      for i in fracStart..<parseEnd {
        fracValue = fracValue * 10 + Int64(bytes[i] - UInt8(ascii: "0"))
        divisor *= 10
      }
      fractionalSeconds = Double(fracValue) / divisor
    }

    guard idx < bytes.count else {
      return nil
    }

    var tzOffsetSeconds: Int64 = 0
    if bytes[idx] == UInt8(ascii: "Z") || bytes[idx] == UInt8(ascii: "z") {
      guard idx + 1 == bytes.count else { return nil }
    } else if bytes[idx] == UInt8(ascii: "+") || bytes[idx] == UInt8(ascii: "-") {
      let isNegative = bytes[idx] == UInt8(ascii: "-")
      idx += 1
      guard idx + 5 == bytes.count,
        bytes[idx + 2] == UInt8(ascii: ":"),
        let tzHour = parseDigits(bytes, range: idx..<(idx + 2)),
        let tzMin = parseDigits(bytes, range: (idx + 3)..<(idx + 5)),
        tzHour < 24,
        tzMin < 60
      else {
        return nil
      }
      let totalOffset = Int64(tzHour) * 3600 + Int64(tzMin) * 60
      tzOffsetSeconds = isNegative ? -totalOffset : totalOffset
    } else {
      return nil
    }

    let mdayStart = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    var yday = Int64(mdayStart[month - 1])
    if isLeap && month > 2 { yday += 1 }
    yday += Int64(day - 1)

    var daysSinceEpoch = yday
    daysSinceEpoch += Int64(365 * year)
    daysSinceEpoch += Int64((year - 1) / 4)
    daysSinceEpoch -= Int64((year - 1) / 100)
    daysSinceEpoch += Int64((year - 1) / 400)
    daysSinceEpoch -= 719_527  // days from 0000-01-01 to 1970-01-01

    let totalSeconds =
      daysSinceEpoch * 86_400
      + Int64(hour) * 3600
      + Int64(minute) * 60
      + Int64(second)
      - tzOffsetSeconds

    return Date(timeIntervalSince1970: TimeInterval(totalSeconds) + fractionalSeconds)
  }

  private static func parseDigits(_ bytes: [UInt8], range: Range<Int>) -> Int? {
    var result = 0
    for i in range {
      let b = bytes[i]
      guard b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") else {
        return nil
      }
      result = result * 10 + Int(b - UInt8(ascii: "0"))
    }
    return result
  }
}

/// The JSON request body sent to the IAM Service Account Credentials `:generateAccessToken` endpoint.
///
/// - SeeAlso: [Method: projects.serviceAccounts.generateAccessToken](https://cloud.google.com/iam/docs/reference/credentials/rest/v1/projects.serviceAccounts/generateAccessToken)
struct IAMGenerateAccessTokenRequest: Codable, Sendable, Equatable {
  /// The OAuth 2.0 scopes to include in the generated access token.
  let scope: [String]

  /// The ordered sequence of service accounts in a delegation chain.
  let delegates: [String]?

  /// Desired lifetime duration of the access token in seconds, formatted with an `"s"` suffix (e.g. `"3600s"`).
  let lifetime: String
}

/// The JSON response body returned by the IAM Service Account Credentials `:generateAccessToken` endpoint.
struct IAMGenerateAccessTokenResponse: Codable, Sendable, Equatable {
  /// The generated OAuth 2.0 access token.
  let accessToken: String

  /// Token expiration time in RFC 3339 format (e.g. `"2026-10-26T20:00:00Z"`).
  let expireTime: String
}
