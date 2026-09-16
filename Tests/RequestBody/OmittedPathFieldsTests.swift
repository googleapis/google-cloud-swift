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
import GoogleAuth
import GoogleCloudBuildV1
import GoogleCloudGax
import GoogleCloudSecretManagerV1
import GoogleCloudTestHelpers
import GoogleCloudWKT
import GoogleIAMV1
import Testing

/// Verifies the generated code does not duplicate the URL path parameters in the request body.
///
/// Some services reject requests where a field appears both in the URL path and in the JSON
/// payload. See https://github.com/googleapis/google-cloud-swift/issues/521.
@Suite struct OmittedPathFieldsTests {
  /// The client options to reach `server` without credentials.
  static func options(_ server: CaptureServer) throws -> ClientOptions {
    let credentials = try Credentials(configuration: .anonymous)
    return ClientOptions().with {
      $0.endpoint = server.endpoint
      $0.credentials = credentials
    }
  }

  @Test func addSecretVersionOmitsParent() async throws {
    try await CaptureServer.withServer { server in
      let client = try SecretManagerServiceClient(Self.options(server))
      _ = try await client.addSecretVersion(
        request: .init().with {
          $0.parent = "projects/my-project/secrets/my-secret"
          $0.payload = SecretPayload().with { $0.data = Data("secret-data".utf8) }
        })

      let request = try #require(server.requests.first)
      #expect(request.method == .POST)
      #expect(request.uri.hasPrefix("/v1/projects/my-project/secrets/my-secret:addVersion?"))
      let json = try request.json()
      #expect(json["parent"] == nil, "unexpected 'parent' in \(json)")
      #expect(json["payload"] != nil, "missing 'payload' in \(json)")
    }
  }

  @Test func setIamPolicyOmitsResourceAndKeepsSiblings() async throws {
    try await CaptureServer.withServer { server in
      let client = try SecretManagerServiceClient(Self.options(server))
      _ = try await client.setIamPolicy(
        request: .init().with {
          $0.resource = "projects/my-project/secrets/my-secret"
          $0.policy = Policy().with { $0.version = 3 }
          $0.updateMask = FieldMask(paths: ["bindings"])
        })

      let request = try #require(server.requests.first)
      #expect(request.uri.hasPrefix("/v1/projects/my-project/secrets/my-secret:setIamPolicy?"))
      let json = try request.json()
      #expect(json["resource"] == nil, "unexpected 'resource' in \(json)")
      #expect(json["policy"] != nil, "missing 'policy' in \(json)")
      #expect(json["updateMask"] != nil, "missing 'updateMask' in \(json)")
    }
  }

  @Test func cancelBuildOmitsAllPathFields() async throws {
    try await CaptureServer.withServer { server in
      // This binding interpolates two fields into the path:
      //     POST /v1/projects/{projectId}/builds/{id}:cancel
      let client = try CloudBuildClient(Self.options(server))
      _ = try await client.cancelBuild(
        request: .init().with {
          $0.projectId = "my-project"
          $0.id = "my-build"
        })

      let request = try #require(server.requests.first)
      #expect(request.uri.hasPrefix("/v1/projects/my-project/builds/my-build:cancel?"))
      let json = try request.json()
      #expect(json["projectId"] == nil, "unexpected 'projectId' in \(json)")
      #expect(json["id"] == nil, "unexpected 'id' in \(json)")
    }
  }

  @Test func createSecretKeepsNamedBody() async throws {
    try await CaptureServer.withServer { server in
      // `createSecret` uses `body: "secret"`, only the named field is sent. The path parameters
      // are not part of that payload to begin with, nothing is omitted.
      let client = try SecretManagerServiceClient(Self.options(server))
      _ = try await client.createSecret(
        request: .init().with {
          $0.parent = "projects/my-project"
          $0.secretId = "my-secret"
          $0.secret = Secret().with { $0.etag = "my-etag" }
        })

      let request = try #require(server.requests.first)
      #expect(request.uri.hasPrefix("/v1/projects/my-project/secrets?"))
      let json = try request.json()
      #expect(json["etag"] as? String == "my-etag")
      #expect(json["parent"] == nil, "unexpected 'parent' in \(json)")
      #expect(json["secretId"] == nil, "unexpected 'secretId' in \(json)")
    }
  }
}
