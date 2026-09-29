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

import ArgumentParser
import Foundation
import GoogleGax
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

enum EnduranceError: Error, CustomStringConvertible, Equatable {
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

public struct Endurance: AsyncParsableCommand, Sendable {
  public static let configuration = CommandConfiguration(
    commandName: "Endurance",
    abstract: "Endurance test for the Google Cloud Secret Manager Swift client library."
  )

  public init() {}

  @Option(
    name: [.customLong("requests-per-minute"), .customLong("request-rate")],
    help: "The target request rate in requests per minute across all workers.",
    transform: { string in
      let cleaned = string.replacingOccurrences(of: "_", with: "")
      guard let value = Int(cleaned), value > 0 else {
        throw ValidationError("Invalid request rate: '\(string)'")
      }
      return value
    }
  )
  var requestsPerMinute: Int = 80_000

  @Option(
    name: .customLong("iterations"),
    help: "Optional maximum number of access iterations per worker before exiting."
  )
  var iterations: Int? = nil

  public func validate() throws {
    guard requestsPerMinute > 0 else {
      throw ValidationError("requests-per-minute must be positive")
    }
    if let iterations, iterations <= 0 {
      throw ValidationError("iterations must be positive")
    }
  }

  public func run() async throws {
    _ = try await run(secrets: nil)
  }

  @discardableResult
  func run(secrets: [String]? = nil) async throws -> MetricsTracker {
    do {
      return try await startWorkers(
        requestsPerMinute: requestsPerMinute,
        iterations: iterations,
        secrets: secrets
      )
    } catch {
      reportError(error, task: "main")
      throw error
    }
  }
}

/// Helper to create a decorated retry policy for SecretManagerServiceClient methods.
func makeRetryPolicy(
  methodName: String,
  counter: RetryAttemptCounter,
  task: String = "worker"
) -> some RetryPolicy {
  BaseRetryPolicy.defaultPolicy
    .countedAndLogged(counter: counter, methodName: methodName, task: task)
}

/// Starts concurrent worker tasks for all endurance secrets found in the project.
@discardableResult
func startWorkers(
  requestsPerMinute: Int,
  iterations: Int? = nil,
  secrets: [String]? = nil
) async throws -> MetricsTracker {
  let clientOptions = ClientOptions().with {
    $0.retryPolicy = BaseRetryPolicy.defaultPolicy
  }
  let metrics = MetricsTracker()

  let enduranceSecrets: [String]
  if let secrets, !secrets.isEmpty {
    enduranceSecrets = secrets
  } else {
    let value = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]
    guard let projectId = value, !projectId.isEmpty else {
      throw EnduranceError.missingProjectId
    }
    let discoveryClient = try SecretManagerServiceClient(clientOptions)
    enduranceSecrets = try await getEnduranceSecrets(
      client: discoveryClient,
      projectId: projectId,
      counter: metrics.retryAttempts
    )
  }
  let totalWorkers = enduranceSecrets.count
  precondition(totalWorkers > 0, "totalWorkers must not be 0")

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
            requestsPerMinute: requestsPerMinute,
            iterations: iterations,
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
  return metrics
}

/// Continuously perform RPCs to a given secret.
func worker(
  client: SecretManagerServiceClient,
  secret: String,
  taskId: Int,
  totalWorkers: Int,
  requestsPerMinute: Int,
  iterations: Int? = nil,
  metrics: MetricsTracker
) async throws {
  let taskName = "task[\(taskId)]"

  // First create a secret version, to ensure the loop will succeed.
  var version = try await updateSecret(
    client: client,
    secret: secret,
    counter: metrics.retryAttempts,
    task: taskName
  )

  // We want to create a new version every minute on average across all workers.
  // That will keep this test well below the quota:
  //   https://cloud.google.com/secret-manager/quotas
  let addVersionPeriod = Duration.seconds(60.0 * Double(totalWorkers))
  let reportPeriod = Duration.seconds(10)

  var lastAddVersion = ContinuousClock.now
  var lastReport = ContinuousClock.now
  var errorCount: UInt64 = 0
  var successCount: UInt64 = 0
  var updateCount: UInt64 = 1
  var completedIterations = 0

  while iterations == nil || completedIterations < iterations! {
    let now = ContinuousClock.now
    if now >= lastAddVersion + addVersionPeriod {
      do {
        version = try await updateSecret(
          client: client,
          secret: secret,
          counter: metrics.retryAttempts,
          task: taskName
        )
        lastAddVersion = ContinuousClock.now
        updateCount += 1
      } catch {
        errorCount += 1
        if errorCount > tooManyErrors && successCount == 0 {
          throw error
        }
        reportError(error, task: taskName)
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
          "success_count=\(totals.totalSuccess), " + "error_count=\(totals.totalError), "
            + "version_count=\(totals.totalUpdate), " + "retry_count=\(totals.totalRetry), "
            + "current_success_count=\(successCount), " + "current_error_count=\(errorCount), "
            + "total_workers=\(totalWorkers)",
          task: taskName
        )
      }
      lastReport = ContinuousClock.now
      errorCount = 0
      successCount = 0
      updateCount = 0
    }

    // We want to average about `requestsPerMinute` across all workers. When deploying the test
    // configure this value to keep the request rate within quota:
    //   https://cloud.google.com/secret-manager/quotas
    let waitDuration = Duration.seconds((60.0 * Double(totalWorkers)) / Double(requestsPerMinute))
    let nextTargetTime = ContinuousClock.now + waitDuration

    let accessRequest = AccessSecretVersionRequest().with {
      $0.name = version.name
    }
    let requestOptions = RequestOptions().with {
      $0.attemptTimeout = .seconds(1)
      $0.retryPolicy = makeRetryPolicy(
        methodName: "accessSecretVersion",
        counter: metrics.retryAttempts,
        task: taskName
      )
    }

    do {
      _ = try await client.accessSecretVersion(request: accessRequest, options: requestOptions)
      successCount += 1
    } catch {
      errorCount += 1
      if errorCount > tooManyErrors && successCount == 0 {
        throw error
      }
      reportError(error, task: taskName)
    }

    completedIterations += 1
    if let iterations, completedIterations >= iterations {
      break
    }

    if ContinuousClock.now < nextTargetTime {
      try await Task.sleep(until: nextTargetTime, clock: .continuous)
    }
  }

  if successCount > 0 || errorCount > 0 || updateCount > 0 {
    _ = await metrics.record(
      successes: successCount,
      errors: errorCount,
      updates: updateCount
    )
  }
}

/// Cleans up old versions and creates a new secret version with a payload.
private func updateSecret(
  client: SecretManagerServiceClient,
  secret: String,
  counter: RetryAttemptCounter,
  task: String
) async throws -> SecretVersion {
  // To keep things tidy, remove any existing versions.
  let listOptions = RequestOptions().with {
    $0.retryPolicy = makeRetryPolicy(
      methodName: "listSecretVersions",
      counter: counter,
      task: task
    )
  }
  let items = client.listSecretVersionsByItems(
    request: .init().with { $0.parent = secret },
    options: listOptions
  )
  for try await version in items {
    if version.state == .destroyed {
      continue
    }
    _ = try await client.destroySecretVersion(
      request: .init().with { $0.name = version.name },
      options: .init().with {
        $0.idempotency = true
        $0.attemptTimeout = .seconds(5)
        $0.retryPolicy = makeRetryPolicy(
          methodName: "destroySecretVersion",
          counter: counter,
          task: task
        )
      })
  }

  let version = try await client.addSecretVersion(
    request: .init().with {
      $0.parent = secret
      $0.payload = SecretPayload().with { payload in
        payload.data = payloadData
        payload.dataCrc32C = payloadCrc32c
      }
    },
    options: .init().with {
      $0.idempotency = true
      $0.attemptTimeout = .seconds(5)
      $0.retryPolicy = makeRetryPolicy(
        methodName: "addSecretVersion",
        counter: counter,
        task: task
      )
    })
  return version
}

/// Retrieves all secret resource names labeled with `endurance-test`.
private func getEnduranceSecrets(
  client: SecretManagerServiceClient,
  projectId: String,
  counter: RetryAttemptCounter
) async throws -> [String] {
  var secrets: [String] = []
  let options = RequestOptions().with {
    $0.retryPolicy = makeRetryPolicy(
      methodName: "listSecrets",
      counter: counter,
      task: "main"
    )
  }
  let items = client.listSecretsByItems(
    request: .init().with { $0.parent = "projects/\(projectId)" },
    options: options
  )
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
