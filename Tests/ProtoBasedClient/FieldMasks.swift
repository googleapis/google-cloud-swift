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
// wiring WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
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
public enum FieldMasks {
  private static let retryOptions = testRetryOptions

  static public func run(_ logger: Logger) async throws {
    let projectId = try projectId()
    let secretId = randomSecretId()
    let secretName = "projects/\(projectId)/secrets/\(secretId)"
    let client = try SecretManagerServiceClient()

    logger.info("Creating secret with initial labels and annotations")
    let initialSecret: Secret
    do {
      initialSecret = try await client.createSecret(
        request: .init().with {
          $0.parent = "projects/\(projectId)"
          $0.secretId = secretId
          $0.secret = Secret().with { secret in
            secret.replication = Replication().with { replication in
              replication.replication = .automatic(Replication.Automatic())
            }
            secret.labels = [
              "integration-test": "true",
              "key1": "value1",
            ]
            secret.annotations = [
              "annotation1": "orig1"
            ]
          }
        },
        options: retryOptions
      )
    } catch let error where error.isAlreadyExists {
      logger.info("createSecret() returned alreadyExists; fetching existing secret")
      initialSecret = try await client.getSecret(
        request: .init().with { $0.name = secretName },
        options: retryOptions
      )
    }
    logger.info("Created secret = \(initialSecret)")

    defer {
      Task {
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
    }

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

    // Test 1: Partial update using flattened method and array literal updateMask: ["annotations"].
    // We pass changed values for both labels and annotations, but the field mask only specifies "annotations".
    logger.info("Testing partial update with array literal updateMask: [\"annotations\"]")
    var candidateLabels = currentSecret.labels
    candidateLabels["key1"] = "SHOULD_BE_IGNORED"
    candidateLabels["new_key"] = "SHOULD_BE_IGNORED"

    var candidateAnnotations = currentSecret.annotations
    candidateAnnotations["annotation1"] = "updated1"

    let updatedSecret1 = try await client.updateSecret(
      secret: Secret().with {
        $0.name = currentSecret.name
        $0.etag = currentSecret.etag
        $0.labels = candidateLabels
        $0.annotations = candidateAnnotations
      },
      updateMask: ["annotations"]
    )
    logger.info("Result of updating annotations only: \(updatedSecret1)")

    // Verify annotations were updated, but labels were ignored because "labels" was not in updateMask.
    #expect(updatedSecret1.annotations["annotation1"] == "updated1")
    #expect(updatedSecret1.labels["key1"] == "value1")
    #expect(updatedSecret1.labels["new_key"] == nil)

    // Test 2: Multiple fields update using array literal with snake_case path: ["labels", "version_aliases"].
    logger.info(
      "Testing updateMask with multiple fields and snake_case path: [\"labels\", \"version_aliases\"]"
    )
    var nextLabels = updatedSecret1.labels
    nextLabels["key1"] = "value1-updated"

    let updatedSecret2 = try await client.updateSecret(
      request: .init().with {
        $0.updateMask = ["labels", "version_aliases"]
        $0.secret = Secret().with {
          $0.name = updatedSecret1.name
          $0.etag = updatedSecret1.etag
          $0.labels = nextLabels
          $0.versionAliases = ["alias1": versionNumber]
          $0.annotations = ["annotation1": "SHOULD_NOT_CHANGE"]
        }
      },
      options: retryOptions
    )
    logger.info("Result of updating labels and version_aliases: \(updatedSecret2)")

    #expect(updatedSecret2.labels["key1"] == "value1-updated")
    #expect(updatedSecret2.versionAliases["alias1"] == versionNumber)
    #expect(updatedSecret2.annotations["annotation1"] == "updated1")

    // Test 3: Updating with explicit GoogleWKT.WKTFieldMask(paths:) and resetting a field.
    logger.info("Testing update with explicit WKTFieldMask(paths:) to clear annotations")
    let updatedSecret3 = try await client.updateSecret(
      request: .init().with {
        $0.updateMask = GoogleWKT.WKTFieldMask(paths: ["annotations"])
        $0.secret = Secret().with {
          $0.name = updatedSecret2.name
          $0.etag = updatedSecret2.etag
          $0.annotations = [:]
        }
      },
      options: retryOptions
    )
    logger.info("Result of resetting annotations: \(updatedSecret3)")

    #expect(updatedSecret3.annotations.isEmpty)
    #expect(updatedSecret3.labels["key1"] == "value1-updated")
    #expect(updatedSecret3.versionAliases["alias1"] == versionNumber)

    // Test 4: Full replacement update using wildcard mask: ["*"].
    logger.info("Testing full replacement update with wildcard mask: [\"*\"]")
    let updatedSecret4 = try await client.updateSecret(
      secret: Secret().with {
        $0.name = updatedSecret3.name
        $0.etag = updatedSecret3.etag
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
    logger.info("Result of wildcard update: \(updatedSecret4)")

    #expect(updatedSecret4.labels["wildcard"] == "success")
    #expect(updatedSecret4.labels["key1"] == nil)
    #expect(updatedSecret4.annotations["wildcard-annotation"] == "success")
    #expect(updatedSecret4.versionAliases.isEmpty)
  }
}
