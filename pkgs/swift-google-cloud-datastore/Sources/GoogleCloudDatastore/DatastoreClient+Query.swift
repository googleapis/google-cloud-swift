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
import GoogleGax
import GoogleWKT

enum WireQuerySource: Sendable {
  case structured(Query)
  case gql(GqlQuery)
}

extension PropertyOrder {
  func toProto() -> DatastoreV1Stub.PropertyOrder {
    DatastoreV1Stub.PropertyOrder().with { proto in
      proto.property = DatastoreV1Stub.PropertyReference().with { $0.name = property }
      proto.direction = (direction == .ascending) ? .ascending : .descending
    }
  }
}

extension Filter.Operator {
  func toProto() -> DatastoreV1Stub.PropertyFilter.Operator {
    switch self {
    case .lessThan: return .lessThan
    case .lessThanOrEqual: return .lessThanOrEqual
    case .greaterThan: return .greaterThan
    case .greaterThanOrEqual: return .greaterThanOrEqual
    case .equal: return .equal
    case .notEqual: return .notEqual
    case .in: return .in
    case .notIn: return .notIn
    case .hasAncestor: return .hasAncestor
    }
  }
}

extension Filter {
  func toProto(
    defaultProjectId: String,
    defaultDatabaseId: String,
    defaultNamespaceId: String
  ) throws -> DatastoreV1Stub.Filter {
    switch self {
    case .property(let name, let op, let value):
      let wireVal = try PropertyValue(value).toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
      return DatastoreV1Stub.Filter().with {
        $0.filterType = .propertyFilter(
          DatastoreV1Stub.PropertyFilter().with { pf in
            pf.property = DatastoreV1Stub.PropertyReference().with { $0.name = name }
            pf.op = op.toProto()
            pf.value = wireVal
          }
        )
      }
    case .and(let subfilters):
      return try compositeProto(
        op: .and,
        subfilters: subfilters,
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
    case .or(let subfilters):
      return try compositeProto(
        op: .or,
        subfilters: subfilters,
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
    }
  }

  private func compositeProto(
    op: DatastoreV1Stub.CompositeFilter.Operator,
    subfilters: [Filter],
    defaultProjectId: String,
    defaultDatabaseId: String,
    defaultNamespaceId: String
  ) throws -> DatastoreV1Stub.Filter {
    let wireFilters = try subfilters.map {
      try $0.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
    }
    return DatastoreV1Stub.Filter().with {
      $0.filterType = .compositeFilter(
        DatastoreV1Stub.CompositeFilter().with {
          $0.op = op
          $0.filters = wireFilters
        }
      )
    }
  }
}

extension Query {
  func toProto(
    defaultProjectId: String,
    defaultDatabaseId: String,
    defaultNamespaceId: String
  ) throws -> DatastoreV1Stub.Query {
    let effectiveNamespace = namespaceId ?? defaultNamespaceId
    return try DatastoreV1Stub.Query().with { proto in
      proto.projection = projection.map { name in
        DatastoreV1Stub.Projection().with {
          $0.property = DatastoreV1Stub.PropertyReference().with { $0.name = name }
        }
      }
      if let kind, !kind.isEmpty {
        proto.kind = [DatastoreV1Stub.KindExpression().with { $0.name = kind }]
      }
      if let filter {
        proto.filter = try filter.toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: effectiveNamespace
        )
      }
      proto.order = order.map { $0.toProto() }
      proto.distinctOn = distinctOn.map { name in
        DatastoreV1Stub.PropertyReference().with { $0.name = name }
      }
      if let startCursor {
        proto.startCursor = startCursor.bytes
      }
      if let endCursor {
        proto.endCursor = endCursor.bytes
      }
      proto.offset = max(0, offset)
      if let limit {
        proto.limit = limit
      }
    }
  }
}

extension GqlQueryParameter {
  func toProto(
    defaultProjectId: String,
    defaultDatabaseId: String,
    defaultNamespaceId: String
  ) throws -> DatastoreV1Stub.GqlQueryParameter {
    try DatastoreV1Stub.GqlQueryParameter().with { proto in
      switch self {
      case .value(let val):
        let wireVal = try PropertyValue(val).toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: defaultNamespaceId
        )
        proto.parameterType = .value(wireVal)
      case .cursor(let cursor):
        proto.parameterType = .cursor(cursor.bytes)
      }
    }
  }
}

extension GqlQuery {
  func toProto(
    defaultProjectId: String,
    defaultDatabaseId: String,
    defaultNamespaceId: String
  ) throws -> DatastoreV1Stub.GqlQuery {
    let effectiveNamespace = namespaceId ?? defaultNamespaceId
    var wireNamed: [String: DatastoreV1Stub.GqlQueryParameter] = [:]
    wireNamed.reserveCapacity(namedBindings.count)
    for (k, v) in namedBindings {
      wireNamed[k] = try v.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: effectiveNamespace
      )
    }
    let wirePositional = try positionalBindings.map {
      try $0.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: effectiveNamespace
      )
    }
    return DatastoreV1Stub.GqlQuery().with { proto in
      proto.queryString = queryString
      proto.allowLiterals = allowLiterals
      proto.namedBindings = wireNamed
      proto.positionalBindings = wirePositional
    }
  }
}

extension MoreResultsType {
  init(fromProto proto: DatastoreV1Stub.QueryResultBatch.MoreResultsType) {
    switch proto {
    case .notFinished: self = .notFinished
    case .moreResultsAfterLimit: self = .moreResultsAfterLimit
    case .moreResultsAfterCursor: self = .moreResultsAfterCursor
    case .noMoreResults, .unspecified, .unknownIntValue, .unknownStringValue: self = .noMoreResults
    }
  }
}

extension ExplainMetrics {
  init(fromProto proto: DatastoreV1Stub.ExplainMetrics) {
    let plan = proto.planSummary.map { PlanSummary(indexesUsed: $0.indexesUsed) }
    let stats = proto.executionStats.map {
      ExecutionStats(
        resultsReturned: $0.resultsReturned,
        executionDuration: $0.executionDuration,
        readOperations: $0.readOperations,
        debugStats: $0.debugStats
      )
    }
    self.init(planSummary: plan, executionStats: stats)
  }
}

actor QueryBatchPager {
  let client: DatastoreClient
  let source: WireQuerySource
  let propertyMask: [String]?
  let explainOptions: DatastoreV1Stub.ExplainOptions?
  let requestOptions: GoogleGax.RequestOptions?
  let transaction: Transaction?

  var currentReadOptions: DatastoreV1Stub.ReadOptions?
  var partitionId: DatastoreV1Stub.PartitionId?
  var queryType: DatastoreV1Stub.RunQueryRequest.QueryTypeOneOf?
  var isFirstRequest: Bool = true
  var isFinished: Bool = false
  var explainMetrics: ExplainMetrics?
  var bufferedEntities: ArraySlice<Entity> = []

  init(
    client: DatastoreClient,
    source: WireQuerySource,
    initialReadOptions: DatastoreV1Stub.ReadOptions?,
    propertyMask: [String]?,
    explainOptions: DatastoreV1Stub.ExplainOptions?,
    requestOptions: GoogleGax.RequestOptions?,
    transaction: Transaction?
  ) {
    self.client = client
    self.source = source
    self.currentReadOptions = initialReadOptions
    self.propertyMask = propertyMask
    self.explainOptions = explainOptions
    self.requestOptions = requestOptions
    self.transaction = transaction
  }

  private func initializeIfNeeded() async throws {
    guard queryType == nil else { return }
    let effectiveNs: String
    switch source {
    case .structured(let query):
      effectiveNs = query.namespaceId ?? client.namespaceId
      queryType = .query(
        try query.toProto(
          defaultProjectId: client.projectId,
          defaultDatabaseId: client.databaseId,
          defaultNamespaceId: effectiveNs
        ))
    case .gql(let gqlQuery):
      effectiveNs = gqlQuery.namespaceId ?? client.namespaceId
      queryType = .gqlQuery(
        try gqlQuery.toProto(
          defaultProjectId: client.projectId,
          defaultDatabaseId: client.databaseId,
          defaultNamespaceId: effectiveNs
        ))
    }
    partitionId =
      PartitionId(
        projectId: client.projectId, databaseId: client.databaseId, namespaceId: effectiveNs
      ).toProto()
    if let tx = transaction {
      currentReadOptions = await tx.prepareTransactionalRead()
    }
  }

  func nextBatch() async throws -> QueryBatch? {
    if isFinished { return nil }

    let wasFirst = isFirstRequest
    do {
      try await initializeIfNeeded()
    } catch {
      isFinished = true
      if wasFirst {
        transaction?.completeInitiation(transactionId: nil)
      }
      throw error
    }

    let wireMask: DatastoreV1Stub.PropertyMask? = propertyMask.map { paths in
      DatastoreV1Stub.PropertyMask().with { $0.paths = paths }
    }
    let request = DatastoreV1Stub.RunQueryRequest().with {
      $0.projectId = client.projectId
      $0.databaseId = client.databaseId
      $0.partitionId = partitionId
      $0.readOptions = currentReadOptions
      $0.propertyMask = wireMask
      $0.explainOptions = explainOptions
      $0.queryType = queryType
    }

    let response: DatastoreV1Stub.RunQueryResponse
    do {
      response = try await client.stub.runQuery(
        request: request,
        options: client.effectiveRequestOptions(requestOptions)
      )
      if isFirstRequest {
        isFirstRequest = false
        if !response.transaction.isEmpty {
          transaction?.completeInitiation(transactionId: response.transaction)
          currentReadOptions = DatastoreV1Stub.ReadOptions().with {
            $0.consistencyType = .transaction(response.transaction)
          }
        } else {
          transaction?.completeInitiation(transactionId: nil)
        }
      }
    } catch {
      if isFirstRequest {
        isFirstRequest = false
        transaction?.completeInitiation(transactionId: nil)
      }
      isFinished = true
      throw error
    }

    if let protoMetrics = response.explainMetrics {
      explainMetrics = ExplainMetrics(fromProto: protoMetrics)
    }

    guard let protoBatch = response.batch else {
      isFinished = true
      return nil
    }

    let items = try protoBatch.entityResults.map { entityResult -> EntityItem in
      let entity = try Entity(fromEntityResult: entityResult)
      let cursor = entityResult.cursor.isEmpty ? nil : Cursor(bytes: entityResult.cursor)
      return EntityItem(entity: entity, cursor: cursor)
    }
    let skippedCursor =
      protoBatch.skippedCursor.isEmpty ? nil : Cursor(bytes: protoBatch.skippedCursor)
    let endCursor = protoBatch.endCursor.isEmpty ? nil : Cursor(bytes: protoBatch.endCursor)
    let moreResults = MoreResultsType(fromProto: protoBatch.moreResults)

    let batch = QueryBatch(
      items: items,
      skippedResults: protoBatch.skippedResults,
      skippedCursor: skippedCursor,
      endCursor: endCursor,
      moreResults: moreResults,
      readTime: protoBatch.readTime
    )

    guard moreResults == .notFinished else {
      isFinished = true
      return batch
    }

    // Prepare continuation query for next batch when NOT_FINISHED
    var nextQuery: DatastoreV1Stub.Query
    if case .query(let q) = queryType {
      nextQuery = q
    } else if let compiledQuery = response.query {
      nextQuery = compiledQuery
    } else {
      isFinished = true
      return batch
    }

    var madeProgress = false
    if protoBatch.skippedResults > 0 {
      nextQuery.offset = max(0, nextQuery.offset - protoBatch.skippedResults)
      if !protoBatch.skippedCursor.isEmpty {
        nextQuery.startCursor = protoBatch.skippedCursor
      } else if !protoBatch.endCursor.isEmpty {
        nextQuery.startCursor = protoBatch.endCursor
      }
      madeProgress = true
    }

    if !protoBatch.entityResults.isEmpty {
      nextQuery.offset = 0
      if !protoBatch.endCursor.isEmpty {
        nextQuery.startCursor = protoBatch.endCursor
      }
      if let currentLimit = nextQuery.limit {
        let remaining = currentLimit - Int32(protoBatch.entityResults.count)
        if remaining <= 0 {
          isFinished = true
          return batch
        }
        nextQuery.limit = remaining
      }
      madeProgress = true
    }

    if !madeProgress {
      if !protoBatch.endCursor.isEmpty && protoBatch.endCursor != nextQuery.startCursor {
        nextQuery.startCursor = protoBatch.endCursor
      } else {
        isFinished = true
        return batch
      }
    }

    queryType = .query(nextQuery)
    return batch
  }

  func nextEntity() async throws -> Entity? {
    while bufferedEntities.isEmpty {
      guard let batch = try await nextBatch() else {
        return nil
      }
      bufferedEntities = ArraySlice(batch.items.map(\.entity))
    }
    return bufferedEntities.removeFirst()
  }
}

extension DatastoreClient {
  func runQueryInternal(
    source: WireQuerySource,
    options: ReadOptions?,
    transaction: Transaction?
  ) -> AsyncThrowingStream<Entity, any Error> {
    let pager = QueryBatchPager(
      client: self,
      source: source,
      initialReadOptions: options?.toWireReadOptions(),
      propertyMask: options?.propertyMask,
      explainOptions: nil,
      requestOptions: options?.requestOptions ?? transaction?.options.requestOptions,
      transaction: transaction
    )
    return AsyncThrowingStream {
      try await pager.nextEntity()
    }
  }

  func runQueryBatchesInternal(
    source: WireQuerySource,
    options: ReadOptions?,
    transaction: Transaction?
  ) -> AsyncThrowingStream<QueryBatch, any Error> {
    let pager = QueryBatchPager(
      client: self,
      source: source,
      initialReadOptions: options?.toWireReadOptions(),
      propertyMask: options?.propertyMask,
      explainOptions: nil,
      requestOptions: options?.requestOptions ?? transaction?.options.requestOptions,
      transaction: transaction
    )
    return AsyncThrowingStream {
      try await pager.nextBatch()
    }
  }

  func explainQueryInternal(
    source: WireQuerySource,
    analyze: Bool,
    options: ReadOptions?
  ) async throws -> QueryExplainResult {
    let explainOpts = DatastoreV1Stub.ExplainOptions().with { $0.analyze = analyze }
    let pager = QueryBatchPager(
      client: self,
      source: source,
      initialReadOptions: options?.toWireReadOptions(),
      propertyMask: options?.propertyMask,
      explainOptions: explainOpts,
      requestOptions: options?.requestOptions,
      transaction: nil
    )
    var allEntities: [Entity] = []
    var finalCursor: Cursor? = nil
    while let batch = try await pager.nextBatch() {
      allEntities.append(contentsOf: batch.items.map(\.entity))
      if let endCursor = batch.endCursor {
        finalCursor = endCursor
      }
    }
    let metrics = await pager.explainMetrics ?? ExplainMetrics()
    return QueryExplainResult(entities: allEntities, endCursor: finalCursor, metrics: metrics)
  }
}
