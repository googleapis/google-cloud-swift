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

/// Protocol defining the public Cloud Datastore client interface, enabling dependency injection
/// and unit test mocking.
public protocol DatastoreProtocol: Sendable {
  /// The Google Cloud project ID targeted by this client.
  var projectId: String { get }
  /// The Datastore database ID targeted by this client (`""` for the `(default)` database).
  var databaseId: String { get }
  /// The default multi-tenant namespace ID targeted by this client (`""` for the default namespace).
  var namespaceId: String { get }

  // MARK: - Point Reads (Lookup)

  func get(_ key: Key, options: ReadOptions?) async throws -> Entity?
  func getMulti(_ keys: [Key], options: ReadOptions?) async throws -> [Entity?]

  // MARK: - Non-Transactional Writes (Commit)

  @discardableResult
  func insert(_ entity: Entity, options: GoogleGax.RequestOptions?) async throws -> Key
  func insert(_ entity: IncompleteEntity, options: GoogleGax.RequestOptions?) async throws -> Key
  @discardableResult
  func upsert(_ entity: Entity, options: GoogleGax.RequestOptions?) async throws -> Key
  func upsert(_ entity: IncompleteEntity, options: GoogleGax.RequestOptions?) async throws -> Key
  func update(_ entity: Entity, options: GoogleGax.RequestOptions?) async throws
  func delete(_ key: Key, options: GoogleGax.RequestOptions?) async throws
  @discardableResult
  func mutate(
    _ mutations: [Mutation], options: GoogleGax.RequestOptions?
  ) async throws -> [MutationResult]

  // MARK: - Key ID Allocation & Reservation

  func allocateIds(
    _ keys: [IncompleteKey], options: GoogleGax.RequestOptions?
  ) async throws -> [Key]
  func allocateId(_ key: IncompleteKey, options: GoogleGax.RequestOptions?) async throws -> Key
  func reserveIds(_ keys: [Key], options: GoogleGax.RequestOptions?) async throws
  func reserveIdsSequential(
    startingAt key: Key, count: Int, options: GoogleGax.RequestOptions?
  ) async throws

  // MARK: - Transactions

  @discardableResult
  func runInTransaction<T: Sendable>(
    options: TransactionOptions,
    _ body: @Sendable (Transaction) async throws -> T
  ) async throws -> (result: T, commitResult: CommitResult)

  // MARK: - Queries & Aggregations

  func runQuery(
    _ query: Query, options: ReadOptions?
  ) -> AsyncThrowingStream<Entity, any Error>
  func runQuery(
    _ query: GqlQuery, options: ReadOptions?
  ) -> AsyncThrowingStream<Entity, any Error>
  func runQueryBatches(
    _ query: Query, options: ReadOptions?
  ) -> AsyncThrowingStream<QueryBatch, any Error>
  func runQueryBatches(
    _ query: GqlQuery, options: ReadOptions?
  ) -> AsyncThrowingStream<QueryBatch, any Error>
  func runAggregationQuery(
    _ query: AggregationQuery, options: ReadOptions?
  ) async throws -> AggregationResults

  // MARK: - Query Profiling (Explain)

  func explainQuery(
    _ query: Query, analyze: Bool, options: ReadOptions?
  ) async throws -> QueryExplainResult
  func explainQuery(
    _ query: GqlQuery, analyze: Bool, options: ReadOptions?
  ) async throws -> QueryExplainResult
  func explainAggregationQuery(
    _ query: AggregationQuery, analyze: Bool, options: ReadOptions?
  ) async throws -> AggregationExplainResult
}
