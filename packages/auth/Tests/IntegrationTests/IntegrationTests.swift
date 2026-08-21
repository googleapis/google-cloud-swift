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
@testable import GoogleCloudAuth
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil))
struct AuthHTTPClientIntegrationTests {
  @Test func concurrentCallsStressTest() async {
    func runOnce() async {
      do {
        let client = AuthHTTPClient()
        // Test with a basic unauthenticated request to an external url.
        // Since AuthHTTPClient only does GET/POST and decoding, we can use getString.
        let result = try await client.getString(url: URL(string: "https://www.google.com")!)
        #expect(!result.isEmpty)
      } catch {
        Issue.record("Request failed: \(error)")
      }
    }

    let iterations = 100
    print("Starting concurrent requests stress test for (\(iterations) iterations)...")
    for _ in 1...iterations {
      await runOnce()
      // Give it a tiny sleep to allow concurrent scheduling
      try? await Task.sleep(for: .milliseconds(10))
    }
    print("Finished \(iterations) iterations without crashing.")
  }
}
