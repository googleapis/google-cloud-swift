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

/// Errors that can occur when building a retry throttler.
public enum RetryThrottlerError: Error {
  /// The scaling factor is out of range (must be >= 0.0).
  case scalingOutOfRange(Double)
  /// The minimum tokens must be less than or equal to the initial tokens.
  case tooFewMinTokens(min: UInt64, initial: UInt64)
}

extension RetryThrottlerError: Equatable {
  public static func == (lhs: RetryThrottlerError, rhs: RetryThrottlerError) -> Bool {
    switch (lhs, rhs) {
    case (.scalingOutOfRange(let l), .scalingOutOfRange(let r)): return l == r
    case (.tooFewMinTokens(let lm, let li), .tooFewMinTokens(let rm, let ri)):
      return lm == rm && li == ri
    default: return false
    }
  }
}
