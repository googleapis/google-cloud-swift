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
import GoogleWKT
import Logging
import Testing

/// Integration tests for updating resources using field masks.
enum FieldMasks {
  private static let retryOptions = testRetryOptions

  static func run(_ logger: Logger) async throws {
    let projectId = try projectId()
    let secretId = randomSecretId()
    let client = try SecretManagerServiceClient()

    try await withTestSecret(
      client: client, projectId: projectId, secretId: secretId, logger: logger
    ) { initialSecret in
      #expect(initialSecret.labels["key1"] == "value1")
      #expect(initialSecret.annotations["annotation1"] == "orig1")

      // Add a secret version so version 1 exists for version alias testing.
      logger.info("Adding secret version to \(initialSecret.name)")
      let version1 = try await client.addSecretVersion(
        request: .init().with {
          $0.parent = initialSecret.name
          $0.payload = SecretPayload().with {
            $0.data = Data("test-data".utf8)
          }
        },
        options: retryOptions
      )
      logger.info("Added secret version: \(version1.name)")
      let versionNumber = Int64(version1.name.split(separator: "/").last ?? "1") ?? 1

      // Fetch the secret to ensure we have the fresh etag.
      let currentSecret = try await client.getSecret(
        request: .init().with { $0.name = initialSecret.name },
        options: retryOptions
      )

      let secret1 = try await testPartialUpdate(
        client: client, secret: currentSecret, logger: logger)
      let secret2 = try await testMultipleFieldsAndSnakeCase(
        client: client, secret: secret1, versionNumber: versionNumber, logger: logger)
      let secret3 = try await testClearingField(
        client: client, secret: secret2, versionNumber: versionNumber, logger: logger)
      try await testWildcardReplacement(client: client, secret: secret3, logger: logger)
    }
  }

  /// Scoped test helper to create a Secret and guarantee its awaited cleanup.
  private static func withTestSecret(
    client: SecretManagerServiceClient,
    projectId: String,
    secretId: String,
    logger: Logger,
    _ body: (Secret) async throws -> Void
  ) async throws {
    let secretName = "projects/\(projectId)/secrets/\(secretId)"
    logger.info("Creating secret with initial labels and annotations: \(secretName)")
    let secret: Secret
    do {
      secret = try await client.createSecret(
        request: .init().with {
          $0.parent = "projects/\(projectId)"
          $0.secretId = secretId
          $0.secret = Secret().with { s in
            s.replication = Replication().with { replication in
              replication.replication = .automatic(Replication.Automatic())
            }
            s.labels = [
              "integration-test": "true",
              "key1": "value1",
            ]
            s.annotations = [
              "annotation1": "orig1"
            ]
          }
        },
        options: retryOptions
      )
    } catch let error where error.isAlreadyExists {
      logger.info("createSecret() returned alreadyExists; fetching existing secret")
      secret = try await client.getSecret(
        request: .init().with { $0.name = secretName },
        options: retryOptions
      )
    }
    logger.info("Created secret = \(secret)")

    func cleanup() async {
      logger.info("Cleaning up secret \(secretName)")
      do {
        try await client.deleteSecret(
          request: .init().with { $0.name = secretName },
          options: retryOptions
        )
      } catch let error where error.isNotFound {
        // Already deleted
      } catch {
        logger.warning("Failed to clean up secret \(secretName): \(error)")
      }
    }

    do {
      try await body(secret)
    } catch {
      await cleanup()
      throw error
    }
    await cleanup()
  }

  /// Test 1: Partial update using flattened method and array literal updateMask: ["annotations"].
  /// We pass changed values for both labels and annotations, but the field mask only specifies "annotations".
  private static func testPartialUpdate(
    client: SecretManagerServiceClient,
    secret: Secret,
    logger: Logger
  ) async throws -> Secret {
    logger.info("Testing partial update with array literal updateMask: [\"annotations\"]")
    var candidateLabels = secret.labels
    candidateLabels["key1"] = "SHOULD_BE_IGNORED"
    candidateLabels["new_key"] = "SHOULD_BE_IGNORED"

    var candidateAnnotations = secret.annotations
    candidateAnnotations["annotation1"] = "updated1"

    let updatedSecret = try await client.updateSecret(
      secret: Secret().with {
        $0.name = secret.name
        $0.etag = secret.etag
        $0.labels = candidateLabels
        $0.annotations = candidateAnnotations
      },
      updateMask: ["annotations"]
    )
    logger.info("Result of updating annotations only: \(updatedSecret)")

    #expect(updatedSecret.annotations["annotation1"] == "updated1")
    #expect(updatedSecret.labels["key1"] == "value1")
    #expect(updatedSecret.labels["new_key"] == nil)
    return updatedSecret
  }

  /// Test 2: Multiple fields update using array literal with snake_case path: ["labels", "version_aliases"].
  private static func testMultipleFieldsAndSnakeCase(
    client: SecretManagerServiceClient,
    secret: Secret,
    versionNumber: Int64,
    logger: Logger
  ) async throws -> Secret {
    logger.info(
      "Testing updateMask with multiple fields and snake_case path: [\"labels\", \"version_aliases\"]"
    )
    var nextLabels = secret.labels
    nextLabels["key1"] = "value1-updated"

    let updatedSecret = try await client.updateSecret(
      request: .init().with {
        $0.updateMask = ["labels", "version_aliases"]
        $0.secret = Secret().with {
          $0.name = secret.name
          $0.etag = secret.etag
          $0.labels = nextLabels
          $0.versionAliases = ["alias1": versionNumber]
          $0.annotations = ["annotation1": "SHOULD_NOT_CHANGE"]
        }
      },
      options: retryOptions
    )
    logger.info("Result of updating labels and version_aliases: \(updatedSecret)")

    #expect(updatedSecret.labels["key1"] == "value1-updated")
    #expect(updatedSecret.versionAliases["alias1"] == versionNumber)
    #expect(updatedSecret.annotations["annotation1"] == "updated1")
    return updatedSecret
  }

  /// Test 3: Updating with explicit GoogleWKT.WKTFieldMask(paths:) and resetting a field.
  private static func testClearingField(
    client: SecretManagerServiceClient,
    secret: Secret,
    versionNumber: Int64,
    logger: Logger
  ) async throws -> Secret {
    logger.info("Testing update with explicit WKTFieldMask(paths:) to clear annotations")
    let updatedSecret = try await client.updateSecret(
      request: .init().with {
        $0.updateMask = GoogleWKT.WKTFieldMask(paths: ["annotations"])
        $0.secret = Secret().with {
          $0.name = secret.name
          $0.etag = secret.etag
          $0.annotations = [:]
        }
      },
      options: retryOptions
    )
    logger.info("Result of resetting annotations: \(updatedSecret)")

    #expect(updatedSecret.annotations.isEmpty)
    #expect(updatedSecret.labels["key1"] == "value1-updated")
    #expect(updatedSecret.versionAliases["alias1"] == versionNumber)
    return updatedSecret
  }

  /// Test 4: Full replacement update using wildcard mask: ["*"].
  private static func testWildcardReplacement(
    client: SecretManagerServiceClient,
    secret: Secret,
    logger: Logger
  ) async throws {
    logger.info("Testing full replacement update with wildcard mask: [\"*\"]")
    let updatedSecret = try await client.updateSecret(
      secret: Secret().with {
        $0.name = secret.name
        $0.etag = secret.etag
        $0.labels = [
          "integration-test": "true",
          "wildcard": "success",
        ]
        $0.annotations = [
          "wildcard-annotation": "success"
        ]
        $0.versionAliases = [:]
      },
      updateMask: ["*"]
    )
    logger.info("Result of wildcard update: \(updatedSecret)")

    #expect(updatedSecret.labels["wildcard"] == "success")
    #expect(updatedSecret.labels["key1"] == nil)
    #expect(updatedSecret.annotations["wildcard-annotation"] == "success")
    #expect(updatedSecret.versionAliases.isEmpty)
  }
}
