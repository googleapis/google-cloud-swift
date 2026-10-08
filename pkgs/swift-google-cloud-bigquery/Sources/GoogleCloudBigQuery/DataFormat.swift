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

/// The format of data loaded into, or read from, BigQuery.
public struct DataFormat: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Comma-separated values. See ``CSVOptions``.
  public static let csv = DataFormat(rawValue: "CSV")
  /// Newline-delimited JSON.
  public static let json = DataFormat(rawValue: "NEWLINE_DELIMITED_JSON")
  /// Apache Avro. See ``AvroOptions``.
  public static let avro = DataFormat(rawValue: "AVRO")
  /// Apache Parquet. See ``ParquetOptions``.
  public static let parquet = DataFormat(rawValue: "PARQUET")
  /// Apache ORC.
  public static let orc = DataFormat(rawValue: "ORC")
  /// A Datastore backup.
  public static let datastoreBackup = DataFormat(rawValue: "DATASTORE_BACKUP")
  /// A Google Sheets spreadsheet (external tables only).
  public static let googleSheets = DataFormat(rawValue: "GOOGLE_SHEETS")
  /// A Bigtable table (external tables only).
  public static let bigtable = DataFormat(rawValue: "BIGTABLE")
  /// Apache Iceberg.
  public static let iceberg = DataFormat(rawValue: "ICEBERG")

  public var description: String { self.rawValue }
}

/// Options for reading CSV data.
public struct CSVOptions: Sendable, Hashable {
  /// Accept rows that are missing trailing optional columns.
  public var allowJaggedRows: Bool?

  /// Accept quoted values that contain newlines.
  public var allowQuotedNewlines: Bool?

  /// The character encoding, for example `UTF-8` or `ISO-8859-1`.
  public var encoding: String?

  /// The field separator, for example `","` or `"\t"`.
  public var fieldDelimiter: String?

  /// The quote character. Use the empty string to disable quoting.
  public var quote: String?

  /// The string that represents `NULL`.
  public var nullMarker: String?

  /// Strings that represent `NULL`. Cannot be combined with ``nullMarker``.
  public var nullMarkers: [String]?

  /// The number of header rows to skip.
  public var skipLeadingRows: Int64?

  /// Preserve embedded ASCII control characters (`0x00` to `0x1F`).
  public var preserveASCIIControlCharacters: Bool?

  /// How columns in the file are matched to the schema: `POSITION` or `NAME`.
  public var sourceColumnMatch: String?

  /// Creates CSV options. Unset options use the service defaults.
  public init(
    allowJaggedRows: Bool? = nil,
    allowQuotedNewlines: Bool? = nil,
    encoding: String? = nil,
    fieldDelimiter: String? = nil,
    quote: String? = nil,
    nullMarker: String? = nil,
    nullMarkers: [String]? = nil,
    skipLeadingRows: Int64? = nil,
    preserveASCIIControlCharacters: Bool? = nil,
    sourceColumnMatch: String? = nil
  ) {
    self.allowJaggedRows = allowJaggedRows
    self.allowQuotedNewlines = allowQuotedNewlines
    self.encoding = encoding
    self.fieldDelimiter = fieldDelimiter
    self.quote = quote
    self.nullMarker = nullMarker
    self.nullMarkers = nullMarkers
    self.skipLeadingRows = skipLeadingRows
    self.preserveASCIIControlCharacters = preserveASCIIControlCharacters
    self.sourceColumnMatch = sourceColumnMatch
  }
}

/// Options for reading Parquet data.
public struct ParquetOptions: Sendable, Hashable {
  /// Infer the `LIST` logical type as an array of its element type.
  public var enableListInference: Bool?

  /// Infer the `ENUM` logical type as `STRING` instead of `BYTES`.
  public var enumAsString: Bool?

  /// How the `MAP` logical type is converted, for example `ARRAY_OF_STRUCT`.
  public var mapTargetType: String?

  /// Creates Parquet options. Unset options use the service defaults.
  public init(
    enableListInference: Bool? = nil, enumAsString: Bool? = nil, mapTargetType: String? = nil
  ) {
    self.enableListInference = enableListInference
    self.enumAsString = enumAsString
    self.mapTargetType = mapTargetType
  }
}

/// Options for reading Avro data.
public struct AvroOptions: Sendable, Hashable {
  /// Convert Avro logical types, such as `timestamp-micros`, to the matching BigQuery types.
  public var useAvroLogicalTypes: Bool?

  /// Creates Avro options. Unset options use the service defaults.
  public init(useAvroLogicalTypes: Bool? = nil) {
    self.useAvroLogicalTypes = useAvroLogicalTypes
  }
}

/// Options for data laid out with Hive partitioning, such as `gs://b/t/dt=2024-01-01/file.csv`.
public struct HivePartitioningOptions: Sendable, Hashable {
  /// How partition keys are typed: `AUTO`, `STRINGS`, or `CUSTOM`.
  public var mode: String?

  /// The common URI prefix of all the source URIs, before the partition keys.
  public var sourceURIPrefix: String?

  /// Require queries to filter on a partition key.
  public var requirePartitionFilter: Bool?

  /// The partition keys detected by the service. Output only.
  public var fields: [String]?

  /// Creates Hive partitioning options.
  public init(
    mode: String? = nil, sourceURIPrefix: String? = nil, requirePartitionFilter: Bool? = nil,
    fields: [String]? = nil
  ) {
    self.mode = mode
    self.sourceURIPrefix = sourceURIPrefix
    self.requirePartitionFilter = requirePartitionFilter
    self.fields = fields
  }
}
