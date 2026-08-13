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
@_spi(GoogleCloudInternal) import GoogleCloudGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

#if IntegrationTests

  @Suite struct HTTPClientIntegrationTests {
    @Test func concurrentRequests() async {
      func runOnce() async {
        do {
          let options = ClientOptions().with {
            $0.credentials = try? Credentials(configuration: .anonymous)
          }
          let client = try _HTTPClient(from: options, withDefaultEndpoint: "https://www.google.com")
          let request = try await client.newRequest(percentEncodedPath: "", query: [])
          let response = try await request.execute()
          #expect(response.status.code == 200)
        } catch {
          Issue.record("Request failed: \(error)")
        }
      }

      let iterations = 100
      print("Starting concurrent requests stress tests for (\(iterations) iterations)...")
      for _ in 1...iterations {
        await runOnce()
        // Give it a tiny sleep to allow concurrent scheduling
        try? await Task.sleep(for: .milliseconds(10))
      }
      print("Finished \(iterations) iterations without crashing.")
    }
  }

#endif
