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

@_spi(GoogleCloudInternal) import GoogleGax
import GoogleAuth

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
      $0.pollingBackoffPolicy = LinearBackoffPolicy(delay: .seconds(2))
    }
    #expect(got.retryPolicy != nil)
    #expect(got.backoffPolicy != nil)
    #expect(got.pollingBackoffPolicy is LinearBackoffPolicy)

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
    #expect(got.pollingBackoffPolicy == nil)
    #expect(got.headers.isEmpty)
  }

  @Test func headers() {
    let got = RequestOptions().with {
      $0.headers["x-custom-header"] = "custom-value"
    }
    #expect(got.headers["x-custom-header"] == "custom-value")
  }

  @Test func sanitizeCustomHeadersStripsReserved() {
    let input: [String: String] = [
      "authorization": "Bearer bad",
      "AUTHORIZATION": "Bearer bad-upper",
      "Authorization": "Bearer bad-title",
      "x-goog-api-key": "bad-key",
      "X-Goog-Api-Key": "bad-key-upper",
      "x-goog-user-project": "bad-project",
      "X-Goog-User-Project": "bad-project-upper",
      "host": "bad-host",
      "Host": "bad-host-upper",
      "x-goog-api-client": "bad-client",
      "x-goog-request-params": "bad-params",
      "user-agent": "bad-agent",
      "User-Agent": "bad-agent-upper",
      "x-goog-gcs-idempotency-token": "token-123",
      "x-custom-header": "custom-val",
    ]
    let sanitized = _sanitizeCustomHeaders(input)
    #expect(sanitized.count == 2)
    #expect(sanitized["x-goog-gcs-idempotency-token"] == "token-123")
    #expect(sanitized["x-custom-header"] == "custom-val")
  }

  @Test func sanitizeCustomHeadersExcludesAuthHeaders() {
    let input: [String: String] = [
      "x-custom-future-auth": "custom-value",
      "X-Another-Future-Auth": "another-value",
      "x-legitimate-custom": "legit-val",
    ]
    let authHeaders = GoogleAuth.AuthHeaders([
      ("x-custom-future-auth", "real-auth-val"),
      ("x-another-future-auth", "real-another-val"),
    ])
    let sanitized = _sanitizeCustomHeaders(input, excluding: authHeaders)
    #expect(sanitized == ["x-legitimate-custom": "legit-val"])
  }
}
