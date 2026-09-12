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
import GoogleCloudBuildV1
import GoogleCloudGax
import GoogleCloudTestHelpers
import Logging
import Testing

/// Run tests for Cloud Build multiple HTTP bindings.
public enum CloudBuild {
  static public func run(_ logger: Logger) async throws {
    let project = try projectId()
    let client = try CloudBuildClient()

    logger.info("Testing listBuilds with projectId (binding 1)")
    let byProject = try await testListBuildsByProject(
      client: client, projectId: project, logger: logger)

    logger.info("Testing listBuilds with parent (binding 2)")
    let byParent = try await testListBuildsByParent(
      client: client, projectId: project, logger: logger)

    logger.info("Testing getBuild with different fields")
    let build = byProject.builds.first ?? byParent.builds.first
    await testGetBuild(client: client, projectId: project, existingBuild: build, logger: logger)

    logger.info("Testing Cloud Build binding error when required fields are missing")
    await testCloudBuildBindingErrors(client: client, projectId: project, logger: logger)
  }

  static func testListBuildsByProject(
    client: CloudBuildClient, projectId: String, logger: Logger
  ) async throws -> ListBuildsResponse {
    // Binding 1: GET /v1/projects/{project_id}/builds
    // Uses `projectId` in path.
    let response = try await client.listBuilds(
      request: ListBuildsRequest().with {
        $0.projectId = projectId
        $0.pageSize = 5
      })
    logger.info("listBuilds(projectId) returned \(response.builds.count) builds")
    return response
  }

  static func testListBuildsByParent(
    client: CloudBuildClient, projectId: String, logger: Logger
  ) async throws -> ListBuildsResponse {
    // Binding 2: GET /v1/{parent=projects/*/locations/*}/builds
    // Uses `parent` in path.
    let response = try await client.listBuilds(
      request: ListBuildsRequest().with {
        $0.parent = "projects/\(projectId)/locations/global"
        $0.pageSize = 5
      })
    logger.info("listBuilds(parent) returned \(response.builds.count) builds")
    return response
  }

  static func testGetBuild(
    client: CloudBuildClient, projectId: String, existingBuild: Build?, logger: Logger
  ) async {
    if let existingBuild {
      logger.info("Found existing build id=\(existingBuild.id), name=\(existingBuild.name)")
      // Binding 1: GET /v1/projects/{project_id}/builds/{id}
      // Uses `projectId` and `id` in path.
      do {
        let build1 = try await client.getBuild(
          request: GetBuildRequest().with {
            $0.projectId = projectId
            $0.id = existingBuild.id
          })
        #expect(build1.id == existingBuild.id)
        logger.info("Successfully fetched build via binding 1 (projectId + id)")
      } catch {
        Issue.record("Failed to get build via binding 1: \(error)")
      }

      // Binding 2: GET /v1/{name=projects/*/locations/*/builds/*}
      // Uses `name` in path.
      let name =
        existingBuild.name.isEmpty
        ? "projects/\(projectId)/locations/global/builds/\(existingBuild.id)"
        : existingBuild.name
      do {
        let build2 = try await client.getBuild(
          request: GetBuildRequest().with {
            $0.name = name
          })
        #expect(build2.id == existingBuild.id)
        logger.info("Successfully fetched build via binding 2 (name)")
      } catch {
        Issue.record("Failed to get build via binding 2: \(error)")
      }
    } else {
      logger.info("No existing builds in project; testing getBuild routing with non-existent build")
      let fakeId = "non-existent-build-\(UUID().uuidString.prefix(8))"

      // Binding 1: GET /v1/projects/{project_id}/builds/{id}
      do {
        _ = try await client.getBuild(
          request: GetBuildRequest().with {
            $0.projectId = projectId
            $0.id = fakeId
          })
        Issue.record("Expected getBuild to throw RequestError.service, but it succeeded")
      } catch let RequestError.service(error) {
        #expect(error.httpStatusCode == 404)
        logger.info("Binding 1 reached Cloud Build and returned expected 404 NOT_FOUND")
      } catch {
        Issue.record("Expected RequestError.service, got: \(error)")
      }

      // Binding 2: GET /v1/{name=projects/*/locations/*/builds/*}
      let fakeName = "projects/\(projectId)/locations/global/builds/\(fakeId)"
      do {
        _ = try await client.getBuild(
          request: GetBuildRequest().with {
            $0.name = fakeName
          })
        Issue.record("Expected getBuild to throw RequestError.service, but it succeeded")
      } catch let RequestError.service(error) {
        #expect(error.httpStatusCode == 404)
        logger.info("Binding 2 reached Cloud Build and returned expected 404 NOT_FOUND")
      } catch {
        Issue.record("Expected RequestError.service, got: \(error)")
      }
    }
  }

  static func testCloudBuildBindingErrors(
    client: CloudBuildClient, projectId: String, logger: Logger
  ) async {
    // 1. listBuilds with no fields set (both candidate bindings fail)
    do {
      _ = try await client.listBuilds(request: ListBuildsRequest())
      Issue.record("Expected listBuilds with empty request to throw RequestError.binding")
    } catch let RequestError.binding(bindingError) {
      #expect(bindingError.paths.count == 2)
      // Candidate 1 expects project_id
      #expect(bindingError.paths[0].substitutions.count == 1)
      #expect(bindingError.paths[0].substitutions[0].fieldName == "project_id")
      // Candidate 2 expects parent matching projects/*/locations/*
      #expect(bindingError.paths[1].substitutions.count == 1)
      #expect(bindingError.paths[1].substitutions[0].fieldName == "parent")
      logger.info("Caught expected BindingError for empty listBuilds request: \(bindingError)")
    } catch {
      Issue.record("Expected RequestError.binding, got: \(error)")
    }

    // 2. getBuild with only projectId (missing id for candidate 1, and missing name for candidate 2)
    do {
      _ = try await client.getBuild(
        request: GetBuildRequest().with {
          $0.projectId = projectId
        })
      Issue.record("Expected getBuild with missing id to throw RequestError.binding")
    } catch let RequestError.binding(bindingError) {
      #expect(bindingError.paths.count == 2)
      // Candidate 1 fails because id is unset
      #expect(bindingError.paths[0].substitutions.count == 1)
      #expect(bindingError.paths[0].substitutions[0].fieldName == "id")
      // Candidate 2 fails because name is unset
      #expect(bindingError.paths[1].substitutions.count == 1)
      #expect(bindingError.paths[1].substitutions[0].fieldName == "name")
      logger.info("Caught expected BindingError for partial getBuild request: \(bindingError)")
    } catch {
      Issue.record("Expected RequestError.binding, got: \(error)")
    }
  }
}
