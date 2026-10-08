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
import GoogleGax
import Testing

@testable import GoogleCloudBigQuery

private let session = "https://bigquery.googleapis.com/upload/session/abc"
private let quantum = 256 * 1024
private let destination = TableID(datasetID: "d", tableID: "t")

private struct BrokenConnection: Error {}

/// Queues the response that opens the upload session.
private func enqueueSession(_ fake: FakeHTTPTransport) {
  fake.enqueue(json: "", headers: ["Location": session])
}

/// Queues a 308 response that reports the first `count` bytes as received.
private func enqueueIncomplete(_ fake: FakeHTTPTransport, received count: Int) {
  fake.enqueue(
    .response(
      HTTPResponse(statusCode: 308, headers: count == 0 ? [:] : ["Range": "bytes=0-\(count - 1)"])))
}

/// Queues the response that finishes the upload with the created job.
private func enqueueJob(_ fake: FakeHTTPTransport, status: Int = 200) {
  fake.enqueue(
    status: status,
    json: JobFixtures.job(
      id: "upload-job", state: "PENDING",
      configuration:
        #"{"load": {"destinationTable": {"projectId": "test-project", "datasetId": "d", "tableId": "t"}}}"#
    ))
}

/// The bytes `0, 1, 2, …` repeated, `count` long.
private func bytes(_ count: Int) -> Data {
  Data((0..<count).map { UInt8(truncatingIfNeeded: $0) })
}

/// The upload requests: those sent to the session URL.
private func uploads(_ fake: FakeHTTPTransport) -> [HTTPRequest] {
  fake.requests.filter {
    if case .url(let url) = $0.target { return url == session }
    return false
  }
}

@Suite struct BigQueryClientUploadTests {
  // Baseline: U.BigQueryImpl.68, U.TableDataWriteChannel.01, U.WriteChannelConfiguration.01
  @Test func loadOpensASessionWithTheJobConfiguration() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueJob(fake, status: 201)
    var configuration = LoadJobConfiguration(destinationTable: destination, format: .csv)
    configuration.writeDisposition = .writeAppend
    let job = try await fake.client(location: "EU").load(
      .data(Data("a,b\n".utf8)), configuration: configuration, jobID: JobID(jobID: "my-job"))

    #expect(job.id.jobID == "upload-job")
    #expect(job.status.state == .pending)
    let open = try #require(fake.requests.first)
    #expect(open.method == .post)
    #expect(open.path == "/upload/bigquery/v2/projects/test-project/jobs")
    #expect(open.queryValue("uploadType") == "resumable")
    #expect(open.headers["x-upload-content-type"] == "application/octet-stream")
    let body = try open.jsonBody()
    let reference = try #require(body["jobReference"] as? [String: Any])
    #expect(reference["jobId"] as? String == "my-job")
    #expect(reference["projectId"] as? String == "test-project")
    #expect(reference["location"] as? String == "EU")
    let load = try #require((body["configuration"] as? [String: Any])?["load"] as? [String: Any])
    let table = try #require(load["destinationTable"] as? [String: Any])
    #expect(table["projectId"] as? String == "test-project")
    #expect(table["tableId"] as? String == "t")
    #expect(load["sourceFormat"] as? String == "CSV")
    #expect(load["writeDisposition"] as? String == "WRITE_APPEND")

    let chunks = uploads(fake)
    #expect(chunks.count == 1)
    #expect(chunks.first?.method == .put)
    #expect(chunks.first?.headers["content-range"] == "bytes 0-3/4")
    #expect(chunks.first?.body == Data("a,b\n".utf8))
  }

  // Baseline: U.BigQueryImpl.68
  @Test func loadGeneratesAJobIDWhenNoneIsGiven() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueJob(fake)
    _ = try await fake.client().load(
      .data(Data("x".utf8)), configuration: LoadJobConfiguration(destinationTable: destination))
    let reference = try #require(
      try fake.requests.first?.jsonBody()["jobReference"] as? [String: Any])
    let jobID = try #require(reference["jobId"] as? String)
    #expect(!jobID.isEmpty)
  }

  // Baseline: U.TableDataWriteChannel.02
  @Test func sessionOpenRetriesTransientErrors() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503, reasons: ["backendError"])
    enqueueSession(fake)
    enqueueJob(fake)
    let job = try await fake.client().load(
      .data(Data("x".utf8)), configuration: LoadJobConfiguration(destinationTable: destination))
    #expect(job.id.jobID == "upload-job")
    #expect(fake.requests.count == 3)
  }

  // Baseline: U.TableDataWriteChannel.02
  @Test func sessionOpenSurfacesNonRetryableErrors() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 400, reasons: ["invalid"])
    let error = await #expect(throws: BigQueryError.self) {
      try await fake.client().load(
        .data(Data("x".utf8)), configuration: LoadJobConfiguration(destinationTable: destination))
    }
    #expect(error?.httpStatusCode == 400)
    #expect(fake.requests.count == 1)
  }

  // Design: §6.4
  @Test func sessionWithoutLocationIsMalformed() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "")
    await #expect(throws: (any Error).self) {
      try await fake.client().load(
        .data(Data("x".utf8)), configuration: LoadJobConfiguration(destinationTable: destination))
    }
    #expect(uploads(fake).isEmpty)
  }

  // Baseline: U.TableDataWriteChannel.03, U.TableDataWriteChannel.05
  @Test func chunksAreRoundedDownToMultiplesOf256KiB() async throws {
    let fake = FakeHTTPTransport()
    let data = bytes(2 * quantum + 10)
    enqueueSession(fake)
    enqueueIncomplete(fake, received: quantum)
    enqueueIncomplete(fake, received: 2 * quantum)
    enqueueJob(fake)
    _ = try await fake.client().load(
      .data(data), configuration: LoadJobConfiguration(destinationTable: destination),
      chunkSize: quantum + 1000)

    let chunks = uploads(fake)
    #expect(
      chunks.map { $0.headers["content-range"] } == [
        "bytes 0-262143/*", "bytes 262144-524287/*", "bytes 524288-524297/524298",
      ])
    #expect(chunks.map { $0.body?.count } == [quantum, quantum, 10])
    #expect(chunks.reduce(Data()) { $0 + ($1.body ?? Data()) } == data)
  }

  // Baseline: U.TableDataWriteChannel.03
  @Test func chunkSizeIsAtLeast256KiB() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueIncomplete(fake, received: quantum)
    enqueueJob(fake)
    _ = try await fake.client().load(
      .data(bytes(quantum + 1)), configuration: LoadJobConfiguration(destinationTable: destination),
      chunkSize: 1)
    #expect(uploads(fake).map { $0.body?.count } == [quantum, 1])
  }

  // Baseline: U.TableDataWriteChannel.05
  @Test func exactMultipleSendsTheTotalWithTheLastChunk() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueIncomplete(fake, received: quantum)
    enqueueJob(fake)
    let job = try await fake.client().load(
      .data(bytes(2 * quantum)), configuration: LoadJobConfiguration(destinationTable: destination),
      chunkSize: quantum)
    #expect(job.id.jobID == "upload-job")
    #expect(
      uploads(fake).map { $0.headers["content-range"] } == [
        "bytes 0-262143/*", "bytes 262144-524287/524288",
      ])
  }

  // Design: §6.4
  @Test func emptyUploadSendsOneRequestWithZeroTotal() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueJob(fake)
    _ = try await fake.client().load(
      .data(Data()), configuration: LoadJobConfiguration(destinationTable: destination))
    let chunks = uploads(fake)
    #expect(chunks.map { $0.headers["content-range"] } == ["bytes */0"])
    #expect(chunks.first?.body?.isEmpty != false)
  }

  // Baseline: U.TableDataWriteChannel.04
  @Test func retryableChunkErrorQueriesStatusAndResumes() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    fake.enqueueError(status: 503, reasons: ["backendError"])
    enqueueIncomplete(fake, received: 4)
    enqueueJob(fake)
    let data = bytes(10)
    _ = try await fake.client().load(
      .data(data), configuration: LoadJobConfiguration(destinationTable: destination))

    let chunks = uploads(fake)
    #expect(
      chunks.map { $0.headers["content-range"] } == [
        "bytes 0-9/10", "bytes */10", "bytes 4-9/10",
      ])
    #expect(chunks[1].body?.isEmpty != false)
    #expect(chunks[2].body == data.dropFirst(4))
  }

  // Baseline: U.TableDataWriteChannel.04
  @Test func ioErrorQueriesStatusOfAnUnfinishedChunk() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    fake.enqueue(.error(BrokenConnection()))
    enqueueIncomplete(fake, received: 0)
    enqueueIncomplete(fake, received: quantum)
    enqueueJob(fake)
    _ = try await fake.client().load(
      .data(bytes(quantum + 1)), configuration: LoadJobConfiguration(destinationTable: destination),
      chunkSize: quantum)
    #expect(
      uploads(fake).map { $0.headers["content-range"] } == [
        "bytes 0-262143/*", "bytes */*", "bytes 0-262143/*", "bytes 262144-262144/262145",
      ])
  }

  // Baseline: U.TableDataWriteChannel.04
  @Test func statusQueryThatFinishesTheUploadReturnsTheJob() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    fake.enqueueError(status: 500, reasons: ["backendError"])
    enqueueJob(fake)
    let job = try await fake.client().load(
      .data(bytes(10)), configuration: LoadJobConfiguration(destinationTable: destination))
    #expect(job.id.jobID == "upload-job")
    #expect(uploads(fake).map { $0.headers["content-range"] } == ["bytes 0-9/10", "bytes */10"])
  }

  // Baseline: U.TableDataWriteChannel.04
  @Test func nonRetryableChunkErrorSurfaces() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    fake.enqueueError(status: 400, reasons: ["invalid"], message: "bad data")
    let error = await #expect(throws: BigQueryError.self) {
      try await fake.client().load(
        .data(bytes(10)), configuration: LoadJobConfiguration(destinationTable: destination))
    }
    #expect(error?.httpStatusCode == 400)
    #expect(error?.reason == "invalid")
    #expect(uploads(fake).count == 1)
  }

  // Design: §6.4
  @Test func uploadGivesUpAfterSixFailures() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    for _ in 0..<6 { fake.enqueueError(status: 503, reasons: ["backendError"]) }
    let error = await #expect(throws: BigQueryError.self) {
      try await fake.client().load(
        .data(bytes(10)), configuration: LoadJobConfiguration(destinationTable: destination))
    }
    #expect(error?.httpStatusCode == 503)
    #expect(uploads(fake).count == 6)
    #expect(fake.pendingReplies == 0)
  }

  // Design: §6.4
  @Test func partialCommitResendsTheRestOfTheChunk() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueIncomplete(fake, received: 100_000)
    enqueueIncomplete(fake, received: quantum)
    enqueueJob(fake)
    let data = bytes(quantum + 5)
    _ = try await fake.client().load(
      .data(data), configuration: LoadJobConfiguration(destinationTable: destination),
      chunkSize: quantum)
    let chunks = uploads(fake)
    #expect(
      chunks.map { $0.headers["content-range"] } == [
        "bytes 0-262143/*", "bytes 100000-262143/*", "bytes 262144-262148/262149",
      ])
    #expect(chunks[1].body == data[100_000..<quantum])
  }

  // Design: §6.4
  @Test func rangeOutsideTheChunkIsMalformed() async throws {
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueIncomplete(fake, received: quantum + 100)
    await #expect(throws: (any Error).self) {
      try await fake.client().load(
        .data(bytes(quantum + 5)),
        configuration: LoadJobConfiguration(destinationTable: destination),
        chunkSize: quantum)
    }
  }
}

@Suite struct UploadSourceTests {
  // Design: §6.4
  @Test func fileSourceUploadsTheFileContents() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bq-upload-\(UUID().uuidString).csv")
    let data = bytes(quantum + 7)
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueIncomplete(fake, received: quantum)
    enqueueJob(fake)
    _ = try await fake.client().load(
      .file(url), configuration: LoadJobConfiguration(destinationTable: destination),
      chunkSize: quantum)
    let chunks = uploads(fake)
    #expect(chunks.reduce(Data()) { $0 + ($1.body ?? Data()) } == data)
    #expect(chunks.last?.headers["content-range"] == "bytes 262144-262150/262151")
  }

  // Design: §6.4
  @Test func missingFileFailsBeforeOpeningASession() async throws {
    let fake = FakeHTTPTransport()
    await #expect(throws: (any Error).self) {
      try await fake.client().load(
        .file(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")),
        configuration: LoadJobConfiguration(destinationTable: destination))
    }
    #expect(fake.requests.isEmpty)
  }

  // Baseline: U.TableDataWriteChannel.06 (ADAPT: write-after-close is unrepresentable, because
  // `load` consumes the whole source in one call and there is no channel to write to later.)
  // Design: §6.4
  @Test func streamSourceConcatenatesPiecesAndSkipsEmptyOnes() async throws {
    let pieces = [Data("ab".utf8), Data(), Data("cd".utf8)]
    let fake = FakeHTTPTransport()
    enqueueSession(fake)
    enqueueJob(fake)
    _ = try await fake.client().load(
      .stream(pieces.async), configuration: LoadJobConfiguration(destinationTable: destination))
    let chunks = uploads(fake)
    #expect(chunks.map { $0.headers["content-range"] } == ["bytes 0-3/4"])
    #expect(chunks.first?.body == Data("abcd".utf8))
  }

  // Design: §6.4
  @Test func readerSplitsLargeStreamPiecesIntoChunks() async throws {
    var reader = try UploadReader(.stream([bytes(10)].async))
    let first = try await reader.nextChunk(size: 4)
    let second = try await reader.nextChunk(size: 4)
    let third = try await reader.nextChunk(size: 4)
    #expect(first.data == bytes(10).prefix(4) && !first.isLast)
    #expect(second.data.count == 4 && !second.isLast)
    #expect(third.data.count == 2 && third.isLast)
  }
}

/// An asynchronous sequence over an array, for stream upload tests.
private struct ArrayAsyncSequence: AsyncSequence, Sendable {
  typealias Element = Data
  let elements: [Data]

  struct AsyncIterator: AsyncIteratorProtocol {
    var remaining: ArraySlice<Data>
    mutating func next() async -> Data? { remaining.popFirst() }
  }

  func makeAsyncIterator() -> AsyncIterator { AsyncIterator(remaining: elements[...]) }
}

extension Array where Element == Data {
  fileprivate var async: ArrayAsyncSequence { ArrayAsyncSequence(elements: self) }
}
