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

import GoogleCloudBigQueryV2

/// The type a load job uses for decimal source values, in order of preference.
public struct DecimalTargetType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let numeric = DecimalTargetType(rawValue: "NUMERIC")
  public static let bigNumeric = DecimalTargetType(rawValue: "BIGNUMERIC")
  public static let string = DecimalTargetType(rawValue: "STRING")

  public var description: String { self.rawValue }
}

/// How a load job maps source column names to BigQuery column names.
public struct ColumnNameCharacterMap: RawRepresentable, Sendable, Hashable,
  CustomStringConvertible
{
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Only letters, digits, and underscores are allowed.
  public static let strict = ColumnNameCharacterMap(rawValue: "STRICT")
  /// Flexible column names; invalid characters are replaced with underscores.
  public static let v1 = ColumnNameCharacterMap(rawValue: "V1")
  /// Flexible column names; more characters are allowed than with ``v1``.
  public static let v2 = ColumnNameCharacterMap(rawValue: "V2")

  public var description: String { self.rawValue }
}

/// How a load job interprets its source URIs.
public struct FileSetSpecType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Each URI names files directly, with wildcards. The service default.
  public static let fileSystemMatch = FileSetSpecType(
    rawValue: "FILE_SET_SPEC_TYPE_FILE_SYSTEM_MATCH")
  /// Each URI names a newline-delimited manifest of files.
  public static let newLineDelimitedManifest = FileSetSpecType(
    rawValue: "FILE_SET_SPEC_TYPE_NEW_LINE_DELIMITED_MANIFEST")

  public var description: String { self.rawValue }
}

/// A JSON variant for load jobs.
public struct JSONExtension: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Newline-delimited GeoJSON.
  public static let geoJSON = JSONExtension(rawValue: "GEOJSON")

  public var description: String { self.rawValue }
}

/// The configuration of a load job.
///
/// The same configuration loads from Cloud Storage (``sourceURIs``, with
/// ``BigQueryClient/createJob(_:id:selectedFields:options:)``) and from local data (with
/// ``BigQueryClient/load(_:configuration:jobID:chunkSize:options:)``, which ignores
/// ``sourceURIs``).
public struct LoadJobConfiguration: Sendable, Equatable {
  /// The table to load into.
  public var destinationTable: TableID
  /// The Cloud Storage URIs to load from, for example `gs://bucket/path/*.csv`.
  public var sourceURIs: [String]
  /// The format of the source data. The service default is CSV.
  public var format: DataFormat?
  /// Options for CSV sources.
  public var csvOptions: CSVOptions?
  /// Options for Parquet sources.
  public var parquetOptions: ParquetOptions?
  /// Options for Avro sources.
  public var avroOptions: AvroOptions?
  /// Hive partitioning of the source files.
  public var hivePartitioning: HivePartitioningOptions?
  /// The schema of the destination table. Omit it when the table exists or with
  /// ``autodetect``.
  public var schema: Schema?
  /// Whether to infer the schema from the source data.
  public var autodetect: Bool?
  /// Whether the job may create the destination table.
  public var createDisposition: CreateDisposition?
  /// What the job does when the destination table has data.
  public var writeDisposition: WriteDisposition?
  /// Schema changes the job may make to the destination table.
  public var schemaUpdateOptions: [SchemaUpdateOption]
  /// The number of bad records to skip before the job fails.
  public var maxBadRecords: Int32?
  /// Whether to ignore values that do not match the schema.
  public var ignoreUnknownValues: Bool?
  /// Time partitioning of the destination table.
  public var timePartitioning: TimePartitioning?
  /// Range partitioning of the destination table.
  public var rangePartitioning: RangePartitioning?
  /// Clustering of the destination table.
  public var clustering: Clustering?
  /// Encryption of the destination table.
  public var destinationEncryption: EncryptionConfiguration?
  /// A file that supplies the schema, for self-describing formats.
  public var referenceFileSchemaURI: String?
  /// The types to use for decimal values, in order of preference.
  public var decimalTargetTypes: [DecimalTargetType]
  /// The Datastore backup properties to load.
  public var projectionFields: [String]
  /// A JSON variant, for JSON sources.
  public var jsonExtension: JSONExtension?
  /// How to map source column names.
  public var columnNameCharacterMap: ColumnNameCharacterMap?
  /// How to interpret ``sourceURIs``.
  public var fileSetSpecType: FileSetSpecType?
  /// The default time zone of timestamp values without one.
  public var timeZone: String?
  /// The format of `DATE` values.
  public var dateFormat: String?
  /// The format of `DATETIME` values.
  public var dateTimeFormat: String?
  /// The format of `TIME` values.
  public var timeFormat: String?
  /// The format of `TIMESTAMP` values.
  public var timestampFormat: String?
  /// Connection properties, for example ``ConnectionProperty/sessionID(_:)``.
  public var connectionProperties: [ConnectionProperty]
  /// Whether to start a new session.
  public var createSession: Bool?
  /// Labels for the job.
  public var labels: [String: String]
  /// The maximum time the job may run.
  public var jobTimeout: Duration?
  /// The reservation that runs the job.
  public var reservation: String?

  /// Creates a load configuration.
  public init(destinationTable: TableID, sourceURIs: [String] = [], format: DataFormat? = nil) {
    self.destinationTable = destinationTable
    self.sourceURIs = sourceURIs
    self.format = format
    self.schemaUpdateOptions = []
    self.decimalTargetTypes = []
    self.projectionFields = []
    self.connectionProperties = []
    self.labels = [:]
  }

  var common: CommonJobFields {
    CommonJobFields(labels: self.labels, jobTimeout: self.jobTimeout, reservation: self.reservation)
  }
}

// MARK: - Wire conversion

extension LoadJobConfiguration {
  init(
    wire: GoogleCloudBigQueryV2.JobConfigurationLoad, common: GoogleCloudBigQueryV2.JobConfiguration
  ) {
    self.init(
      destinationTable: wire.destinationTable.map(TableID.init(wire:))
        ?? TableID(datasetID: "", tableID: ""),
      sourceURIs: wire.sourceUris,
      format: wire.sourceFormat.nonEmpty.map(DataFormat.init(rawValue:)))
    let csv = CSVOptions(
      allowJaggedRows: wire.allowJaggedRows, allowQuotedNewlines: wire.allowQuotedNewlines,
      encoding: wire.encoding.nonEmpty, fieldDelimiter: wire.fieldDelimiter.nonEmpty,
      quote: wire.quote, nullMarker: wire.nullMarker,
      nullMarkers: wire.nullMarkers.isEmpty ? nil : wire.nullMarkers,
      skipLeadingRows: wire.skipLeadingRows.map(Int64.init),
      preserveASCIIControlCharacters: wire.preserveAsciiControlCharacters,
      sourceColumnMatch: specifiedEnumValue(wire.sourceColumnMatch.stringValue))
    self.csvOptions = csv == CSVOptions() ? nil : csv
    self.parquetOptions = wire.parquetOptions.map {
      ParquetOptions(
        enableListInference: $0.enableListInference, enumAsString: $0.enumAsString,
        mapTargetType: specifiedEnumValue($0.mapTargetType.stringValue))
    }
    self.avroOptions = wire.useAvroLogicalTypes.map { AvroOptions(useAvroLogicalTypes: $0) }
    self.hivePartitioning = wire.hivePartitioningOptions.map(hivePartitioningOptions(fromWire:))
    self.schema = wire.schema.map(Schema.init(wire:))
    self.autodetect = wire.autodetect
    self.createDisposition = wire.createDisposition.nonEmpty.map(CreateDisposition.init)
    self.writeDisposition = wire.writeDisposition.nonEmpty.map(WriteDisposition.init)
    self.schemaUpdateOptions = wire.schemaUpdateOptions.map(SchemaUpdateOption.init(rawValue:))
    self.maxBadRecords = wire.maxBadRecords
    self.ignoreUnknownValues = wire.ignoreUnknownValues
    self.timePartitioning = wire.timePartitioning.map(TimePartitioning.init(wire:))
    self.rangePartitioning = wire.rangePartitioning.map(RangePartitioning.init(wire:))
    self.clustering = wire.clustering.map(Clustering.init(wire:))
    self.destinationEncryption = wire.destinationEncryptionConfiguration.map(
      EncryptionConfiguration.init(wire:))
    self.referenceFileSchemaURI = wire.referenceFileSchemaUri
    self.decimalTargetTypes = wire.decimalTargetTypes.compactMap {
      specifiedEnumValue($0.stringValue).map(DecimalTargetType.init(rawValue:))
    }
    self.projectionFields = wire.projectionFields
    self.jsonExtension = specifiedEnumValue(wire.jsonExtension.stringValue).map(
      JSONExtension.init(rawValue:))
    self.columnNameCharacterMap = specifiedEnumValue(wire.columnNameCharacterMap.stringValue)
      .map(ColumnNameCharacterMap.init(rawValue:))
    // FILE_SYSTEM_MATCH is the proto3 default, so it cannot be told apart from "unset".
    if wire.fileSetSpecType != .fileSystemMatch, let value = wire.fileSetSpecType.stringValue {
      self.fileSetSpecType = FileSetSpecType(rawValue: value)
    }
    self.timeZone = wire.timeZone
    self.dateFormat = wire.dateFormat
    self.dateTimeFormat = wire.datetimeFormat
    self.timeFormat = wire.timeFormat
    self.timestampFormat = wire.timestampFormat
    self.connectionProperties = wire.connectionProperties.map(ConnectionProperty.init(wire:))
    self.createSession = wire.createSession
    let shared = CommonJobFields(wire: common)
    self.labels = shared.labels
    self.jobTimeout = shared.jobTimeout
    self.reservation = shared.reservation
  }

  var wire: GoogleCloudBigQueryV2.JobConfigurationLoad {
    GoogleCloudBigQueryV2.JobConfigurationLoad().with {
      $0.destinationTable = self.destinationTable.wire
      $0.sourceUris = self.sourceURIs
      $0.sourceFormat = self.format?.rawValue ?? ""
      if let csv = self.csvOptions {
        $0.allowJaggedRows = csv.allowJaggedRows
        $0.allowQuotedNewlines = csv.allowQuotedNewlines
        $0.encoding = csv.encoding ?? ""
        $0.fieldDelimiter = csv.fieldDelimiter ?? ""
        $0.quote = csv.quote
        $0.nullMarker = csv.nullMarker
        $0.nullMarkers = csv.nullMarkers ?? []
        $0.skipLeadingRows = csv.skipLeadingRows.map { Int32(clamping: $0) }
        $0.preserveAsciiControlCharacters = csv.preserveASCIIControlCharacters
        if let match = csv.sourceColumnMatch {
          $0.sourceColumnMatch = .init(stringValue: match)
        }
      }
      if let parquet = self.parquetOptions {
        $0.parquetOptions = GoogleCloudBigQueryV2.ParquetOptions().with {
          $0.enableListInference = parquet.enableListInference
          $0.enumAsString = parquet.enumAsString
          if let mapTargetType = parquet.mapTargetType {
            $0.mapTargetType = .init(stringValue: mapTargetType)
          }
        }
      }
      $0.useAvroLogicalTypes = self.avroOptions?.useAvroLogicalTypes
      $0.hivePartitioningOptions = self.hivePartitioning.map(wireHivePartitioningOptions)
      $0.schema = self.schema?.wire
      $0.autodetect = self.autodetect
      $0.createDisposition = self.createDisposition?.rawValue ?? ""
      $0.writeDisposition = self.writeDisposition?.rawValue ?? ""
      $0.schemaUpdateOptions = self.schemaUpdateOptions.map(\.rawValue)
      $0.maxBadRecords = self.maxBadRecords
      $0.ignoreUnknownValues = self.ignoreUnknownValues
      $0.timePartitioning = self.timePartitioning?.wire
      $0.rangePartitioning = self.rangePartitioning?.wire
      $0.clustering = self.clustering?.wire
      $0.destinationEncryptionConfiguration = self.destinationEncryption?.wire
      $0.referenceFileSchemaUri = self.referenceFileSchemaURI
      $0.decimalTargetTypes = self.decimalTargetTypes.map { .init(stringValue: $0.rawValue) }
      $0.projectionFields = self.projectionFields
      if let jsonExtension = self.jsonExtension {
        $0.jsonExtension = .init(stringValue: jsonExtension.rawValue)
      }
      if let map = self.columnNameCharacterMap {
        $0.columnNameCharacterMap = .init(stringValue: map.rawValue)
      }
      if let spec = self.fileSetSpecType {
        $0.fileSetSpecType = .init(stringValue: spec.rawValue)
      }
      $0.timeZone = self.timeZone
      $0.dateFormat = self.dateFormat
      $0.datetimeFormat = self.dateTimeFormat
      $0.timeFormat = self.timeFormat
      $0.timestampFormat = self.timestampFormat
      $0.connectionProperties = self.connectionProperties.map(\.wire)
      $0.createSession = self.createSession
    }
  }

  func withDefaultProject(_ projectID: String) -> LoadJobConfiguration {
    var copy = self
    copy.destinationTable = copy.destinationTable.withDefaultProject(projectID)
    return copy
  }
}

private func hivePartitioningOptions(
  fromWire wire: GoogleCloudBigQueryV2.HivePartitioningOptions
) -> HivePartitioningOptions {
  HivePartitioningOptions(
    mode: wire.mode.nonEmpty, sourceURIPrefix: wire.sourceUriPrefix.nonEmpty,
    requirePartitionFilter: wire.requirePartitionFilter,
    fields: wire.fields.isEmpty ? nil : wire.fields)
}

private func wireHivePartitioningOptions(
  _ options: HivePartitioningOptions
) -> GoogleCloudBigQueryV2.HivePartitioningOptions {
  GoogleCloudBigQueryV2.HivePartitioningOptions().with {
    $0.mode = options.mode ?? ""
    $0.sourceUriPrefix = options.sourceURIPrefix ?? ""
    $0.requirePartitionFilter = options.requirePartitionFilter
  }
}
