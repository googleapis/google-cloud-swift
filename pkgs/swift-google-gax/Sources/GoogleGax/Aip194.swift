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
import GoogleRpc

/// A retry policy that follows [AIP-194].
///
/// Use ``unbounded()`` decorated with ``RetryPolicy/withTimeLimit(_:)``,
/// ``RetryPolicy/withAttemptLimit(_:)``, and ``RetryPolicy/strictIdempotency()``
/// to configure limits and idempotency handling. For standard default retry behavior,
/// use ``BaseRetryPolicy/defaultPolicy``.
///
/// The policy interprets AIP-194 **strictly**, the retry decision for server-side errors are based
/// only on the status code, and the only retryable status code is `UNAVAILABLE`.
///
/// [AIP-194]: https://google.aip.dev/194
final public class Aip194: Sendable {
  init() {}

  /// Creates an unconstrained AIP-194 policy without attempt or time limits.
  ///
  /// Decorate this policy with ``RetryPolicy/withTimeLimit(_:)`` and/or
  /// ``RetryPolicy/withAttemptLimit(_:)`` (and ``RetryPolicy/strictIdempotency()``
  /// when used as a retry policy) to bound the loop:
  /// ```swift
  /// let policy = Aip194.unbounded()
  ///   .strictIdempotency()
  ///   .withTimeLimit(.seconds(30))
  ///   .withAttemptLimit(5)
  /// ```
  ///
  /// - Warning: Without attempt or time limit decorators, this policy retries
  ///   transient errors indefinitely.
  public static func unbounded() -> Aip194 {
    Aip194()
  }

  func isRetryable(_ error: RequestError) -> Bool {
    if let code = error.serviceCode, code == GoogleRpc.Code.unavailable {
      return true
    }

    // Some services return a status of "Unknown" and a http status code of
    // 503 (`SERVICE_UNAVAILABLE`). That is not how gRPC status codes are supposed to work, but the
    // intent is clear: we need to retry.
    if let httpStatus = error.httpStatusCode, httpStatus == 503 {
      return true
    }
    return false
  }
}

extension RequestError {
  fileprivate var httpStatusCode: Int? {
    if case .http(let details) = self {
      return details.httpStatusCode
    }
    return nil
  }

  fileprivate var serviceCode: GoogleRpc.Code? {
    if case .service(let details) = self {
      return details.code
    }
    return nil
  }
}
