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

/// A project that the caller can use with BigQuery, as returned by
/// ``BigQueryClient/listProjects(pageSize:pageToken:options:)``.
public struct Project: Sendable, Hashable {
  /// The project ID, for example `my-project`.
  public var projectID: String

  /// The numeric project number.
  public var numericID: UInt64?

  /// The project's display name.
  public var friendlyName: String?

  /// Creates a project description.
  public init(projectID: String, numericID: UInt64? = nil, friendlyName: String? = nil) {
    self.projectID = projectID
    self.numericID = numericID
    self.friendlyName = friendlyName
  }
}
