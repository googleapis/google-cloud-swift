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
import Testing

@testable import GoogleCloudBigQuery

/// Live tests of loading local data through resumable uploads.
@Suite(.enabled(if: integrationTestsEnabled()))
struct UploadIntegrationTests {
  // Baseline: IT-153, IT-154
  @Test func uploadFromAFileWithLabels() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-bq-upload-\(UUID().uuidString).json")
      try Data(#"{"name": "a", "n": 1}\#n{"name": "b", "n": 2}\#n"#.utf8).write(to: url)
      defer { try? FileManager.default.removeItem(at: url) }

      let table = JobsIT.table(dataset)
      var load = LoadJobConfiguration(destinationTable: table, format: .json)
      load.schema = Schema([Field("name", .string), Field("n", .int64)])
      load.labels = ["swift-it": "upload"]
      let job = try await client.load(.file(url), configuration: load)
      let done = try await client.waitForJob(job.id)
      #expect(done.status.errorResult == nil)
      #expect(done.statistics?.load?.outputRows == 2)
      guard case .load(let fetched) = done.configuration else {
        Issue.record("expected a load configuration")
        return
      }
      #expect(fetched.labels == ["swift-it": "upload"])
      #expect(
        try await JobsIT.column(client, "SELECT name FROM \(JobsIT.sql(table)) ORDER BY n", "name")
          == ["a", "b"])
    }
  }

  // Design: §6.4
  @Test func multiChunkStreamUpload() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let lines = (0..<40_000).map { "row-\($0),\($0)\n" }
      let data = Data(lines.joined().utf8)
      #expect(data.count > 2 * 256 * 1024)
      let pieces = stride(from: 0, to: data.count, by: 100_000).map {
        data.subdata(in: $0..<min($0 + 100_000, data.count))
      }
      let table = JobsIT.table(dataset)
      var load = LoadJobConfiguration(destinationTable: table, format: .csv)
      load.schema = Schema([Field("name", .string), Field("n", .int64)])
      let job = try await client.load(
        .stream(
          AsyncStream { continuation in
            for piece in pieces { continuation.yield(piece) }
            continuation.finish()
          }), configuration: load, jobID: JobsIT.jobID(), chunkSize: 256 * 1024)
      let done = try await client.waitForJob(job.id)
      #expect(done.statistics?.load?.outputRows == 40_000)
      #expect(done.statistics?.load?.inputFileBytes == Int64(data.count))
    }
  }

  // Baseline: IT-155
  @Test func uploadWithDecimalTargetTypes() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      var load = LoadJobConfiguration(destinationTable: JobsIT.table(dataset))
      load.createDisposition = .createIfNeeded
      load.autodetect = true
      load.decimalTargetTypes = [.string, .numeric, .bigNumeric]
      let job = try await client.load(.data(Data("foo".utf8)), configuration: load)
      let done = try await client.waitForJob(job.id)
      #expect(done.status.errorResult == nil)
      guard case .load(let fetched) = done.configuration else {
        Issue.record("expected a load configuration")
        return
      }
      #expect(fetched.decimalTargetTypes == [.string, .numeric, .bigNumeric])
    }
  }

  // Baseline: IT-157
  @Test func uploadPreservesASCIIControlCharacters() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = JobsIT.table(dataset)
      var load = LoadJobConfiguration(destinationTable: table, format: .csv)
      load.csvOptions = CSVOptions(preserveASCIIControlCharacters: true)
      load.schema = Schema([Field("value", .string)])
      let job = try await client.load(.data(Data("\u{0}".utf8)), configuration: load)
      _ = try await client.waitForJob(job.id)
      #expect(
        try await JobsIT.column(client, "SELECT value FROM \(JobsIT.sql(table))", "value")
          == ["\u{0}"])
    }
  }

  // Baseline: IT-109
  @Test func uploadIntoASessionTable() async throws {
    let client = try IntegrationTest.makeClient()
    let table = TableID(datasetID: "_SESSION", tableID: "swift_session_upload")
    var first = LoadJobConfiguration(destinationTable: table, format: .csv)
    first.csvOptions = CSVOptions(fieldDelimiter: ",")
    first.createDisposition = .createIfNeeded
    first.schema = Schema([Field("name", .string), Field("n", .int64)])
    first.createSession = true
    let firstID = JobsIT.jobID(location: "us")
    _ = try await client.load(.data(Data("a,1\nb,2\n".utf8)), configuration: first, jobID: firstID)
    let started = try await client.waitForJob(firstID)
    #expect(started.id.jobID == firstID.jobID)
    let sessionID = try #require(started.statistics?.sessionInfo?.sessionID)

    var second = first
    second.createSession = nil
    second.connectionProperties = [.sessionID(sessionID)]
    let secondID = JobsIT.jobID(location: "us")
    _ = try await client.load(.data(Data("c,3\n".utf8)), configuration: second, jobID: secondID)
    let appended = try await client.waitForJob(secondID)
    #expect(appended.statistics?.sessionInfo?.sessionID == sessionID)

    var read = QueryJobConfiguration("SELECT COUNT(*) AS c FROM _SESSION.swift_session_upload")
    read.connectionProperties = [.sessionID(sessionID)]
    let result = try await client.query(read, location: "us")
    #expect(JobsIT.scalars(try await result.rows.collect(), "c") == ["3"])
  }
}
