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

import DatastoreV1Stub
public import GoogleGax

extension DatastoreClient {
  @discardableResult
  public func insert(
    _ entity: Entity, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    let results = try await mutate([.insert(entity)], options: options)
    guard let key = results.first?.key else {
      throw DatastoreError.invalidArgument("Commit did not return a Key for insert")
    }
    return key
  }

  public func insert(
    _ entity: IncompleteEntity, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    let results = try await mutate([.insert(entity)], options: options)
    guard let key = results.first?.key else {
      throw DatastoreError.invalidArgument("Server did not return an allocated Key for insert")
    }
    return key
  }

  @discardableResult
  public func upsert(
    _ entity: Entity, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    let results = try await mutate([.upsert(entity)], options: options)
    guard let key = results.first?.key else {
      throw DatastoreError.invalidArgument("Commit did not return a Key for upsert")
    }
    return key
  }

  public func upsert(
    _ entity: IncompleteEntity, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    let results = try await mutate([.upsert(entity)], options: options)
    guard let key = results.first?.key else {
      throw DatastoreError.invalidArgument("Server did not return an allocated Key for upsert")
    }
    return key
  }

  public func update(_ entity: Entity, options: GoogleGax.RequestOptions? = nil) async throws {
    _ = try await mutate([.update(entity)], options: options)
  }

  public func delete(_ key: Key, options: GoogleGax.RequestOptions? = nil) async throws {
    _ = try await mutate([.delete(key)], options: options)
  }

  @discardableResult
  public func mutate(
    _ mutations: [Mutation], options: GoogleGax.RequestOptions? = nil
  ) async throws -> [MutationResult] {
    guard !mutations.isEmpty else { return [] }
    let commitResult = try await executeCommit(
      mutations: mutations,
      mode: .nonTransactional,
      transactionSelector: nil,
      options: options
    )
    return commitResult.mutationResults
  }

  private struct DeleteDedupKey: Hashable {
    let key: Key
    let baseVersion: Int64?
  }

  func executeCommit(
    mutations: [Mutation],
    mode: DatastoreV1Stub.CommitRequest.Mode,
    transactionSelector: DatastoreV1Stub.CommitRequest.TransactionSelectorOneOf?,
    options: GoogleGax.RequestOptions?
  ) async throws -> CommitResult {
    var wireMutations: [DatastoreV1Stub.Mutation] = []
    var fallbackKeys: [Key?] = []
    // Maps each caller index `0..<mutations.count` to its index in `wireMutations`
    var callerToWireIndex: [Int] = []
    var seenDeletes: [DeleteDedupKey: Int] = [:]

    for mutation in mutations {
      if case .delete(let key, let baseVersion) = mutation.kind {
        let normalizedKey = try Key(
          fromProto: key.toProto(
            defaultProjectId: projectId,
            defaultDatabaseId: databaseId,
            defaultNamespaceId: namespaceId
          ))
        let dedupKey = DeleteDedupKey(key: normalizedKey, baseVersion: baseVersion)
        if let existingWireIdx = seenDeletes[dedupKey] {
          callerToWireIndex.append(existingWireIdx)
          continue
        }
        let wireIdx = wireMutations.count
        seenDeletes[dedupKey] = wireIdx
        callerToWireIndex.append(wireIdx)
        wireMutations.append(
          try mutation.toProto(
            defaultProjectId: projectId,
            defaultDatabaseId: databaseId,
            defaultNamespaceId: namespaceId
          ))
        fallbackKeys.append(nil)
      } else {
        let wireIdx = wireMutations.count
        callerToWireIndex.append(wireIdx)
        wireMutations.append(
          try mutation.toProto(
            defaultProjectId: projectId,
            defaultDatabaseId: databaseId,
            defaultNamespaceId: namespaceId
          ))
        fallbackKeys.append(
          try mutation.normalizedFallbackKey(
            defaultProjectId: projectId,
            defaultDatabaseId: databaseId,
            defaultNamespaceId: namespaceId
          ))
      }
    }

    let request = DatastoreV1Stub.CommitRequest().with {
      $0.projectId = projectId
      $0.databaseId = databaseId
      $0.mode = mode
      $0.mutations = wireMutations
      $0.transactionSelector = transactionSelector
    }
    let response = try await stub.commit(
      request: request,
      options: effectiveRequestOptions(options)
    )

    var decodedWireResults: [MutationResult] = []
    decodedWireResults.reserveCapacity(wireMutations.count)
    for idx in 0..<wireMutations.count {
      let protoRes =
        idx < response.mutationResults.count
        ? response.mutationResults[idx]
        : DatastoreV1Stub.MutationResult()
      decodedWireResults.append(
        try MutationResult(fromProto: protoRes, fallbackKey: fallbackKeys[idx])
      )
    }

    let finalResults = callerToWireIndex.map { decodedWireResults[$0] }
    return CommitResult(commitTime: response.commitTime, mutationResults: finalResults)
  }
}
