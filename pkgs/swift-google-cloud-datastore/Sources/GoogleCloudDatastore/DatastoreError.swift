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

/// Errors specific to the Cloud Datastore veneer client.
public enum DatastoreError: Error, Sendable, Equatable {
  /// An invalid argument was supplied to a Datastore operation.
  case invalidArgument(String)

  /// Attempted to enqueue a write mutation inside a read-only transaction.
  case readOnlyTransaction

  /// A `PendingKey` could not be resolved from the transaction's `CommitResult`.
  case unresolvedPendingKey(String)
}
