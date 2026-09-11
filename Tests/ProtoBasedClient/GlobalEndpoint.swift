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
@_spi(GoogleCloudInternal) import struct GoogleCloudGax._CRC32C
import GoogleCloudLocation
import GoogleCloudSecretManagerV1
import GoogleCloudTestHelpers
import GoogleCloudWKT
import GoogleIAMV1
import Logging

/// Run tests for the global endpoint.
public enum GlobalEndpoint {
  private static let retryOptions = testRetryOptions

  static public func run(_ logger: Logger) async throws {
    let projectId = try projectId()
    let secretId = randomSecretId()
    let secretName = "projects/\(projectId)/secrets/\(secretId)"
    let client = try SecretManagerServiceClient()

    logger.info("Testing createSecret()")
    let create: Secret
    do {
      create = try await client.createSecret(
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
        options: retryOptions
      )
    } catch let error where error.isAlreadyExists {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      logger.info("createSecret() returned alreadyExists; fetching existing secret")
      create = try await client.getSecret(
        request: .init().with { $0.name = secretName },
        options: retryOptions
      )
    }
    logger.info("create = \(create)")

    logger.info("\nTesting getSecret()")
    let get = try await client.getSecret(
      request: .init().with { $0.name = create.name },
      options: retryOptions
    )
    logger.info("get = \(get)")

    try await testSecretVersions(client: client, secretName: create.name, logger: logger)
    try await testIAM(client: client, secretName: create.name, logger: logger)
    try await testLocations(client: client, projectId: projectId, logger: logger)

    logger.info("\nTesting updateSecret()")
    var updatedLabels = get.labels
    updatedLabels["updated"] = "test-1"
    var updatedAnnotations = get.annotations
    updatedAnnotations["updated"] = "test-1"

    let update: Secret
    do {
      update = try await client.updateSecret(
        request: .init().with {
          $0.updateMask = GoogleCloudWKT.FieldMask(paths: [
            "annotations", "labels", "versionAliases",
          ])
          $0.secret = Secret().with { secret in
            secret.name = create.name
            secret.labels = updatedLabels
            secret.etag = get.etag
            secret.versionAliases = ["test-alias": Int64(1)]
            secret.annotations = updatedAnnotations
          }
        },
        options: retryOptions
      )
    } catch let error where error.isFailedPreconditionOrAborted {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      logger.info("updateSecret() returned precondition/aborted; verifying updated secret")
      let currentSecret = try await client.getSecret(
        request: .init().with { $0.name = create.name },
        options: retryOptions
      )
      guard currentSecret.labels["updated"] == "test-1",
        currentSecret.annotations["updated"] == "test-1"
      else {
        throw error
      }
      update = currentSecret
    }
    logger.info("update = \(update)")

    logger.info("\nTesting listSecrets()")
    let secrets = try client.listSecrets(
      byItem: .init().with { $0.parent = "projects/\(projectId)" },
      options: retryOptions
    )
    var count: UInt64 = 0
    for try await secret in secrets {
      logger.info("  secret = \(secret)")
      count += 1
    }
    logger.info("item count = \(count)")

    logger.info("\nTesting deleteSecret()")
    do {
      try await client.deleteSecret(
        request: .init().with { $0.name = get.name },
        options: retryOptions
      )
      logger.info("deleteSecret() was successful")
    } catch let error where error.isNotFound {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      logger.info("deleteSecret() returned notFound (already deleted)")
    }
  }

  static private func testSecretVersions(
    client: SecretManagerServiceClient, secretName: String, logger: Logger
  )
    async throws
  {
    logger.info("\nTesting secret version CRUD")
    let data = Data("the quick brown fox jumps over the lazy dog".utf8)
    let checksum = _CRC32C.compute(data)
    let version: SecretVersion
    do {
      version = try await client.addSecretVersion(
        request: .init().with {
          $0.parent = secretName
          $0.payload = SecretPayload().with { payload in
            payload.data = data
            payload.dataCrc32C = Int64(checksum)
          }
        },
        options: retryOptions
      )
    } catch let error where error.isAlreadyExists {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      logger.info("addSecretVersion() returned alreadyExists; fetching latest version")
      version = try await client.getSecretVersion(
        request: .init().with { $0.name = "\(secretName)/versions/latest" },
        options: retryOptions
      )
    }
    logger.info("version = \(version)")

    logger.info("\nTesting getSecretVersion()")
    let getVersion = try await client.getSecretVersion(
      request: .init().with { $0.name = version.name },
      options: retryOptions
    )
    logger.info("getVersion = \(getVersion)")

    logger.info("\nTesting accessSecretVersion()")
    let accessVersion = try await client.accessSecretVersion(
      request: .init().with { $0.name = version.name },
      options: retryOptions
    )
    logger.info("accessVersion payload length = \(accessVersion.payload?.data.count ?? 0)")

    logger.info("\nTesting disableSecretVersion()")
    let disabledVersion: SecretVersion
    do {
      disabledVersion = try await client.disableSecretVersion(
        request: .init().with { $0.name = version.name },
        options: retryOptions
      )
    } catch let error where error.isFailedPreconditionOrAborted {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      logger.info("disableSecretVersion() returned precondition/aborted; verifying current state")
      disabledVersion = try await client.getSecretVersion(
        request: .init().with { $0.name = version.name },
        options: retryOptions
      )
      guard disabledVersion.state == .disabled else {
        throw error
      }
    }
    logger.info("disabledVersion state = \(disabledVersion.state)")

    logger.info("\nTesting enableSecretVersion()")
    let enabledVersion: SecretVersion
    do {
      enabledVersion = try await client.enableSecretVersion(
        request: .init().with { $0.name = version.name },
        options: retryOptions
      )
    } catch let error where error.isFailedPreconditionOrAborted {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      logger.info("enableSecretVersion() returned precondition/aborted; verifying current state")
      enabledVersion = try await client.getSecretVersion(
        request: .init().with { $0.name = version.name },
        options: retryOptions
      )
      guard enabledVersion.state == .enabled else {
        throw error
      }
    }
    logger.info("enabledVersion state = \(enabledVersion.state)")

    logger.info("\nTesting listSecretVersions()")
    let versions = try client.listSecretVersions(
      byItem: .init().with { $0.parent = secretName },
      options: retryOptions
    )
    for try await version in versions {
      logger.info("  version = \(version)")
    }

    logger.info("\nTesting destroySecretVersion()")
    let destroyedVersion: SecretVersion
    do {
      destroyedVersion = try await client.destroySecretVersion(
        request: .init().with { $0.name = version.name },
        options: retryOptions
      )
    } catch let error where error.isFailedPreconditionOrAborted {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      logger.info("destroySecretVersion() returned precondition/aborted; verifying current state")
      destroyedVersion = try await client.getSecretVersion(
        request: .init().with { $0.name = version.name },
        options: retryOptions
      )
      guard destroyedVersion.state == .destroyed else {
        throw error
      }
    }
    logger.info("destroyedVersion state = \(destroyedVersion.state)")
  }

  static private func testIAM(
    client: SecretManagerServiceClient, secretName: String, logger: Logger
  )
    async throws
  {
    logger.info("\nTesting IAM operations")
    let serviceAccount = try testServiceAccount()
    logger.info("Testing getIamPolicy()")
    var policy = try await client.getIamPolicy(
      request: .init().with { $0.resource = secretName },
      options: retryOptions
    )
    logger.info("policy = \(policy)")

    logger.info("Testing testIamPermissions()")
    let permissions = try await client.testIamPermissions(
      request: .init().with {
        $0.resource = secretName
        $0.permissions = ["secretmanager.versions.access"]
      },
      options: retryOptions
    )
    logger.info("permissions = \(permissions)")

    logger.info("Testing setIamPolicy()")
    let role = "roles/secretmanager.secretVersionAdder"
    let member = "serviceAccount:\(serviceAccount)"
    if let index = policy.bindings.firstIndex(where: { $0.role == role }) {
      if !policy.bindings[index].members.contains(member) {
        policy.bindings[index].members.append(member)
      }
    } else {
      policy.bindings.append(
        Binding().with { binding in
          binding.role = role
          binding.members = [member]
        })
    }
    let updatedPolicy: Policy
    do {
      updatedPolicy = try await client.setIamPolicy(
        request: .init().with {
          $0.resource = secretName
          $0.policy = policy
        },
        options: retryOptions
      )
    } catch let error where error.isFailedPreconditionOrAborted {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      logger.info("setIamPolicy() returned precondition/aborted; verifying current policy")
      let currentPolicy = try await client.getIamPolicy(
        request: .init().with { $0.resource = secretName },
        options: retryOptions
      )
      guard
        currentPolicy.bindings.contains(where: {
          $0.role == role && $0.members.contains(member)
        })
      else {
        throw error
      }
      updatedPolicy = currentPolicy
    }
    logger.info("updatedPolicy = \(updatedPolicy)")
  }

  static private func testLocations(
    client: SecretManagerServiceClient, projectId: String, logger: Logger
  )
    async throws
  {
    logger.info("\nTesting location operations")
    logger.info("Testing listLocations()")
    var count: Int64 = 0
    var first: Location? = nil
    let locations = try client.listLocations(
      byItem: .init().with { $0.name = "projects/\(projectId)" },
      options: retryOptions
    )
    for try await location in locations {
      logger.info("  location = \(location)")
      count += 1
      if first == nil {
        first = location
      }
    }
    logger.info("locations count = \(count)")

    if let firstLocation = first {
      logger.info("Testing getLocation() for \(firstLocation.name)")
      let location = try await client.getLocation(
        request: .init().with { $0.name = firstLocation.name },
        options: retryOptions
      )
      logger.info("location = \(location)")
    }
  }
}
