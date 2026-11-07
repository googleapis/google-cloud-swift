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

/// Identifies the logical partition (project, database, and namespace) of a Datastore key or query.
public struct PartitionId: Sendable, Hashable, Codable {
  /// The Google Cloud project ID.
  public var projectId: String

  /// The Datastore database ID (`""` for the default database).
  public var databaseId: String

  /// The multi-tenant namespace ID (`""` for the default namespace).
  public var namespaceId: String

  /// Creates a `PartitionId`.
  public init(projectId: String = "", databaseId: String = "", namespaceId: String = "") {
    self.projectId = projectId
    self.databaseId = databaseId
    self.namespaceId = namespaceId
  }
}

/// A completed element in a key's path (kind plus either a numeric ID or string name).
public struct PathElement: Sendable, Hashable, Codable {
  /// The identifier of a completed `PathElement`.
  public enum ID: Sendable, Hashable, Codable {
    /// A non-zero 64-bit signed integer ID.
    case id(Int64)
    /// A non-empty UTF-8 string name.
    case name(String)
  }

  /// The entity kind (non-empty string).
  public var kind: String

  /// The element's numeric ID or string name.
  public var id: ID

  /// Creates a `PathElement` with a numeric ID.
  public init(kind: String, id: Int64) {
    self.kind = kind
    self.id = .id(id)
  }

  /// Creates a `PathElement` with a string name.
  public init(kind: String, name: String) {
    self.kind = kind
    self.id = .name(name)
  }

  /// Creates a `PathElement` with an `ID`.
  public init(kind: String, id: ID) {
    self.kind = kind
    self.id = id
  }
}

/// An incomplete Datastore key whose leaf element has a `kind` but no `id` or `name`.
///
/// Used exclusively with `insert`, `upsert`, or `allocateIds` so the server allocates
/// a unique numeric `Int64` ID.
public struct IncompleteKey: Sendable, Hashable, Codable {
  /// The logical partition for this key.
  public var partitionId: PartitionId

  /// Completed ancestor path elements (parent, grandparent, etc.), ordered from root to parent.
  public var ancestors: [PathElement]

  /// The entity kind of the leaf element.
  public var kind: String

  /// Creates an `IncompleteKey`.
  public init(kind: String, parent: Key? = nil, partitionId: PartitionId? = nil) {
    self.partitionId = partitionId ?? parent?.partitionId ?? .init()
    self.ancestors = parent?.path ?? []
    self.kind = kind
  }

  /// Creates an `IncompleteKey` with explicit ancestor path elements.
  public init(ancestors: [PathElement], kind: String, partitionId: PartitionId = .init()) {
    self.partitionId = partitionId
    self.ancestors = ancestors
    self.kind = kind
  }

  /// Returns a complete `Key` by assigning a numeric `Int64` ID to this incomplete key's leaf.
  public func completed(id: Int64) -> Key {
    Key(ancestors: ancestors, leaf: PathElement(kind: kind, id: id), partitionId: partitionId)
  }

  /// Returns a complete `Key` by assigning a string `name` to this incomplete key's leaf.
  public func completed(name: String) -> Key {
    Key(ancestors: ancestors, leaf: PathElement(kind: kind, name: name), partitionId: partitionId)
  }
}

/// A complete Datastore key where every element in the path (ancestors and leaf)
/// has a non-zero numeric `id` or a non-empty string `name`.
public struct Key: Sendable, Hashable, Codable {
  /// The logical partition for this key.
  public var partitionId: PartitionId

  /// Completed ancestor path elements, ordered from root to immediate parent.
  public var ancestors: [PathElement]

  /// The completed leaf element identifying this entity.
  public var leaf: PathElement

  /// Full path including `ancestors` followed by `leaf`.
  public var path: [PathElement] { ancestors + [leaf] }

  /// The leaf entity kind.
  public var kind: String { leaf.kind }

  /// The leaf identifier (`.id(Int64)` or `.name(String)`).
  public var id: PathElement.ID { leaf.id }

  /// The immediate parent `Key`, or `nil` if this is a root key.
  public var parent: Key? {
    guard let parentLeaf = ancestors.last else { return nil }
    return Key(
      ancestors: Array(ancestors.dropLast()),
      leaf: parentLeaf,
      partitionId: partitionId
    )
  }

  /// Creates a complete `Key` with a numeric `Int64` ID.
  public init(kind: String, id: Int64, parent: Key? = nil, partitionId: PartitionId? = nil) {
    self.partitionId = partitionId ?? parent?.partitionId ?? .init()
    self.ancestors = parent?.path ?? []
    self.leaf = PathElement(kind: kind, id: id)
  }

  /// Creates a complete `Key` with a string `name`.
  public init(kind: String, name: String, parent: Key? = nil, partitionId: PartitionId? = nil) {
    self.partitionId = partitionId ?? parent?.partitionId ?? .init()
    self.ancestors = parent?.path ?? []
    self.leaf = PathElement(kind: kind, name: name)
  }

  /// Creates a complete `Key` from explicit `ancestors` and a `leaf` element.
  public init(
    ancestors: [PathElement] = [], leaf: PathElement, partitionId: PartitionId = .init()
  ) {
    self.partitionId = partitionId
    self.ancestors = ancestors
    self.leaf = leaf
  }
}

extension DatastoreProtocol {
  /// Creates an `IncompleteKey` bound to this client's `projectId`, `databaseId`, and `namespaceId`.
  public func incompleteKey(
    kind: String, parent: Key? = nil, namespaceId: String? = nil
  ) -> IncompleteKey {
    let partition = PartitionId(
      projectId: projectId,
      databaseId: databaseId,
      namespaceId: namespaceId ?? parent?.partitionId.namespaceId ?? self.namespaceId
    )
    return IncompleteKey(kind: kind, parent: parent, partitionId: partition)
  }

  /// Creates a complete `Key` with a numeric `Int64` ID bound to this client's partition.
  public func key(
    kind: String, id: Int64, parent: Key? = nil, namespaceId: String? = nil
  ) -> Key {
    let partition = PartitionId(
      projectId: projectId,
      databaseId: databaseId,
      namespaceId: namespaceId ?? parent?.partitionId.namespaceId ?? self.namespaceId
    )
    return Key(kind: kind, id: id, parent: parent, partitionId: partition)
  }

  /// Creates a complete `Key` with a string `name` bound to this client's partition.
  public func key(
    kind: String, name: String, parent: Key? = nil, namespaceId: String? = nil
  ) -> Key {
    let partition = PartitionId(
      projectId: projectId,
      databaseId: databaseId,
      namespaceId: namespaceId ?? parent?.partitionId.namespaceId ?? self.namespaceId
    )
    return Key(kind: kind, name: name, parent: parent, partitionId: partition)
  }

  /// Creates a complete `Key` from an ancestor chain of `PathElement`s and a leaf `PathElement`.
  public func key(
    ancestors: [PathElement], leaf: PathElement, namespaceId: String? = nil
  ) -> Key {
    let partition = PartitionId(
      projectId: projectId,
      databaseId: databaseId,
      namespaceId: namespaceId ?? self.namespaceId
    )
    return Key(ancestors: ancestors, leaf: leaf, partitionId: partition)
  }
}
