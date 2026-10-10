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

import Foundation
import GoogleCloudBigQueryV2

// Conversions between `Dataset`, `Acl`, and `Expr` and the generated wire messages.

extension Dataset {
  init(wire: GoogleCloudBigQueryV2.Dataset) {
    self.init(id: DatasetID(wire: wire.datasetReference ?? .init()))
    self.friendlyName = wire.friendlyName
    self.description = wire.description
    self.location = wire.location.nonEmpty
    self.labels = wire.labels.isEmpty ? nil : wire.labels
    self.defaultTableExpiration = wire.defaultTableExpirationMs.map { .milliseconds($0) }
    self.defaultPartitionExpiration = wire.defaultPartitionExpirationMs.map { .milliseconds($0) }
    self.access = wire.access.isEmpty ? nil : wire.access.map(Acl.init(wire:))
    self.defaultEncryptionConfiguration = wire.defaultEncryptionConfiguration.map(
      EncryptionConfiguration.init(wire:))
    self.defaultCollation = wire.defaultCollation
    self.maxTimeTravelHours = wire.maxTimeTravelHours
    if wire.storageBillingModel != .unspecified {
      self.storageBillingModel = wire.storageBillingModel.stringValue.map(
        StorageBillingModel.init(rawValue:))
    }
    self.isCaseInsensitive = wire.isCaseInsensitive
    self.resourceTags = wire.resourceTags.isEmpty ? nil : wire.resourceTags
    self.externalDatasetReference = wire.externalDatasetReference.map(
      ExternalDatasetReference.init(wire:))
    self.etag = wire.etag.nonEmpty
    self.generatedID = wire.id.nonEmpty
    self.selfLink = wire.selfLink.nonEmpty
    self.creationTime = Date(millisecondsSinceEpoch: wire.creationTime)
    self.lastModifiedTime = Date(millisecondsSinceEpoch: wire.lastModifiedTime)
  }

  /// A partial dataset from `datasets.list`.
  init(wire: GoogleCloudBigQueryV2.ListFormatDataset) {
    self.init(id: DatasetID(wire: wire.datasetReference ?? .init()))
    self.friendlyName = wire.friendlyName
    self.location = wire.location.nonEmpty
    self.labels = wire.labels.isEmpty ? nil : wire.labels
    self.externalDatasetReference = wire.externalDatasetReference.map(
      ExternalDatasetReference.init(wire:))
    self.generatedID = wire.id.nonEmpty
  }

  /// The request message for create and update. Output-only fields are not set.
  var wire: GoogleCloudBigQueryV2.Dataset {
    GoogleCloudBigQueryV2.Dataset().with {
      $0.datasetReference = self.id.wire
      $0.friendlyName = self.friendlyName
      $0.description = self.description
      $0.location = self.location ?? ""
      $0.labels = self.labels ?? [:]
      $0.defaultTableExpirationMs = self.defaultTableExpiration?.wholeMilliseconds
      $0.defaultPartitionExpirationMs = self.defaultPartitionExpiration?.wholeMilliseconds
      $0.access = self.access?.map(\.wire) ?? []
      $0.defaultEncryptionConfiguration = self.defaultEncryptionConfiguration?.wire
      $0.defaultCollation = self.defaultCollation
      $0.maxTimeTravelHours = self.maxTimeTravelHours
      if let storageBillingModel = self.storageBillingModel {
        $0.storageBillingModel = .init(stringValue: storageBillingModel.rawValue)
      }
      $0.isCaseInsensitive = self.isCaseInsensitive
      $0.resourceTags = self.resourceTags ?? [:]
      $0.externalDatasetReference = self.externalDatasetReference?.wire
    }
  }

  /// The proto3 scalar defaults that ``wire`` would encode but that this dataset does not set.
  ///
  /// They are omitted so that create and update send only the caller's values.
  var omittedWireDefaults: [String] {
    var paths = [
      "kind", "etag", "id", "selfLink", "creationTime", "lastModifiedTime", "type",
      "defaultRoundingMode",
    ]
    if self.location == nil { paths.append("location") }
    if self.storageBillingModel == nil { paths.append("storageBillingModel") }
    return paths
  }

  /// Returns the dataset with the project filled in, in its ID and in the authorized views,
  /// routines, and datasets of its access list.
  func resolved(by client: BigQueryClient) -> Dataset {
    var dataset = self
    dataset.id = client.resolve(self.id)
    let project = dataset.id.projectID
    dataset.access = self.access?.map { acl in
      var acl = acl
      switch acl.entity.value {
      case .view(var table) where table.projectID?.isEmpty ?? true:
        table.projectID = project
        acl.entity = .view(table)
      case .routine(var routine) where routine.projectID?.isEmpty ?? true:
        routine.projectID = project
        acl.entity = .routine(routine)
      case .dataset(var authorized, let targetTypes) where authorized.projectID?.isEmpty ?? true:
        authorized.projectID = project
        acl.entity = .dataset(authorized, targetTypes: targetTypes)
      default:
        break
      }
      return acl
    }
    return dataset
  }
}

extension ExternalDatasetReference {
  init(wire: GoogleCloudBigQueryV2.ExternalDatasetReference) {
    self.init(externalSource: wire.externalSource, connection: wire.connection)
  }

  var wire: GoogleCloudBigQueryV2.ExternalDatasetReference {
    GoogleCloudBigQueryV2.ExternalDatasetReference().with {
      $0.externalSource = self.externalSource
      $0.connection = self.connection
    }
  }
}

extension Acl {
  init(wire: GoogleCloudBigQueryV2.Access) {
    let entity: Entity
    if let dataset = wire.dataset {
      entity = .dataset(
        DatasetID(wire: dataset.dataset ?? .init()),
        targetTypes: dataset.targetTypes.compactMap { $0.stringValue.map(TargetType.init) })
    } else if let view = wire.view {
      entity = .view(TableID(wire: view))
    } else if let routine = wire.routine {
      entity = .routine(RoutineID(wire: routine))
    } else if let domain = wire.domain.nonEmpty {
      entity = .domain(domain)
    } else if let group = wire.groupByEmail.nonEmpty {
      entity = .group(group)
    } else if let specialGroup = wire.specialGroup.nonEmpty {
      entity = .specialGroup(specialGroup)
    } else if let user = wire.userByEmail.nonEmpty {
      entity = .user(user)
    } else if let member = wire.iamMember.nonEmpty {
      entity = .iamMember(member)
    } else {
      entity = Entity(.unrecognized)
    }
    self.init(
      entity, role: wire.role.nonEmpty.map(Role.init(rawValue:)),
      condition: Expr(conditionOf: wire))
  }

  var wire: GoogleCloudBigQueryV2.Access {
    GoogleCloudBigQueryV2.Access().with {
      switch self.entity.value {
      case .user(let email): $0.userByEmail = email
      case .group(let email): $0.groupByEmail = email
      case .domain(let domain): $0.domain = domain
      case .specialGroup(let name): $0.specialGroup = name
      case .iamMember(let member): $0.iamMember = member
      case .view(let table): $0.view = table.wire
      case .routine(let routine): $0.routine = routine.wire
      case .dataset(let dataset, let targetTypes):
        $0.dataset = GoogleCloudBigQueryV2.DatasetAccessEntry().with {
          $0.dataset = dataset.wire
          $0.targetTypes = targetTypes.map { .init(stringValue: $0.rawValue) }
        }
      case .unrecognized: break
      }
      $0.role = self.role?.rawValue ?? ""
      if let condition = self.condition {
        $0.condition = .init()
        $0.condition?.expression = condition.expression
        $0.condition?.title = condition.title ?? ""
        $0.condition?.description = condition.description ?? ""
        $0.condition?.location = condition.location ?? ""
      }
    }
  }
}

extension Expr {
  /// Converts the condition of an access entry. The generated `google.type.Expr` is used
  /// through type inference only, so `GoogleType` need not be a direct dependency.
  init?(conditionOf wire: GoogleCloudBigQueryV2.Access) {
    guard let condition = wire.condition else { return nil }
    self.init(
      condition.expression, title: condition.title.nonEmpty,
      description: condition.description.nonEmpty, location: condition.location.nonEmpty)
  }
}
