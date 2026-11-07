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
import GoogleType
import GoogleWKT

extension PropertyValue {
  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = "",
    forceExcludeFromIndexes: Bool = false
  ) throws -> DatastoreV1Stub.Value {
    let effectiveExclude = excludeFromIndexes || forceExcludeFromIndexes
    switch value {
    case .array(let elements):
      var wireElements: [DatastoreV1Stub.Value] = []
      wireElements.reserveCapacity(elements.count)
      for element in elements {
        if case .array = element.value {
          throw DatastoreError.invalidArgument(
            "Datastore ArrayValue cannot directly contain another ArrayValue"
          )
        }
        wireElements.append(
          try element.toProto(
            defaultProjectId: defaultProjectId,
            defaultDatabaseId: defaultDatabaseId,
            defaultNamespaceId: defaultNamespaceId,
            forceExcludeFromIndexes: effectiveExclude
          )
        )
      }
      // Datastore wire format requires exclude_from_indexes = false and meaning = 0 on outer ArrayValue
      return DatastoreV1Stub.Value().with {
        $0.excludeFromIndexes = false
        $0.meaning = 0
        $0.valueType = .arrayValue(
          DatastoreV1Stub.ArrayValue().with {
            $0.values = wireElements
          })
      }

    default:
      var proto = DatastoreV1Stub.Value()
      proto.excludeFromIndexes = effectiveExclude
      if let meaning {
        proto.meaning = meaning
      }
      switch value {
      case .null:
        proto.valueType = .nullValue(GoogleWKT.WKTNullValue())
      case .bool(let b):
        proto.valueType = .booleanValue(b)
      case .int64(let i):
        proto.valueType = .integerValue(i)
      case .double(let d):
        proto.valueType = .doubleValue(d)
      case .timestamp(let ts):
        proto.valueType = .timestampValue(ts)
      case .string(let s):
        proto.valueType = .stringValue(s)
      case .bytes(let data):
        proto.valueType = .blobValue(data)
      case .geoPoint(let latLng):
        proto.valueType = .geoPointValue(latLng)
      case .key(let k):
        proto.valueType = .keyValue(
          k.toProto(
            defaultProjectId: defaultProjectId,
            defaultDatabaseId: defaultDatabaseId,
            defaultNamespaceId: defaultNamespaceId
          ))
      case .entity(let embedded):
        proto.valueType = .entityValue(
          try embedded.toProto(
            defaultProjectId: defaultProjectId,
            defaultDatabaseId: defaultDatabaseId,
            defaultNamespaceId: defaultNamespaceId
          ))
      case .array:
        break
      }
      return proto
    }
  }

  init(fromProto proto: DatastoreV1Stub.Value) throws {
    let preservedMeaning: Int32? = proto.meaning != 0 ? proto.meaning : nil
    guard let valueType = proto.valueType else {
      self.init(.null, excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
      return
    }
    switch valueType {
    case .nullValue:
      self.init(.null, excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
    case .booleanValue(let b):
      self.init(.bool(b), excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
    case .integerValue(let i):
      self.init(.int64(i), excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
    case .doubleValue(let d):
      self.init(.double(d), excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
    case .timestampValue(let ts):
      self.init(
        .timestamp(ts), excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
    case .stringValue(let s):
      self.init(.string(s), excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
    case .blobValue(let data):
      self.init(
        .bytes(data), excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
    case .geoPointValue(let latLng):
      self.init(
        .geoPoint(latLng), excludeFromIndexes: proto.excludeFromIndexes, meaning: preservedMeaning)
    case .keyValue(let k):
      self.init(
        .key(try GoogleCloudDatastore.Key(fromProto: k)),
        excludeFromIndexes: proto.excludeFromIndexes,
        meaning: preservedMeaning
      )
    case .entityValue(let e):
      self.init(
        .entity(try EmbeddedEntity(fromProto: e)),
        excludeFromIndexes: proto.excludeFromIndexes,
        meaning: preservedMeaning
      )
    case .arrayValue(let arr):
      let decodedElements = try arr.values.map { try PropertyValue(fromProto: $0) }
      let allExcluded =
        !decodedElements.isEmpty && decodedElements.allSatisfy { $0.excludeFromIndexes }
      self.init(
        .array(decodedElements),
        excludeFromIndexes: proto.excludeFromIndexes || allExcluded,
        meaning: preservedMeaning
      )
    }
  }
}

extension EmbeddedEntity {
  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = ""
  ) throws -> DatastoreV1Stub.Entity {
    var wireProps: [String: DatastoreV1Stub.Value] = [:]
    wireProps.reserveCapacity(properties.count)
    for (name, prop) in properties {
      wireProps[name] = try prop.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
    }
    return DatastoreV1Stub.Entity().with {
      if let key {
        $0.key = key.toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: defaultNamespaceId
        )
      }
      $0.properties = wireProps
    }
  }

  init(fromProto proto: DatastoreV1Stub.Entity) throws {
    let decodedKey: Key?
    if let k = proto.key, !k.path.isEmpty {
      decodedKey = try? Key(fromProto: k)
    } else {
      decodedKey = nil
    }
    var decodedProps: [String: PropertyValue] = [:]
    decodedProps.reserveCapacity(proto.properties.count)
    for (name, val) in proto.properties {
      decodedProps[name] = try PropertyValue(fromProto: val)
    }
    self.init(key: decodedKey, properties: decodedProps)
  }
}

extension IncompleteEntity {
  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = ""
  ) throws -> DatastoreV1Stub.Entity {
    var wireProps: [String: DatastoreV1Stub.Value] = [:]
    wireProps.reserveCapacity(properties.count)
    for (name, prop) in properties {
      wireProps[name] = try prop.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
    }
    return DatastoreV1Stub.Entity().with {
      $0.key = key.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
      $0.properties = wireProps
    }
  }
}

extension Entity {
  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = ""
  ) throws -> DatastoreV1Stub.Entity {
    var wireProps: [String: DatastoreV1Stub.Value] = [:]
    wireProps.reserveCapacity(properties.count)
    for (name, prop) in properties {
      wireProps[name] = try prop.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
    }
    return DatastoreV1Stub.Entity().with {
      $0.key = key.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
      $0.properties = wireProps
    }
  }

  init(fromEntityResult result: DatastoreV1Stub.EntityResult) throws {
    guard let protoEntity = result.entity else {
      throw DatastoreError.invalidArgument("EntityResult is missing its entity payload")
    }
    guard let protoKey = protoEntity.key else {
      throw DatastoreError.invalidArgument("EntityResult entity is missing a Key")
    }
    let decodedKey = try Key(fromProto: protoKey)
    var decodedProps: [String: PropertyValue] = [:]
    decodedProps.reserveCapacity(protoEntity.properties.count)
    for (name, val) in protoEntity.properties {
      decodedProps[name] = try PropertyValue(fromProto: val)
    }
    self.init(
      key: decodedKey,
      properties: decodedProps,
      version: result.version != 0 ? result.version : nil,
      createTime: result.createTime,
      updateTime: result.updateTime
    )
  }
}

extension ReadOptions {
  func toWireReadOptions() -> DatastoreV1Stub.ReadOptions? {
    guard let selector else { return nil }
    return DatastoreV1Stub.ReadOptions().with {
      switch selector {
      case .consistency(.strong):
        $0.consistencyType = .readConsistency(.strong)
      case .consistency(.eventual):
        $0.consistencyType = .readConsistency(.eventual)
      case .readTime(let ts):
        $0.consistencyType = .readTime(ts)
      }
    }
  }

  func toWirePropertyMask() -> DatastoreV1Stub.PropertyMask? {
    guard let propertyMask else { return nil }
    return DatastoreV1Stub.PropertyMask().with {
      $0.paths = propertyMask
    }
  }
}
