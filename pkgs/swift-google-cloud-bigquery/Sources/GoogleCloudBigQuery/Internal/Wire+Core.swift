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

// Conversions between the core public types and the generated wire messages.
//
// Each public type has `init(wire:)` and `var wire`. IDs must be resolved with
// `BigQueryClient.resolve(_:)` before conversion; a `nil` project becomes `""`.

extension DatasetID {
  init(wire: GoogleCloudBigQueryV2.DatasetReference) {
    self.init(projectID: wire.projectId.nonEmpty, datasetID: wire.datasetId)
  }

  var wire: GoogleCloudBigQueryV2.DatasetReference {
    GoogleCloudBigQueryV2.DatasetReference().with {
      $0.projectId = self.projectID ?? ""
      $0.datasetId = self.datasetID
    }
  }
}

extension TableID {
  init(wire: GoogleCloudBigQueryV2.TableReference) {
    self.init(projectID: wire.projectId.nonEmpty, datasetID: wire.datasetId, tableID: wire.tableId)
  }

  var wire: GoogleCloudBigQueryV2.TableReference {
    GoogleCloudBigQueryV2.TableReference().with {
      $0.projectId = self.projectID ?? ""
      $0.datasetId = self.datasetID
      $0.tableId = self.tableID
    }
  }
}

extension RoutineID {
  init(wire: GoogleCloudBigQueryV2.RoutineReference) {
    self.init(
      projectID: wire.projectId.nonEmpty, datasetID: wire.datasetId, routineID: wire.routineId)
  }

  var wire: GoogleCloudBigQueryV2.RoutineReference {
    GoogleCloudBigQueryV2.RoutineReference().with {
      $0.projectId = self.projectID ?? ""
      $0.datasetId = self.datasetID
      $0.routineId = self.routineID
    }
  }
}

extension ModelID {
  init(wire: GoogleCloudBigQueryV2.ModelReference) {
    self.init(projectID: wire.projectId.nonEmpty, datasetID: wire.datasetId, modelID: wire.modelId)
  }

  var wire: GoogleCloudBigQueryV2.ModelReference {
    GoogleCloudBigQueryV2.ModelReference().with {
      $0.projectId = self.projectID ?? ""
      $0.datasetId = self.datasetID
      $0.modelId = self.modelID
    }
  }
}

extension JobID {
  init(wire: GoogleCloudBigQueryV2.JobReference) {
    self.init(projectID: wire.projectId.nonEmpty, jobID: wire.jobId, location: wire.location)
  }

  var wire: GoogleCloudBigQueryV2.JobReference {
    GoogleCloudBigQueryV2.JobReference().with {
      $0.projectId = self.projectID ?? ""
      $0.jobId = self.jobID
      $0.location = self.location
    }
  }
}

extension Schema {
  init(wire: GoogleCloudBigQueryV2.TableSchema) {
    self.init(wire.fields.map(Field.init(wire:)))
  }

  var wire: GoogleCloudBigQueryV2.TableSchema {
    GoogleCloudBigQueryV2.TableSchema().with { $0.fields = self.fields.map(\.wire) }
  }
}

extension Field {
  init(wire: GoogleCloudBigQueryV2.TableFieldSchema) {
    self.init(
      wire.name, FieldType(rawValue: wire.type), mode: wire.mode.nonEmpty.map(Mode.init(rawValue:)),
      fields: wire.fields.map(Field.init(wire:)), description: wire.description)
    self.maxLength = wire.maxLength == 0 ? nil : wire.maxLength
    self.precision = wire.precision == 0 ? nil : wire.precision
    self.scale = wire.scale == 0 ? nil : wire.scale
    if wire.roundingMode != .unspecified, let name = wire.roundingMode.stringValue {
      self.roundingMode = RoundingMode(rawValue: name)
    }
    self.collation = wire.collation
    self.defaultValueExpression = wire.defaultValueExpression
    self.rangeElementType = wire.rangeElementType.map { FieldType(rawValue: $0.type) }
    self.policyTags = wire.policyTags?.names
  }

  var wire: GoogleCloudBigQueryV2.TableFieldSchema {
    GoogleCloudBigQueryV2.TableFieldSchema().with {
      $0.name = self.name
      $0.type = self.type.rawValue
      $0.mode = self.mode?.rawValue ?? ""
      $0.fields = self.fields.map(\.wire)
      $0.description = self.description
      $0.maxLength = self.maxLength ?? 0
      $0.precision = self.precision ?? 0
      $0.scale = self.scale ?? 0
      if let roundingMode = self.roundingMode {
        $0.roundingMode = GoogleCloudBigQueryV2.TableFieldSchema.RoundingMode(
          stringValue: roundingMode.rawValue)
      }
      $0.collation = self.collation
      $0.defaultValueExpression = self.defaultValueExpression
      if let rangeElementType = self.rangeElementType {
        $0.rangeElementType = GoogleCloudBigQueryV2.TableFieldSchema.FieldElementType().with {
          $0.type = rangeElementType.rawValue
        }
      }
      if let policyTags = self.policyTags {
        $0.policyTags = GoogleCloudBigQueryV2.TableFieldSchema.PolicyTagList().with {
          $0.names = policyTags
        }
      }
    }
  }
}

extension EncryptionConfiguration {
  init(wire: GoogleCloudBigQueryV2.EncryptionConfiguration) {
    self.init(kmsKeyName: wire.kmsKeyName)
  }

  var wire: GoogleCloudBigQueryV2.EncryptionConfiguration {
    GoogleCloudBigQueryV2.EncryptionConfiguration().with { $0.kmsKeyName = self.kmsKeyName }
  }
}

extension TimePartitioning {
  /// A missing `type` means `DAY`, as in Java (`TimePartitioning.fromPb`).
  init(wire: GoogleCloudBigQueryV2.TimePartitioning) {
    self.init(
      type: wire.type.isEmpty ? .day : PartitionType(rawValue: wire.type), field: wire.field,
      expiration: wire.expirationMs.map { .milliseconds($0) })
  }

  var wire: GoogleCloudBigQueryV2.TimePartitioning {
    GoogleCloudBigQueryV2.TimePartitioning().with {
      $0.type = self.type.rawValue
      $0.field = self.field
      $0.expirationMs = self.expiration.map(\.wholeMilliseconds)
    }
  }
}

extension RangePartitioning {
  init(wire: GoogleCloudBigQueryV2.RangePartitioning) {
    let range = wire.range
    self.init(
      field: wire.field,
      range: Range(
        start: range.flatMap { Int64($0.start) } ?? 0,
        end: range.flatMap { Int64($0.end) } ?? 0,
        interval: range.flatMap { Int64($0.interval) } ?? 0))
  }

  var wire: GoogleCloudBigQueryV2.RangePartitioning {
    GoogleCloudBigQueryV2.RangePartitioning().with {
      $0.field = self.field
      $0.range = GoogleCloudBigQueryV2.RangePartitioning.Range().with {
        $0.start = String(self.range.start)
        $0.end = String(self.range.end)
        $0.interval = String(self.range.interval)
      }
    }
  }
}

extension Clustering {
  init(wire: GoogleCloudBigQueryV2.Clustering) {
    self.init(fields: wire.fields)
  }

  var wire: GoogleCloudBigQueryV2.Clustering {
    GoogleCloudBigQueryV2.Clustering().with { $0.fields = self.fields }
  }
}

extension UserDefinedFunction {
  init?(wire: GoogleCloudBigQueryV2.UserDefinedFunctionResource) {
    if let code = wire.inlineCode {
      self = .inline(code)
    } else if let uri = wire.resourceUri {
      self = .fromURI(uri)
    } else {
      return nil
    }
  }

  var wire: GoogleCloudBigQueryV2.UserDefinedFunctionResource {
    GoogleCloudBigQueryV2.UserDefinedFunctionResource().with {
      switch self {
      case .inline(let code): $0.inlineCode = code
      case .fromURI(let uri): $0.resourceUri = uri
      }
    }
  }
}

extension Duration {
  /// The duration in whole milliseconds, truncated towards zero.
  var wholeMilliseconds: Int64 {
    let (seconds, attoseconds) = self.components
    return seconds * 1000 + attoseconds / 1_000_000_000_000_000
  }
}
