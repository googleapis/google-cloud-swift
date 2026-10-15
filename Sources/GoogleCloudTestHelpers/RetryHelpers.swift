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
public import GoogleGax
import GoogleRpc

/// A retry and polling error policy for integration tests that retries transient service flakes,
/// including `INTERNAL` (HTTP 500), `UNKNOWN`, `DEADLINE_EXCEEDED` (HTTP 504),
/// `RESOURCE_EXHAUSTED` (HTTP 429), `UNAVAILABLE` (HTTP 503), and HTTP 408 / 5xx errors.
public struct TestRetryPolicy: RetryPolicy, PollingErrorPolicy, Sendable, Equatable {
  public init() {}

  /// The default retry policy for integration tests, with a 60-second time limit and 10-attempt limit.
  public static var defaultRetryPolicy: some RetryPolicy {
    let policy: some RetryPolicy = TestRetryPolicy().retryOnIO()
    return policy.withTimeLimit(.seconds(60)).withAttemptLimit(10)
  }

  /// The default polling error policy for integration tests, with a 30-minute time limit.
  public static var defaultPollingErrorPolicy: some PollingErrorPolicy {
    let policy: some PollingErrorPolicy = TestRetryPolicy().continueOnIO()
    return policy.withTimeLimit(.seconds(30 * 60))
  }

  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    if error.isTransientTestError {
      return .retry(error)
    }
    return .permanent(error)
  }

  public func onError(state: PollingState, error: RequestError) -> PollingResult {
    if error.isTransientTestError {
      return .retry(error)
    }
    return .permanent(error)
  }
}

/// Shared ClientOptions for integration tests that configure resilient retry and polling error
/// policies and enforce a 15-second per-attempt timeout.
public let testClientOptions = ClientOptions().with {
  $0.attemptTimeout = .seconds(15)
  $0.retryPolicy = TestRetryPolicy.defaultRetryPolicy
  $0.pollingErrorPolicy = TestRetryPolicy.defaultPollingErrorPolicy
}

/// Shared RequestOptions for integration tests that retry non-idempotent operations
/// and enforce a 15-second attempt timeout to prevent premature exhaustion of retry loop budgets.
public let testRetryOptions = RequestOptions().with {
  $0.idempotent = true
  $0.attemptTimeout = .seconds(15)
  $0.retryPolicy = TestRetryPolicy.defaultRetryPolicy
  $0.pollingErrorPolicy = TestRetryPolicy.defaultPollingErrorPolicy
}

extension RequestError {
  /// Returns `true` if the error represents a transient network, HTTP, or service error in tests.
  public var isTransientTestError: Bool {
    switch self {
    case .io:
      return true
    case .http(let details):
      let code = details.statusCode
      return code == 408 || code == 429 || (500...599).contains(code)
    case .service(let err):
      if let httpCode = err.httpStatusCode,
        httpCode == 408 || httpCode == 429 || (500...599).contains(httpCode)
      {
        return true
      }
      let code = err.code
      return code == .unavailable || code == .resourceExhausted || code == .deadlineExceeded
        || code == .internal || code == .unknown
    case .exhausted(let details):
      return details.source?.isTransientTestError ?? false
    default:
      return false
    }
  }

  public var isAlreadyExists: Bool {
    switch self {
    case .service(let err):
      return err.code == .alreadyExists || err.httpStatusCode == 409
    case .http(let details):
      return details.statusCode == 409
    case .exhausted(let details):
      return details.source?.isAlreadyExists ?? false
    default:
      return false
    }
  }

  public var isNotFound: Bool {
    switch self {
    case .service(let err):
      return err.code == .notFound || err.httpStatusCode == 404
    case .http(let details):
      return details.statusCode == 404
    case .exhausted(let details):
      return details.source?.isNotFound ?? false
    default:
      return false
    }
  }

  public var isFailedPreconditionOrAborted: Bool {
    switch self {
    case .service(let err):
      return err.code == .failedPrecondition || err.code == .aborted || err.httpStatusCode == 412
        || err.httpStatusCode == 409
    case .http(let details):
      return details.statusCode == 412 || details.statusCode == 409
    case .exhausted(let details):
      return details.source?.isFailedPreconditionOrAborted ?? false
    default:
      return false
    }
  }
}

extension Swift.Error {
  public var isTransientTestError: Bool {
    (self as? RequestError)?.isTransientTestError ?? false
  }
  public var isAlreadyExists: Bool {
    (self as? RequestError)?.isAlreadyExists ?? false
  }
  public var isNotFound: Bool {
    (self as? RequestError)?.isNotFound ?? false
  }
  public var isFailedPreconditionOrAborted: Bool {
    (self as? RequestError)?.isFailedPreconditionOrAborted ?? false
  }
}
