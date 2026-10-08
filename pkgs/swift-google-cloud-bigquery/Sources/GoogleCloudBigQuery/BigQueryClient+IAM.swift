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
public import GoogleGax
import GoogleIAMV1

extension BigQueryClient {
  /// Returns the IAM policy of a table or view.
  ///
  /// - Parameters:
  ///   - table: the table. A `nil` project means the client's project.
  ///   - requestedPolicyVersion: the policy version (1 or 3) to return. Policies with
  ///     conditional bindings require version 3. `nil` uses the service default.
  ///   - options: per-call options.
  public func getIAMPolicy(
    for table: TableID,
    requestedPolicyVersion: Int32? = nil,
    options: RequestOptions = .init()
  ) async throws -> IAMPolicy {
    let wire = GetIamPolicyRequest().with {
      if let requestedPolicyVersion {
        $0.options = GetPolicyOptions().with {
          $0.requestedPolicyVersion = requestedPolicyVersion
        }
      }
    }
    let policy: Policy = try await self.transport.json(
      self.iamRequest(table, "getIamPolicy", body: RequestBody.json(wire, omitting: ["resource"]),
        options: options),
      idempotent: true)
    return IAMPolicy(wire: policy)
  }

  /// Replaces the IAM policy of a table or view.
  ///
  /// To change a policy safely, read it with ``getIAMPolicy(for:requestedPolicyVersion:options:)``,
  /// change its bindings, and pass it back with its ``IAMPolicy/etag``: the service then
  /// rejects the update if the policy changed in between.
  ///
  /// The request is retried only when the policy has an etag, because a retry could otherwise
  /// overwrite a concurrent change.
  ///
  /// - Parameters:
  ///   - policy: the complete new policy.
  ///   - table: the table. A `nil` project means the client's project.
  ///   - options: per-call options.
  /// - Returns: the policy as stored by the service.
  public func setIAMPolicy(
    _ policy: IAMPolicy,
    for table: TableID,
    options: RequestOptions = .init()
  ) async throws -> IAMPolicy {
    let wire = SetIamPolicyRequest().with { $0.policy = policy.wire }
    var omitting = ["resource"]
    if policy.version == nil { omitting.append("policy.version") }
    if policy.etag == nil { omitting.append("policy.etag") }
    let stored: Policy = try await self.transport.json(
      self.iamRequest(
        table, "setIamPolicy", body: RequestBody.json(wire, omitting: omitting), options: options),
      idempotent: policy.etag != nil)
    return IAMPolicy(wire: stored)
  }

  /// Returns the subset of `permissions` that the caller has on a table or view.
  ///
  /// - Parameters:
  ///   - permissions: the permissions to check, for example `["bigquery.tables.getData"]`.
  ///   - table: the table. A `nil` project means the client's project.
  ///   - options: per-call options.
  /// - Returns: the granted permissions, or an empty array if none are granted.
  public func testIAMPermissions(
    _ permissions: [String],
    for table: TableID,
    options: RequestOptions = .init()
  ) async throws -> [String] {
    let wire = TestIamPermissionsRequest().with { $0.permissions = permissions }
    let response: TestIamPermissionsResponse = try await self.transport.json(
      self.iamRequest(
        table, "testIamPermissions", body: RequestBody.json(wire, omitting: ["resource"]),
        options: options),
      idempotent: true)
    return response.permissions
  }

  /// Builds `POST /bigquery/v2/projects/{p}/datasets/{d}/tables/{t}:{method}`.
  private func iamRequest(
    _ table: TableID, _ method: String, body: Data, options: RequestOptions
  ) -> HTTPRequest {
    let table = self.resolve(table)
    let path =
      DatasetID(projectID: table.projectID, datasetID: table.datasetID).resourcePath
      + "/tables/\(HTTPRequest.encode(segment: table.tableID)):\(method)"
    return HTTPRequest(method: .post, path: path, body: body, options: options)
  }
}

extension IAMPolicy {
  init(wire: Policy) {
    self.init(
      version: wire.version == 0 ? nil : wire.version,
      bindings: wire.bindings.map { binding in
        Binding(
          role: binding.role, members: binding.members,
          condition: binding.condition.map {
            Expr(
              $0.expression, title: $0.title.nonEmpty, description: $0.description.nonEmpty,
              location: $0.location.nonEmpty)
          })
      },
      etag: wire.etag.isEmpty ? nil : wire.etag)
  }

  var wire: Policy {
    Policy().with {
      $0.version = self.version ?? 0
      $0.etag = self.etag ?? Data()
      $0.bindings = self.bindings.map { binding in
        GoogleIAMV1.Binding().with {
          $0.role = binding.role
          $0.members = binding.members
          if let condition = binding.condition {
            $0.condition = .init()
            $0.condition?.expression = condition.expression
            $0.condition?.title = condition.title ?? ""
            $0.condition?.description = condition.description ?? ""
            $0.condition?.location = condition.location ?? ""
          }
        }
      }
    }
  }
}
