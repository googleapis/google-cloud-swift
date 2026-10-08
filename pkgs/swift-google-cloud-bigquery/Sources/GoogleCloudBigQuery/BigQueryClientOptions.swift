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

public import GoogleGax

/// Configuration for a ``BigQueryClient``.
///
/// ```swift
/// let client = try BigQueryClient(
///   BigQueryClientOptions().with {
///     $0.projectID = "my-project"
///     $0.location = "US"
///   })
/// ```
public struct BigQueryClientOptions: Sendable {
  /// Common options used by all Google Swift SDK clients.
  ///
  /// Use this to override the endpoint, credentials, retry and backoff policies, or the logger.
  /// If `client.retryPolicy` is `nil` the client uses ``BigQueryRetryPolicy/defaultPolicy``.
  /// The default `client.attemptTimeout` is 60 seconds.
  public var client: GoogleGax.ClientOptions = GoogleGax.ClientOptions().with {
    $0.attemptTimeout = .seconds(60)
  }

  /// The project used for requests that do not name a project explicitly.
  ///
  /// If `nil`, the client uses the `GOOGLE_CLOUD_PROJECT` or `GCLOUD_PROJECT` environment variables,
  /// or the `project_id` in the file named by `GOOGLE_APPLICATION_CREDENTIALS`.
  public var projectID: String?

  /// The default location for jobs and queries, for example `US` or `europe-west1`.
  ///
  /// The location is used for job IDs that do not specify a location. Datasets do not inherit
  /// this location.
  public var location: String?

  /// The job creation mode used by queries that do not set one.
  ///
  /// If `nil`, the service default applies.
  public var defaultJobCreationMode: JobCreationMode?

  /// Creates the default options.
  public init() {}

  /// Returns a copy of these options modified by `config`.
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}
