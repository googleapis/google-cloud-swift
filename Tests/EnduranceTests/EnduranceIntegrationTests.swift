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
import GoogleCloudSecretManagerV1
import GoogleCloudTestHelpers
import GoogleGax
@testable import Endurance
import Testing

@Suite(.enabled(if: enduranceIntegrationEnabled()))
struct EnduranceIntegrationTests {
  @Test func smoke() async throws {
    let projectId = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]!
    let secretId = randomSecretId()
    let secretName = "projects/\(projectId)/secrets/\(secretId)"
    let client = try SecretManagerServiceClient()

    let secret: Secret
    do {
      secret = try await client.createSecret(
        request: .init().with {
          $0.parent = "projects/\(projectId)"
          $0.secretId = secretId
          $0.secret = Secret().with { secret in
            secret.replication = Replication().with { replication in
              replication.replication = .automatic(Replication.Automatic())
            }
            secret.labels = ["integration-test": "true"]
          }
        },
        options: testRetryOptions
      )
    } catch let error where error.isAlreadyExists {
      secret = try await client.getSecret(
        request: .init().with { $0.name = secretName },
        options: testRetryOptions
      )
    }

    do {
      let parsed = try Endurance.parseAsRoot([
        "--requests-per-minute=6_000",
        "--iterations=3",
      ])
      guard let endurance = parsed as? Endurance else {
        Issue.record("cannot convert to Endurance")
        return
      }
      let metrics = try await endurance.run(secrets: [secret.name])
      #expect(await metrics.totalSuccessCount == 3)
      #expect(await metrics.totalErrorCount == 0)
      #expect(await metrics.totalUpdateCount == 1)
    } catch {
      _ = try? await client.deleteSecret(
        request: .init().with { $0.name = secret.name },
        options: testRetryOptions
      )
      throw error
    }
    _ = try await client.deleteSecret(
      request: .init().with { $0.name = secret.name },
      options: testRetryOptions
    )
  }
}

func enduranceIntegrationEnabled() -> Bool {
  guard let projectId = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] else {
    return false
  }
  return !projectId.isEmpty
}
