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
import GoogleGax
import Testing

@Suite struct ContinueIOTests {
  @Test func retryIO() {
    let p = NeverRetry().retryOnIO()

    let ioError = mockIOError()
    #expect(p.onError(state: idempotentState(), error: ioError) == .retry(ioError))
    #expect(p.onError(state: nonIdempotentState(), error: ioError) == .retry(ioError))
    #expect(p.onThrottle(state: idempotentState(), error: ioError) == .exhausted(ioError))
    #expect(p.onThrottle(state: nonIdempotentState(), error: ioError) == .exhausted(ioError))

    let otherError = RequestError.binding(BindingError())
    #expect(p.onError(state: idempotentState(), error: otherError) == .exhausted(otherError))
    #expect(p.onError(state: nonIdempotentState(), error: otherError) == .exhausted(otherError))
    #expect(p.onThrottle(state: idempotentState(), error: ioError) == .exhausted(ioError))
    #expect(p.onThrottle(state: nonIdempotentState(), error: ioError) == .exhausted(ioError))

    #expect(p.remainingTime(state: idempotentState()) == nil)
    #expect(p.remainingTime(state: nonIdempotentState()) == nil)
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
