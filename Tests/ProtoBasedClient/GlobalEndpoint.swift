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

import GoogleCloudLocation
import GoogleCloudSecretManagerV1
import GoogleCloudTestHelpers
import GoogleCloudWkt
import GoogleIamV1
import CryptoSwift
import Logging
import Foundation

/// Run tests for the global endpoint.
public enum GlobalEndpoint {
  static public func run(_ logger: Logger) async throws {
    let projectId = try projectId()
    let secretId = randomSecretId()
    let client = try SecretManagerServiceClient()

    logger.info("Testing createSecret()")
    let create = try await client.createSecret(
      request: .init().with {
        $0.parent = "projects/\(projectId)"
        $0.secretId = secretId
        $0.secret = Secret().with {
          $0.replication = Replication().with {
            $0.replication = .automatic(Replication.Automatic())
          }
          $0.labels = ["integration-test": "true"]
        }
      })
    logger.info("create = \(create)")

    logger.info("\nTesting getSecret()")
    let get = try await client.getSecret(request: .init().with { $0.name = create.name })
    logger.info("get = \(get)")

    try await testSecretVersions(client: client, secretName: create.name, logger: logger)
    try await testIAM(client: client, secretName: create.name, logger: logger)
    try await testLocations(client: client, projectId: projectId, logger: logger)

    logger.info("\nTesting updateSecret()")
    var updatedLabels = get.labels
    updatedLabels["updated"] = "test-1"
    var updatedAnnotations = get.annotations
    updatedAnnotations["updated"] = "test-1"

    let update = try await client.updateSecret(
      request: .init().with {
        $0.updateMask = GoogleCloudWkt.FieldMask(paths: ["annotations", "labels", "versionAliases"])
        $0.secret = Secret().with {
          $0.name = create.name
          $0.labels = updatedLabels
          $0.etag = get.etag
          $0.versionAliases = ["test-alias": Int64(1)]
          $0.annotations = updatedAnnotations
        }
      }
    )
    logger.info("update = \(update)")

    logger.info("\nTesting listSecrets()")
    let secrets = try client.listSecrets(
      byItem: .init().with { $0.parent = "projects/\(projectId)" })
    var count: UInt64 = 0
    for try await secret in secrets {
      logger.info("  secret = \(secret)")
      count += 1
    }
    logger.info("item count = \(count)")

    logger.info("\nTesting deleteSecret()")
    try await client.deleteSecret(request: .init().with { $0.name = get.name })
    logger.info("deleteSecret() was successful")
  }

  static private func testSecretVersions(
    client: SecretManagerServiceClient, secretName: String, logger: Logger
  )
    async throws
  {
    logger.info("\nTesting secret version CRUD")
    let data = Data("the quick brown fox jumps over the lazy dog".utf8)
    let checksum = CryptoSwift.Checksum.crc32c(data.byteArray)
    let version = try await client.addSecretVersion(
      request: .init().with {
        $0.parent = secretName
        $0.payload = SecretPayload().with {
          $0.data = data
          $0.dataCrc32C = Int64(checksum)
        }
      })
    logger.info("version = \(version)")

    logger.info("\nTesting getSecretVersion()")
    let getVersion = try await client.getSecretVersion(
      request: .init().with { $0.name = version.name })
    logger.info("getVersion = \(getVersion)")

    logger.info("\nTesting accessSecretVersion()")
    let accessVersion = try await client.accessSecretVersion(
      request: .init().with { $0.name = version.name })
    logger.info("accessVersion payload length = \(accessVersion.payload?.data.count ?? 0)")

    logger.info("\nTesting disableSecretVersion()")
    let disabledVersion = try await client.disableSecretVersion(
      request: .init().with { $0.name = version.name })
    logger.info("disabledVersion state = \(disabledVersion.state)")

    logger.info("\nTesting enableSecretVersion()")
    let enabledVersion = try await client.enableSecretVersion(
      request: .init().with { $0.name = version.name })
    logger.info("enabledVersion state = \(enabledVersion.state)")

    logger.info("\nTesting listSecretVersions()")
    let versions = try client.listSecretVersions(
      byItem: .init().with { $0.parent = secretName })
    for try await version in versions {
      logger.info("  version = \(version)")
    }

    logger.info("\nTesting destroySecretVersion()")
    let destroyedVersion = try await client.destroySecretVersion(
      request: .init().with { $0.name = version.name })
    logger.info("destroyedVersion state = \(destroyedVersion.state)")
  }

  static private func testIAM(
    client: SecretManagerServiceClient, secretName: String, logger: Logger
  )
    async throws
  {
    logger.info("\nTesting IAM operations")
    let serviceAccount = try testServiceAccount();
    logger.info("Testing getIamPolicy()")
    var policy = try await client.getIamPolicy(
      request: .init().with { $0.resource = secretName })
    logger.info("policy = \(policy)")

    logger.info("Testing testIamPermissions()")
    let permissions = try await client.testIamPermissions(
      request: .init().with {
        $0.resource = secretName
        $0.permissions = ["secretmanager.versions.access"]
      })
    logger.info("permissions = \(permissions)")

    logger.info("Testing setIamPolicy()")
    let role = "roles/secretmanager.secretVersionAdder"
    if var found = policy.bindings.first(where: { $0.role == role }) {
      found.members.append("serviceAccount:\(serviceAccount)")
    } else {
      policy.bindings.append(
        Binding().with {
          $0.role = role
          $0.members = ["serviceAccount:\(serviceAccount)"]
        })
    }
    let updatedPolicy = try await client.setIamPolicy(
      request: .init().with {
        $0.resource = secretName
        $0.policy = policy
      })
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
      byItem: .init().with { $0.name = "projects/\(projectId)" })
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
        request: .init().with { $0.name = firstLocation.name })
      logger.info("location = \(location)")
    }
  }
}
