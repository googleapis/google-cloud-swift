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

/// Describes data stored outside BigQuery, for external tables and for the
/// temporary tables of a query.
///
/// Set it on ``Table/externalDataConfiguration`` to create a permanent
/// external table, or pass it in a query's table definitions to query the data
/// without creating a table.
///
/// When ``schema`` is set on a table's configuration, the client sends it as
/// the table schema, which is where BigQuery expects the schema of a permanent
/// external table. A configuration read back from the server has no
/// ``schema``; read ``Table/schema`` instead.
public struct ExternalDataConfiguration: Sendable, Hashable {
  /// The fully-qualified URIs that point to the data, for example
  /// `gs://bucket/path/*.csv`.
  public var sourceURIs: [String]
  /// The format of the data. `nil` for an object table (see ``objectMetadata``).
  public var format: DataFormat?
  /// The schema of the data. Required for CSV and JSON data unless
  /// ``autodetect`` is set; not allowed for Avro, Parquet, ORC, Bigtable, and
  /// Datastore backups.
  public var schema: Schema?
  /// Whether BigQuery should infer the schema and format options.
  public var autodetect: Bool?
  /// The compression of the data: `GZIP` or `NONE` (the default).
  public var compression: String?
  /// Whether values that do not match the schema are ignored instead of
  /// treated as bad records.
  public var ignoreUnknownValues: Bool?
  /// The maximum number of bad records BigQuery ignores when reading the data.
  public var maxBadRecords: Int32?
  /// The connection used to read the data, in the form
  /// `{project}.{location}.{connection}` or
  /// `projects/{project}/locations/{location}/connections/{connection}`.
  public var connectionID: String?
  /// Options for CSV data.
  public var csvOptions: CSVOptions?
  /// Options for Google Sheets data.
  public var googleSheetsOptions: GoogleSheetsOptions?
  /// Options for Bigtable data.
  public var bigtableOptions: BigtableOptions?
  /// Options for Parquet data.
  public var parquetOptions: ParquetOptions?
  /// Options for Avro data.
  public var avroOptions: AvroOptions?
  /// Options for Hive-partitioned data.
  public var hivePartitioningOptions: HivePartitioningOptions?
  /// The types that Parquet and ORC decimal values may be converted to, in
  /// order of preference.
  public var decimalTargetTypes: [DecimalTargetType]?
  /// How ``sourceURIs`` are interpreted.
  public var fileSetSpecType: FileSetSpecType?
  /// Makes the table an object table over the files matched by
  /// ``sourceURIs``. Requires ``connectionID``.
  public var objectMetadata: ObjectMetadata?
  /// A file whose schema is used for the table, for self-describing formats
  /// such as Avro and Parquet.
  public var referenceFileSchemaURI: String?
  /// Whether BigQuery caches the file metadata of a BigLake table.
  public var metadataCacheMode: MetadataCacheMode?
  /// The time zone used to parse timestamps without an explicit time zone.
  public var timeZone: String?
  /// The format used to parse DATE values.
  public var dateFormat: String?
  /// The format used to parse DATETIME values.
  public var dateTimeFormat: String?
  /// The format used to parse TIME values.
  public var timeFormat: String?
  /// The format used to parse TIMESTAMP values.
  public var timestampFormat: String?

  /// Creates a configuration for the data at `sourceURIs`.
  public init(sourceURIs: [String], format: DataFormat?, schema: Schema? = nil) {
    self.sourceURIs = sourceURIs
    self.format = format
    self.schema = schema
  }
}

/// Options for external data in Google Sheets.
public struct GoogleSheetsOptions: Sendable, Hashable {
  /// The number of header rows to skip.
  public var skipLeadingRows: Int64?
  /// The range of the sheet to read, for example `sheet1!A1:B20`.
  public var range: String?

  /// Creates Google Sheets options.
  public init(skipLeadingRows: Int64? = nil, range: String? = nil) {
    self.skipLeadingRows = skipLeadingRows
    self.range = range
  }
}

/// Options for external data in Bigtable.
public struct BigtableOptions: Sendable, Hashable {
  /// The column families to expose in the table schema.
  public var columnFamilies: [BigtableColumnFamily]
  /// Whether column families not listed in ``columnFamilies`` are left out of
  /// the schema.
  public var ignoreUnspecifiedColumnFamilies: Bool?
  /// Whether the row key is read as a string instead of bytes.
  public var readRowKeyAsString: Bool?
  /// Whether each column family is read as a single JSON column.
  public var outputColumnFamiliesAsJSON: Bool?

  /// Creates Bigtable options.
  public init(
    columnFamilies: [BigtableColumnFamily] = [],
    ignoreUnspecifiedColumnFamilies: Bool? = nil,
    readRowKeyAsString: Bool? = nil,
    outputColumnFamiliesAsJSON: Bool? = nil
  ) {
    self.columnFamilies = columnFamilies
    self.ignoreUnspecifiedColumnFamilies = ignoreUnspecifiedColumnFamilies
    self.readRowKeyAsString = readRowKeyAsString
    self.outputColumnFamiliesAsJSON = outputColumnFamiliesAsJSON
  }
}

/// A Bigtable column family exposed by an external table.
public struct BigtableColumnFamily: Sendable, Hashable {
  /// The identifier of the column family.
  public var familyID: String
  /// The type of the values: `BYTES`, `STRING`, `INTEGER`, `FLOAT`, `BOOLEAN`,
  /// or `JSON`.
  public var type: String?
  /// The encoding of the values: `TEXT`, `BINARY`, or `PROTO_BINARY`.
  public var encoding: String?
  /// Columns that need a specific field name, type, or encoding.
  public var columns: [BigtableColumn]
  /// Whether only the latest version of each value is exposed.
  public var onlyReadLatest: Bool?

  /// Creates a column family.
  public init(
    familyID: String,
    type: String? = nil,
    encoding: String? = nil,
    columns: [BigtableColumn] = [],
    onlyReadLatest: Bool? = nil
  ) {
    self.familyID = familyID
    self.type = type
    self.encoding = encoding
    self.columns = columns
    self.onlyReadLatest = onlyReadLatest
  }
}

/// A Bigtable column exposed by an external table.
///
/// Only UTF-8 qualifiers are supported; the generated wire model omits
/// `qualifierEncoded` (design §13).
public struct BigtableColumn: Sendable, Hashable {
  /// The column qualifier.
  public var qualifier: String
  /// The name of the column in the table schema, when the qualifier is not a
  /// valid field name.
  public var fieldName: String?
  /// The type of the values.
  public var type: String?
  /// The encoding of the values.
  public var encoding: String?
  /// Whether only the latest version of each value is exposed.
  public var onlyReadLatest: Bool?

  /// Creates a column.
  public init(
    qualifier: String,
    fieldName: String? = nil,
    type: String? = nil,
    encoding: String? = nil,
    onlyReadLatest: Bool? = nil
  ) {
    self.qualifier = qualifier
    self.fieldName = fieldName
    self.type = type
    self.encoding = encoding
    self.onlyReadLatest = onlyReadLatest
  }
}

/// The configuration of a BigLake managed table (Apache Iceberg format).
public struct BigLakeConfiguration: Sendable, Hashable {
  /// The connection used to read and write the table's files.
  public var connectionID: String
  /// The Cloud Storage location of the table's files, for example
  /// `gs://bucket/path/`.
  public var storageURI: String
  /// The format of the data files.
  public var fileFormat: FileFormat
  /// The format of the table metadata.
  public var tableFormat: TableFormat

  /// Creates a BigLake configuration.
  public init(
    connectionID: String,
    storageURI: String,
    fileFormat: FileFormat = .parquet,
    tableFormat: TableFormat = .iceberg
  ) {
    self.connectionID = connectionID
    self.storageURI = storageURI
    self.fileFormat = fileFormat
    self.tableFormat = tableFormat
  }

  /// The format of BigLake data files.
  public struct FileFormat: RawRepresentable, Sendable, Hashable {
    /// The wire value.
    public var rawValue: String
    /// Creates a value from its wire representation.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Apache Parquet.
    public static let parquet = FileFormat(rawValue: "PARQUET")
  }

  /// The format of BigLake table metadata.
  public struct TableFormat: RawRepresentable, Sendable, Hashable {
    /// The wire value.
    public var rawValue: String
    /// Creates a value from its wire representation.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Apache Iceberg.
    public static let iceberg = TableFormat(rawValue: "ICEBERG")
  }
}

/// A type that Parquet and ORC decimal values may be converted to.
public struct DecimalTargetType: RawRepresentable, Sendable, Hashable {
  /// The wire value.
  public var rawValue: String
  /// Creates a value from its wire representation.
  public init(rawValue: String) { self.rawValue = rawValue }
  /// `NUMERIC`.
  public static let numeric = DecimalTargetType(rawValue: "NUMERIC")
  /// `BIGNUMERIC`.
  public static let bigNumeric = DecimalTargetType(rawValue: "BIGNUMERIC")
  /// `STRING`.
  public static let string = DecimalTargetType(rawValue: "STRING")
}

/// How the source URIs of external data are interpreted.
public struct FileSetSpecType: RawRepresentable, Sendable, Hashable {
  /// The wire value.
  public var rawValue: String
  /// Creates a value from its wire representation.
  public init(rawValue: String) { self.rawValue = rawValue }
  /// The URIs are matched against the object store (the default).
  public static let fileSystemMatch = FileSetSpecType(
    rawValue: "FILE_SET_SPEC_TYPE_FILE_SYSTEM_MATCH")
  /// The URIs name newline-delimited manifest files, one URI per line.
  public static let newLineDelimitedManifest = FileSetSpecType(
    rawValue: "FILE_SET_SPEC_TYPE_NEW_LINE_DELIMITED_MANIFEST")
}

/// The kind of object metadata an object table exposes.
public struct ObjectMetadata: RawRepresentable, Sendable, Hashable {
  /// The wire value.
  public var rawValue: String
  /// Creates a value from its wire representation.
  public init(rawValue: String) { self.rawValue = rawValue }
  /// One row per object, with the object's metadata.
  public static let simple = ObjectMetadata(rawValue: "SIMPLE")
  /// One row per directory.
  public static let directory = ObjectMetadata(rawValue: "DIRECTORY")
}

/// Whether BigQuery caches the file metadata of a BigLake table.
public struct MetadataCacheMode: RawRepresentable, Sendable, Hashable {
  /// The wire value.
  public var rawValue: String
  /// Creates a value from its wire representation.
  public init(rawValue: String) { self.rawValue = rawValue }
  /// BigQuery refreshes the cache automatically.
  public static let automatic = MetadataCacheMode(rawValue: "AUTOMATIC")
  /// The cache is refreshed only by `BQ.REFRESH_EXTERNAL_METADATA_CACHE`.
  public static let manual = MetadataCacheMode(rawValue: "MANUAL")
}

// MARK: - Wire conversions

extension ExternalDataConfiguration {
  init(wire: GoogleCloudBigQueryV2.ExternalDataConfiguration) {
    self.init(
      sourceURIs: wire.sourceUris,
      format: wire.sourceFormat.nonEmpty.map(DataFormat.init(rawValue:)),
      schema: wire.schema.map(Schema.init(wire:)))
    autodetect = wire.autodetect
    compression = wire.compression.nonEmpty
    ignoreUnknownValues = wire.ignoreUnknownValues
    maxBadRecords = wire.maxBadRecords
    connectionID = wire.connectionId.nonEmpty
    csvOptions = wire.csvOptions.map(CSVOptions.init(wire:))
    googleSheetsOptions = wire.googleSheetsOptions.map(GoogleSheetsOptions.init(wire:))
    bigtableOptions = wire.bigtableOptions.map(BigtableOptions.init(wire:))
    parquetOptions = wire.parquetOptions.map(ParquetOptions.init(wire:))
    avroOptions = wire.avroOptions.map(AvroOptions.init(wire:))
    hivePartitioningOptions = wire.hivePartitioningOptions.map(HivePartitioningOptions.init(wire:))
    decimalTargetTypes =
      wire.decimalTargetTypes.isEmpty
      ? nil : wire.decimalTargetTypes.map { DecimalTargetType(rawValue: $0.stringValue ?? "") }
    fileSetSpecType = FileSetSpecType(rawValue: wire.fileSetSpecType.stringValue ?? "")
    objectMetadata = wire.objectMetadata.flatMap {
      $0 == .unspecified ? nil : ObjectMetadata(rawValue: $0.stringValue ?? "")
    }
    referenceFileSchemaURI = wire.referenceFileSchemaUri
    metadataCacheMode =
      wire.metadataCacheMode == .unspecified
      ? nil : MetadataCacheMode(rawValue: wire.metadataCacheMode.stringValue ?? "")
    timeZone = wire.timeZone
    dateFormat = wire.dateFormat
    dateTimeFormat = wire.datetimeFormat
    timeFormat = wire.timeFormat
    timestampFormat = wire.timestampFormat
  }

  var wire: GoogleCloudBigQueryV2.ExternalDataConfiguration {
    .init().with {
      $0.sourceUris = sourceURIs
      $0.sourceFormat = format?.rawValue ?? ""
      $0.schema = schema?.wire
      $0.autodetect = autodetect
      $0.compression = compression ?? ""
      $0.ignoreUnknownValues = ignoreUnknownValues
      $0.maxBadRecords = maxBadRecords
      $0.connectionId = connectionID ?? ""
      $0.csvOptions = csvOptions?.externalWire
      $0.googleSheetsOptions = googleSheetsOptions?.wire
      $0.bigtableOptions = bigtableOptions?.wire
      $0.parquetOptions = parquetOptions?.wire
      $0.avroOptions = avroOptions?.wire
      $0.hivePartitioningOptions = hivePartitioningOptions?.wire
      $0.decimalTargetTypes = (decimalTargetTypes ?? []).map { .init(stringValue: $0.rawValue) }
      if let fileSetSpecType {
        $0.fileSetSpecType = .init(stringValue: fileSetSpecType.rawValue)
      }
      $0.objectMetadata = objectMetadata.map { .init(stringValue: $0.rawValue) }
      $0.referenceFileSchemaUri = referenceFileSchemaURI
      if let metadataCacheMode {
        $0.metadataCacheMode = .init(stringValue: metadataCacheMode.rawValue)
      }
      $0.timeZone = timeZone
      $0.dateFormat = dateFormat
      $0.datetimeFormat = dateTimeFormat
      $0.timeFormat = timeFormat
      $0.timestampFormat = timestampFormat
    }
  }
}

extension GoogleSheetsOptions {
  init(wire: GoogleCloudBigQueryV2.GoogleSheetsOptions) {
    self.init(skipLeadingRows: wire.skipLeadingRows, range: wire.range.nonEmpty)
  }

  var wire: GoogleCloudBigQueryV2.GoogleSheetsOptions {
    .init().with {
      $0.skipLeadingRows = skipLeadingRows
      $0.range = range ?? ""
    }
  }
}

extension BigtableOptions {
  init(wire: GoogleCloudBigQueryV2.BigtableOptions) {
    self.init(
      columnFamilies: wire.columnFamilies.map(BigtableColumnFamily.init(wire:)),
      ignoreUnspecifiedColumnFamilies: wire.ignoreUnspecifiedColumnFamilies,
      readRowKeyAsString: wire.readRowkeyAsString,
      outputColumnFamiliesAsJSON: wire.outputColumnFamiliesAsJson)
  }

  var wire: GoogleCloudBigQueryV2.BigtableOptions {
    .init().with {
      $0.columnFamilies = columnFamilies.map(\.wire)
      $0.ignoreUnspecifiedColumnFamilies = ignoreUnspecifiedColumnFamilies
      $0.readRowkeyAsString = readRowKeyAsString
      $0.outputColumnFamiliesAsJson = outputColumnFamiliesAsJSON
    }
  }
}

extension BigtableColumnFamily {
  init(wire: GoogleCloudBigQueryV2.BigtableColumnFamily) {
    self.init(
      familyID: wire.familyId, type: wire.type.nonEmpty, encoding: wire.encoding.nonEmpty,
      columns: wire.columns.map(BigtableColumn.init(wire:)), onlyReadLatest: wire.onlyReadLatest)
  }

  var wire: GoogleCloudBigQueryV2.BigtableColumnFamily {
    .init().with {
      $0.familyId = familyID
      $0.type = type ?? ""
      $0.encoding = encoding ?? ""
      $0.columns = columns.map(\.wire)
      $0.onlyReadLatest = onlyReadLatest
    }
  }
}

extension BigtableColumn {
  init(wire: GoogleCloudBigQueryV2.BigtableColumn) {
    self.init(
      qualifier: wire.qualifierString ?? "", fieldName: wire.fieldName.nonEmpty,
      type: wire.type.nonEmpty, encoding: wire.encoding.nonEmpty,
      onlyReadLatest: wire.onlyReadLatest)
  }

  var wire: GoogleCloudBigQueryV2.BigtableColumn {
    .init().with {
      $0.qualifierString = qualifier
      $0.fieldName = fieldName ?? ""
      $0.type = type ?? ""
      $0.encoding = encoding ?? ""
      $0.onlyReadLatest = onlyReadLatest
    }
  }
}

extension BigLakeConfiguration {
  init(wire: GoogleCloudBigQueryV2.BigLakeConfiguration) {
    self.init(
      connectionID: wire.connectionId, storageURI: wire.storageUri,
      fileFormat: FileFormat(rawValue: wire.fileFormat.stringValue ?? ""),
      tableFormat: TableFormat(rawValue: wire.tableFormat.stringValue ?? ""))
  }

  var wire: GoogleCloudBigQueryV2.BigLakeConfiguration {
    .init().with {
      $0.connectionId = connectionID
      $0.storageUri = storageURI
      $0.fileFormat = .init(stringValue: fileFormat.rawValue)
      $0.tableFormat = .init(stringValue: tableFormat.rawValue)
    }
  }
}

// The format options below are core types (DataFormat.swift). Their wire
// conversions live here because external tables are their first consumer;
// load jobs reuse the Parquet, Avro and Hive conversions and flatten CSV.

extension CSVOptions {
  init(wire: GoogleCloudBigQueryV2.CsvOptions) {
    self.init()
    allowJaggedRows = wire.allowJaggedRows
    allowQuotedNewlines = wire.allowQuotedNewlines
    encoding = wire.encoding.nonEmpty
    fieldDelimiter = wire.fieldDelimiter.nonEmpty
    quote = wire.quote
    nullMarker = wire.nullMarker
    nullMarkers = wire.nullMarkers.isEmpty ? nil : wire.nullMarkers
    skipLeadingRows = wire.skipLeadingRows
    preserveASCIIControlCharacters = wire.preserveAsciiControlCharacters
    sourceColumnMatch = wire.sourceColumnMatch.nonEmpty
  }

  /// The nested `csvOptions` message used by external tables.
  var externalWire: GoogleCloudBigQueryV2.CsvOptions {
    .init().with {
      $0.allowJaggedRows = allowJaggedRows
      $0.allowQuotedNewlines = allowQuotedNewlines
      $0.encoding = encoding ?? ""
      $0.fieldDelimiter = fieldDelimiter ?? ""
      $0.quote = quote
      $0.nullMarker = nullMarker
      $0.nullMarkers = nullMarkers ?? []
      $0.skipLeadingRows = skipLeadingRows
      $0.preserveAsciiControlCharacters = preserveASCIIControlCharacters
      $0.sourceColumnMatch = sourceColumnMatch ?? ""
    }
  }
}

extension ParquetOptions {
  init(wire: GoogleCloudBigQueryV2.ParquetOptions) {
    self.init()
    enableListInference = wire.enableListInference
    enumAsString = wire.enumAsString
    mapTargetType = wire.mapTargetType == .unspecified ? nil : wire.mapTargetType.stringValue ?? ""
  }

  var wire: GoogleCloudBigQueryV2.ParquetOptions {
    .init().with {
      $0.enableListInference = enableListInference
      $0.enumAsString = enumAsString
      if let mapTargetType {
        $0.mapTargetType = .init(stringValue: mapTargetType)
      }
    }
  }
}

extension AvroOptions {
  init(wire: GoogleCloudBigQueryV2.AvroOptions) {
    self.init()
    useAvroLogicalTypes = wire.useAvroLogicalTypes
  }

  var wire: GoogleCloudBigQueryV2.AvroOptions {
    .init().with { $0.useAvroLogicalTypes = useAvroLogicalTypes }
  }
}

extension HivePartitioningOptions {
  init(wire: GoogleCloudBigQueryV2.HivePartitioningOptions) {
    self.init()
    mode = wire.mode.nonEmpty
    sourceURIPrefix = wire.sourceUriPrefix.nonEmpty
    requirePartitionFilter = wire.requirePartitionFilter
    fields = wire.fields.isEmpty ? nil : wire.fields
  }

  var wire: GoogleCloudBigQueryV2.HivePartitioningOptions {
    .init().with {
      $0.mode = mode ?? ""
      $0.sourceUriPrefix = sourceURIPrefix ?? ""
      $0.requirePartitionFilter = requirePartitionFilter
      $0.fields = fields ?? []
    }
  }
}
