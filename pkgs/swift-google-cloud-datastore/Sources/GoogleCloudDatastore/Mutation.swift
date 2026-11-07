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

public import GoogleWKT

/// An atomic server-side transformation applied to an entity property during `Commit`.
public struct PropertyTransform: Sendable, Equatable {
  enum Operation: Sendable, Equatable {
    case setToServerTime
    case increment(Value)
    case maximum(Value)
    case minimum(Value)
    case appendMissingElements([PropertyValue])
    case removeAllFromArray([PropertyValue])
  }

  /// The dot-delimited property path to transform.
  public let propertyPath: String
  let operation: Operation

  init(propertyPath: String, operation: Operation) {
    self.propertyPath = propertyPath
    self.operation = operation
  }

  /// Sets the property to the timestamp at which the server processes the request (`REQUEST_TIME`).
  public static func setToServerTime(_ propertyPath: String) -> Self {
    Self(propertyPath: propertyPath, operation: .setToServerTime)
  }

  /// Atomically adds `amount` (`Int64`) to the numeric property (initializing to `0 + amount` if missing).
  public static func increment(_ propertyPath: String, by amount: Int64) -> Self {
    Self(propertyPath: propertyPath, operation: .increment(.int64(amount)))
  }

  /// Atomically adds `amount` (`Double`) to the numeric property (initializing to `0.0 + amount` if missing).
  public static func increment(_ propertyPath: String, by amount: Double) -> Self {
    Self(propertyPath: propertyPath, operation: .increment(.double(amount)))
  }

  /// Atomically sets the property to the greater of its current value and `value` (`Int64`).
  public static func maximum(_ propertyPath: String, _ value: Int64) -> Self {
    Self(propertyPath: propertyPath, operation: .maximum(.int64(value)))
  }

  /// Atomically sets the property to the greater of its current value and `value` (`Double`).
  public static func maximum(_ propertyPath: String, _ value: Double) -> Self {
    Self(propertyPath: propertyPath, operation: .maximum(.double(value)))
  }

  /// Atomically sets the property to the lesser of its current value and `value` (`Int64`).
  public static func minimum(_ propertyPath: String, _ value: Int64) -> Self {
    Self(propertyPath: propertyPath, operation: .minimum(.int64(value)))
  }

  /// Atomically sets the property to the lesser of its current value and `value` (`Double`).
  public static func minimum(_ propertyPath: String, _ value: Double) -> Self {
    Self(propertyPath: propertyPath, operation: .minimum(.double(value)))
  }

  /// Atomically appends each element in `elements` that is not already present in the target array property.
  public static func appendMissingElements(_ propertyPath: String, _ elements: [PropertyValue])
    -> Self
  {
    Self(propertyPath: propertyPath, operation: .appendMissingElements(elements))
  }

  /// Atomically removes all occurrences of any element in `elements` from the target array property.
  public static func removeAllFromArray(_ propertyPath: String, _ elements: [PropertyValue]) -> Self
  {
    Self(propertyPath: propertyPath, operation: .removeAllFromArray(elements))
  }
}

/// A single write mutation executed in a `Commit` request or buffered in a `Transaction`.
public struct Mutation: Sendable, Equatable {
  enum Kind: Sendable, Equatable {
    case insertComplete(Entity)
    case insertIncomplete(IncompleteEntity)
    case upsertComplete(Entity, baseVersion: Int64?, propertyMask: [String]?)
    case upsertIncomplete(IncompleteEntity)
    case update(Entity, baseVersion: Int64?, propertyMask: [String]?)
    case delete(Key, baseVersion: Int64?)
  }

  let kind: Kind
  /// Server-side property transformations attached to this mutation.
  public let transforms: [PropertyTransform]

  init(kind: Kind, transforms: [PropertyTransform] = []) {
    self.kind = kind
    self.transforms = transforms
  }

  /// Inserts a new entity with a complete ``Key``. Fails with `ALREADY_EXISTS` if the key already exists.
  public static func insert(
    _ entity: Entity,
    transforms: [PropertyTransform] = []
  ) -> Self {
    Self(kind: .insertComplete(entity), transforms: transforms)
  }

  /// Inserts a new entity with an ``IncompleteKey``, allocating a new numeric ID on the server.
  public static func insert(
    _ entity: IncompleteEntity,
    transforms: [PropertyTransform] = []
  ) -> Self {
    Self(kind: .insertIncomplete(entity), transforms: transforms)
  }

  /// Upserts an entity with a complete ``Key`` (overwriting or applying `propertyMask`).
  public static func upsert(
    _ entity: Entity,
    baseVersion: Int64? = nil,
    propertyMask: [String]? = nil,
    transforms: [PropertyTransform] = []
  ) -> Self {
    Self(
      kind: .upsertComplete(entity, baseVersion: baseVersion, propertyMask: propertyMask),
      transforms: transforms
    )
  }

  /// Upserts an entity with an ``IncompleteKey``, allocating a new numeric ID on the server.
  public static func upsert(
    _ entity: IncompleteEntity,
    transforms: [PropertyTransform] = []
  ) -> Self {
    Self(kind: .upsertIncomplete(entity), transforms: transforms)
  }

  /// Updates an existing entity with a complete ``Key``. Fails with `NOT_FOUND` if the key does not exist.
  public static func update(
    _ entity: Entity,
    baseVersion: Int64? = nil,
    propertyMask: [String]? = nil,
    transforms: [PropertyTransform] = []
  ) -> Self {
    Self(
      kind: .update(entity, baseVersion: baseVersion, propertyMask: propertyMask),
      transforms: transforms
    )
  }

  /// Applies only ``PropertyTransform``s to an existing entity without overwriting any existing properties
  /// (sends an empty `PropertyMask()` on the wire).
  public static func transform(
    key: Key,
    baseVersion: Int64? = nil,
    transforms: [PropertyTransform]
  ) -> Self {
    Self(
      kind: .update(Entity(key: key), baseVersion: baseVersion, propertyMask: []),
      transforms: transforms
    )
  }

  /// Deletes the entity with the specified complete ``Key``.
  public static func delete(
    _ key: Key,
    baseVersion: Int64? = nil
  ) -> Self {
    Self(kind: .delete(key, baseVersion: baseVersion))
  }
}

/// Result metadata for a single committed ``Mutation``.
public struct MutationResult: Sendable, Equatable {
  /// The complete ``Key`` of the mutated entity (either newly allocated by the server or normalized from the input mutation).
  public let key: Key?

  /// The new version timestamp of the entity after the mutation.
  public let version: Int64

  /// The server timestamp at which the entity was created, if applicable.
  public let createTime: GoogleWKT.WKTTimestamp?

  /// The server timestamp at which the entity was updated.
  public let updateTime: GoogleWKT.WKTTimestamp?

  /// Whether a conflict was detected during the mutation.
  public let conflictDetected: Bool

  /// Values produced by ``PropertyTransform``s, in the same order as the request's `transforms`.
  public let transformResults: [PropertyValue]

  /// Creates a ``MutationResult``.
  public init(
    key: Key?,
    version: Int64,
    createTime: GoogleWKT.WKTTimestamp? = nil,
    updateTime: GoogleWKT.WKTTimestamp? = nil,
    conflictDetected: Bool = false,
    transformResults: [PropertyValue] = []
  ) {
    self.key = key
    self.version = version
    self.createTime = createTime
    self.updateTime = updateTime
    self.conflictDetected = conflictDetected
    self.transformResults = transformResults
  }
}

/// Token representing an incomplete key whose numeric ID will be allocated when the transaction commits.
public struct PendingKey: Sendable, Hashable {
  let mutationIndex: Int
  /// The original incomplete key passed to the transactional mutation.
  public let incompleteKey: IncompleteKey

  init(mutationIndex: Int, incompleteKey: IncompleteKey) {
    self.mutationIndex = mutationIndex
    self.incompleteKey = incompleteKey
  }
}

/// Result metadata returned upon successful transaction commit.
public struct CommitResult: Sendable, Equatable {
  /// The server timestamp at which the commit was applied.
  public let commitTime: GoogleWKT.WKTTimestamp?

  /// Results for each buffered mutation in the transaction.
  public let mutationResults: [MutationResult]

  /// Creates a ``CommitResult``.
  public init(
    commitTime: GoogleWKT.WKTTimestamp? = nil,
    mutationResults: [MutationResult] = []
  ) {
    self.commitTime = commitTime
    self.mutationResults = mutationResults
  }

  /// Resolves a ``PendingKey`` returned by `tx.insert(_: IncompleteEntity)` or `tx.upsert(_: IncompleteEntity)`
  /// into its newly allocated complete ``Key``.
  public func resolveKey(_ pendingKey: PendingKey) throws -> Key {
    guard pendingKey.mutationIndex >= 0 && pendingKey.mutationIndex < mutationResults.count else {
      throw DatastoreError.unresolvedPendingKey(
        "Mutation index \(pendingKey.mutationIndex) out of bounds (\(mutationResults.count))"
      )
    }
    guard let allocatedKey = mutationResults[pendingKey.mutationIndex].key else {
      throw DatastoreError.unresolvedPendingKey(
        "Server did not return an allocated key at mutation index \(pendingKey.mutationIndex)"
      )
    }
    return allocatedKey
  }
}
