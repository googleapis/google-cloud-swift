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
import GoogleCloudBigQueryV2
public import GoogleGax

extension BigQueryClient {
  /// Returns the email of the service account that BigQuery uses for a project, for example
  /// to grant it access to a Cloud KMS key.
  ///
  /// - Parameters:
  ///   - projectID: the project, or `nil` for the client's project.
  ///   - options: per-call options.
  public func getServiceAccount(
    projectID: String? = nil,
    options: RequestOptions = .init()
  ) async throws -> String {
    let path =
      "/bigquery/v2/projects/\(HTTPRequest.encode(segment: projectID ?? self.projectID))"
      + "/serviceAccount"
    let response: GetServiceAccountResponse = try await self.transport.json(
      HTTPRequest(method: .get, path: path, options: options), idempotent: true)
    return response.email
  }

  /// Lists the projects that the caller can use with BigQuery.
  ///
  /// - Parameters:
  ///   - pageSize: the maximum number of projects per page, or `nil` for the service default.
  ///   - pageToken: the page to start from, from ``Page/nextPageToken``.
  ///   - options: per-call options, applied to every page request.
  public func listProjects(
    pageSize: Int? = nil,
    pageToken: String? = nil,
    options: RequestOptions = .init()
  ) -> PagedSequence<Project> {
    PagedSequence { [transport] token in
      let list: ProjectList = try await transport.json(
        HTTPRequest(
          method: .get, path: "/bigquery/v2/projects",
          query: ResourcePaging.query(pageSize, token ?? pageToken), options: options),
        idempotent: true)
      return Page(
        items: (list.projects ?? []).map(Project.init(wire:)),
        nextPageToken: list.nextPageToken?.nonEmpty)
    }
  }
}

/// The `projects.list` response. The `bigquery/v2` protos do not define it.
struct ProjectList: Decodable {
  struct Entry: Decodable {
    struct Reference: Decodable {
      var projectId: String?
    }

    var id: String?
    var numericId: String?
    var projectReference: Reference?
    var friendlyName: String?
  }

  var projects: [Entry]?
  var nextPageToken: String?
}

extension Project {
  init(wire: ProjectList.Entry) {
    self.init(
      projectID: wire.projectReference?.projectId ?? wire.id ?? "",
      numericID: wire.numericId.flatMap { UInt64($0) },
      friendlyName: wire.friendlyName?.nonEmpty)
  }
}
