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

// Conversions between `Model` and the generated wire messages.

extension Model {
  init(wire: GoogleCloudBigQueryV2.Model) {
    self.init(
      id: ModelID(wire: wire.modelReference ?? .init()),
      friendlyName: wire.friendlyName.nonEmpty,
      description: wire.description.nonEmpty,
      labels: wire.labels.isEmpty ? nil : wire.labels,
      expirationTime: Date(millisecondsSinceEpoch: wire.expirationTime),
      encryptionConfiguration: wire.encryptionConfiguration.map(EncryptionConfiguration.init(wire:))
    )
    self.etag = wire.etag.nonEmpty
    if wire.modelType != .unspecified {
      self.modelType = wire.modelType.stringValue.map(ModelType.init(rawValue:))
    }
    self.creationTime = Date(millisecondsSinceEpoch: wire.creationTime)
    self.lastModifiedTime = Date(millisecondsSinceEpoch: wire.lastModifiedTime)
    self.location = wire.location.nonEmpty
    self.trainingRuns = wire.trainingRuns.map(TrainingRun.init(wire:))
    self.featureColumns = wire.featureColumns.map(StandardSQLField.init(wire:))
    self.labelColumns = wire.labelColumns.map(StandardSQLField.init(wire:))
  }

  /// The PATCH request message. Only the mutable properties are set.
  var wire: GoogleCloudBigQueryV2.Model {
    GoogleCloudBigQueryV2.Model().with {
      $0.modelReference = self.id.wire
      $0.friendlyName = self.friendlyName ?? ""
      $0.description = self.description ?? ""
      $0.labels = self.labels ?? [:]
      $0.expirationTime = self.expirationTime?.millisecondsSinceEpoch ?? 0
      $0.encryptionConfiguration = self.encryptionConfiguration?.wire
    }
  }

  /// The proto3 scalar defaults that ``wire`` would encode but that this model does not set.
  var omittedWireDefaults: [String] {
    var paths = [
      "etag", "creationTime", "lastModifiedTime", "location", "modelType", "defaultTrialId",
    ]
    if self.friendlyName == nil { paths.append("friendlyName") }
    if self.description == nil { paths.append("description") }
    if self.expirationTime == nil { paths.append("expirationTime") }
    return paths
  }
}

extension Model.TrainingRun {
  init(wire: GoogleCloudBigQueryV2.Model.TrainingRun) {
    self.init(
      startTime: wire.startTime.map(Date.init(wire:)),
      trainingOptions: wire.trainingOptions.map(Model.TrainingOptions.init(wire:)))
  }
}

extension Model.TrainingOptions {
  init(wire: GoogleCloudBigQueryV2.Model.TrainingRun.TrainingOptions) {
    self.init(
      maxIterations: wire.maxIterations == 0 ? nil : wire.maxIterations,
      lossType: wire.lossType == .unspecified
        ? nil : wire.lossType.stringValue.map(LossType.init(rawValue:)),
      learnRate: wire.learnRate == 0 ? nil : wire.learnRate,
      learnRateStrategy: wire.learnRateStrategy == .unspecified
        ? nil : wire.learnRateStrategy.stringValue.map(LearnRateStrategy.init(rawValue:)),
      earlyStop: wire.earlyStop,
      dataSplitColumn: wire.dataSplitColumn.nonEmpty)
  }
}
