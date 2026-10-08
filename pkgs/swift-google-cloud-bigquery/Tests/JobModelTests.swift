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

// Statistics and status are output-only: the client decodes them but never sends them. Their
// "round trip" tests decode a JSON fixture that sets every field and check every field.

@Suite struct JobTests {
  // Baseline: U.Job.11, U.JobInfo.01
  @Test func decodesEveryField() throws {
    let wire = try WireJSON.decode(
      #"""
      {"jobReference": {"projectId": "p", "jobId": "j", "location": "EU"},
       "etag": "e", "selfLink": "https://x/j", "user_email": "me@example.com",
       "status": {"state": "DONE"},
       "configuration": {"labels": {"k": "v"}, "query": {"query": "SELECT 1"}},
       "statistics": {"creationTime": "1000"}}
      """#, as: GoogleCloudBigQueryV2.Job.self)
    let job = Job(wire: wire)
    #expect(job.id == JobID(projectID: "p", jobID: "j", location: "EU"))
    #expect(job.etag == "e")
    #expect(job.selfLink == "https://x/j")
    #expect(job.userEmail == "me@example.com")
    #expect(job.status.state == .done)
    #expect(job.statistics?.creationTime == Date(timeIntervalSince1970: 1))
    var expected = QueryJobConfiguration("SELECT 1")
    expected.labels = ["k": "v"]
    #expect(job.configuration == .query(expected))
  }

  // Baseline: U.Job.11
  @Test func jobWithoutConfigurationDecodes() throws {
    let wire = try WireJSON.decode(
      #"{"jobReference": {"projectId": "p", "jobId": "j"}, "status": {"state": "RUNNING"}}"#,
      as: GoogleCloudBigQueryV2.Job.self)
    let job = Job(wire: wire)
    #expect(job.configuration == nil)
    #expect(job.statistics == nil)
    #expect(job.etag == nil)
  }
}

@Suite struct JobStatusTests {
  // Baseline: U.JobStatus.01, U.JobStatus.02
  @Test func decodesStateErrorResultAndErrors() throws {
    let wire = try WireJSON.decode(
      #"""
      {"state": "DONE",
       "errorResult": {"reason": "invalid", "location": "q", "message": "bad", "debugInfo": "d"},
       "errors": [{"reason": "invalid", "location": "q", "message": "bad", "debugInfo": "d"},
                  {"reason": "stopped", "message": "stopped"}]}
      """#, as: GoogleCloudBigQueryV2.JobStatus.self)
    let status = JobStatus(wire: wire)
    #expect(status.state == .done)
    #expect(status.isDone)
    #expect(
      status.errorResult
        == BigQueryError.Detail(reason: "invalid", location: "q", message: "bad", debugInfo: "d"))
    #expect(status.errors.map(\.reason) == ["invalid", "stopped"])
    let failure = try #require(status.failure(jobID: JobID(jobID: "j")))
    #expect(failure.kind == .job)
    #expect(failure.errors.map(\.reason) == ["invalid", "stopped"])
    #expect(JobStatus(state: .running).failure(jobID: nil) == nil)
  }
}

@Suite struct JobStatisticsTests {
  // Baseline: U.JobStatistics.01
  @Test func decodesEveryField() throws {
    let wire = try WireJSON.decode(
      #"""
      {"creationTime": "1000", "startTime": "2000", "endTime": "3000",
       "totalBytesProcessed": "10", "totalSlotMs": "11", "completionRatio": 0.5,
       "numChildJobs": "2", "parentJobId": "parent", "reservation_id": "res",
       "scriptStatistics": {"evaluationKind": "STATEMENT", "stackFrames": [
         {"startLine": 1, "startColumn": 2, "endLine": 3, "endColumn": 4, "procedureId": "proc",
          "text": "SELECT 1"}]},
       "transactionInfo": {"transactionId": "tx"}, "sessionInfo": {"sessionId": "s"},
       "query": {"billingTier": 1, "cacheHit": true, "statementType": "CREATE_TABLE",
         "ddlOperationPerformed": "CREATE",
         "ddlTargetTable": {"projectId": "p", "datasetId": "d", "tableId": "t"},
         "ddlTargetRoutine": {"projectId": "p", "datasetId": "d", "routineId": "r"},
         "ddlTargetDataset": {"projectId": "p", "datasetId": "d"},
         "estimatedBytesProcessed": "12", "numDmlAffectedRows": "13",
         "dmlStats": {"insertedRowCount": "1", "deletedRowCount": "2", "updatedRowCount": "3"},
         "exportDataStatistics": {"fileCount": "4", "rowCount": "5"},
         "referencedTables": [{"projectId": "p", "datasetId": "d", "tableId": "t"}],
         "referencedRoutines": [{"projectId": "p", "datasetId": "d", "routineId": "r"}],
         "totalBytesBilled": "14", "totalBytesProcessed": "15", "totalPartitionsProcessed": "16",
         "totalSlotMs": "17", "queryPlan": [{"name": "S00", "id": "0"}],
         "timeline": [{"elapsedMs": "1", "totalSlotMs": "2", "pendingUnits": "3",
                       "completedUnits": "4", "activeUnits": "5", "estimatedRunnableUnits": "6"}],
         "schema": {"fields": [{"name": "x", "type": "INT64"}]},
         "searchStatistics": {"indexUsageMode": "PARTIALLY_USED", "indexUnusedReasons": [
           {"code": "INDEX_CONFIG_NOT_AVAILABLE", "message": "m", "indexName": "i",
            "baseTable": {"projectId": "p", "datasetId": "d", "tableId": "t"}}]},
         "metadataCacheStatistics": {"tableMetadataCacheUsage": [
           {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "t"},
            "unusedReason": "EXCEEDED_MAX_STALENESS", "explanation": "old",
            "tableType": "BIGLAKE"}]},
         "undeclaredQueryParameters": [{"name": "a", "parameterType": {"type": "INT64"}}]},
       "load": {"inputFiles": "1", "inputFileBytes": "2", "outputRows": "3", "outputBytes": "4",
                "badRecords": "5"},
       "extract": {"destinationUriFileCounts": ["6"], "inputBytes": "7"},
       "copy": {"copiedRows": "8", "copiedLogicalBytes": "9"}}
      """#, as: GoogleCloudBigQueryV2.JobStatistics.self)
    let statistics = JobStatistics(wire: wire)
    #expect(statistics.creationTime == Date(timeIntervalSince1970: 1))
    #expect(statistics.startTime == Date(timeIntervalSince1970: 2))
    #expect(statistics.endTime == Date(timeIntervalSince1970: 3))
    #expect(statistics.totalBytesProcessed == 10)
    #expect(statistics.totalSlotMs == 11)
    #expect(statistics.completionRatio == 0.5)
    #expect(statistics.numChildJobs == 2)
    #expect(statistics.parentJobID == "parent")
    #expect(statistics.scriptStatistics?.evaluationKind == .statement)
    #expect(statistics.scriptStatistics?.stackFrames.first?.procedureID == "proc")
    #expect(statistics.scriptStatistics?.stackFrames.first?.endColumn == 4)
    #expect(statistics.transactionInfo?.transactionID == "tx")
    #expect(statistics.sessionInfo?.sessionID == "s")

    let query = try #require(statistics.query)
    #expect(query.billingTier == 1)
    #expect(query.cacheHit == true)
    #expect(query.statementType == .createTable)
    #expect(query.ddlOperationPerformed == "CREATE")
    #expect(query.ddlTargetTable == TableID(projectID: "p", datasetID: "d", tableID: "t"))
    #expect(query.ddlTargetRoutine == RoutineID(projectID: "p", datasetID: "d", routineID: "r"))
    #expect(query.ddlTargetDataset == DatasetID(projectID: "p", datasetID: "d"))
    #expect(query.estimatedBytesProcessed == 12)
    #expect(query.numDMLAffectedRows == 13)
    #expect(query.dmlStats == DMLStats(insertedRowCount: 1, deletedRowCount: 2, updatedRowCount: 3))
    #expect(query.exportDataStatistics == ExportDataStatistics(fileCount: 4, rowCount: 5))
    #expect(query.referencedTables.count == 1)
    #expect(query.referencedRoutines.count == 1)
    #expect(query.totalBytesBilled == 14)
    #expect(query.totalBytesProcessed == 15)
    #expect(query.totalPartitionsProcessed == 16)
    #expect(query.totalSlotMs == 17)
    #expect(query.queryPlan.first?.name == "S00")
    #expect(query.timeline.first?.estimatedRunnableUnits == 6)
    #expect(query.schema?.fields.map(\.name) == ["x"])
    #expect(query.searchStatistics?.indexUsageMode == .partiallyUsed)
    #expect(query.searchStatistics?.indexUnusedReasons.first?.indexName == "i")
    #expect(query.metadataCacheStatistics?.tableMetadataCacheUsage.count == 1)
    #expect(query.undeclaredQueryParameters == [UndeclaredQueryParameter(name: "a", type: "INT64")])

    #expect(
      statistics.load
        == LoadStatistics(
          inputFiles: 1, inputFileBytes: 2, outputRows: 3, outputBytes: 4, badRecords: 5))
    #expect(statistics.extract == ExtractStatistics(destinationURIFileCounts: [6], inputBytes: 7))
    #expect(statistics.copy == CopyStatistics(copiedRows: 8, copiedLogicalBytes: 9))
  }

  // Baseline: U.JobStatistics.02
  @Test func partialStatisticsDecode() throws {
    let wire = try WireJSON.decode(
      #"{"creationTime": "1000", "query": {}}"#, as: GoogleCloudBigQueryV2.JobStatistics.self)
    let statistics = JobStatistics(wire: wire)
    #expect(statistics.creationTime == Date(timeIntervalSince1970: 1))
    #expect(statistics.startTime == nil)
    #expect(statistics.numChildJobs == nil)
    #expect(statistics.query?.statementType == nil)
    #expect(statistics.query?.queryPlan.isEmpty == true)
    #expect(statistics.load == nil)
  }
}

@Suite struct QueryStageTests {
  // Baseline: U.QueryStage.01
  @Test func decodesEveryField() throws {
    let wire = try WireJSON.decode(
      #"""
      {"name": "S00: Input", "id": "1", "startMs": "1000", "endMs": "2000", "inputStages": ["0"],
       "status": "COMPLETE", "steps": [{"kind": "READ", "substeps": ["FROM t"]}],
       "recordsRead": "1", "recordsWritten": "2", "parallelInputs": "3",
       "completedParallelInputs": "4", "shuffleOutputBytes": "5",
       "shuffleOutputBytesSpilled": "6", "slotMs": "7",
       "waitMsAvg": "8", "waitMsMax": "9", "waitRatioAvg": 0.1, "waitRatioMax": 0.2,
       "readMsAvg": "10", "readMsMax": "11", "readRatioAvg": 0.3, "readRatioMax": 0.4,
       "computeMsAvg": "12", "computeMsMax": "13", "computeRatioAvg": 0.5, "computeRatioMax": 0.6,
       "writeMsAvg": "14", "writeMsMax": "15", "writeRatioAvg": 0.7, "writeRatioMax": 0.8}
      """#, as: GoogleCloudBigQueryV2.ExplainQueryStage.self)
    let stage = QueryStage(wire: wire)
    #expect(stage.name == "S00: Input")
    #expect(stage.id == 1)
    #expect(stage.startTime == Date(timeIntervalSince1970: 1))
    #expect(stage.endTime == Date(timeIntervalSince1970: 2))
    #expect(stage.inputStages == [0])
    #expect(stage.status == "COMPLETE")
    #expect(stage.steps == [QueryStage.Step(kind: "READ", substeps: ["FROM t"])])
    #expect(stage.recordsRead == 1)
    #expect(stage.recordsWritten == 2)
    #expect(stage.parallelInputs == 3)
    #expect(stage.completedParallelInputs == 4)
    #expect(stage.shuffleOutputBytes == 5)
    #expect(stage.shuffleOutputBytesSpilled == 6)
    #expect(stage.slotMs == 7)
    #expect(stage.waitMsAvg == 8)
    #expect(stage.waitMsMax == 9)
    #expect(stage.waitRatioAvg == 0.1)
    #expect(stage.waitRatioMax == 0.2)
    #expect(stage.readMsAvg == 10)
    #expect(stage.readMsMax == 11)
    #expect(stage.readRatioAvg == 0.3)
    #expect(stage.readRatioMax == 0.4)
    #expect(stage.computeMsAvg == 12)
    #expect(stage.computeMsMax == 13)
    #expect(stage.computeRatioAvg == 0.5)
    #expect(stage.computeRatioMax == 0.6)
    #expect(stage.writeMsAvg == 14)
    #expect(stage.writeMsMax == 15)
    #expect(stage.writeRatioAvg == 0.7)
    #expect(stage.writeRatioMax == 0.8)
  }
}

@Suite struct DMLStatsTests {
  // Baseline: U.DmlStats.01
  @Test func decodesEveryField() throws {
    let wire = try WireJSON.decode(
      #"{"insertedRowCount": "1", "deletedRowCount": "2", "updatedRowCount": "3"}"#,
      as: GoogleCloudBigQueryV2.DmlStats.self)
    #expect(
      DMLStats(wire: wire)
        == DMLStats(insertedRowCount: 1, deletedRowCount: 2, updatedRowCount: 3))
  }
}

@Suite struct MetadataCacheStatisticsTests {
  // Baseline: U.MetadataCacheStats.01, U.TableMetadataCacheUsage.01
  @Test func decodesEveryField() throws {
    let wire = try WireJSON.decode(
      #"""
      {"tableMetadataCacheUsage": [
        {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "t"},
         "unusedReason": "METADATA_CACHING_NOT_ENABLED", "explanation": "off",
         "tableType": "EXTERNAL"},
        {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "u"}}]}
      """#, as: GoogleCloudBigQueryV2.MetadataCacheStatistics.self)
    let statistics = MetadataCacheStatistics(wire: wire)
    #expect(
      statistics.tableMetadataCacheUsage == [
        TableMetadataCacheUsage(
          table: TableID(projectID: "p", datasetID: "d", tableID: "t"),
          unusedReason: .metadataCachingNotEnabled, explanation: "off", tableType: "EXTERNAL"),
        TableMetadataCacheUsage(table: TableID(projectID: "p", datasetID: "d", tableID: "u")),
      ])
  }
}
