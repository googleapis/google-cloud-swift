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

/// Determines the default project of a client.
enum ProjectDiscovery {
  /// Returns the first project ID found in, in order: `explicit`, `GOOGLE_CLOUD_PROJECT`,
  /// `GCLOUD_PROJECT`, and the `project_id` of the `GOOGLE_APPLICATION_CREDENTIALS` file.
  ///
  /// - Throws: ``BigQueryError`` with kind `invalidArgument` if no source has a project.
  static func resolve(explicit: String?, environment: [String: String]) throws -> String {
    if let explicit, !explicit.isEmpty { return explicit }
    for name in ["GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT"] {
      if let project = environment[name], !project.isEmpty { return project }
    }
    if let path = environment["GOOGLE_APPLICATION_CREDENTIALS"], !path.isEmpty,
      let data = FileManager.default.contents(atPath: path),
      let file = try? JSONDecoder().decode(CredentialsFile.self, from: data),
      let project = file.projectID, !project.isEmpty
    {
      return project
    }
    throw BigQueryError.invalidArgument(
      "cannot determine the project ID: set BigQueryClientOptions.projectID or the "
        + "GOOGLE_CLOUD_PROJECT environment variable")
  }

  private struct CredentialsFile: Decodable {
    var projectID: String?

    enum CodingKeys: String, CodingKey {
      case projectID = "project_id"
    }
  }
}
