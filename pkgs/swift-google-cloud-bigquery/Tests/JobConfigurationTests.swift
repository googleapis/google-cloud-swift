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

/// Decodes a wire `JobConfiguration` fixture, converts it, and checks that converting the result
/// back to wire form and again to the public type gives the same value.
private func roundTrip(_ json: String) throws -> GoogleCloudBigQuery.JobConfiguration {
  let wire = try WireJSON.decode(json, as: GoogleCloudBigQueryV2.JobConfiguration.self)
  let converted: GoogleCloudBigQuery.JobConfiguration? = .init(wire: wire)
  let configuration = try #require(converted)
  let encoded = try WireJSON.decode(
    String(decoding: try RequestBody.json(configuration.wire), as: UTF8.self),
    as: GoogleCloudBigQueryV2.JobConfiguration.self)
  #expect(GoogleCloudBigQuery.JobConfiguration(wire: encoded) == configuration)
  return configuration
}

@Suite struct QueryJobConfigurationTests {
  // Baseline: U.QueryJobConfiguration.01, U.QueryJobConfiguration.03
  @Test func roundTripsEveryField() throws {
    let configuration = try roundTrip(
      #"""
      {"dryRun": true, "jobTimeoutMs": "1000", "labels": {"k": "v"}, "reservation": "r",
       "query": {"query": "SELECT @a", "useLegacySql": false, "parameterMode": "NAMED",
         "queryParameters": [{"name": "a", "parameterType": {"type": "INT64"},
                              "parameterValue": {"value": "1"}}],
         "defaultDataset": {"projectId": "p", "datasetId": "d"},
         "destinationTable": {"projectId": "p", "datasetId": "d", "tableId": "t"},
         "createDisposition": "CREATE_NEVER", "writeDisposition": "WRITE_APPEND",
         "schemaUpdateOptions": ["ALLOW_FIELD_ADDITION"],
         "userDefinedFunctionResources": [{"inlineCode": "f"}, {"resourceUri": "gs://b/f.js"}],
         "priority": "BATCH", "allowLargeResults": true, "flattenResults": false,
         "useQueryCache": false, "maximumBytesBilled": "100",
         "destinationEncryptionConfiguration": {"kmsKeyName": "k"},
         "timePartitioning": {"type": "DAY", "field": "ts", "expirationMs": "5000"},
         "clustering": {"fields": ["c"]},
         "scriptOptions": {"statementTimeoutMs": "10", "statementByteBudget": "20",
                           "keyResultStatement": "FIRST_SELECT"},
         "connectionProperties": [{"key": "time_zone", "value": "UTC"}],
         "createSession": true}}
      """#)
    guard case .query(let query) = configuration else {
      Issue.record("expected a query configuration")
      return
    }
    #expect(query.query == "SELECT @a")
    #expect(query.parameters == .named(["a": .int64(1)]))
    #expect(query.defaultDataset == DatasetID(projectID: "p", datasetID: "d"))
    #expect(query.destinationTable == TableID(projectID: "p", datasetID: "d", tableID: "t"))
    #expect(query.createDisposition == .createNever)
    #expect(query.writeDisposition == .writeAppend)
    #expect(query.schemaUpdateOptions == [.allowFieldAddition])
    #expect(query.userDefinedFunctions == [.inline("f"), .fromURI("gs://b/f.js")])
    #expect(query.priority == .batch)
    #expect(query.allowLargeResults == true)
    #expect(query.flattenResults == false)
    #expect(query.useQueryCache == false)
    #expect(query.maximumBytesBilled == 100)
    #expect(query.destinationEncryption == EncryptionConfiguration(kmsKeyName: "k"))
    #expect(
      query.timePartitioning == TimePartitioning(type: .day, field: "ts", expiration: .seconds(5)))
    #expect(query.clustering == Clustering(fields: ["c"]))
    #expect(
      query.scriptOptions
        == ScriptOptions(
          statementTimeout: .milliseconds(10), statementByteBudget: 20,
          keyResultStatement: .firstSelect))
    #expect(query.connectionProperties == [.timeZone("UTC")])
    #expect(query.createSession == true)
    #expect(query.dryRun)
    #expect(query.jobTimeout == .seconds(1))
    #expect(query.labels == ["k": "v"])
    #expect(query.reservation == "r")
  }

  // Baseline: U.QueryJobConfiguration.02, U.JobInfo.02
  @Test func defaultProjectFillsOnlyMissingProjects() {
    var query = QueryJobConfiguration("SELECT 1")
    query.defaultDataset = DatasetID(datasetID: "d")
    query.destinationTable = TableID(projectID: "explicit", datasetID: "d", tableID: "t")
    let filled = query.withDefaultProject("p")
    #expect(filled.defaultDataset?.projectID == "p")
    #expect(filled.destinationTable?.projectID == "explicit")
  }

  // Design: §6.1
  @Test func positionalParametersRoundTrip() throws {
    let configuration = try roundTrip(
      #"""
      {"query": {"query": "SELECT ?", "parameterMode": "POSITIONAL",
        "queryParameters": [{"parameterType": {"type": "STRING"}, "parameterValue": {"value": "x"}}]}}
      """#)
    guard case .query(let query) = configuration else {
      Issue.record("expected a query configuration")
      return
    }
    #expect(query.parameters == .positional([.string("x")]))
  }
}

@Suite struct LoadJobConfigurationTests {
  // Baseline: U.LoadJobConfiguration.01, U.LoadJobConfiguration.03
  @Test func roundTripsEveryField() throws {
    let configuration = try roundTrip(
      #"""
      {"labels": {"k": "v"}, "jobTimeoutMs": "2000",
       "load": {"destinationTable": {"projectId": "p", "datasetId": "d", "tableId": "t"},
         "sourceUris": ["gs://b/a.csv"], "sourceFormat": "CSV",
         "allowJaggedRows": true, "allowQuotedNewlines": true, "encoding": "UTF-8",
         "fieldDelimiter": "|", "quote": "'", "nullMarker": "\\N", "skipLeadingRows": 1,
         "preserveAsciiControlCharacters": true,
         "schema": {"fields": [{"name": "x", "type": "INT64"}]}, "autodetect": false,
         "createDisposition": "CREATE_IF_NEEDED", "writeDisposition": "WRITE_TRUNCATE",
         "schemaUpdateOptions": ["ALLOW_FIELD_RELAXATION"], "maxBadRecords": 3,
         "ignoreUnknownValues": true,
         "rangePartitioning": {"field": "x", "range": {"start": "0", "end": "10", "interval": "1"}},
         "destinationEncryptionConfiguration": {"kmsKeyName": "k"},
         "decimalTargetTypes": ["NUMERIC", "STRING"], "projectionFields": ["a"],
         "jsonExtension": "GEOJSON", "fileSetSpecType": "FILE_SET_SPEC_TYPE_NEW_LINE_DELIMITED_MANIFEST",
         "timeZone": "UTC", "dateFormat": "YYYY", "connectionProperties": [{"key": "k", "value": "v"}],
         "createSession": false,
         "hivePartitioningOptions": {"mode": "AUTO", "sourceUriPrefix": "gs://b/",
                                     "requirePartitionFilter": true}}}
      """#)
    guard case .load(let load) = configuration else {
      Issue.record("expected a load configuration")
      return
    }
    #expect(load.destinationTable == TableID(projectID: "p", datasetID: "d", tableID: "t"))
    #expect(load.sourceURIs == ["gs://b/a.csv"])
    #expect(load.format == .csv)
    #expect(load.csvOptions?.fieldDelimiter == "|")
    #expect(load.csvOptions?.quote == "'")
    #expect(load.csvOptions?.skipLeadingRows == 1)
    #expect(load.csvOptions?.allowJaggedRows == true)
    #expect(load.schema?.fields.map(\.name) == ["x"])
    #expect(load.autodetect == false)
    #expect(load.writeDisposition == .writeTruncate)
    #expect(load.schemaUpdateOptions == [.allowFieldRelaxation])
    #expect(load.maxBadRecords == 3)
    #expect(load.ignoreUnknownValues == true)
    #expect(load.rangePartitioning?.range.end == 10)
    #expect(load.decimalTargetTypes == [.numeric, .string])
    #expect(load.projectionFields == ["a"])
    #expect(load.jsonExtension == .geoJSON)
    #expect(load.fileSetSpecType == .newLineDelimitedManifest)
    #expect(load.timeZone == "UTC")
    #expect(load.hivePartitioning?.mode == "AUTO")
    #expect(load.labels == ["k": "v"])
    #expect(load.jobTimeout == .seconds(2))
  }

  // Baseline: U.LoadJobConfiguration.02, U.WriteChannelConfiguration.02
  @Test func defaultProjectFillsOnlyMissingProjects() {
    let missing = LoadJobConfiguration(destinationTable: TableID(datasetID: "d", tableID: "t"))
    #expect(missing.withDefaultProject("p").destinationTable.projectID == "p")
    let explicit = LoadJobConfiguration(
      destinationTable: TableID(projectID: "explicit", datasetID: "d", tableID: "t"))
    #expect(explicit.withDefaultProject("p").destinationTable.projectID == "explicit")
  }

  // Baseline: U.WriteChannelConfiguration.01
  @Test func uploadConfigurationRoundTripsWithoutSourceURIs() throws {
    var load = LoadJobConfiguration(
      destinationTable: TableID(projectID: "p", datasetID: "d", tableID: "t"), format: .json)
    load.schema = Schema([Field("x", .int64)])
    load.writeDisposition = .writeAppend
    load.ignoreUnknownValues = true
    let configuration = GoogleCloudBigQuery.JobConfiguration.load(load)
    let encoded = try WireJSON.decode(
      String(decoding: try RequestBody.json(configuration.wire), as: UTF8.self),
      as: GoogleCloudBigQueryV2.JobConfiguration.self)
    #expect(encoded.load?.sourceUris.isEmpty == true)
    #expect(GoogleCloudBigQuery.JobConfiguration(wire: encoded) == configuration)
  }
}

@Suite struct ExtractJobConfigurationTests {
  // Baseline: U.ExtractJobConfiguration.01, U.ExtractJobConfiguration.03
  @Test func roundTripsTableExtract() throws {
    let configuration = try roundTrip(
      #"""
      {"labels": {"k": "v"},
       "extract": {"sourceTable": {"projectId": "p", "datasetId": "d", "tableId": "t"},
         "destinationUris": ["gs://b/out-*.csv"], "destinationFormat": "CSV",
         "compression": "GZIP", "printHeader": false, "fieldDelimiter": ";",
         "useAvroLogicalTypes": true}}
      """#)
    guard case .extract(let extract) = configuration else {
      Issue.record("expected an extract configuration")
      return
    }
    #expect(extract.source.table == TableID(projectID: "p", datasetID: "d", tableID: "t"))
    #expect(extract.destinationURIs == ["gs://b/out-*.csv"])
    #expect(extract.format == .csv)
    #expect(extract.compression == .gzip)
    #expect(extract.printHeader == false)
    #expect(extract.fieldDelimiter == ";")
    #expect(extract.useAvroLogicalTypes == true)
    #expect(extract.labels == ["k": "v"])
  }

  // Baseline: U.ExtractJobConfiguration.01
  @Test func roundTripsModelExtract() throws {
    let configuration = try roundTrip(
      #"""
      {"extract": {"sourceModel": {"projectId": "p", "datasetId": "d", "modelId": "m"},
         "destinationUris": ["gs://b/model"], "destinationFormat": "ML_TF_SAVED_MODEL",
         "modelExtractOptions": {"trialId": "3"}}}
      """#)
    guard case .extract(let extract) = configuration else {
      Issue.record("expected an extract configuration")
      return
    }
    #expect(extract.source.model == ModelID(projectID: "p", datasetID: "d", modelID: "m"))
    #expect(extract.format == .mlTFSavedModel)
    #expect(extract.modelTrialID == 3)
  }

  // Baseline: U.ExtractJobConfiguration.02
  @Test func defaultProjectFillsOnlyMissingProjects() {
    let missing = ExtractJobConfiguration(
      source: .table(TableID(datasetID: "d", tableID: "t")), destinationURIs: ["gs://b/x"])
    #expect(missing.withDefaultProject("p").source.table?.projectID == "p")
    let explicit = ExtractJobConfiguration(
      source: .model(ModelID(projectID: "explicit", datasetID: "d", modelID: "m")),
      destinationURIs: ["gs://b/x"])
    #expect(explicit.withDefaultProject("p").source.model?.projectID == "explicit")
  }
}

@Suite struct CopyJobConfigurationTests {
  // Baseline: U.CopyJobConfiguration.01, U.CopyJobConfiguration.03
  @Test func roundTripsEveryField() throws {
    let configuration = try roundTrip(
      #"""
      {"reservation": "r",
       "copy": {"sourceTables": [{"projectId": "p", "datasetId": "d", "tableId": "a"},
                                 {"projectId": "p", "datasetId": "d", "tableId": "b"}],
         "destinationTable": {"projectId": "p", "datasetId": "d", "tableId": "c"},
         "operationType": "SNAPSHOT", "destinationExpirationTime": "2030-01-02T03:04:05.123456Z",
         "createDisposition": "CREATE_NEVER", "writeDisposition": "WRITE_EMPTY",
         "destinationEncryptionConfiguration": {"kmsKeyName": "k"}}}
      """#)
    guard case .copy(let copy) = configuration else {
      Issue.record("expected a copy configuration")
      return
    }
    #expect(copy.sourceTables.map(\.tableID) == ["a", "b"])
    #expect(copy.destinationTable.tableID == "c")
    #expect(copy.operationType == .snapshot)
    let expiration = try #require(copy.destinationExpirationTime)
    #expect(abs(expiration.timeIntervalSince1970 - 1_893_553_445.123456) < 0.000_01)
    #expect(copy.createDisposition == .createNever)
    #expect(copy.writeDisposition == .writeEmpty)
    #expect(copy.destinationEncryption == EncryptionConfiguration(kmsKeyName: "k"))
    #expect(copy.reservation == "r")
  }

  // Baseline: U.CopyJobConfiguration.02
  @Test func defaultProjectFillsOnlyMissingProjects() {
    let copy = CopyJobConfiguration(
      sourceTables: [
        TableID(datasetID: "d", tableID: "a"),
        TableID(projectID: "explicit", datasetID: "d", tableID: "b"),
      ],
      destinationTable: TableID(datasetID: "d", tableID: "c"))
    let filled = copy.withDefaultProject("p")
    #expect(filled.sourceTables.map(\.projectID) == ["p", "explicit"])
    #expect(filled.destinationTable.projectID == "p")
  }
}

@Suite struct ConnectionPropertyTests {
  // Baseline: U.ConnectionProperty.01
  @Test func roundTrips() throws {
    let wire = try WireJSON.decode(
      #"{"key": "session_id", "value": "abc"}"#, as: GoogleCloudBigQueryV2.ConnectionProperty.self)
    let property = GoogleCloudBigQuery.ConnectionProperty(wire: wire)
    #expect(property == .sessionID("abc"))
    #expect(GoogleCloudBigQuery.ConnectionProperty(wire: property.wire) == property)
  }
}
