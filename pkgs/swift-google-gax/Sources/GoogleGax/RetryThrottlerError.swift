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

/// Errors that can occur when building a retry throttler.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum RetryThrottlerError: Error, Sendable {
  /// The factor is out of range (must be >= 0.0).
  case factorOutOfRange(Double)
  /// The minimum tokens must be less than or equal to the initial tokens.
  case tooFewMinTokens(tokens: Int, minTokens: Int)
  /// The token counts and error costs must be non-negative.
  case tokensOutOfRange(tokens: Int, minTokens: Int, errorCost: Int)
}

extension RetryThrottlerError: Equatable {
  public static func == (lhs: RetryThrottlerError, rhs: RetryThrottlerError) -> Bool {
    switch (lhs, rhs) {
    case (.factorOutOfRange(let l), .factorOutOfRange(let r)): return l == r
    case (.tooFewMinTokens(let lt, let lm), .tooFewMinTokens(let rt, let rm)):
      return lt == rt && lm == rm
    case (.tokensOutOfRange(let lt, let lm, let le), .tokensOutOfRange(let rt, let rm, let re)):
      return lt == rt && lm == rm && le == re
    default: return false
    }
  }
}

extension RetryThrottlerError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .factorOutOfRange(let factor):
      return "Retry throttler factor out of range: \(factor) (must be >= 0.0)"
    case .tooFewMinTokens(let tokens, let minTokens):
      return "Minimum tokens (\(minTokens)) must be <= initial tokens (\(tokens))"
    case .tokensOutOfRange(let tokens, let minTokens, let errorCost):
      return
        "Token counts and error costs must be non-negative (tokens: \(tokens), minTokens: \(minTokens), errorCost: \(errorCost))"
    }
  }
}

extension RetryThrottlerError: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .factorOutOfRange(let factor):
      return "RetryThrottlerError.factorOutOfRange(\(factor))"
    case .tooFewMinTokens(let tokens, let minTokens):
      return "RetryThrottlerError.tooFewMinTokens(tokens: \(tokens), minTokens: \(minTokens))"
    case .tokensOutOfRange(let tokens, let minTokens, let errorCost):
      return
        "RetryThrottlerError.tokensOutOfRange(tokens: \(tokens), minTokens: \(minTokens), errorCost: \(errorCost))"
    }
  }
}

extension RetryThrottlerError: LocalizedError {
  public var errorDescription: String? {
    description
  }

  public var failureReason: String? {
    description
  }

  public var recoverySuggestion: String? {
    "Ensure token counts, minimum tokens, and error cost are non-negative and minTokens does not exceed tokens."
  }
}
