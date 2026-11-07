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
import Foundation
public import GoogleGax
public import GoogleWKT
import Synchronization

/// Options configuring a Datastore transaction.
public struct TransactionOptions: Sendable {
  public enum Mode: Sendable, Equatable {
    case readWrite
    case readOnly(readTime: GoogleWKT.WKTTimestamp? = nil)
  }

  public var mode: Mode
  public var maxAttempts: Int?
  public var requestOptions: GoogleGax.RequestOptions?

  public init(
    mode: Mode = .readWrite,
    maxAttempts: Int? = nil,
    requestOptions: GoogleGax.RequestOptions? = nil
  ) {
    self.mode = mode
    self.maxAttempts = maxAttempts
    self.requestOptions = requestOptions
  }

  public static let readWrite = Self(mode: .readWrite)

  public static func readOnly(readTime: GoogleWKT.WKTTimestamp? = nil) -> Self {
    Self(mode: .readOnly(readTime: readTime))
  }
}

/// An active transaction context passed to the `runInTransaction` closure.
public final class Transaction: Sendable {
  private struct State: Sendable {
    var transactionId: Data? = nil
    var isInitiating: Bool = false
    var initiationWaiters: [CheckedContinuation<Void, Never>] = []
    var mutations: [Mutation] = []
  }

  let client: DatastoreClient
  let options: TransactionOptions
  let previousTransaction: Data?
  private let state: Mutex<State>

  init(
    client: DatastoreClient,
    options: TransactionOptions,
    previousTransaction: Data? = nil
  ) {
    self.client = client
    self.options = options
    self.previousTransaction = previousTransaction
    self.state = Mutex(State())
  }

  var acquiredTransactionId: Data? {
    state.withLock { $0.transactionId }
  }

  func takeSnapshot() -> (transactionId: Data?, mutations: [Mutation]) {
    state.withLock { ($0.transactionId, $0.mutations) }
  }

  func wireTransactionOptions() -> DatastoreV1Stub.TransactionOptions {
    DatastoreV1Stub.TransactionOptions().with { proto in
      switch options.mode {
      case .readWrite:
        proto.mode = .readWrite(
          DatastoreV1Stub.TransactionOptions.ReadWrite().with { rw in
            if let prev = previousTransaction, !prev.isEmpty {
              rw.previousTransaction = prev
            }
          }
        )
      case .readOnly(let readTime):
        proto.mode = .readOnly(
          DatastoreV1Stub.TransactionOptions.ReadOnly().with { ro in
            ro.readTime = readTime
          }
        )
      }
    }
  }

  /// Acquires the `ReadOptions` for a transactional read RPC.
  ///
  /// The first read in the transaction populates `new_transaction` and gates any concurrent
  /// reads until the server returns the `transaction` identifier. Subsequent reads reuse the
  /// established `transaction` identifier.
  func prepareTransactionalRead() async -> DatastoreV1Stub.ReadOptions {
    while true {
      let existingOrClaimed: DatastoreV1Stub.ReadOptions? = state.withLock { state in
        if let txId = state.transactionId {
          return DatastoreV1Stub.ReadOptions().with {
            $0.consistencyType = .transaction(txId)
          }
        }
        if !state.isInitiating {
          state.isInitiating = true
          return DatastoreV1Stub.ReadOptions().with {
            $0.consistencyType = .newTransaction(wireTransactionOptions())
          }
        }
        return nil
      }
      if let readOpts = existingOrClaimed {
        return readOpts
      }
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let shouldResumeImmediately = state.withLock { state -> Bool in
          if state.transactionId != nil || !state.isInitiating {
            return true
          }
          state.initiationWaiters.append(continuation)
          return false
        }
        if shouldResumeImmediately {
          continuation.resume()
        }
      }
    }
  }

  func completeInitiation(transactionId: Data?) {
    let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      if let txId = transactionId, !txId.isEmpty {
        state.transactionId = txId
      }
      state.isInitiating = false
      let pending = state.initiationWaiters
      state.initiationWaiters.removeAll()
      return pending
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  // MARK: - Transactional Reads

  public func get(_ key: Key, propertyMask: [String]? = nil) async throws -> Entity? {
    let results = try await getMulti([key], propertyMask: propertyMask)
    return results.first ?? nil
  }

  public func getMulti(_ keys: [Key], propertyMask: [String]? = nil) async throws -> [Entity?] {
    guard !keys.isEmpty else { return [] }
    let readOpts = await prepareTransactionalRead()
    do {
      let result = try await client.lookupInternal(
        keys: keys,
        wireReadOptions: readOpts,
        propertyMask: propertyMask,
        requestOptions: options.requestOptions,
        onFirstResponse: { [self] txId in
          self.completeInitiation(transactionId: txId)
        }
      )
      completeInitiation(transactionId: nil)
      return result
    } catch {
      completeInitiation(transactionId: nil)
      throw error
    }
  }

  public func runQuery(_ query: Query) -> AsyncThrowingStream<Entity, any Error> {
    client.runQueryInternal(source: .structured(query), options: nil, transaction: self)
  }

  public func runQuery(_ query: GqlQuery) -> AsyncThrowingStream<Entity, any Error> {
    client.runQueryInternal(source: .gql(query), options: nil, transaction: self)
  }

  public func runQueryBatches(_ query: Query) -> AsyncThrowingStream<QueryBatch, any Error> {
    client.runQueryBatchesInternal(source: .structured(query), options: nil, transaction: self)
  }

  public func runQueryBatches(_ query: GqlQuery) -> AsyncThrowingStream<QueryBatch, any Error> {
    client.runQueryBatchesInternal(source: .gql(query), options: nil, transaction: self)
  }

  public func runAggregationQuery(_ query: AggregationQuery) async throws -> AggregationResults {
    let readOpts = await prepareTransactionalRead()
    do {
      let (results, _) = try await client.executeAggregationQuery(
        query: query,
        wireReadOptions: readOpts,
        explainOptions: nil,
        requestOptions: options.requestOptions,
        onFirstResponse: { [self] txId in
          self.completeInitiation(transactionId: txId)
        }
      )
      completeInitiation(transactionId: nil)
      return results
    } catch {
      completeInitiation(transactionId: nil)
      throw error
    }
  }

  // MARK: - Buffered Transactional Writes

  private func ensureReadWrite() throws {
    guard case .readWrite = options.mode else {
      throw DatastoreError.readOnlyTransaction
    }
  }

  public func insert(_ entity: Entity, transforms: [PropertyTransform] = []) throws {
    try mutate([.insert(entity, transforms: transforms)])
  }

  public func insert(
    _ entity: IncompleteEntity, transforms: [PropertyTransform] = []
  ) throws -> PendingKey {
    try ensureReadWrite()
    let idx = state.withLock { state -> Int in
      let index = state.mutations.count
      state.mutations.append(.insert(entity, transforms: transforms))
      return index
    }
    return PendingKey(mutationIndex: idx, incompleteKey: entity.key)
  }

  public func upsert(
    _ entity: Entity,
    baseVersion: Int64? = nil,
    propertyMask: [String]? = nil,
    transforms: [PropertyTransform] = []
  ) throws {
    try mutate([
      .upsert(
        entity,
        baseVersion: baseVersion,
        propertyMask: propertyMask,
        transforms: transforms
      )
    ])
  }

  public func upsert(
    _ entity: IncompleteEntity, transforms: [PropertyTransform] = []
  ) throws -> PendingKey {
    try ensureReadWrite()
    let idx = state.withLock { state -> Int in
      let index = state.mutations.count
      state.mutations.append(.upsert(entity, transforms: transforms))
      return index
    }
    return PendingKey(mutationIndex: idx, incompleteKey: entity.key)
  }

  public func update(
    _ entity: Entity,
    baseVersion: Int64? = nil,
    propertyMask: [String]? = nil,
    transforms: [PropertyTransform] = []
  ) throws {
    try mutate([
      .update(
        entity,
        baseVersion: baseVersion,
        propertyMask: propertyMask,
        transforms: transforms
      )
    ])
  }

  public func delete(_ key: Key, baseVersion: Int64? = nil) throws {
    try mutate([.delete(key, baseVersion: baseVersion)])
  }

  public func mutate(_ mutations: [Mutation]) throws {
    try ensureReadWrite()
    state.withLock { state in
      state.mutations.append(contentsOf: mutations)
    }
  }
}
