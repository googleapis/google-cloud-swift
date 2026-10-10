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
public import GoogleGax

extension BigQueryClient {
  /// Uploads local data and creates a load job for it.
  ///
  /// ```swift
  /// let job = try await client.load(
  ///   .file(URL(filePath: "/tmp/people.csv")),
  ///   configuration: LoadJobConfiguration(
  ///     destinationTable: TableID(datasetID: "d", tableID: "people"), format: .csv))
  /// try await client.waitForJob(job.id)
  /// ```
  ///
  /// The data is sent in a resumable upload session, one chunk at a time. If a chunk fails
  /// because of a network error or a retryable HTTP status, the upload asks the service how much
  /// data it received and resumes from there. The method returns once the job is created; use
  /// ``waitForJob(_:timeout:options:)`` to wait for the load to finish.
  ///
  /// - Parameters:
  ///   - source: the data to upload.
  ///   - configuration: the load job. Its ``LoadJobConfiguration/sourceURIs`` are ignored.
  ///   - jobID: the job ID, or `nil` to generate one. A `nil` project or location uses the
  ///     client's.
  ///   - chunkSize: the size of each uploaded chunk in bytes, rounded down to a multiple of
  ///     256 KiB (at least 256 KiB). Larger chunks use more memory and need fewer requests.
  ///   - options: per-call options.
  public func load(
    _ source: UploadSource,
    configuration: LoadJobConfiguration,
    jobID: JobID? = nil,
    chunkSize: Int = 15 << 20,
    options: RequestOptions = .init()
  ) async throws -> Job {
    let id = self.resolve(jobID ?? JobID.random())
    let chunkSize = max(Self.uploadQuantum, chunkSize / Self.uploadQuantum * Self.uploadQuantum)
    var reader = try UploadReader(source)
    defer { reader.close() }
    let session = try await self.startUpload(id, configuration: configuration, options: options)
    var offset: Int64 = 0
    while true {
      let chunk = try await reader.nextChunk(size: chunkSize)
      if let job = try await self.uploadChunk(
        chunk.data, offset: offset, isLast: chunk.isLast, session: session, options: options)
      {
        return job
      }
      guard !chunk.isLast else {
        throw RequestError.malformedResponse("upload finished without returning the job")
      }
      offset += Int64(chunk.data.count)
    }
  }
}

// MARK: - Resumable upload

extension BigQueryClient {
  /// Upload chunks must be a multiple of this size, except the last one.
  static let uploadQuantum = 256 * 1024

  /// The number of consecutive failed chunk attempts before the upload gives up.
  static let uploadMaxFailures = 6

  /// Starts a resumable upload session and returns its URL.
  private func startUpload(
    _ id: JobID, configuration: LoadJobConfiguration, options: RequestOptions
  ) async throws -> String {
    let projectID = id.projectID ?? self.projectID
    let job = GoogleCloudBigQueryV2.Job().with {
      $0.jobReference = id.wire
      $0.configuration = JobConfiguration.load(configuration).withDefaultProject(projectID).wire
    }
    let response = try await self.transport.send(
      HTTPRequest(
        method: .post,
        path: "/upload/bigquery/v2/projects/\(HTTPRequest.encode(segment: projectID))/jobs",
        query: [URLQueryItem(name: "uploadType", value: "resumable")],
        headers: [
          "content-type": "application/json; charset=UTF-8",
          "x-upload-content-type": "application/octet-stream",
        ],
        body: try RequestBody.json(job), options: options),
      idempotent: true)
    guard let session = response.header("location"), !session.isEmpty else {
      throw RequestError.malformedResponse("resumable upload response without a Location header")
    }
    return session
  }

  /// Uploads one chunk that starts at `offset` of the whole upload.
  ///
  /// - Returns: the job if the service finished the upload, or `nil` if it expects more data.
  private func uploadChunk(
    _ data: Data, offset: Int64, isLast: Bool, session: String, options: RequestOptions
  ) async throws -> Job? {
    let end = offset + Int64(data.count)
    let total = isLast ? String(end) : "*"
    var committed = offset
    var failures = 0
    var needsStatus = false
    while true {
      do {
        if needsStatus {
          // Ask how many bytes the service has, then resend the rest of the chunk.
          let response = try await self.transport.sendOnce(
            HTTPRequest(
              method: .put, url: session, headers: ["content-range": "bytes */\(total)"],
              body: Data(), options: options))
          if let job = try Self.finishedUpload(response) { return job }
          try Self.checkUploadStatus(response)
          committed = try Self.committedBytes(response, chunkStart: offset, chunkEnd: end)
          needsStatus = false
        }
        let pending = data.dropFirst(Int(committed - offset))
        let range =
          pending.isEmpty ? "bytes */\(total)" : "bytes \(committed)-\(end - 1)/\(total)"
        let response = try await self.transport.sendOnce(
          HTTPRequest(
            method: .put, url: session, headers: ["content-range": range], body: Data(pending),
            options: options))
        if let job = try Self.finishedUpload(response) { return job }
        try Self.checkUploadStatus(response)
        committed = try Self.committedBytes(response, chunkStart: offset, chunkEnd: end)
        if committed == end { return nil }
        // The service kept only part of the chunk: send the rest.
      } catch {
        failures += 1
        guard Self.isRetryableUploadError(error), failures < Self.uploadMaxFailures else {
          throw (error as? UploadStatusError)?.error ?? error
        }
        needsStatus = true
        try await self.transport.sleep(.seconds(1 << min(failures - 1, 5)))
      }
    }
  }

  /// The job in a response that finishes the upload (200 or 201), or `nil` for any other status.
  private static func finishedUpload(_ response: HTTPResponse) throws -> Job? {
    guard response.statusCode == 200 || response.statusCode == 201 else { return nil }
    let job: GoogleCloudBigQueryV2.Job = try BigQueryTransport.decode(response.body)
    return Job(wire: job)
  }

  /// Throws for any status other than 308 (resume incomplete).
  private static func checkUploadStatus(_ response: HTTPResponse) throws {
    guard response.statusCode != 308 else { return }
    throw UploadStatusError(
      error: BigQueryError(httpStatusCode: response.statusCode, payload: response.body))
  }

  /// The number of bytes the service has, from the `Range: bytes=0-N` header of a 308 response.
  private static func committedBytes(
    _ response: HTTPResponse, chunkStart: Int64, chunkEnd: Int64
  ) throws -> Int64 {
    var committed: Int64 = 0
    if let range = response.header("range") {
      guard range.hasPrefix("bytes=0-"), let last = Int64(range.dropFirst("bytes=0-".count))
      else {
        throw RequestError.malformedResponse("unexpected Range header in upload response: \(range)")
      }
      committed = last + 1
    }
    guard committed >= chunkStart && committed <= chunkEnd else {
      throw RequestError.malformedResponse(
        "upload service reports \(committed) bytes, expected \(chunkStart) to \(chunkEnd)")
    }
    return committed
  }

  /// `true` for errors after which the upload queries its status and resumes.
  private static func isRetryableUploadError(_ error: any Error) -> Bool {
    switch error {
    case RequestError.io:
      return true
    case let error as UploadStatusError:
      if [408, 429, 500, 502, 503, 504].contains(error.error.httpStatusCode ?? 0) {
        return true
      }
      return error.error.errors.contains {
        $0.reason.map(BigQueryRetryErrors.retryableReasons.contains) ?? false
      }
    default:
      return false
    }
  }
}

/// A non-308 status from an upload request, before deciding whether to resume.
private struct UploadStatusError: Error {
  var error: BigQueryError
}
