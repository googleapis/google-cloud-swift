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
import Logging
import Testing
import GoogleCloudGax
import GoogleCloudTestHelpers

// All the code is compiled by default.
//
// The functions are only invoked if the `GOOGLE_CLOUD_PROJECT` environment variable is set.
@Suite(.enabled(if: protoBasedClientEnabled())) struct ProtoBasedClient {
  @Test func globalEndpoint() async throws {
    await cleanupStaleSecrets()
    try await runLoggedTest(#function, { try await GlobalEndpoint.run($0) })
  }

  @Test func logging() async throws {
    await cleanupStaleSecrets()
    try await runLoggedTest(#function, { try await Logging.run($0) })
  }

  @Test func longRunningOperations() async throws {
    await cleanUpStaleWorkflows()
    try await runLoggedTest(#function, { try await LongrunningOperations.run($0) })
  }
}

func protoBasedClientEnabled() -> Bool {
  // These functions test two separate environment variables used in the integration tests.
  return ((try? projectId()) != nil) && ((try? testServiceAccount()) != nil)
}
