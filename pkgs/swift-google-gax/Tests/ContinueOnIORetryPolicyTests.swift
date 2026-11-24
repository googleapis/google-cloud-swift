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
import GoogleAuth
import GoogleGax
import Testing

@Suite struct ContinueIOTests {
  @Test func retryIO() async throws {
    let p = NeverRetry().retryOnIO()

    let ioError = mockIOError()
    #expect(p.onError(state: idempotentState(), error: ioError) == .retry(ioError))
    #expect(p.onError(state: nonIdempotentState(), error: ioError) == .retry(ioError))
    #expect(p.onThrottle(state: idempotentState(), error: ioError) == .exhausted(ioError))
    #expect(p.onThrottle(state: nonIdempotentState(), error: ioError) == .exhausted(ioError))

    let credentialsError = RequestError.io(CredentialsError.parseError("invalid universe domain"))
    #expect(
      p.onError(state: idempotentState(), error: credentialsError) == .permanent(credentialsError)
    )
    #expect(
      p.onError(state: nonIdempotentState(), error: credentialsError)
        == .permanent(credentialsError)
    )

    let permanentFetchError = RequestError.io(
      CredentialsError.cannotFetchToken(
        message: "invalid_grant",
        underlyingError: CredentialsError.parseError("revoked")
      )
    )
    #expect(
      p.onError(state: idempotentState(), error: permanentFetchError)
        == .permanent(permanentFetchError)
    )

    let cancelledFetchError = RequestError.io(
      CredentialsError.cannotFetchToken(
        message: "cancelled",
        underlyingError: URLError(.cancelled)
      )
    )
    #expect(
      p.onError(state: idempotentState(), error: cancelledFetchError)
        == .permanent(cancelledFetchError)
    )

    let transientCredentialsError = RequestError.io(try await makeTransientCredentialsError())
    #expect(
      p.onError(state: idempotentState(), error: transientCredentialsError)
        == .retry(transientCredentialsError)
    )
    #expect(
      p.onError(state: nonIdempotentState(), error: transientCredentialsError)
        == .retry(transientCredentialsError)
    )

    let cancellationError = RequestError.io(CancellationError())
    #expect(
      p.onError(state: idempotentState(), error: cancellationError)
        == .permanent(cancellationError)
    )
    #expect(
      p.onError(state: nonIdempotentState(), error: cancellationError)
        == .permanent(cancellationError)
    )

    let otherError = RequestError.binding(BindingError())
    #expect(p.onError(state: idempotentState(), error: otherError) == .permanent(otherError))
    #expect(p.onError(state: nonIdempotentState(), error: otherError) == .permanent(otherError))
    #expect(p.onThrottle(state: idempotentState(), error: ioError) == .exhausted(ioError))
    #expect(p.onThrottle(state: nonIdempotentState(), error: ioError) == .exhausted(ioError))

    #expect(p.remainingTime(state: idempotentState()) == nil)
    #expect(p.remainingTime(state: nonIdempotentState()) == nil)
  }

  @Test func nonRetryableCredentialsAndCancellationErrorsArePermanentWithAlwaysRetry() async throws
  {
    let p = AlwaysRetry.unbounded().retryOnIO()

    let ioError = mockIOError()
    #expect(p.onError(state: idempotentState(), error: ioError) == .retry(ioError))

    let credentialsError = RequestError.io(CredentialsError.parseError("invalid universe domain"))
    #expect(
      p.onError(state: idempotentState(), error: credentialsError) == .permanent(credentialsError)
    )
    #expect(
      p.onError(state: nonIdempotentState(), error: credentialsError)
        == .permanent(credentialsError)
    )

    let permanentFetchError = RequestError.io(
      CredentialsError.cannotFetchToken(
        message: "invalid_grant",
        underlyingError: CredentialsError.parseError("revoked")
      )
    )
    #expect(
      p.onError(state: idempotentState(), error: permanentFetchError)
        == .permanent(permanentFetchError)
    )

    let cancelledFetchError = RequestError.io(
      CredentialsError.cannotFetchToken(
        message: "cancelled",
        underlyingError: URLError(.cancelled)
      )
    )
    #expect(
      p.onError(state: idempotentState(), error: cancelledFetchError)
        == .permanent(cancelledFetchError)
    )

    let transientCredentialsError = RequestError.io(try await makeTransientCredentialsError())
    #expect(
      p.onError(state: idempotentState(), error: transientCredentialsError)
        == .retry(transientCredentialsError)
    )
    #expect(
      p.onError(state: nonIdempotentState(), error: transientCredentialsError)
        == .retry(transientCredentialsError)
    )

    let cancellationError = RequestError.io(CancellationError())
    #expect(
      p.onError(state: idempotentState(), error: cancellationError)
        == .permanent(cancellationError)
    )
    #expect(
      p.onError(state: nonIdempotentState(), error: cancellationError)
        == .permanent(cancellationError)
    )

    let otherError = RequestError.binding(BindingError())
    #expect(p.onError(state: idempotentState(), error: otherError) == .retry(otherError))
  }

  @Test func equatable() {
    let a = NeverRetry().retryOnIO()
    let b = NeverRetry().retryOnIO()
    #expect(a == b)

    let p1 = NeverRetry().withAttemptLimit(1).retryOnIO()
    let p2 = NeverRetry().withAttemptLimit(2).retryOnIO()
    #expect(p1 != p2)
  }
}
