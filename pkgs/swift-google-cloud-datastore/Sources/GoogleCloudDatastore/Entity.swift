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

/// Common interface shared by ``Entity``, ``IncompleteEntity``, and ``EmbeddedEntity``.
public protocol EntityProtocol: Sendable, Equatable {
  /// Dictionary of property names to ``PropertyValue``s.
  var properties: [String: PropertyValue] { get set }
}

extension EntityProtocol {
  /// Accesses the ``PropertyValue`` (value + `excludeFromIndexes`) for `property`.
  public subscript(property: String) -> PropertyValue? {
    get { properties[property] }
    set { properties[property] = newValue }
  }

  /// Accesses the unwrapped ``Value`` for `property`.
  /// Setting a new ``Value`` preserves any existing `excludeFromIndexes` flag on that property.
  public subscript(value property: String) -> Value? {
    get { properties[property]?.value }
    set {
      if let newValue {
        let existingExclude = properties[property]?.excludeFromIndexes ?? false
        properties[property] = PropertyValue(newValue, excludeFromIndexes: existingExclude)
      } else {
        properties.removeValue(forKey: property)
      }
    }
  }
}

/// A persisted or complete-keyed Datastore entity with a complete ``Key``.
public struct Entity: EntityProtocol, Sendable, Equatable {
  /// The complete key uniquely identifying this entity.
  public var key: Key

  /// The entity's properties.
  public var properties: [String: PropertyValue]

  /// The entity's microsecond version number returned by the server (`EntityResult.version`), if known.
  public var version: Int64?

  /// The entity's creation timestamp (`EntityResult.create_time`), if returned by the server.
  public var createTime: GoogleWKT.WKTTimestamp?

  /// The entity's last modification timestamp (`EntityResult.update_time`), if returned by the server.
  public var updateTime: GoogleWKT.WKTTimestamp?

  /// Creates an ``Entity`` with a complete ``Key``.
  public init(
    key: Key,
    properties: [String: PropertyValue] = [:],
    version: Int64? = nil,
    createTime: GoogleWKT.WKTTimestamp? = nil,
    updateTime: GoogleWKT.WKTTimestamp? = nil
  ) {
    self.key = key
    self.properties = properties
    self.version = version
    self.createTime = createTime
    self.updateTime = updateTime
  }
}

/// A new Datastore entity bound to an ``IncompleteKey`` whose numeric ID will be
/// allocated by the server upon `insert` or `upsert`.
public struct IncompleteEntity: EntityProtocol, Sendable, Equatable {
  /// The incomplete key specifying the entity's partition, ancestors, and kind.
  public var key: IncompleteKey

  /// The entity's properties.
  public var properties: [String: PropertyValue]

  /// Creates an ``IncompleteEntity`` with an ``IncompleteKey``.
  public init(
    key: IncompleteKey,
    properties: [String: PropertyValue] = [:]
  ) {
    self.key = key
    self.properties = properties
  }
}

/// An entity embedded inside a ``Value/entity(_:)`` property of another entity.
public struct EmbeddedEntity: EntityProtocol, Sendable, Equatable {
  /// Optional key associated with the embedded entity.
  public var key: Key?

  /// The embedded entity's properties.
  public var properties: [String: PropertyValue]

  /// Creates an ``EmbeddedEntity``.
  public init(
    key: Key? = nil,
    properties: [String: PropertyValue] = [:]
  ) {
    self.key = key
    self.properties = properties
  }
}
