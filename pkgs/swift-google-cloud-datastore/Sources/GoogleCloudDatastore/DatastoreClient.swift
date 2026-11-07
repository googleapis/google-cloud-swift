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
public import GoogleGax

/// High-level client for interacting with Google Cloud Datastore (`google.datastore.v1.Datastore`).
public final class DatastoreClient: DatastoreProtocol, Sendable {
  public let projectId: String
  public let databaseId: String
  public let namespaceId: String
  public let options: DatastoreClientOptions

  public init(_ options: DatastoreClientOptions) throws {
    let trimmedProject = options.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedProject.isEmpty else {
      throw DatastoreError.invalidArgument("projectId must not be empty")
    }
    self.projectId = trimmedProject
    self.databaseId = options.databaseId
    self.namespaceId = options.namespaceId
    self.options = options
  }

  public func get(_ key: Key, options: ReadOptions? = nil) async throws -> Entity? {
    fatalError("unimplemented")
  }

  public func getMulti(_ keys: [Key], options: ReadOptions? = nil) async throws -> [Entity?] {
    fatalError("unimplemented")
  }

  @discardableResult
  public func insert(
    _ entity: Entity, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    fatalError("unimplemented")
  }

  public func insert(
    _ entity: IncompleteEntity, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    fatalError("unimplemented")
  }

  @discardableResult
  public func upsert(
    _ entity: Entity, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    fatalError("unimplemented")
  }

  public func upsert(
    _ entity: IncompleteEntity, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    fatalError("unimplemented")
  }

  public func update(_ entity: Entity, options: GoogleGax.RequestOptions? = nil) async throws {
    fatalError("unimplemented")
  }

  public func delete(_ key: Key, options: GoogleGax.RequestOptions? = nil) async throws {
    fatalError("unimplemented")
  }

  @discardableResult
  public func mutate(
    _ mutations: [Mutation], options: GoogleGax.RequestOptions? = nil
  ) async throws -> [MutationResult] {
    fatalError("unimplemented")
  }

  public func allocateIds(
    _ keys: [IncompleteKey], options: GoogleGax.RequestOptions? = nil
  ) async throws -> [Key] {
    fatalError("unimplemented")
  }

  public func allocateId(
    _ key: IncompleteKey, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    fatalError("unimplemented")
  }

  public func reserveIds(_ keys: [Key], options: GoogleGax.RequestOptions? = nil) async throws {
    fatalError("unimplemented")
  }

  public func reserveIdsSequential(
    startingAt key: Key, count: Int, options: GoogleGax.RequestOptions? = nil
  ) async throws {
    fatalError("unimplemented")
  }

  @discardableResult
  public func runInTransaction<T: Sendable>(
    options: TransactionOptions = .readWrite,
    _ body: @Sendable (Transaction) async throws -> T
  ) async throws -> (result: T, commitResult: CommitResult) {
    fatalError("unimplemented")
  }

  public func runQuery(
    _ query: Query, options: ReadOptions? = nil
  ) -> AsyncThrowingStream<Entity, any Error> {
    fatalError("unimplemented")
  }

  public func runQuery(
    _ query: GqlQuery, options: ReadOptions? = nil
  ) -> AsyncThrowingStream<Entity, any Error> {
    fatalError("unimplemented")
  }

  public func runQueryBatches(
    _ query: Query, options: ReadOptions? = nil
  ) -> AsyncThrowingStream<QueryBatch, any Error> {
    fatalError("unimplemented")
  }

  public func runQueryBatches(
    _ query: GqlQuery, options: ReadOptions? = nil
  ) -> AsyncThrowingStream<QueryBatch, any Error> {
    fatalError("unimplemented")
  }

  public func runAggregationQuery(
    _ query: AggregationQuery, options: ReadOptions? = nil
  ) async throws -> AggregationResults {
    fatalError("unimplemented")
  }

  public func explainQuery(
    _ query: Query, analyze: Bool = false, options: ReadOptions? = nil
  ) async throws -> QueryExplainResult {
    fatalError("unimplemented")
  }

  public func explainQuery(
    _ query: GqlQuery, analyze: Bool = false, options: ReadOptions? = nil
  ) async throws -> QueryExplainResult {
    fatalError("unimplemented")
  }

  public func explainAggregationQuery(
    _ query: AggregationQuery, analyze: Bool = false, options: ReadOptions? = nil
  ) async throws -> AggregationExplainResult {
    fatalError("unimplemented")
  }
}
