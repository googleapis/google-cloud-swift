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
import Testing

@testable import GoogleCloudBigQuery

/// The public type, which `GoogleCloudBigQueryV2` also declares.
private typealias ExternalDataConfiguration = GoogleCloudBigQuery.ExternalDataConfiguration

@Suite struct ExternalDataConfigurationTests {
  /// Decodes `json` as a wire message, converts it to the public type, and checks that the
  /// conversion back to the wire and to the public type again preserves every field.
  private func roundTrip(_ json: String) throws -> ExternalDataConfiguration {
    let wire = try WireJSON.decode(json, as: GoogleCloudBigQueryV2.ExternalDataConfiguration.self)
    let value = ExternalDataConfiguration(wire: wire)
    #expect(ExternalDataConfiguration(wire: value.wire) == value)
    #expect(try WireJSON.object(value.wire) == WireJSON.object(wire))
    return value
  }

  // Baseline: U.ExternalTableDefinition.01, U.CsvOptions.01
  @Test func csvConfigurationRoundTrips() throws {
    let value = try roundTrip(
      #"""
      {"sourceUris": ["gs://b/a.csv", "gs://b/b.csv"], "sourceFormat": "CSV",
       "schema": {"fields": [{"name": "a", "type": "STRING"}]},
       "autodetect": false, "compression": "GZIP", "ignoreUnknownValues": true, "maxBadRecords": 42,
       "connectionId": "p.us.conn", "fileSetSpecType": "FILE_SET_SPEC_TYPE_NEW_LINE_DELIMITED_MANIFEST",
       "referenceFileSchemaUri": "gs://b/ref", "metadataCacheMode": "MANUAL",
       "timeZone": "America/New_York", "dateFormat": "YYYY-MM-DD", "datetimeFormat": "YYYY-MM-DD HH24:MI:SS",
       "timeFormat": "HH24:MI:SS", "timestampFormat": "YYYY-MM-DD HH24:MI:SS.FF6 TZH",
       "csvOptions": {"fieldDelimiter": ";", "skipLeadingRows": "1", "quote": "'",
         "allowQuotedNewlines": true, "allowJaggedRows": true, "encoding": "UTF-8",
         "preserveAsciiControlCharacters": true, "nullMarker": "\\N", "nullMarkers": ["", "NULL"],
         "sourceColumnMatch": "NAME"}}
      """#)
    #expect(value.sourceURIs == ["gs://b/a.csv", "gs://b/b.csv"])
    #expect(value.format == .csv)
    #expect(value.schema == Schema([Field("a", .string)]))
    #expect(value.autodetect == false)
    #expect(value.compression == "GZIP")
    #expect(value.ignoreUnknownValues == true)
    #expect(value.maxBadRecords == 42)
    #expect(value.connectionID == "p.us.conn")
    #expect(value.fileSetSpecType == .newLineDelimitedManifest)
    #expect(value.referenceFileSchemaURI == "gs://b/ref")
    #expect(value.metadataCacheMode == .manual)
    #expect(value.timeZone == "America/New_York")
    #expect(value.dateFormat == "YYYY-MM-DD")
    #expect(value.dateTimeFormat == "YYYY-MM-DD HH24:MI:SS")
    #expect(value.timeFormat == "HH24:MI:SS")
    #expect(value.timestampFormat == "YYYY-MM-DD HH24:MI:SS.FF6 TZH")
    let csv = try #require(value.csvOptions)
    #expect(csv.fieldDelimiter == ";")
    #expect(csv.skipLeadingRows == 1)
    #expect(csv.quote == "'")
    #expect(csv.allowQuotedNewlines == true)
    #expect(csv.allowJaggedRows == true)
    #expect(csv.encoding == "UTF-8")
    #expect(csv.preserveASCIIControlCharacters == true)
    #expect(csv.nullMarker == "\\N")
    #expect(csv.nullMarkers == ["", "NULL"])
    #expect(csv.sourceColumnMatch == "NAME")
  }

  // Baseline: U.CsvOptions.01
  @Test func emptyQuoteIsSentAndKept() throws {
    var csv = CSVOptions()
    csv.quote = ""
    var configuration = ExternalDataConfiguration(sourceURIs: ["gs://b/a"], format: .csv)
    configuration.csvOptions = csv
    let wire = configuration.wire
    let object = try WireJSON.object(wire)
    #expect((object["csvOptions"] as? NSDictionary)?["quote"] as? String == "")
    #expect(ExternalDataConfiguration(wire: wire).csvOptions?.quote == "")
  }

  // Baseline: U.ExternalTableDefinition.01, U.ParquetOptions.01
  @Test func parquetConfigurationRoundTrips() throws {
    let value = try roundTrip(
      #"""
      {"sourceUris": ["gs://b/*.parquet"], "sourceFormat": "PARQUET",
       "decimalTargetTypes": ["NUMERIC", "BIGNUMERIC", "STRING"],
       "parquetOptions": {"enumAsString": true, "enableListInference": true,
         "mapTargetType": "ARRAY_OF_STRUCT"}}
      """#)
    #expect(value.format == .parquet)
    #expect(value.decimalTargetTypes == [.numeric, .bigNumeric, .string])
    #expect(value.parquetOptions?.enumAsString == true)
    #expect(value.parquetOptions?.enableListInference == true)
    #expect(value.parquetOptions?.mapTargetType == "ARRAY_OF_STRUCT")
  }

  // Baseline: U.AvroOptions.01
  @Test func avroConfigurationRoundTrips() throws {
    let value = try roundTrip(
      #"""
      {"sourceUris": ["gs://b/*.avro"], "sourceFormat": "AVRO",
       "avroOptions": {"useAvroLogicalTypes": true}}
      """#)
    #expect(value.format == .avro)
    #expect(value.avroOptions?.useAvroLogicalTypes == true)
  }

  // Baseline: U.HivePartitioningOptions.01
  @Test func hivePartitioningRoundTrips() throws {
    let value = try roundTrip(
      #"""
      {"sourceUris": ["gs://b/hive/*"], "sourceFormat": "CSV", "autodetect": true,
       "hivePartitioningOptions": {"mode": "CUSTOM", "sourceUriPrefix": "gs://b/hive/{pkey:STRING}/",
         "requirePartitionFilter": true, "fields": ["pkey"]}}
      """#)
    let hive = try #require(value.hivePartitioningOptions)
    #expect(hive.mode == "CUSTOM")
    #expect(hive.sourceURIPrefix == "gs://b/hive/{pkey:STRING}/")
    #expect(hive.requirePartitionFilter == true)
    #expect(hive.fields == ["pkey"])
  }

  // Baseline: U.GoogleSheetsOptions.01
  @Test func googleSheetsConfigurationRoundTrips() throws {
    let value = try roundTrip(
      #"""
      {"sourceUris": ["https://docs.google.com/spreadsheets/d/x"], "sourceFormat": "GOOGLE_SHEETS",
       "googleSheetsOptions": {"skipLeadingRows": "1", "range": "sheet1!A1:B20"}}
      """#)
    #expect(value.format == .googleSheets)
    #expect(
      value.googleSheetsOptions == GoogleSheetsOptions(skipLeadingRows: 1, range: "sheet1!A1:B20"))
  }

  // Baseline: U.BigtableOptions.01
  @Test func bigtableConfigurationRoundTrips() throws {
    let value = try roundTrip(
      #"""
      {"sourceUris": ["https://googleapis.com/bigtable/projects/p/instances/i/tables/t"],
       "sourceFormat": "BIGTABLE",
       "bigtableOptions": {"ignoreUnspecifiedColumnFamilies": true, "readRowkeyAsString": true,
         "outputColumnFamiliesAsJson": true,
         "columnFamilies": [{"familyId": "f", "type": "INTEGER", "encoding": "BINARY",
           "onlyReadLatest": true,
           "columns": [{"qualifierString": "q", "fieldName": "col", "type": "STRING",
             "encoding": "TEXT", "onlyReadLatest": false}]}]}}
      """#)
    let expected = BigtableOptions(
      columnFamilies: [
        BigtableColumnFamily(
          familyID: "f", type: "INTEGER", encoding: "BINARY",
          columns: [
            BigtableColumn(
              qualifier: "q", fieldName: "col", type: "STRING", encoding: "TEXT",
              onlyReadLatest: false)
          ],
          onlyReadLatest: true)
      ],
      ignoreUnspecifiedColumnFamilies: true, readRowKeyAsString: true,
      outputColumnFamiliesAsJSON: true)
    #expect(value.bigtableOptions == expected)
  }

  // Baseline: U.ExternalTableDefinition.01
  @Test func objectTableRoundTrips() throws {
    let value = try roundTrip(
      #"""
      {"sourceUris": ["gs://b/*"], "sourceFormat": "", "objectMetadata": "SIMPLE",
       "connectionId": "projects/p/locations/us/connections/c", "metadataCacheMode": "AUTOMATIC"}
      """#)
    #expect(value.format == nil)
    #expect(value.objectMetadata == .simple)
    #expect(value.metadataCacheMode == .automatic)
  }

  // Baseline: U.ExternalTableDefinition.01
  @Test func absentFieldsDecodeToServerDefaults() throws {
    let value = try roundTrip(
      #"{"sourceUris": ["gs://b/a.json"], "sourceFormat": "NEWLINE_DELIMITED_JSON"}"#)
    var expected = ExternalDataConfiguration(sourceURIs: ["gs://b/a.json"], format: .json)
    // The proto3 default of `fileSetSpecType` is a real value, the server default.
    expected.fileSetSpecType = .fileSystemMatch
    #expect(value == expected)
  }

  // Baseline: U.BigLakeConfiguration.01
  @Test func bigLakeConfigurationRoundTrips() throws {
    let wire = try WireJSON.decode(
      #"""
      {"connectionId": "p.us.c", "storageUri": "gs://b/iceberg/", "fileFormat": "PARQUET",
       "tableFormat": "ICEBERG"}
      """#, as: GoogleCloudBigQueryV2.BigLakeConfiguration.self)
    let value = BigLakeConfiguration(wire: wire)
    #expect(
      value
        == BigLakeConfiguration(
          connectionID: "p.us.c", storageURI: "gs://b/iceberg/", fileFormat: .parquet,
          tableFormat: .iceberg))
    #expect(
      try WireJSON.object(value.wire)
        == WireJSON.object(
          #"""
          {"connectionId": "p.us.c", "storageUri": "gs://b/iceberg/", "fileFormat": "PARQUET",
           "tableFormat": "ICEBERG"}
          """#))
  }

  // Baseline: U.BigLakeConfiguration.02
  @Test func bigLakeConfigurationWithoutFieldsDecodes() throws {
    let wire = try WireJSON.decode("{}", as: GoogleCloudBigQueryV2.BigLakeConfiguration.self)
    let value = BigLakeConfiguration(wire: wire)
    #expect(value.connectionID.isEmpty)
    #expect(value.storageURI.isEmpty)
  }

  // Baseline: U.FormatOptions.01
  @Test func dataFormatsUseWireNames() {
    #expect(DataFormat.csv.rawValue == "CSV")
    #expect(DataFormat.json.rawValue == "NEWLINE_DELIMITED_JSON")
    #expect(DataFormat.avro.rawValue == "AVRO")
    #expect(DataFormat.parquet.rawValue == "PARQUET")
    #expect(DataFormat.orc.rawValue == "ORC")
    #expect(DataFormat.datastoreBackup.rawValue == "DATASTORE_BACKUP")
    #expect(DataFormat.googleSheets.rawValue == "GOOGLE_SHEETS")
    #expect(DataFormat.bigtable.rawValue == "BIGTABLE")
    #expect(DataFormat.iceberg.rawValue == "ICEBERG")
  }
}
