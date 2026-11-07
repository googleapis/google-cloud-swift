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
public import GoogleWKT

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
  let options: TransactionOptions

  init(options: TransactionOptions) {
    self.options = options
  }

  public func get(_ key: Key, propertyMask: [String]? = nil) async throws -> Entity? {
    fatalError("unimplemented")
  }

  public func getMulti(_ keys: [Key], propertyMask: [String]? = nil) async throws -> [Entity?] {
    fatalError("unimplemented")
  }

  public func runQuery(_ query: Query) -> AsyncThrowingStream<Entity, any Error> {
    fatalError("unimplemented")
  }

  public func runQuery(_ query: GqlQuery) -> AsyncThrowingStream<Entity, any Error> {
    fatalError("unimplemented")
  }

  public func runQueryBatches(_ query: Query) -> AsyncThrowingStream<QueryBatch, any Error> {
    fatalError("unimplemented")
  }

  public func runQueryBatches(_ query: GqlQuery) -> AsyncThrowingStream<QueryBatch, any Error> {
    fatalError("unimplemented")
  }

  public func runAggregationQuery(_ query: AggregationQuery) async throws -> AggregationResults {
    fatalError("unimplemented")
  }

  public func insert(_ entity: Entity, transforms: [PropertyTransform] = []) throws {
    fatalError("unimplemented")
  }

  public func insert(
    _ entity: IncompleteEntity, transforms: [PropertyTransform] = []
  ) throws -> PendingKey {
    fatalError("unimplemented")
  }

  public func upsert(
    _ entity: Entity,
    baseVersion: Int64? = nil,
    propertyMask: [String]? = nil,
    transforms: [PropertyTransform] = []
  ) throws {
    fatalError("unimplemented")
  }

  public func upsert(
    _ entity: IncompleteEntity, transforms: [PropertyTransform] = []
  ) throws -> PendingKey {
    fatalError("unimplemented")
  }

  public func update(
    _ entity: Entity,
    baseVersion: Int64? = nil,
    propertyMask: [String]? = nil,
    transforms: [PropertyTransform] = []
  ) throws {
    fatalError("unimplemented")
  }

  public func delete(_ key: Key, baseVersion: Int64? = nil) throws {
    fatalError("unimplemented")
  }

  public func mutate(_ mutations: [Mutation]) throws {
    fatalError("unimplemented")
  }
}
