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
@_spi(GoogleCloudInternal) import GoogleGax

/// A client for [BigQuery].
///
/// ```swift
/// let client = try BigQueryClient()
/// let result = try await client.query("SELECT 17 AS answer")
/// for try await row in result.rows {
///   print(try row["answer"]?.int64Value ?? 0)
/// }
/// ```
///
/// The client is safe to share across tasks. Create one client and reuse it.
///
/// [BigQuery]: https://cloud.google.com/bigquery
public final class BigQueryClient: Sendable {
  /// The default service endpoint.
  public static let defaultEndpoint = "https://bigquery.googleapis.com"

  /// The project used for requests that do not name a project explicitly.
  public let projectID: String

  /// The default location for jobs and queries.
  public let location: String?

  /// The job creation mode used by queries that do not set one.
  let defaultJobCreationMode: JobCreationMode?

  /// Sends requests to the service.
  let transport: BigQueryTransport

  /// Creates a client.
  ///
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind/invalidArgument`` if no project
  ///   can be determined, or an error if the endpoint or credentials are invalid.
  public convenience init(_ options: BigQueryClientOptions = .init()) throws {
    let projectID = try ProjectDiscovery.resolve(
      explicit: options.projectID, environment: ProcessInfo.processInfo.environment)
    var clientOptions = options.client
    if clientOptions.retryPolicy == nil {
      clientOptions.retryPolicy = BigQueryRetryPolicy.defaultPolicy
    }
    let http = try GoogleGax._HTTPClient(
      from: clientOptions, withDefaultEndpoint: Self.defaultEndpoint)
    self.init(
      projectID: projectID,
      location: options.location,
      defaultJobCreationMode: options.defaultJobCreationMode,
      transport: BigQueryTransport(
        http: GaxHTTPTransport(client: http), clientOptions: clientOptions)
    )
  }

  /// Creates a client over an arbitrary transport. Used by the unit tests.
  init(
    projectID: String,
    location: String? = nil,
    defaultJobCreationMode: JobCreationMode? = nil,
    transport: BigQueryTransport
  ) {
    self.projectID = projectID
    self.location = location
    self.defaultJobCreationMode = defaultJobCreationMode
    self.transport = transport
  }

  /// Returns `id` with the client project filled in when it has none.
  func resolve(_ id: DatasetID) -> DatasetID {
    var id = id
    if id.projectID?.isEmpty ?? true { id.projectID = self.projectID }
    return id
  }

  /// Returns `id` with the client project filled in when it has none.
  func resolve(_ id: TableID) -> TableID {
    var id = id
    if id.projectID?.isEmpty ?? true { id.projectID = self.projectID }
    return id
  }

  /// Returns `id` with the client project filled in when it has none.
  func resolve(_ id: RoutineID) -> RoutineID {
    var id = id
    if id.projectID?.isEmpty ?? true { id.projectID = self.projectID }
    return id
  }

  /// Returns `id` with the client project filled in when it has none.
  func resolve(_ id: ModelID) -> ModelID {
    var id = id
    if id.projectID?.isEmpty ?? true { id.projectID = self.projectID }
    return id
  }

  /// Returns `id` with the client project and location filled in when it has none.
  func resolve(_ id: JobID) -> JobID {
    var id = id
    if id.projectID?.isEmpty ?? true { id.projectID = self.projectID }
    if id.location?.isEmpty ?? true { id.location = self.location }
    return id
  }
}
