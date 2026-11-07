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

/// Configuration options for ``DatastoreClient``.
public struct DatastoreClientOptions: Sendable {
  /// Standard GoogleGax client networking, authentication, retry, and telemetry options.
  public var client: GoogleGax.ClientOptions

  /// The Google Cloud project ID.
  public var projectId: String

  /// The target Datastore database ID within the project.
  ///
  /// The default database is represented by the empty string `""`.
  public var databaseId: String

  /// The default multi-tenant namespace ID applied to keys and queries created
  /// through this client when not explicitly overridden.
  public var namespaceId: String

  /// Maximum number of attempts for `runInTransaction` when retrying on contention (`ABORTED`).
  public var maxTransactionAttempts: Int

  /// Backoff policy used between transaction retry attempts.
  public var transactionBackoffPolicy: any GoogleGax.BackoffPolicy

  /// Creates configuration options for a ``DatastoreClient``.
  /// - Parameters:
  ///   - projectId: The Google Cloud project ID.
  ///   - databaseId: The database ID (defaults to `""` for the default database).
  ///   - namespaceId: The default namespace ID (defaults to `""`).
  ///   - maxTransactionAttempts: Maximum transaction attempts (defaults to `5`).
  ///   - transactionBackoffPolicy: Backoff policy between transaction retries.
  ///   - client: Underlying `GoogleGax.ClientOptions`.
  public init(
    projectId: String,
    databaseId: String = "",
    namespaceId: String = "",
    maxTransactionAttempts: Int = 5,
    transactionBackoffPolicy: any GoogleGax.BackoffPolicy = ExponentialBackoff(),
    client: GoogleGax.ClientOptions = .init()
  ) {
    self.projectId = projectId
    self.databaseId = databaseId
    self.namespaceId = namespaceId
    self.maxTransactionAttempts = maxTransactionAttempts
    self.transactionBackoffPolicy = transactionBackoffPolicy
    self.client = client
  }

  /// Returns a modified copy of ``DatastoreClientOptions``.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}
