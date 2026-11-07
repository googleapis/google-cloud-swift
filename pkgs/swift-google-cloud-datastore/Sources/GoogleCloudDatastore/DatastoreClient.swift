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
public import Foundation
import GoogleAuth
public import GoogleGax
import GoogleRpc

/// High-level client for interacting with Google Cloud Datastore (`google.datastore.v1.Datastore`).
public final class DatastoreClient: DatastoreProtocol, Sendable {
  public let projectId: String
  public let databaseId: String
  public let namespaceId: String
  public let options: DatastoreClientOptions
  let stub: any DatastoreRPCStub

  /// Creates a new `DatastoreClient` with the provided `DatastoreClientOptions`.
  public convenience init(
    _ options: DatastoreClientOptions,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    var effectiveOptions = options
    if let rawEmulatorHost = environment["DATASTORE_EMULATOR_HOST"]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !rawEmulatorHost.isEmpty
    {
      let emulatorEndpoint: String
      if rawEmulatorHost.hasPrefix("http://") || rawEmulatorHost.hasPrefix("https://") {
        emulatorEndpoint = rawEmulatorHost
      } else {
        emulatorEndpoint = "http://\(rawEmulatorHost)"
      }
      if effectiveOptions.client.endpoint == nil {
        effectiveOptions.client.endpoint = emulatorEndpoint
      }
      if effectiveOptions.client.credentials == nil {
        effectiveOptions.client.credentials = try GoogleAuth.Credentials(
          configuration: .anonymous
        )
      }
    }
    let trimmedProject = effectiveOptions.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedProject.isEmpty else {
      throw DatastoreError.invalidArgument("projectId must not be empty")
    }
    let stub = try DatastoreStubFactory.makeStub(effectiveOptions.client)
    try self.init(options: effectiveOptions, stub: stub)
  }

  init(options: DatastoreClientOptions, stub: any DatastoreRPCStub) throws {
    let trimmedProject = options.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedProject.isEmpty else {
      throw DatastoreError.invalidArgument("projectId must not be empty")
    }
    self.projectId = trimmedProject
    self.databaseId = options.databaseId
    self.namespaceId = options.namespaceId
    self.options = options
    self.stub = stub
  }

  private static let routingParamAllowedCharacters: CharacterSet = {
    var set = CharacterSet.urlQueryAllowed
    set.remove(charactersIn: "&=+/?#")
    return set
  }()

  func effectiveRequestOptions(_ base: GoogleGax.RequestOptions?) -> GoogleGax.RequestOptions {
    var opts = base ?? GoogleGax.RequestOptions()
    let encodedProject =
      projectId.addingPercentEncoding(withAllowedCharacters: Self.routingParamAllowedCharacters)
      ?? projectId
    let requestParams: String
    let resourcePrefix: String
    if databaseId.isEmpty {
      requestParams = "project_id=\(encodedProject)"
      resourcePrefix = "projects/\(projectId)"
    } else {
      let encodedDb =
        databaseId.addingPercentEncoding(withAllowedCharacters: Self.routingParamAllowedCharacters)
        ?? databaseId
      requestParams = "project_id=\(encodedProject)&database_id=\(encodedDb)"
      resourcePrefix = "projects/\(projectId)/databases/\(databaseId)"
    }
    opts.headers["x-goog-request-params"] = requestParams
    opts.headers["google-cloud-resource-prefix"] = resourcePrefix
    return opts
  }

  // MARK: - Key ID Allocation & Reservation

  public func allocateIds(
    _ keys: [IncompleteKey], options: GoogleGax.RequestOptions? = nil
  ) async throws -> [Key] {
    guard !keys.isEmpty else { return [] }
    let request = DatastoreV1Stub.AllocateIdsRequest().with {
      $0.projectId = projectId
      $0.databaseId = databaseId
      $0.keys = keys.map {
        $0.toProto(
          defaultProjectId: projectId,
          defaultDatabaseId: databaseId,
          defaultNamespaceId: namespaceId
        )
      }
    }
    let response = try await stub.allocateIds(
      request: request,
      options: effectiveRequestOptions(options)
    )
    return try response.keys.map { try Key(fromProto: $0) }
  }

  public func allocateId(
    _ key: IncompleteKey, options: GoogleGax.RequestOptions? = nil
  ) async throws -> Key {
    let allocated = try await allocateIds([key], options: options)
    guard let first = allocated.first else {
      throw DatastoreError.invalidArgument("Server returned empty AllocateIdsResponse")
    }
    return first
  }

  public func reserveIds(
    _ keys: [Key], options: GoogleGax.RequestOptions? = nil
  ) async throws {
    guard !keys.isEmpty else { return }
    let request = DatastoreV1Stub.ReserveIdsRequest().with {
      $0.projectId = projectId
      $0.databaseId = databaseId
      $0.keys = keys.map {
        $0.toProto(
          defaultProjectId: projectId,
          defaultDatabaseId: databaseId,
          defaultNamespaceId: namespaceId
        )
      }
    }
    _ = try await stub.reserveIds(
      request: request,
      options: effectiveRequestOptions(options)
    )
  }

  public func reserveIdsSequential(
    startingAt key: Key, count: Int, options: GoogleGax.RequestOptions? = nil
  ) async throws {
    guard count > 0 else {
      throw DatastoreError.invalidArgument("reserveIdsSequential count must be > 0")
    }
    guard case .id(let startId) = key.id else {
      throw DatastoreError.invalidArgument(
        "reserveIdsSequential requires a Key with a numeric Int64 ID"
      )
    }
    let keysToReserve = try (0..<count).map { offset -> Key in
      let (nextId, overflow) = startId.addingReportingOverflow(Int64(offset))
      if overflow || nextId == 0 {
        throw DatastoreError.invalidArgument("Sequential ID reservation overflowed or produced 0")
      }
      return Key(
        ancestors: key.ancestors,
        leaf: PathElement(kind: key.kind, id: nextId),
        partitionId: key.partitionId
      )
    }
    try await reserveIds(keysToReserve, options: options)
  }

  @discardableResult
  public func runInTransaction<T: Sendable>(
    options: TransactionOptions = .readWrite,
    _ body: @Sendable (Transaction) async throws -> T
  ) async throws -> (result: T, commitResult: CommitResult) {
    let maxAttempts = max(1, options.maxAttempts ?? self.options.maxTransactionAttempts)
    let startInstant = ContinuousClock.now
    var previousTransaction: Data? = nil

    for attempt in 1...maxAttempts {
      let tx = Transaction(
        client: self,
        options: options,
        previousTransaction: previousTransaction
      )
      let bodyResult: T
      do {
        bodyResult = try await body(tx)
      } catch {
        let acquiredTxId = tx.acquiredTransactionId
        if let txId = acquiredTxId {
          if isRetryableTransactionError(error, duringCommit: false) {
            previousTransaction = txId
          }
          let rollbackReq = DatastoreV1Stub.RollbackRequest().with {
            $0.projectId = projectId
            $0.databaseId = databaseId
            $0.transaction = txId
          }
          _ = try? await stub.rollback(
            request: rollbackReq,
            options: effectiveRequestOptions(options.requestOptions)
          )
        }
        if attempt < maxAttempts && isRetryableTransactionError(error, duringCommit: false) {
          let delay = self.options.transactionBackoffPolicy.backoffDelay(
            for: RetryState(idempotent: true, start: startInstant, attemptCount: attempt)
          )
          try await ContinuousClock().sleep(for: delay)
          continue
        }
        throw error
      }

      let (acquiredTxId, bufferedMutations) = tx.takeSnapshot()
      if let txId = acquiredTxId {
        previousTransaction = txId
      }

      switch options.mode {
      case .readOnly:
        return (bodyResult, CommitResult())
      case .readWrite:
        if acquiredTxId == nil && bufferedMutations.isEmpty {
          return (bodyResult, CommitResult())
        }
        let selector: DatastoreV1Stub.CommitRequest.TransactionSelectorOneOf
        if let txId = acquiredTxId {
          selector = .transaction(txId)
        } else {
          selector = .singleUseTransaction(tx.wireTransactionOptions())
        }
        do {
          let commitResult = try await executeCommit(
            mutations: bufferedMutations,
            mode: .transactional,
            transactionSelector: selector,
            options: options.requestOptions
          )
          return (bodyResult, commitResult)
        } catch {
          if attempt < maxAttempts && isRetryableTransactionError(error, duringCommit: true) {
            let delay = self.options.transactionBackoffPolicy.backoffDelay(
              for: RetryState(idempotent: true, start: startInstant, attemptCount: attempt)
            )
            try await ContinuousClock().sleep(for: delay)
            continue
          }
          throw error
        }
      }
    }
    preconditionFailure("Unreachable: loop ranging 1...maxAttempts always returns or throws")
  }

  private func isRetryableTransactionError(_ error: any Error, duringCommit: Bool) -> Bool {
    if let requestError = error as? GoogleGax.RequestError {
      switch requestError {
      case .service(let serviceError):
        return isRetryableServiceCode(serviceError.code, duringCommit: duringCommit)
      case .exhausted(let exhaustedError):
        if let underlying = exhaustedError.underlyingError {
          return isRetryableTransactionError(underlying, duringCommit: duringCommit)
        }
        return false
      default:
        return false
      }
    }
    if let serviceError = error as? GoogleGax.ServiceError {
      return isRetryableServiceCode(serviceError.code, duringCommit: duringCommit)
    }
    return false
  }

  private func isRetryableServiceCode(_ code: GoogleRpc.Code, duringCommit: Bool) -> Bool {
    if code == .aborted {
      return true
    }
    if !duringCommit && code == .unavailable {
      return true
    }
    return false
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
