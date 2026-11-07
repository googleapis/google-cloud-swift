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

extension PartitionId {
  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = ""
  ) -> DatastoreV1Stub.PartitionId {
    DatastoreV1Stub.PartitionId().with {
      $0.projectId = projectId.isEmpty ? defaultProjectId : projectId
      $0.databaseId = databaseId.isEmpty ? defaultDatabaseId : databaseId
      $0.namespaceId = namespaceId.isEmpty ? defaultNamespaceId : namespaceId
    }
  }

  init(fromProto proto: DatastoreV1Stub.PartitionId?) {
    guard let proto else {
      self.init()
      return
    }
    self.init(
      projectId: proto.projectId,
      databaseId: proto.databaseId,
      namespaceId: proto.namespaceId
    )
  }
}

extension PathElement {
  func toProto() -> DatastoreV1Stub.Key.PathElement {
    DatastoreV1Stub.Key.PathElement().with {
      $0.kind = kind
      switch id {
      case .id(let numId):
        $0.idType = .id(numId)
      case .name(let strName):
        $0.idType = .name(strName)
      }
    }
  }

  init(fromProto proto: DatastoreV1Stub.Key.PathElement) throws {
    guard !proto.kind.isEmpty else {
      throw DatastoreError.invalidArgument("Key PathElement kind must not be empty")
    }
    switch proto.idType {
    case .id(let numId) where numId != 0:
      self.init(kind: proto.kind, id: numId)
    case .name(let strName) where !strName.isEmpty:
      self.init(kind: proto.kind, name: strName)
    default:
      throw DatastoreError.invalidArgument(
        "Complete Key PathElement for kind '\(proto.kind)' is missing a valid id or name"
      )
    }
  }
}

extension IncompleteKey {
  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = ""
  ) -> DatastoreV1Stub.Key {
    var elements = ancestors.map { $0.toProto() }
    elements.append(
      DatastoreV1Stub.Key.PathElement().with {
        $0.kind = kind
        $0.idType = nil
      })
    return DatastoreV1Stub.Key().with {
      $0.partitionId = partitionId.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
      $0.path = elements
    }
  }
}

extension Key {
  func toProto(
    defaultProjectId: String = "",
    defaultDatabaseId: String = "",
    defaultNamespaceId: String = ""
  ) -> DatastoreV1Stub.Key {
    var elements = ancestors.map { $0.toProto() }
    elements.append(leaf.toProto())
    return DatastoreV1Stub.Key().with {
      $0.partitionId = partitionId.toProto(
        defaultProjectId: defaultProjectId,
        defaultDatabaseId: defaultDatabaseId,
        defaultNamespaceId: defaultNamespaceId
      )
      $0.path = elements
    }
  }

  init(fromProto proto: DatastoreV1Stub.Key) throws {
    guard !proto.path.isEmpty else {
      throw DatastoreError.invalidArgument("Datastore Key path must not be empty")
    }
    let elements = try proto.path.map { try PathElement(fromProto: $0) }
    self.init(
      ancestors: Array(elements.dropLast()),
      leaf: elements[elements.count - 1],
      partitionId: PartitionId(fromProto: proto.partitionId)
    )
  }
}
