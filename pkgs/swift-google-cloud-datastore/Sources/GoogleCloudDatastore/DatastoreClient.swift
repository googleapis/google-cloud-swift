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

/// Client for Google Cloud Datastore data-plane operations (`google.datastore.v1`).
public final class DatastoreClient: DatastoreProtocol, Sendable {
  /// The default service endpoint for Cloud Datastore.
  public static let defaultEndpoint = "https://datastore.googleapis.com"

  /// The configuration options used to initialize this client.
  public let options: DatastoreClientOptions

  public var projectId: String { options.projectId }
  public var databaseId: String { options.databaseId }
  public var namespaceId: String { options.namespaceId }

  /// Creates a new ``DatastoreClient`` with the given options.
  public init(_ options: DatastoreClientOptions) throws {
    if options.projectId.isEmpty {
      throw DatastoreError.invalidArgument("projectId must not be empty")
    }
    self.options = options
  }
}
