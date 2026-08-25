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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import GoogleCloudGax
@_spi(GoogleCloudInternal) import GoogleCloudWkt
@_spi(GoogleCloudInternal) import struct GoogleCloudGax._CRC32C
import Crypto
@_spi(GoogleCloudInternal) import GoogleCloudGax
import NIOHTTP1

package enum ResumableUploadStatus: Sendable {
  case unknown
  case inprogress(UInt64)
  case done(Object)
}

extension StorageClient {
  /// Core upload method accepting any upload source.
  ///
  /// - Parameters:
  ///   - source: The upload source containing the data.
  ///   - bucket: The destination GCS bucket name.
  ///   - objectName: The destination GCS object name.
  ///   - options: Configuration options for the upload.
  /// - Returns: An `UploadTask` to monitor and control the upload.
  public func upload(
    _ source: some UploadSource,
    to bucket: String,
    as objectName: String,
    options: UploadOptions = .default
  ) -> UploadTask {
    let clientOptions = self.options.client
    let effectiveBackoffPolicy =
      options.backoffPolicy ?? self.options.upload.backoffPolicy ?? clientOptions.backoffPolicy
    let effectiveResumePolicy =
      options.resumePolicy ?? self.options.upload.resumePolicy
      ?? StorageResumePolicy<UploadDetails>().stopOnConsecutiveErrors()
    let resumeLoop = _ResumeLoop(
      resumePolicy: effectiveResumePolicy,
      backoffPolicy: effectiveBackoffPolicy
    )
    let effectiveThreshold = Int64(
      options.resumableUploadThreshold ?? self.options.upload.resumableUploadThreshold
        ?? UploadOptions.defaultResumableUploadThreshold)
    let httpClient = self.inner
    return UploadTask.create { continuation in
      var source = source
      let totalSize = source.totalSize

      // Determine if simple or resumable
      let useResumable = totalSize == nil || totalSize! >= effectiveThreshold

      if !useResumable {
        return try await Self.performSimpleUpload(
          httpClient: httpClient,
          source: &source,
          bucket: bucket,
          objectName: objectName,
          metadata: options.metadata,
          options: options,
          totalSize: totalSize,
          continuation: continuation,
          resumeLoop: resumeLoop
        )
      } else {
        return try await Self.continueStreamingUpload(
          httpClient: httpClient,
          source: &source,
          bucket: bucket,
          objectName: objectName,
          metadata: options.metadata,
          uploadId: nil,
          initialStatus: .inprogress(0),
          chunkSize: options.chunkSize,
          totalSize: totalSize,
          options: options,
          continuation: continuation,
          resumeLoop: resumeLoop
        )
      }
    }
  }

  /// Upload method specialized for seekable upload sources.
  ///
  /// - Parameters:
  ///   - source: The seekable upload source containing the data.
  ///   - bucket: The destination GCS bucket name.
  ///   - objectName: The destination GCS object name.
  ///   - options: Configuration options for the upload.
  /// - Returns: An `UploadTask` to monitor and control the upload.
  public func upload(
    _ source: some SeekableUploadSource,
    to bucket: String,
    as objectName: String,
    options: UploadOptions = .default
  ) -> UploadTask {
    let clientOptions = self.options.client
    let effectiveBackoffPolicy =
      options.backoffPolicy ?? self.options.upload.backoffPolicy ?? clientOptions.backoffPolicy
    let effectiveResumePolicy: any ResumePolicy<UploadDetails>
    if let explicitResume = options.resumePolicy ?? self.options.upload.resumePolicy {
      effectiveResumePolicy = explicitResume
    } else {
      effectiveResumePolicy = StorageResumePolicy().stopOnConsecutiveErrors()
    }
    let resumeLoop = _ResumeLoop(
      resumePolicy: effectiveResumePolicy,
      backoffPolicy: effectiveBackoffPolicy
    )
    let effectiveThreshold = Int64(
      options.resumableUploadThreshold ?? self.options.upload.resumableUploadThreshold
        ?? UploadOptions.defaultResumableUploadThreshold)
    let httpClient = self.inner
    return UploadTask.create { continuation in
      var source = source
      let totalSize = source.totalSize

      // Determine if simple or resumable
      let useResumable = totalSize == nil || totalSize! >= effectiveThreshold

      if !useResumable {
        return try await Self.performSimpleUpload(
          httpClient: httpClient,
          source: &source,
          bucket: bucket,
          objectName: objectName,
          metadata: options.metadata,
          options: options,
          totalSize: totalSize,
          continuation: continuation,
          resumeLoop: resumeLoop
        )
      } else {
        return try await Self.continueResumableSeekableUpload(
          httpClient: httpClient,
          source: &source,
          bucket: bucket,
          objectName: objectName,
          metadata: options.metadata,
          uploadId: nil,
          initialStatus: .inprogress(0),
          chunkSize: options.chunkSize,
          totalSize: totalSize,
          options: options,
          continuation: continuation,
          resumeLoop: resumeLoop
        )
      }
    }
  }

  fileprivate static func performSimpleUpload(
    httpClient: GoogleCloudGax._HTTPClient,
    source: inout some UploadSource,
    bucket: String,
    objectName: String,
    metadata: UploadMetadata?,
    options: UploadOptions,
    totalSize: Int64?,
    continuation: AsyncStream<UploadStatus>.Continuation,
    resumeLoop: _ResumeLoop<UploadDetails>
  ) async throws -> Object {
    guard let data = try await source.read(maxBytes: Int(totalSize ?? 0)) else {
      throw UploadError.internalError("Failed to read data from source")
    }
    let checksum = try computeSimpleChecksum(data, options: options.checksums)
    let request = try await buildSimpleUploadRequest(
      httpClient: httpClient,
      bucket: bucket,
      objectName: objectName,
      data: data,
      metadata: metadata,
      options: options,
      checksum: checksum
    )

    let resumeState = ResumeState(details: UploadDetails(bytesUploaded: 0, totalBytes: totalSize))
    return try await resumeLoop.run(state: resumeState) { _ in
      let response: _HTTPClientResponse
      do {
        response = try await request.execute()
      } catch {
        if let reqError = error as? RequestError {
          throw reqError
        }
        throw RequestError.io(error)
      }
      if response.isError() {
        throw await response.decodeError()
      }
      let object = try await handleObjectResponse(response: response)
      continuation.yield(
        UploadStatus(
          bytesUploaded: Int64(data.count), totalBytes: totalSize))
      return object
    }
  }

  fileprivate static func startResumableSession(
    httpClient: GoogleCloudGax._HTTPClient,
    bucket: String,
    objectName: String,
    metadata: UploadMetadata?,
    options: UploadOptions
  ) async throws -> String {
    let startRequest = try await buildStartResumableUploadRequest(
      httpClient: httpClient, bucket: bucket, objectName: objectName, metadata: metadata,
      options: options)
    let startResponse: _HTTPClientResponse
    do {
      startResponse = try await startRequest.execute()
    } catch {
      if let reqError = error as? RequestError {
        throw reqError
      }
      throw RequestError.io(error)
    }
    let statusCode = Int(startResponse.status.code)
    guard statusCode == 200,
      let location = startResponse.headers.first(name: "Location")
    else {
      if startResponse.isError() {
        throw await startResponse.decodeError()
      }
      let startData = try await startResponse.data()
      throw UploadError.unexpectedServerResponse(
        statusCode: statusCode,
        message: String(data: startData, encoding: .utf8) ?? "")
    }
    return location
  }

  fileprivate static func queryUploadStatus(
    httpClient: GoogleCloudGax._HTTPClient,
    uploadId: String,
    options: UploadOptions
  ) async throws -> (status: ResumableUploadStatus, crc32cSeed: UInt32?) {
    let queryRequest = try await buildQueryResumableUploadRequest(
      httpClient: httpClient, uploadId: uploadId, options: options)
    let queryResponse: _HTTPClientResponse
    do {
      queryResponse = try await queryRequest.execute()
    } catch {
      if let reqError = error as? RequestError {
        throw reqError
      }
      throw RequestError.io(error)
    }

    let statusCode = Int(queryResponse.status.code)
    if statusCode == 200 || statusCode == 201 {
      let object = try await handleObjectResponse(response: queryResponse)
      return (.done(object), nil)
    } else if statusCode == 308 {
      let queryStatus = try parseResumableUploadQueryStatus(from: queryResponse.headers)
      return (.inprogress(UInt64(queryStatus.nextOffset)), queryStatus.crc32cSeed)
    } else if queryResponse.isError() {
      throw await queryResponse.decodeError()
    } else {
      let queryData = try await queryResponse.data()
      throw UploadError.unexpectedServerResponse(
        statusCode: statusCode,
        message: String(data: queryData, encoding: .utf8) ?? "")
    }
  }

  fileprivate static func sendNextChunk<S: UploadSource>(
    httpClient: GoogleCloudGax._HTTPClient,
    checksummedSource: inout ChecksummedSource<S>,
    uploadId: String,
    committedBytes: UInt64,
    chunkSize: Int,
    totalSize: Int64?,
    options: UploadOptions,
    continuation: AsyncStream<UploadStatus>.Continuation
  ) async throws -> (status: ResumableUploadStatus, crc32cSeed: UInt32?) {
    let chunkInfo = try await checksummedSource.readChunk(maxBytes: chunkSize)
    let chunk: Data
    let effectiveTotalSize: Int64?
    let checksum: String?

    if let chunkInfo = chunkInfo, !chunkInfo.data.isEmpty {
      chunk = chunkInfo.data
      let isLast = chunkInfo.isLast
      checksum = isLast ? chunkInfo.checksum : nil
      effectiveTotalSize =
        (isLast && totalSize == nil) ? (Int64(committedBytes) + Int64(chunk.count)) : totalSize
    } else {
      chunk = Data()
      effectiveTotalSize = totalSize ?? Int64(committedBytes)
      checksum = checksummedSource.finalizeChecksum()
    }

    let uploadRequest = try await buildUploadChunkRequest(
      httpClient: httpClient,
      uploadId: uploadId,
      data: chunk,
      offset: Int64(committedBytes),
      totalSize: effectiveTotalSize,
      options: options,
      checksum: checksum
    )

    let uploadResponse: _HTTPClientResponse
    do {
      uploadResponse = try await uploadRequest.execute()
    } catch {
      if let reqError = error as? RequestError {
        throw reqError
      }
      throw RequestError.io(error)
    }

    let statusCode = Int(uploadResponse.status.code)
    if statusCode == 200 || statusCode == 201 {
      let object = try await handleObjectResponse(response: uploadResponse)
      continuation.yield(
        UploadStatus(
          bytesUploaded: Int64(committedBytes) + Int64(chunk.count),
          totalBytes: effectiveTotalSize,
          uploadId: uploadId
        )
      )
      return (.done(object), nil)
    } else if statusCode == 308 {
      let nextOffset: Int64
      if let rangeHeader = uploadResponse.headers.first(name: "Range") {
        nextOffset = Int64(try HttpRange.parseNextRangeStart(rangeHeader))
      } else {
        nextOffset = Int64(committedBytes) + Int64(chunk.count)
      }
      var crc32cSeed: UInt32? = nil
      if let runningHashHeader = uploadResponse.headers.first(name: "x-goog-running-hash") {
        crc32cSeed = parseCRC32CFromRunningHash(runningHashHeader)
      }
      continuation.yield(
        UploadStatus(
          bytesUploaded: nextOffset,
          totalBytes: totalSize,
          uploadId: uploadId
        )
      )
      return (.inprogress(UInt64(nextOffset)), crc32cSeed)
    } else if uploadResponse.isError() {
      throw await uploadResponse.decodeError()
    } else {
      let uploadData = try await uploadResponse.data()
      throw UploadError.unexpectedServerResponse(
        statusCode: statusCode,
        message: String(data: uploadData, encoding: .utf8) ?? ""
      )
    }
  }

  fileprivate static func continueStreamingUpload<S: UploadSource>(
    httpClient: GoogleCloudGax._HTTPClient,
    source: inout S,
    bucket: String? = nil,
    objectName: String? = nil,
    metadata: UploadMetadata? = nil,
    uploadId: String?,
    initialStatus: ResumableUploadStatus,
    chunkSize: Int,
    totalSize: Int64?,
    options: UploadOptions,
    continuation: AsyncStream<UploadStatus>.Continuation,
    resumeLoop: _ResumeLoop<UploadDetails>
  ) async throws -> Object {
    var options = options
    var uploadStatus = initialStatus
    var currentUploadId = uploadId
    var checksummedSource: ChecksummedSource<S>? = nil
    var lastCommittedBytes: UInt64 = 0
    let initialBytes: UInt64
    if case .inprogress(let b) = initialStatus {
      initialBytes = b
    } else {
      initialBytes = 0
    }
    var resumeState = ResumeState(
      details: UploadDetails(
        bytesUploaded: initialBytes,
        totalBytes: totalSize
      )
    )

    while true {
      let activeUploadId: String
      if let id = currentUploadId {
        activeUploadId = id
      } else {
        guard let bucket = bucket, let objectName = objectName else {
          throw UploadError.internalError(
            "Missing bucket or object name to start resumable upload")
        }
        let location = try await resumeLoop.run(state: &resumeState) { _ in
          try await startResumableSession(
            httpClient: httpClient,
            bucket: bucket,
            objectName: objectName,
            metadata: metadata,
            options: options
          )
        }
        currentUploadId = location
        activeUploadId = location
        continuation.yield(
          UploadStatus(
            bytesUploaded: 0, totalBytes: totalSize, uploadId: location))
      }

      if case .unknown = uploadStatus {
        do {
          let queryResult = try await queryUploadStatus(
            httpClient: httpClient, uploadId: activeUploadId, options: options)
          uploadStatus = queryResult.status
          if case .inprogress(let committedBytes) = uploadStatus {
            if committedBytes > resumeState.details.bytesUploaded {
              resumeState.details.bytesUploaded = committedBytes
              resumeLoop.onProgress(state: &resumeState)
            }
            continuation.yield(
              UploadStatus(
                bytesUploaded: Int64(committedBytes), totalBytes: totalSize,
                uploadId: activeUploadId))
          }
        } catch {
          try await resumeLoop.handleError(state: &resumeState, error: error)
          continue
        }
      }

      switch uploadStatus {
      case .unknown:
        throw UploadError.internalError("queryUploadStatus returned unknown status")
      case .done(let object):
        continuation.yield(
          UploadStatus(
            bytesUploaded: totalSize ?? Int64(object.size),
            totalBytes: totalSize ?? Int64(object.size),
            uploadId: activeUploadId))
        return object
      case .inprogress(let committedBytes):
        if let total = totalSize, Int64(committedBytes) > total {
          throw UploadError.localSourceTooSmall(
            localSize: total, gcsOffset: Int64(committedBytes))
        }
        if committedBytes > 0 && options.checksums.md5 == .auto {
          options.checksums.md5 = nil
        }

        if checksummedSource == nil {
          if committedBytes > 0 {
            throw UploadError.internalError(
              "Cannot resume non-seekable source at offset \(committedBytes)"
            )
          }
          checksummedSource = ChecksummedSource(source: source, options: options.checksums)
        } else if committedBytes != lastCommittedBytes {
          throw UploadError.internalError(
            "Cannot resume non-seekable source at offset \(committedBytes); expected \(lastCommittedBytes)"
          )
        }

        uploadStatus = .unknown
        let chunkResult: (status: ResumableUploadStatus, crc32cSeed: UInt32?)
        do {
          chunkResult = try await sendNextChunk(
            httpClient: httpClient,
            checksummedSource: &checksummedSource!,
            uploadId: activeUploadId,
            committedBytes: committedBytes,
            chunkSize: chunkSize,
            totalSize: totalSize,
            options: options,
            continuation: continuation
          )
        } catch {
          try await resumeLoop.handleError(state: &resumeState, error: error)
          continue
        }

        if case .done(let object) = chunkResult.status {
          return object
        }
        uploadStatus = chunkResult.status
        if case .inprogress(let nextBytes) = chunkResult.status {
          if nextBytes > resumeState.details.bytesUploaded {
            resumeState.details.bytesUploaded = nextBytes
            resumeLoop.onProgress(state: &resumeState)
          }
          lastCommittedBytes = nextBytes
        }
      }
    }
  }

  fileprivate static func continueResumableSeekableUpload<S: SeekableUploadSource>(
    httpClient: GoogleCloudGax._HTTPClient,
    source: inout S,
    bucket: String? = nil,
    objectName: String? = nil,
    metadata: UploadMetadata? = nil,
    uploadId: String?,
    initialStatus: ResumableUploadStatus,
    initialCrc32cSeed: UInt32? = nil,
    chunkSize: Int,
    totalSize: Int64?,
    options: UploadOptions,
    continuation: AsyncStream<UploadStatus>.Continuation,
    resumeLoop: _ResumeLoop<UploadDetails>
  ) async throws -> Object {
    var options = options
    var uploadStatus = initialStatus
    var currentUploadId = uploadId
    var crc32cSeed = initialCrc32cSeed
    var checksummedSource: ChecksummedSource<S>? = nil
    let initialBytes: UInt64
    if case .inprogress(let b) = initialStatus {
      initialBytes = b
    } else {
      initialBytes = 0
    }
    var resumeState = ResumeState(
      details: UploadDetails(
        bytesUploaded: initialBytes,
        totalBytes: totalSize
      )
    )

    while true {
      let activeUploadId: String
      if let id = currentUploadId {
        activeUploadId = id
      } else {
        guard let bucket = bucket, let objectName = objectName else {
          throw UploadError.internalError(
            "Missing bucket or object name to start resumable upload")
        }
        let location = try await resumeLoop.run(state: &resumeState) { _ in
          try await startResumableSession(
            httpClient: httpClient,
            bucket: bucket,
            objectName: objectName,
            metadata: metadata,
            options: options
          )
        }
        currentUploadId = location
        activeUploadId = location
        continuation.yield(
          UploadStatus(
            bytesUploaded: 0, totalBytes: totalSize, uploadId: location))
      }

      if case .unknown = uploadStatus {
        do {
          let queryResult = try await queryUploadStatus(
            httpClient: httpClient, uploadId: activeUploadId, options: options)
          uploadStatus = queryResult.status
          if let seed = queryResult.crc32cSeed {
            crc32cSeed = seed
          }
          if case .inprogress(let committedBytes) = uploadStatus {
            if committedBytes > resumeState.details.bytesUploaded {
              resumeState.details.bytesUploaded = committedBytes
              resumeLoop.onProgress(state: &resumeState)
            }
            continuation.yield(
              UploadStatus(
                bytesUploaded: Int64(committedBytes), totalBytes: totalSize,
                uploadId: activeUploadId))
          }
        } catch {
          try await resumeLoop.handleError(state: &resumeState, error: error)
          continue
        }
      }

      switch uploadStatus {
      case .unknown:
        throw UploadError.internalError("queryUploadStatus returned unknown status")
      case .done(let object):
        continuation.yield(
          UploadStatus(
            bytesUploaded: totalSize ?? Int64(object.size),
            totalBytes: totalSize ?? Int64(object.size),
            uploadId: activeUploadId))
        return object
      case .inprogress(let committedBytes):
        if let total = totalSize, Int64(committedBytes) > total {
          throw UploadError.localSourceTooSmall(
            localSize: total, gcsOffset: Int64(committedBytes))
        }
        if committedBytes > 0 && options.checksums.md5 == .auto {
          options.checksums.md5 = nil
        }

        if checksummedSource == nil {
          var cs = ChecksummedSource(source: source, options: options.checksums)
          if let seed = crc32cSeed {
            cs.seedCRC32C(seed: seed, bytesHashed: Int64(committedBytes))
          }
          if committedBytes > 0 {
            try await cs.seek(to: Int64(committedBytes))
          }
          checksummedSource = cs
        } else {
          if let seed = crc32cSeed {
            checksummedSource!.seedCRC32C(seed: seed, bytesHashed: Int64(committedBytes))
          }
          try await checksummedSource!.seek(to: Int64(committedBytes))
        }

        uploadStatus = .unknown
        let chunkResult: (status: ResumableUploadStatus, crc32cSeed: UInt32?)
        do {
          chunkResult = try await sendNextChunk(
            httpClient: httpClient,
            checksummedSource: &checksummedSource!,
            uploadId: activeUploadId,
            committedBytes: committedBytes,
            chunkSize: chunkSize,
            totalSize: totalSize,
            options: options,
            continuation: continuation
          )
        } catch {
          try await resumeLoop.handleError(state: &resumeState, error: error)
          continue
        }

        if case .done(let object) = chunkResult.status {
          return object
        }
        uploadStatus = chunkResult.status
        if case .inprogress(let nextBytes) = chunkResult.status {
          if nextBytes > resumeState.details.bytesUploaded {
            resumeState.details.bytesUploaded = nextBytes
            resumeLoop.onProgress(state: &resumeState)
          }
        }
        if let seed = chunkResult.crc32cSeed {
          crc32cSeed = seed
        }
      }
    }
  }

  /// Resumes a previously interrupted file upload using a saved upload ID.
  ///
  /// - Parameters:
  ///   - source: The seekable upload source (must match the original source).
  ///   - uploadId: The saved GCS Upload ID (Session URI).
  ///   - options: Configuration options for the upload.
  /// - Returns: An `UploadTask` to monitor and control the resumed upload.
  public func resumeUpload(
    _ source: some SeekableUploadSource,
    uploadId: String,
    options: UploadOptions = .default
  ) -> UploadTask {
    let clientOptions = self.options.client
    let effectiveBackoffPolicy =
      options.backoffPolicy ?? self.options.upload.backoffPolicy ?? clientOptions.backoffPolicy
    let effectiveResumePolicy: any ResumePolicy<UploadDetails>
    if let explicitResume = options.resumePolicy ?? self.options.upload.resumePolicy {
      effectiveResumePolicy = explicitResume
    } else {
      effectiveResumePolicy = StorageResumePolicy().stopOnConsecutiveErrors()
    }
    let resumeLoop = _ResumeLoop(
      resumePolicy: effectiveResumePolicy,
      backoffPolicy: effectiveBackoffPolicy
    )
    let httpClient = self.inner
    return UploadTask.create { continuation in
      var source = source
      let totalSize = source.totalSize

      return try await Self.continueResumableSeekableUpload(
        httpClient: httpClient,
        source: &source,
        bucket: nil,
        objectName: nil,
        metadata: nil,
        uploadId: uploadId,
        initialStatus: .unknown,
        chunkSize: options.chunkSize,
        totalSize: totalSize,
        options: options,
        continuation: continuation,
        resumeLoop: resumeLoop
      )
    }
  }

  // --- Convenience Overloads ---

  /// Convenience upload method for a local file URL.
  public func upload(
    _ fileURL: URL,
    to bucket: String,
    as objectName: String,
    options: UploadOptions = .default
  ) -> UploadTask {
    return self.upload(
      FileSource(fileURL: fileURL), to: bucket, as: objectName, options: options)
  }

  /// Convenience upload method for in-memory Data.
  public func upload(
    _ data: Data,
    to bucket: String,
    as objectName: String,
    options: UploadOptions = .default
  ) -> UploadTask {
    return self.upload(
      BytesSource(data: data), to: bucket, as: objectName, options: options)
  }
}

// --- Helper Methods Extension ---

/// Status returned by GCS when querying an in-progress resumable upload.
struct ResumableUploadQueryStatus: Sendable {
  let nextOffset: Int64
  let crc32cSeed: UInt32?
}

extension StorageClient {
  fileprivate static func buildSimpleUploadRequest(
    httpClient: GoogleCloudGax._HTTPClient,
    bucket: String,
    objectName: String,
    data: Data,
    metadata: UploadMetadata?,
    options: UploadOptions,
    checksum: String? = nil
  ) async throws -> GoogleCloudGax._HTTPClientRequest {
    var queryItems = [URLQueryItem(name: "uploadType", value: "multipart")]
    queryItems.append(URLQueryItem(name: "name", value: objectName))

    if let kmsKeyName = options.kmsKeyName {
      queryItems.append(URLQueryItem(name: "kmsKeyName", value: kmsKeyName))
    }
    if let predefinedAcl = options.predefinedAcl {
      queryItems.append(URLQueryItem(name: "predefinedAcl", value: predefinedAcl.rawValue))
    }
    if let preconditions = options.preconditions {
      queryItems.append(contentsOf: preconditions.queryItems)
    }

    var request = try await httpClient.newRequest(
      path: "/upload/storage/v1/b/\(bucket)/o", query: queryItems)
    request.setMethod(.POST)

    if let checksum = checksum {
      request.setHeader(name: "x-goog-hash", value: checksum)
    }

    request.applyCustomerSuppliedEncryptionHeaders(options.customerEncryptionKey)

    let boundary = "Boundary-\(UUID().uuidString)"
    request.setHeader(name: "Content-Type", value: "multipart/related; boundary=\(boundary)")

    var body = Data()
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(Data("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
    let metadataJson = try JSONEncoder().encode(metadata ?? UploadMetadata())
    body.append(metadataJson)
    body.append(Data("\r\n".utf8))

    body.append(Data("--\(boundary)\r\n".utf8))
    let dataPartContentType = metadata?.contentType ?? "application/octet-stream"
    body.append(Data("Content-Type: \(dataPartContentType)\r\n\r\n".utf8))
    body.append(data)
    body.append(Data("\r\n".utf8))

    body.append(Data("--\(boundary)--\r\n".utf8))

    request.setBody(data: body)
    return request
  }

  fileprivate static func buildStartResumableUploadRequest(
    httpClient: GoogleCloudGax._HTTPClient,
    bucket: String,
    objectName: String,
    metadata: UploadMetadata?,
    options: UploadOptions
  ) async throws -> GoogleCloudGax._HTTPClientRequest {
    var queryItems = [URLQueryItem(name: "uploadType", value: "resumable")]
    queryItems.append(URLQueryItem(name: "name", value: objectName))

    if let kmsKeyName = options.kmsKeyName {
      queryItems.append(URLQueryItem(name: "kmsKeyName", value: kmsKeyName))
    }
    if let predefinedAcl = options.predefinedAcl {
      queryItems.append(URLQueryItem(name: "predefinedAcl", value: predefinedAcl.rawValue))
    }
    if let preconditions = options.preconditions {
      queryItems.append(contentsOf: preconditions.queryItems)
    }

    var request = try await httpClient.newRequest(
      path: "/upload/storage/v1/b/\(bucket)/o", query: queryItems)
    request.setMethod(.POST)
    request.setHeader(name: "Content-Type", value: "application/json; charset=UTF-8")

    request.applyCustomerSuppliedEncryptionHeaders(options.customerEncryptionKey)

    let metadataJson = try JSONEncoder().encode(metadata ?? UploadMetadata())
    request.setBody(data: metadataJson)
    return request
  }

  fileprivate static func buildQueryResumableUploadRequest(
    httpClient: GoogleCloudGax._HTTPClient,
    uploadId: String,
    options: UploadOptions? = nil
  ) async throws -> GoogleCloudGax._HTTPClientRequest {
    var request = try await httpClient.newRequest(uri: uploadId)
    request.setMethod(.PUT)
    request.setHeader(name: "Content-Type", value: "application/octet-stream")
    request.setHeader(name: "Content-Range", value: "bytes */*")
    request.setHeader(name: "Content-Length", value: "0")

    request.applyCustomerSuppliedEncryptionHeaders(options?.customerEncryptionKey)

    return request
  }

  fileprivate static func buildUploadChunkRequest(
    httpClient: GoogleCloudGax._HTTPClient,
    uploadId: String,
    data: Data,
    offset: Int64,
    totalSize: Int64?,
    options: UploadOptions,
    checksum: String? = nil
  ) async throws -> GoogleCloudGax._HTTPClientRequest {
    var request = try await httpClient.newRequest(uri: uploadId)
    request.setMethod(.PUT)
    request.setHeader(name: "Content-Type", value: "application/octet-stream")

    if let checksum = checksum {
      request.setHeader(name: "x-goog-hash", value: checksum)
    }

    request.applyCustomerSuppliedEncryptionHeaders(options.customerEncryptionKey)

    let totalStr = totalSize.map { String($0) } ?? "*"
    if data.isEmpty {
      request.setHeader(name: "Content-Range", value: "bytes */\(totalStr)")
    } else {
      let end = offset + Int64(data.count) - 1
      request.setHeader(name: "Content-Range", value: "bytes \(offset)-\(end)/\(totalStr)")
    }
    request.setBody(data: data)
    return request
  }

  internal static func parseResumableUploadQueryStatus(from headers: NIOHTTP1.HTTPHeaders) throws
    -> ResumableUploadQueryStatus
  {
    var nextOffset: Int64 = 0
    if let rangeHeader = headers.first(name: "Range") {
      nextOffset = Int64(try HttpRange.parseNextRangeStart(rangeHeader))
    }

    var crc32cSeed: UInt32? = nil
    if let runningHashHeader = headers.first(name: "x-goog-running-hash") {
      crc32cSeed = parseCRC32CFromRunningHash(runningHashHeader)
    }

    return ResumableUploadQueryStatus(nextOffset: nextOffset, crc32cSeed: crc32cSeed)
  }

  internal static func parseCRC32CFromRunningHash(_ headerValue: String) -> UInt32? {
    let parts = headerValue.split(separator: ",")
    for part in parts {
      let trimmed = part.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("crc32c=") {
        let b64 = String(trimmed.dropFirst("crc32c=".count))
        guard let data = Data(base64Encoded: b64), data.count == 4 else { return nil }
        let bigEndian = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        return UInt32(bigEndian: bigEndian)
      }
    }
    return nil
  }

  fileprivate static func handleObjectResponse(response: GoogleCloudGax._HTTPClientResponse)
    async throws
    -> Object
  {
    if response.isError() {
      throw await response.decodeError()
    }
    let data = try await response.data()
    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1Object = try decoder.decode(ObjectV1Response.self, from: data)
    return v1Object.toObject()
  }

  fileprivate static func computeSimpleChecksum(_ data: Data, options: ChecksumOptions) throws
    -> String?
  {
    var calculators = options.makeUploadCalculators()
    guard !calculators.isEmpty else { return nil }
    for i in calculators.indices {
      calculators[i].update(data)
    }
    return calculators.map { "\($0.algorithmName)=\($0.finalize())" }.joined(separator: ", ")
  }
}
