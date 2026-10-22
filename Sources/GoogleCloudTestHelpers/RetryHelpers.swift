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

/// A retry and polling error policy for integration tests that retries transient service flakes.
///
/// Production clients default to ``BaseRetryPolicy`` and ``BasePollingErrorPolicy``, which wrap
/// ``AIP194``. ``AIP194`` is intentionally strict and only retries `UNAVAILABLE` (HTTP 503).
/// In CI integration tests against live Google Cloud backends, services occasionally return other
/// transient errors—such as `INTERNAL` (HTTP 500), `UNKNOWN` (HTTP 500), `DEADLINE_EXCEEDED`
/// (HTTP 504), `RESOURCE_EXHAUSTED` (HTTP 429), or HTTP 408 / 5xx gateway errors. `TestRetryPolicy`
/// treats all of these as retryable so transient backend hiccups do not cause CI flakes.
///
/// This type conforms to both ``RetryPolicy`` and ``PollingErrorPolicy`` so that both individual
/// RPC attempts and long-running operation (LRO) polling loops tolerate transient backend errors.
public struct TestRetryPolicy: RetryPolicy, PollingErrorPolicy, Sendable, Equatable {
  public init() {}

  /// The default retry policy for integration tests, with a 60-second time limit and 10-attempt limit.
  ///
  /// Unlike ``BaseRetryPolicy/defaultPolicy``, this policy intentionally omits
  /// ``RetryPolicy/strictIdempotency()`` because integration tests exercise non-idempotent
  /// mutations (`POST`, `PATCH`, `DELETE`)—sometimes via flattened convenience methods that do not
  /// accept a per-request ``RequestOptions`` override—and handle duplicate or stale-state responses
  /// (`ALREADY_EXISTS`, `NOT_FOUND`, `FAILED_PRECONDITION`, `ABORTED`) at the call site.
  public static var defaultRetryPolicy: some RetryPolicy {
    let policy: some RetryPolicy = TestRetryPolicy().retryOnIO()
    return policy.withTimeLimit(.seconds(60)).withAttemptLimit(10)
  }

  /// The default polling error policy for integration tests, with a 30-minute time limit.
  ///
  /// Continues polling when `GetOperation` encounters I/O errors or transient service/HTTP errors.
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

/// Shared `ClientOptions` for integration tests that configure resilient retry and polling error
/// policies and enforce a 15-second per-attempt timeout.
///
/// Passing `testClientOptions` when initializing a client ensures that all RPCs made through that
/// client—including flattened convenience methods that do not take `RequestOptions` and sample
/// snippets that pass `.init()`—automatically use ``TestRetryPolicy``.
public let testClientOptions = ClientOptions().with {
  $0.attemptTimeout = .seconds(15)
  $0.retryPolicy = TestRetryPolicy.defaultRetryPolicy
  $0.pollingErrorPolicy = TestRetryPolicy.defaultPollingErrorPolicy
}

/// Shared `RequestOptions` for integration tests that retry non-idempotent operations, configure
/// ``TestRetryPolicy`` for both RPC retries and LRO polling, and enforce a 15-second per-attempt
/// timeout so a single slow attempt does not exhaust the overall 60-second retry budget.
public let testRetryOptions = RequestOptions().with {
  $0.idempotent = true
  $0.attemptTimeout = .seconds(15)
  $0.retryPolicy = TestRetryPolicy.defaultRetryPolicy
  $0.pollingErrorPolicy = TestRetryPolicy.defaultPollingErrorPolicy
}

extension RequestError {
  /// Returns `true` if the error represents a transient network, HTTP, or service error in tests.
  ///
  /// This includes:
  /// - Network/socket I/O errors (`.io`)
  /// - HTTP `408` (Request Timeout), `429` (Too Many Requests), and `500...599` (5xx server errors)
  /// - gRPC/service status codes `.unavailable`, `.resourceExhausted`, `.deadlineExceeded`,
  ///   `.internal`, and `.unknown`
  /// - Retry/polling exhaustion errors whose underlying source error was transient
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
      return details.underlyingError?.isTransientTestError ?? false
    default:
      return false
    }
  }

  /// Returns `true` if the error is `ALREADY_EXISTS` (HTTP 409).
  ///
  /// When a non-idempotent `create*` request is retried after the server already processed the
  /// first attempt (for example, if the response was lost or the first attempt timed out), the
  /// retry fails with `ALREADY_EXISTS`. Integration tests catch this and fetch the existing resource.
  public var isAlreadyExists: Bool {
    switch self {
    case .service(let err):
      return err.code == .alreadyExists || err.httpStatusCode == 409
    case .http(let details):
      return details.statusCode == 409
    case .exhausted(let details):
      return details.underlyingError?.isAlreadyExists ?? false
    default:
      return false
    }
  }

  /// Returns `true` if the error is `NOT_FOUND` (HTTP 404).
  ///
  /// When a non-idempotent `delete*` request is retried after the first attempt already deleted
  /// the resource on the server, the retry fails with `NOT_FOUND`. Integration tests treat this as
  /// a successful deletion.
  public var isNotFound: Bool {
    switch self {
    case .service(let err):
      return err.code == .notFound || err.httpStatusCode == 404
    case .http(let details):
      return details.statusCode == 404
    case .exhausted(let details):
      return details.underlyingError?.isNotFound ?? false
    default:
      return false
    }
  }

  /// Returns `true` if the error is `FAILED_PRECONDITION` (HTTP 412) or `ABORTED` (HTTP 409).
  ///
  /// When a non-idempotent `update*` or state-transition request (often guarded by an `etag`) is
  /// retried after the first attempt already mutated the resource on the server, subsequent attempts
  /// fail with a precondition or concurrency conflict. Integration tests catch this and inspect the
  /// current resource state.
  public var isFailedPreconditionOrAborted: Bool {
    switch self {
    case .service(let err):
      return err.code == .failedPrecondition || err.code == .aborted || err.httpStatusCode == 412
        || err.httpStatusCode == 409
    case .http(let details):
      return details.statusCode == 412 || details.statusCode == 409
    case .exhausted(let details):
      return details.underlyingError?.isFailedPreconditionOrAborted ?? false
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
