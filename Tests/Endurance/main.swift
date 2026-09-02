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
import GoogleCloudGax
import GoogleCloudSecretManagerV1

private let tooManyErrors: UInt64 = 100

// Fixed payload string used across endurance test runs.
private let payloadData = Data("the quick brown fox jumps over the lazy dog".utf8)

// Hardcoded CRC32C checksum for `payloadData`.
// This value (0x3c18f4d6) can be verified using:
//   echo -n "the quick brown fox jumps over the lazy dog" > /tmp/payload.txt
//   gcloud storage hash --skip-md5 /tmp/payload.txt
// and converting the CRC32C base64 output to hex or integer.
private let payloadCrc32c: Int64 = 0x3c18f4d6

enum EnduranceError: Error, CustomStringConvertible {
  case missingProjectId
  case noEnduranceSecretsFound(projectId: String)

  var description: String {
    switch self {
    case .missingProjectId:
      return "GOOGLE_CLOUD_PROJECT environment variable is not set"
    case .noEnduranceSecretsFound(let projectId):
      return "no secrets with the `endurance-test` label found in \(projectId)"
    }
  }
}

do {
  try await startWorkers()
} catch {
  reportError(error, task: "main")
}

/// Starts concurrent worker tasks for all endurance secrets found in the project.
private func startWorkers() async throws {
  let value = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]
  guard let projectId = value, !projectId.isEmpty else {
    throw EnduranceError.missingProjectId
  }

  let clientOptions = ClientOptions().with {
    $0.retryPolicy = BaseRetryPolicy()
      .withTimeLimit(.seconds(15))
      .withAttemptLimit(5)
  }
  let discoveryClient = try SecretManagerServiceClient(clientOptions)

  let enduranceSecrets = try await getEnduranceSecrets(
    client: discoveryClient, projectId: projectId)
  let totalWorkers = enduranceSecrets.count
  precondition(totalWorkers > 0, "totalWorkers must not be 0")

  let metrics = MetricsTracker()

  try await withThrowingTaskGroup(of: Void.self) { group in
    for (taskId, secret) in enduranceSecrets.enumerated() {
      group.addTask {
        let taskName = "worker[\(secret)]"
        do {
          let client = try SecretManagerServiceClient(clientOptions)
          try await worker(
            client: client,
            secret: secret,
            taskId: taskId,
            totalWorkers: totalWorkers,
            metrics: metrics
          )
        } catch {
          reportError(error, task: taskName)
          throw error
        }
      }
    }
    try await group.waitForAll()
  }
}

/// Continuously perform RPCs to a given secret.
private func worker(
  client: SecretManagerServiceClient,
  secret: String,
  taskId: Int,
  totalWorkers: Int,
  metrics: MetricsTracker
) async throws {
  // First create a secret version, to ensure the loop will succeed.
  var version = try await updateSecret(client: client, secret: secret)

  // We want to create a new version every minute on average across all workers.
  // That will keep this test well below the quota:
  //   https://cloud.google.com/secret-manager/quotas
  let addVersionPeriod = Duration.seconds(60.0 * Double(totalWorkers))
  let reportPeriod = Duration.seconds(10)

  var lastAddVersion = ContinuousClock.now
  var lastReport = ContinuousClock.now
  var errorCount: UInt64 = 0
  var successCount: UInt64 = 0
  var updateCount: UInt64 = 0

  while true {
    let now = ContinuousClock.now
    if now >= lastAddVersion + addVersionPeriod {
      do {
        version = try await updateSecret(client: client, secret: secret)
        lastAddVersion = ContinuousClock.now
        updateCount += 1
      } catch {
        errorCount += 1
        if errorCount > tooManyErrors && successCount == 0 {
          throw error
        }
        reportError(error, task: "task[\(taskId)]")
      }
    }

    if now >= lastReport + reportPeriod {
      let totals = await metrics.record(
        successes: successCount,
        errors: errorCount,
        updates: updateCount
      )
      if taskId == 0 {
        reportInfo(
          "success_count=\(totals.totalSuccess), error_count=\(totals.totalError), version_count=\(totals.totalUpdate), current_success_count=\(successCount), current_error_count=\(errorCount), total_workers=\(totalWorkers)",
          task: "task[0]"
        )
      }
      lastReport = ContinuousClock.now
      errorCount = 0
      successCount = 0
      updateCount = 0
    }

    // We want to average about 80,000 requests per minute total across all workers.
    // That will keep the test well below the quota:
    //   https://cloud.google.com/secret-manager/quotas
    let waitDuration = Duration.seconds((60.0 * Double(totalWorkers)) / 80_000.0)
    let nextTargetTime = ContinuousClock.now + waitDuration

    let accessRequest = AccessSecretVersionRequest().with {
      $0.name = version.name
    }
    let requestOptions = RequestOptions().with {
      $0.attemptTimeout = .seconds(1)
    }

    do {
      _ = try await client.accessSecretVersion(request: accessRequest, options: requestOptions)
      successCount += 1
    } catch {
      errorCount += 1
      if errorCount > tooManyErrors && successCount == 0 {
        throw error
      }
      reportError(error, task: "task[\(taskId)]")
    }

    if ContinuousClock.now < nextTargetTime {
      try await Task.sleep(until: nextTargetTime, clock: .continuous)
    }
  }
}

/// Cleans up old versions and creates a new secret version with a payload.
private func updateSecret(
  client: SecretManagerServiceClient,
  secret: String
) async throws -> SecretVersion {
  // To keep things tidy, remove any existing versions.
  let items = try client.listSecretVersions(byItem: .init().with { $0.parent = secret })
  for try await version in items {
    if version.state == .destroyed {
      continue
    }
    _ = try await client.destroySecretVersion(
      request: .init().with { $0.name = version.name },
      options: .init().with { $0.idempotency = true })
  }

  let version = try await client.addSecretVersion(
    request: .init().with {
      $0.parent = secret
      $0.payload = SecretPayload().with { payload in
        payload.data = payloadData
        payload.dataCrc32C = payloadCrc32c
      }
    },
    options: .init().with { $0.idempotency = true })
  return version
}

/// Retrieves all secret resource names labeled with `endurance-test`.
private func getEnduranceSecrets(
  client: SecretManagerServiceClient,
  projectId: String
) async throws -> [String] {
  var secrets: [String] = []
  let items = try client.listSecrets(
    byItem: .init().with { $0.parent = "projects/\(projectId)" })
  for try await secret in items {
    if secret.labels["endurance-test"] != nil {
      secrets.append(secret.name)
    }
  }
  if secrets.isEmpty {
    throw EnduranceError.noEnduranceSecretsFound(projectId: projectId)
  }
  return secrets
}
