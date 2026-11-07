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

/// Protocol defining the Google Cloud Datastore data-plane client surface.
public protocol DatastoreProtocol: Sendable {
  /// The Google Cloud project ID bound to this client.
  var projectId: String { get }

  /// The Datastore database ID bound to this client (`""` for the default database).
  var databaseId: String { get }

  /// The default namespace ID bound to this client (`""` for the default namespace).
  var namespaceId: String { get }
}
