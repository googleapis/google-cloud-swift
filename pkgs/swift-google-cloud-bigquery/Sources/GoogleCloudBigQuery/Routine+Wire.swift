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
import GoogleWKT

// Conversions between `Routine` and the StandardSQL types and the generated wire messages.

extension Routine {
  init(wire: GoogleCloudBigQueryV2.Routine) {
    self.init(id: RoutineID(wire: wire.routineReference ?? .init()))
    if wire.routineType != .unspecified {
      self.type = wire.routineType.stringValue.map(RoutineType.init(rawValue:))
    }
    if wire.language != .unspecified {
      self.language = wire.language.stringValue.map(Language.init(rawValue:))
    }
    self.arguments = wire.arguments.isEmpty ? nil : wire.arguments.map(Argument.init(wire:))
    self.returnType = wire.returnType.map(StandardSQLDataType.init(wire:))
    self.returnTableType = wire.returnTableType.map(StandardSQLTableType.init(wire:))
    self.importedLibraries = wire.importedLibraries.isEmpty ? nil : wire.importedLibraries
    self.body = wire.definitionBody.nonEmpty
    self.description = wire.description.nonEmpty
    if wire.determinismLevel != .unspecified {
      self.determinismLevel = wire.determinismLevel.stringValue.map(
        DeterminismLevel.init(rawValue:))
    }
    self.remoteFunctionOptions = wire.remoteFunctionOptions.map(
      RemoteFunctionOptions.init(wire:))
    if wire.dataGovernanceType != .unspecified {
      self.dataGovernanceType = wire.dataGovernanceType.stringValue.map(
        DataGovernanceType.init(rawValue:))
    }
    self.etag = wire.etag.nonEmpty
    self.creationTime = Date(millisecondsSinceEpoch: wire.creationTime)
    self.lastModifiedTime = Date(millisecondsSinceEpoch: wire.lastModifiedTime)
  }

  /// The request message for create and update. Output-only fields are not set.
  var wire: GoogleCloudBigQueryV2.Routine {
    GoogleCloudBigQueryV2.Routine().with {
      $0.routineReference = self.id.wire
      if let type = self.type { $0.routineType = .init(stringValue: type.rawValue) }
      if let language = self.language { $0.language = .init(stringValue: language.rawValue) }
      $0.arguments = self.arguments?.map(\.wire) ?? []
      $0.returnType = self.returnType?.wire
      $0.returnTableType = self.returnTableType?.wire
      $0.importedLibraries = self.importedLibraries ?? []
      $0.definitionBody = self.body ?? ""
      $0.description = self.description ?? ""
      if let level = self.determinismLevel {
        $0.determinismLevel = .init(stringValue: level.rawValue)
      }
      $0.remoteFunctionOptions = self.remoteFunctionOptions?.wire
      if let type = self.dataGovernanceType {
        $0.dataGovernanceType = .init(stringValue: type.rawValue)
      }
    }
  }

  /// The proto3 scalar defaults that ``wire`` would encode but that this routine does not set.
  var omittedWireDefaults: [String] {
    var paths = ["etag", "creationTime", "lastModifiedTime", "securityMode"]
    if self.type == nil { paths.append("routineType") }
    if self.language == nil { paths.append("language") }
    if self.body == nil { paths.append("definitionBody") }
    if self.description == nil { paths.append("description") }
    if self.determinismLevel == nil { paths.append("determinismLevel") }
    if self.dataGovernanceType == nil { paths.append("dataGovernanceType") }
    if let options = self.remoteFunctionOptions {
      if options.endpoint == nil { paths.append("remoteFunctionOptions.endpoint") }
      if options.connection == nil { paths.append("remoteFunctionOptions.connection") }
      if options.maxBatchingRows == nil { paths.append("remoteFunctionOptions.maxBatchingRows") }
    }
    return paths
  }
}

extension Routine.Argument {
  init(wire: GoogleCloudBigQueryV2.Routine.Argument) {
    self.init(name: wire.name.nonEmpty, dataType: wire.dataType.map(StandardSQLDataType.init(wire:)))
    if wire.argumentKind != .unspecified {
      self.kind = wire.argumentKind.stringValue.map(Kind.init(rawValue:))
    }
    if wire.mode != .unspecified {
      self.mode = wire.mode.stringValue.map(Mode.init(rawValue:))
    }
  }

  var wire: GoogleCloudBigQueryV2.Routine.Argument {
    GoogleCloudBigQueryV2.Routine.Argument().with {
      $0.name = self.name ?? ""
      if let kind = self.kind { $0.argumentKind = .init(stringValue: kind.rawValue) }
      if let mode = self.mode { $0.mode = .init(stringValue: mode.rawValue) }
      $0.dataType = self.dataType?.wire
    }
  }
}

extension Routine.RemoteFunctionOptions {
  init(wire: GoogleCloudBigQueryV2.Routine.RemoteFunctionOptions) {
    self.init(
      endpoint: wire.endpoint.nonEmpty, connection: wire.connection.nonEmpty,
      userDefinedContext: wire.userDefinedContext.isEmpty ? nil : wire.userDefinedContext,
      maxBatchingRows: wire.maxBatchingRows == 0 ? nil : wire.maxBatchingRows)
  }

  var wire: GoogleCloudBigQueryV2.Routine.RemoteFunctionOptions {
    GoogleCloudBigQueryV2.Routine.RemoteFunctionOptions().with {
      $0.endpoint = self.endpoint ?? ""
      $0.connection = self.connection ?? ""
      $0.userDefinedContext = self.userDefinedContext ?? [:]
      $0.maxBatchingRows = self.maxBatchingRows ?? 0
    }
  }
}

extension StandardSQLDataType {
  init(wire: GoogleCloudBigQueryV2.StandardSqlDataType) {
    let kind = TypeKind(rawValue: wire.typeKind.stringValue ?? "")
    switch wire.subType {
    case .arrayElementType(let element):
      self.init(typeKind: kind, subType: .array(StandardSQLDataType(wire: element)))
    case .structType(let structType):
      self.init(typeKind: kind, subType: .struct(StandardSQLStructType(wire: structType)))
    case .rangeElementType(let element):
      self.init(typeKind: kind, subType: .range(StandardSQLDataType(wire: element)))
    case nil:
      self.init(typeKind: kind, subType: nil)
    }
  }

  var wire: GoogleCloudBigQueryV2.StandardSqlDataType {
    GoogleCloudBigQueryV2.StandardSqlDataType().with {
      $0.typeKind = .init(stringValue: self.typeKind.rawValue)
      switch self.subType {
      case .array(let element): $0.subType = .arrayElementType(element.wire)
      case .struct(let structType): $0.subType = .structType(structType.wire)
      case .range(let element): $0.subType = .rangeElementType(element.wire)
      case nil: break
      }
    }
  }
}

extension StandardSQLField {
  init(wire: GoogleCloudBigQueryV2.StandardSqlField) {
    self.init(wire.name.nonEmpty, type: wire.type.map { StandardSQLDataType(wire: $0.value) })
  }

  var wire: GoogleCloudBigQueryV2.StandardSqlField {
    GoogleCloudBigQueryV2.StandardSqlField().with {
      $0.name = self.name ?? ""
      $0.type = self.type.map { WKTRecursive(value: $0.wire) }
    }
  }
}

extension StandardSQLStructType {
  init(wire: GoogleCloudBigQueryV2.StandardSqlStructType) {
    self.init(fields: wire.fields.map(StandardSQLField.init(wire:)))
  }

  var wire: GoogleCloudBigQueryV2.StandardSqlStructType {
    GoogleCloudBigQueryV2.StandardSqlStructType().with { $0.fields = self.fields.map(\.wire) }
  }
}

extension StandardSQLTableType {
  init(wire: GoogleCloudBigQueryV2.StandardSqlTableType) {
    self.init(columns: wire.columns.map(StandardSQLField.init(wire:)))
  }

  var wire: GoogleCloudBigQueryV2.StandardSqlTableType {
    GoogleCloudBigQueryV2.StandardSqlTableType().with { $0.columns = self.columns.map(\.wire) }
  }
}
