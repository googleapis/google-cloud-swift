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

extension PropertyTransform {
  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = ""
  ) throws -> DatastoreV1Stub.PropertyTransform {
    try DatastoreV1Stub.PropertyTransform().with {
      $0.property = propertyPath
      switch operation {
      case .setToServerTime:
        $0.transformType = .setToServerValue(.requestTime)
      case .increment(let val):
        $0.transformType = .increment(
          try PropertyValue(val).toProto(
            defaultProjectId: defaultProjectId,
            defaultDatabaseId: defaultDatabaseId,
            defaultNamespaceId: defaultNamespaceId
          ))
      case .maximum(let val):
        $0.transformType = .maximum(
          try PropertyValue(val).toProto(
            defaultProjectId: defaultProjectId,
            defaultDatabaseId: defaultDatabaseId,
            defaultNamespaceId: defaultNamespaceId
          ))
      case .minimum(let val):
        $0.transformType = .minimum(
          try PropertyValue(val).toProto(
            defaultProjectId: defaultProjectId,
            defaultDatabaseId: defaultDatabaseId,
            defaultNamespaceId: defaultNamespaceId
          ))
      case .appendMissingElements(let elements):
        let wireVals = try elements.map {
          try $0.toProto(
            defaultProjectId: defaultProjectId,
            defaultDatabaseId: defaultDatabaseId,
            defaultNamespaceId: defaultNamespaceId
          )
        }
        $0.transformType = .appendMissingElements(
          DatastoreV1Stub.ArrayValue().with { $0.values = wireVals }
        )
      case .removeAllFromArray(let elements):
        let wireVals = try elements.map {
          try $0.toProto(
            defaultProjectId: defaultProjectId,
            defaultDatabaseId: defaultDatabaseId,
            defaultNamespaceId: defaultNamespaceId
          )
        }
        $0.transformType = .removeAllFromArray(
          DatastoreV1Stub.ArrayValue().with { $0.values = wireVals }
        )
      }
    }
  }
}

extension Mutation {
  /// Returns the normalized complete `Key` for `insertComplete`, `upsertComplete`, or `update` mutations,
  /// or `nil` for incomplete-key mutations and `delete` mutations.
  func normalizedFallbackKey(
    defaultProjectId: String,
    defaultDatabaseId: String,
    defaultNamespaceId: String
  ) throws -> Key? {
    switch kind {
    case .insertComplete(let entity),
      .upsertComplete(let entity, _, _),
      .update(let entity, _, _):
      let wireKey = entity.key.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
      return try Key(fromProto: wireKey)
    case .insertIncomplete, .upsertIncomplete, .delete:
      return nil
    }
  }

  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = ""
  ) throws -> DatastoreV1Stub.Mutation {
    var proto = DatastoreV1Stub.Mutation()
    proto.propertyTransforms = try transforms.map {
      try $0.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
    }

    switch kind {
    case .insertComplete(let entity):
      proto.operation = .insert(
        try entity.toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: defaultNamespaceId
        ))

    case .insertIncomplete(let entity):
      proto.operation = .insert(
        try entity.toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: defaultNamespaceId
        ))

    case .upsertComplete(let entity, let baseVersion, let propertyMask):
      proto.operation = .upsert(
        try entity.toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: defaultNamespaceId
        ))
      if let baseVersion {
        proto.conflictDetectionStrategy = .baseVersion(baseVersion)
      }
      if let propertyMask {
        proto.propertyMask = DatastoreV1Stub.PropertyMask().with { $0.paths = propertyMask }
      }

    case .upsertIncomplete(let entity):
      proto.operation = .upsert(
        try entity.toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: defaultNamespaceId
        ))

    case .update(let entity, let baseVersion, let propertyMask):
      proto.operation = .update(
        try entity.toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: defaultNamespaceId
        ))
      if let baseVersion {
        proto.conflictDetectionStrategy = .baseVersion(baseVersion)
      }
      if let propertyMask {
        proto.propertyMask = DatastoreV1Stub.PropertyMask().with { $0.paths = propertyMask }
      }

    case .delete(let key, let baseVersion):
      proto.operation = .delete(
        key.toProto(
          defaultProjectId: defaultProjectId,
          defaultDatabaseId: defaultDatabaseId,
          defaultNamespaceId: defaultNamespaceId
        ))
      if let baseVersion {
        proto.conflictDetectionStrategy = .baseVersion(baseVersion)
      }
    }
    return proto
  }
}

extension MutationResult {
  init(fromProto proto: DatastoreV1Stub.MutationResult, fallbackKey: Key?) throws {
    let resolvedKey: Key?
    if let wireKey = proto.key, !wireKey.path.isEmpty {
      resolvedKey = try Key(fromProto: wireKey)
    } else {
      resolvedKey = fallbackKey
    }
    let decodedTransforms = try proto.transformResults.map { try PropertyValue(fromProto: $0) }
    self.init(
      key: resolvedKey,
      version: proto.version,
      createTime: proto.createTime,
      updateTime: proto.updateTime,
      conflictDetected: proto.conflictDetected,
      transformResults: decodedTransforms
    )
  }
}
