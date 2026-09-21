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

import GoogleAuth
import GoogleGax

@Suite struct ClientOptionsTests {
  struct TestError: Error, Equatable {}

  @Test func then() {
    let got = ClientOptions().with {
      $0.endpoint = "test-only"
      $0.quotaProject = "my-quota-project"
      $0.universeDomain = "my-universe.com"
    }
    #expect(got.endpoint == "test-only")
    #expect(got.quotaProject == "my-quota-project")
    #expect(got.endpoint == "test-only")
    #expect(got.universeDomain == "my-universe.com")
    #expect(got.credentials == nil)
  }

  @Test func thenThrowing() throws {
    let got = try ClientOptions().with {
      $0.endpoint = "https://private.googleapis.com"
      $0.credentials = try Credentials(configuration: .anonymous)
      $0.retryPolicy = BaseRetryPolicy()
        .withAttemptLimit(5)
        .withTimeLimit(.seconds(60))
      $0.backoffPolicy = try ExponentialBackoff(
        config: ExponentialBackoffConfig().with {
          $0.initialDelay = .milliseconds(200)
          $0.maximumDelay = .seconds(15)
          $0.scaling = 1.5
        }
      )
    }
    #expect(got.endpoint == "https://private.googleapis.com")
    #expect(got.credentials != nil)
    #expect(got.retryPolicy != nil)

    #expect(throws: TestError()) {
      try ClientOptions().with { _ in
        throw TestError()
      }
    }
  }

  @Test func readmeExampleCompiles() {
    func readmeSnippet() throws -> ClientOptions {
      let options = try ClientOptions().with {
        // Custom endpoint (e.g. for VPC-SC, private access, or emulators)
        $0.endpoint = "https://private.googleapis.com"

        // Override credentials
        $0.credentials = try Credentials()

        // Configure retry policy (max 5 attempts and max 60 seconds)
        $0.retryPolicy = BaseRetryPolicy()
          .withAttemptLimit(5)
          .withTimeLimit(.seconds(60))

        // Configure exponential backoff
        $0.backoffPolicy = try ExponentialBackoff(
          config: ExponentialBackoffConfig().with {
            $0.initialDelay = .milliseconds(200)
            $0.maximumDelay = .seconds(15)
            $0.scaling = 1.5
          }
        )
      }
      return options
    }
    _ = readmeSnippet
  }

  @Test func defaults() {
    let got = ClientOptions()
    #expect(got.endpoint == nil)
    #expect(got.quotaProject == nil)
    #expect(got.universeDomain == nil)
    #expect(got.credentials == nil)
    #expect(got.retryPolicy == nil)
  }
}
