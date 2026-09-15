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
import GoogleCloudLocation
import GoogleCloudSecretManagerV1
import GoogleCloudTestHelpers
import Logging
import Testing

/// Run integration tests for multiple HTTP bindings mismatch error reporting.
public enum MultipleBindings {
  static public func run(_ logger: Logger) async throws {
    let client = try SecretManagerServiceClient()

    logger.info("Testing multiple bindings mismatch when field is unset/empty")
    await testEmptyFieldThrowsBindingError(client: client, logger: logger)

    logger.info("Testing multiple bindings mismatch when field has wrong format")
    await testMalformedFieldThrowsBindingError(client: client, logger: logger)

    logger.info("Testing multiple bindings mismatch with partial prefix match")
    await testPartialPrefixMismatchThrowsBindingError(client: client, logger: logger)

    logger.info("Testing multiple bindings mismatch on enableManagedRotation")
    await testEnableManagedRotationMismatch(client: client, logger: logger)

    logger.info("Testing single-binding method structured error")
    await testSingleBindingThrowsStructuredError(client: client, logger: logger)

    logger.info("Testing dot validation error")
    await testDotValidationThrowsBindingError(client: client, logger: logger)
  }

  static func testEmptyFieldThrowsBindingError(
    client: SecretManagerServiceClient, logger: Logger
  ) async {
    // getSecret has 2 bindings:
    // 1. GET /v1/{name=projects/*/secrets/*}
    // 2. GET /v1/{name=projects/*/locations/*/secrets/*}
    do {
      _ = try await client.getSecret(request: GetSecretRequest())
      Issue.record("Expected getSecret to throw RequestError.binding, but it succeeded")
    } catch let RequestError.binding(bindingError) {
      logger.info("Caught expected BindingError for empty field: \(bindingError)")
      #expect(bindingError.paths.count == 2)
      #expect(bindingError.paths[0].substitutions.count == 1)
      #expect(bindingError.paths[0].substitutions[0].fieldName == "name")
      #expect(
        bindingError.paths[0].substitutions[0].problem
          == .unsetExpecting("projects/*/secrets/*"))

      #expect(bindingError.paths[1].substitutions.count == 1)
      #expect(bindingError.paths[1].substitutions[0].fieldName == "name")
      #expect(
        bindingError.paths[1].substitutions[0].problem
          == .unsetExpecting("projects/*/locations/*/secrets/*"))

      let desc = bindingError.description
      #expect(desc.contains("at least one of the conditions must be met"))
      #expect(desc.contains("projects/*/secrets/*"))
      #expect(desc.contains("projects/*/locations/*/secrets/*"))
    } catch {
      Issue.record("Expected RequestError.binding, but got: \(error)")
    }
  }

  static func testMalformedFieldThrowsBindingError(
    client: SecretManagerServiceClient, logger: Logger
  ) async {
    let invalidName = "invalid-secret-name"
    do {
      _ = try await client.getSecret(
        request: .init().with {
          $0.name = invalidName
        })
      Issue.record("Expected getSecret to throw RequestError.binding, but it succeeded")
    } catch let RequestError.binding(bindingError) {
      logger.info("Caught expected BindingError for malformed field: \(bindingError)")
      #expect(bindingError.paths.count == 2)
      #expect(bindingError.paths[0].substitutions.count == 1)
      #expect(bindingError.paths[0].substitutions[0].fieldName == "name")
      #expect(
        bindingError.paths[0].substitutions[0].problem
          == .mismatchExpecting(actual: invalidName, expected: "projects/*/secrets/*"))

      #expect(bindingError.paths[1].substitutions.count == 1)
      #expect(bindingError.paths[1].substitutions[0].fieldName == "name")
      #expect(
        bindingError.paths[1].substitutions[0].problem
          == .mismatchExpecting(actual: invalidName, expected: "projects/*/locations/*/secrets/*"))

      let desc = bindingError.description
      #expect(desc.contains("at least one of the conditions must be met"))
      #expect(desc.contains("found: '\(invalidName)'"))
    } catch {
      Issue.record("Expected RequestError.binding, but got: \(error)")
    }
  }

  static func testPartialPrefixMismatchThrowsBindingError(
    client: SecretManagerServiceClient, logger: Logger
  ) async {
    // addSecretVersion has 2 bindings:
    // 1. POST /v1/{parent=projects/*/secrets/*}/versions
    // 2. POST /v1/{parent=projects/*/locations/*/secrets/*}/versions
    // "projects/my-project" matches "projects/*" prefix, but is missing "/secrets/*".
    let partialParent = "projects/my-project"
    do {
      _ = try await client.addSecretVersion(
        request: .init().with {
          $0.parent = partialParent
          $0.payload = SecretPayload().with { $0.data = Data("test".utf8) }
        })
      Issue.record("Expected addSecretVersion to throw RequestError.binding, but it succeeded")
    } catch let RequestError.binding(bindingError) {
      logger.info("Caught expected BindingError for partial match: \(bindingError)")
      #expect(bindingError.paths.count == 2)
      #expect(bindingError.paths[0].substitutions.count == 1)
      #expect(bindingError.paths[0].substitutions[0].fieldName == "parent")
      #expect(
        bindingError.paths[0].substitutions[0].problem
          == .mismatchExpecting(actual: partialParent, expected: "projects/*/secrets/*"))

      #expect(bindingError.paths[1].substitutions.count == 1)
      #expect(bindingError.paths[1].substitutions[0].fieldName == "parent")
      #expect(
        bindingError.paths[1].substitutions[0].problem
          == .mismatchExpecting(actual: partialParent, expected: "projects/*/locations/*/secrets/*")
      )
    } catch {
      Issue.record("Expected RequestError.binding, but got: \(error)")
    }
  }

  static func testEnableManagedRotationMismatch(
    client: SecretManagerServiceClient, logger: Logger
  ) async {
    // enableManagedRotation has 2 bindings:
    // 1. POST /v1/{parent=projects/*/secrets/*}:enableManagedRotation
    // 2. POST /v1/{parent=projects/*/locations/*/secrets/*}:enableManagedRotation
    let invalidParent = "organizations/123/secrets/s1"
    do {
      _ = try await client.enableManagedRotation(
        request: .init().with {
          $0.parent = invalidParent
        })
      Issue.record("Expected enableManagedRotation to throw RequestError.binding, but it succeeded")
    } catch let RequestError.binding(bindingError) {
      logger.info("Caught expected BindingError on enableManagedRotation: \(bindingError)")
      #expect(bindingError.paths.count == 2)
      #expect(
        bindingError.paths[0].substitutions[0].problem
          == .mismatchExpecting(actual: invalidParent, expected: "projects/*/secrets/*"))
      #expect(
        bindingError.paths[1].substitutions[0].problem
          == .mismatchExpecting(actual: invalidParent, expected: "projects/*/locations/*/secrets/*")
      )
    } catch {
      Issue.record("Expected RequestError.binding, but got: \(error)")
    }
  }

  static func testSingleBindingThrowsStructuredError(
    client: SecretManagerServiceClient, logger: Logger
  ) async {
    // listLocations has 1 binding:
    // 1. GET /v1/{name=projects/*}/locations
    do {
      _ = try await client.listLocations(request: GoogleCloudLocation.ListLocationsRequest())
      Issue.record("Expected listLocations to throw RequestError.binding, but it succeeded")
    } catch let RequestError.binding(bindingError) {
      logger.info("Caught expected single-binding error: \(bindingError)")
      #expect(bindingError.paths.count == 1)
      #expect(bindingError.paths[0].substitutions.count == 1)
      #expect(bindingError.paths[0].substitutions[0].fieldName == "name")
      #expect(
        bindingError.paths[0].substitutions[0].problem
          == .unsetExpecting("projects/*"))
      #expect(
        bindingError.description
          == "field 'name' needs to be set and match the template: 'projects/*'")
    } catch {
      Issue.record("Expected RequestError.binding, but got: \(error)")
    }
  }

  static func testDotValidationThrowsBindingError(
    client: SecretManagerServiceClient, logger: Logger
  ) async {
    // 1. Single wildcard '.' throws BindingError
    do {
      _ = try await client.getSecret(
        request: .init().with {
          $0.name = "projects/p/secrets/."
        })
      Issue.record("Expected getSecret with '.' to throw RequestError.binding, but it succeeded")
    } catch let RequestError.binding(bindingError) {
      logger.info("Caught expected BindingError for dot validation: \(bindingError)")
      #expect(bindingError.description == "Invalid value . for name")
      #expect(bindingError.paths.count == 1)
      #expect(bindingError.paths[0].substitutions[0].fieldName == "name")
      #expect(bindingError.paths[0].substitutions[0].problem == .invalidValue(actual: "."))
    } catch {
      Issue.record("Expected RequestError.binding, but got: \(error)")
    }

    // 2. Single wildcard '..' throws BindingError
    do {
      _ = try await client.getSecret(
        request: .init().with {
          $0.name = "projects/p/secrets/.."
        })
      Issue.record("Expected getSecret with '..' to throw RequestError.binding, but it succeeded")
    } catch let RequestError.binding(bindingError) {
      logger.info("Caught expected BindingError for double-dot validation: \(bindingError)")
      #expect(bindingError.description == "Invalid value .. for name")
      #expect(bindingError.paths.count == 1)
      #expect(bindingError.paths[0].substitutions[0].fieldName == "name")
      #expect(bindingError.paths[0].substitutions[0].problem == .invalidValue(actual: ".."))
    } catch {
      Issue.record("Expected RequestError.binding, but got: \(error)")
    }
  }
}
