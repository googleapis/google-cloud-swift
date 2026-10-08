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

/// Identifies a job.
///
/// A `nil` ``projectID`` means the project of the ``BigQueryClient``, and a `nil` ``location``
/// means the client's default location.
public struct JobID: Sendable, Hashable, CustomStringConvertible {
  /// The project that runs the job, or `nil` for the client project.
  public var projectID: String?

  /// The job ID within the project.
  public var jobID: String

  /// The location of the job, or `nil` for the client's default location.
  public var location: String?

  /// Creates a job ID.
  public init(projectID: String? = nil, jobID: String, location: String? = nil) {
    self.projectID = projectID
    self.jobID = jobID
    self.location = location
  }

  /// Creates a job ID that is unique with high probability.
  ///
  /// The client generates job IDs this way when you do not provide one. A client-generated ID
  /// makes job creation safe to retry.
  ///
  /// - Parameters:
  ///   - prefix: Prepended to the random part, for example `"daily_load_"`.
  ///   - projectID: The project, or `nil` for the client project.
  ///   - location: The location, or `nil` for the client's default location.
  public static func random(
    prefix: String = "", projectID: String? = nil, location: String? = nil
  ) -> JobID {
    JobID(
      projectID: projectID, jobID: prefix + UUID().uuidString.lowercased(), location: location)
  }

  /// `project:location.job`, the form used by the `bq` tool.
  public var description: String {
    var text = ""
    if let projectID { text += projectID + ":" }
    if let location { text += location + "." }
    return text + self.jobID
  }
}
