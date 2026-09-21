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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Testing

import GoogleGax

@Suite struct RequestOptionsTests {
  struct TestError: Error, Equatable {}

  @Test func then() {
    let got = RequestOptions().with {
      $0.attemptTimeout = .seconds(3)
      $0.quotaProject = "my-quota-project"
    }
    #expect(got.attemptTimeout == .seconds(3))
    #expect(got.quotaProject == "my-quota-project")
  }

  @Test func thenThrowing() throws {
    let got = try RequestOptions().with {
      $0.retryPolicy = NeverRetry()
      $0.backoffPolicy = try ExponentialBackoff(
        config: ExponentialBackoffConfig().with {
          $0.initialDelay = .milliseconds(100)
        }
      )
    }
    #expect(got.retryPolicy != nil)
    #expect(got.backoffPolicy != nil)

    #expect(throws: TestError()) {
      try RequestOptions().with { _ in
        throw TestError()
      }
    }
  }

  @Test func defaults() {
    let got = RequestOptions()
    #expect(got.attemptTimeout == nil)
    #expect(got.quotaProject == nil)
  }
}
