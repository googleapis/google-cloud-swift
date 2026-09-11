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
import GoogleCloudAuth
import GoogleCloudGax
@testable import GoogleCloudStorage
import Testing

@Suite struct StorageControlClientTests {
  @Test func defaultInitialization() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
    }
    let client = try StorageControlClient(options)
    #expect(
      client.pollingErrorPolicy
        is GoogleCloudGax.LimitedElapsedTime<GoogleCloudGax.BasePollingErrorPolicy>)
    #expect(client.pollingBackoffPolicy is GoogleCloudGax.ExponentialBackoff)
  }

  @Test func customPollingPolicies() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let customErrorPolicy = GoogleCloudGax.BasePollingErrorPolicy().withTimeLimit(.seconds(120))
    let customBackoffPolicy = GoogleCloudGax.ExponentialBackoff()
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.pollingErrorPolicy = customErrorPolicy
      $0.pollingBackoffPolicy = customBackoffPolicy
    }
    let client = try StorageControlClient(options)
    #expect(
      client.pollingErrorPolicy
        is GoogleCloudGax.LimitedElapsedTime<GoogleCloudGax.BasePollingErrorPolicy>)
    #expect(client.pollingBackoffPolicy is GoogleCloudGax.ExponentialBackoff)
  }

  static func assertSendable<T: Sendable>(_ type: T.Type) {}

  @Test func clientIsSendable() {
    Self.assertSendable(StorageControlClient.self)
  }

  @Test func initializationWithCustomEndpoints() throws {
    let credentials = try Credentials(configuration: .anonymous)

    // With explicit https endpoint
    let secureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://custom.endpoint.com:443"
    }
    let _ = try StorageControlClient(secureOptions)

    // With explicit http endpoint (local emulator)
    let insecureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "http://127.0.0.1:8080"
    }
    let _ = try StorageControlClient(insecureOptions)

    // Without scheme
    let bareOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "custom.endpoint.com:443"
    }
    let _ = try StorageControlClient(bareOptions)

    // With universe domain
    let universeOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.universeDomain = "my-universe.com"
    }
    let _ = try StorageControlClient(universeOptions)

    // With VPC-SC odd endpoint
    let oddEndpointOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://private.googleapis.com"
    }
    let _ = try StorageControlClient(oddEndpointOptions)
  }

  @Test(arguments: [
    "",
    "http:///",
    "https:///",
  ]) func badEndpoint(input: String) throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = input
    }
    #expect(throws: ClientError.self) {
      _ = try StorageControlClient(options)
    }
  }

  @Test func defaultInitializationUsesStorageBaseRetryPolicy() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
    }
    #expect(options.retryPolicy == nil)
    _ = try StorageControlClient(options)
  }

  @Test func initializationPreservesExplicitRetryPolicy() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let explicitPolicy = NeverRetry()
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.retryPolicy = explicitPolicy
    }
    #expect(options.retryPolicy != nil)
    _ = try StorageControlClient(options)
  }
}
