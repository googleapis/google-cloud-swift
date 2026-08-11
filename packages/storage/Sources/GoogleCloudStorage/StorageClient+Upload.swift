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
import GoogleCloudWkt
@_spi(GoogleCloudInternal) import struct GoogleCloudGax._CRC32C
import Crypto

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
    let effectiveRetryPolicy =
      options.retryPolicy ?? self.options.upload.retryPolicy
      ?? clientOptions.retryPolicy
    let effectiveBackoffPolicy =
      options.backoffPolicy ?? self.options.upload.backoffPolicy ?? clientOptions.backoffPolicy
    let retryLoop = _RetryLoop(
      retryPolicy: effectiveRetryPolicy,
      backoffPolicy: effectiveBackoffPolicy,
      retryThrottler: clientOptions.retryThrottler,
      idempotent: true
    )
    let httpClient = self.inner
    return UploadTask.create { continuation in
      var source = source
      let totalSize = source.totalSize

      // Determine if simple or resumable
      let threshold = 8 * 1024 * 1024  // 8MB default threshold
      let useResumable = totalSize == nil || totalSize! >= threshold

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
          retryLoop: retryLoop
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
          retryLoop: retryLoop
        )
      }
    }
  }

  /// Upload method accepting any seekable upload source.
  public func upload(
    _ source: some SeekableUploadSource,
    to bucket: String,
    as objectName: String,
    options: UploadOptions = .default
  ) -> UploadTask {
    let clientOptions = self.options.client
    let effectiveRetryPolicy =
      options.retryPolicy ?? self.options.upload.retryPolicy
      ?? clientOptions.retryPolicy
    let effectiveBackoffPolicy =
      options.backoffPolicy ?? self.options.upload.backoffPolicy ?? clientOptions.backoffPolicy
    let retryLoop = _RetryLoop(
      retryPolicy: effectiveRetryPolicy,
      backoffPolicy: effectiveBackoffPolicy,
      retryThrottler: clientOptions.retryThrottler,
      idempotent: true
    )
    let httpClient = self.inner
    return UploadTask.create { continuation in
      var source = source
      let totalSize = source.totalSize

      // Determine if simple or resumable
      let threshold = 8 * 1024 * 1024  // 8MB default threshold
      let useResumable = totalSize == nil || totalSize! >= threshold

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
          retryLoop: retryLoop
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
          retryLoop: retryLoop
        )
      }
    }
  }

  fileprivate static func performSimpleUpload(
    httpClient: HTTPClient,
    source: inout some UploadSource,
    bucket: String,
    objectName: String,
    metadata: UploadMetadata?,
    options: UploadOptions,
    totalSize: Int64?,
    continuation: AsyncStream<UploadStatus>.Continuation,
    retryLoop: _RetryLoop
  ) async throws -> Object {
    guard let data = try await source.read(maxBytes: Int(totalSize ?? 0)) else {
      throw UploadError.internalError("Failed to read data from source")
    }
    let checksum = try computeSimpleChecksum(data, options: options.checksums)
    let request = try await httpClient.buildSimpleUploadRequest(
      bucket: bucket,
      objectName: objectName,
      data: data,
      metadata: metadata,
      options: options,
      checksum: checksum
    )

    return try await retryLoop.run { _ in
      let (responseData, response): (Data, HTTPURLResponse)
      do {
        (responseData, response) = try await httpClient.data(for: request)
      } catch {
        throw RequestError.io(error)
      }
      if response.statusCode == 503 {
        throw HTTPClient.parseError(data: responseData, response: response)
      }
      let object = try httpClient.handleObjectResponse(data: responseData, response: response)
      continuation.yield(
        UploadStatus(
          bytesUploaded: Int64(data.count), totalBytes: totalSize))
      return object
    }
  }

  fileprivate static func startResumableSession(
    httpClient: HTTPClient,
    bucket: String,
    objectName: String,
    metadata: UploadMetadata?,
    options: UploadOptions
  ) async throws -> String {
    let startRequest = try await httpClient.buildStartResumableUploadRequest(
      bucket: bucket, objectName: objectName, metadata: metadata, options: options)
    let (startData, startResponse): (Data, HTTPURLResponse)
    do {
      (startData, startResponse) = try await httpClient.data(for: startRequest)
    } catch {
      throw RequestError.io(error)
    }
    guard startResponse.statusCode == 200,
      let location = startResponse.value(forHTTPHeaderField: "Location")
    else {
      if startResponse.statusCode == 503 {
        throw HTTPClient.parseError(data: startData, response: startResponse)
      }
      throw UploadError.unexpectedServerResponse(
        statusCode: startResponse.statusCode,
        message: String(data: startData, encoding: .utf8) ?? "")
    }
    return location
  }

  fileprivate static func queryUploadStatus(
    httpClient: HTTPClient,
    uploadId: String,
    options: UploadOptions
  ) async throws -> (status: ResumableUploadStatus, crc32cSeed: UInt32?) {
    let queryRequest = try await httpClient.buildQueryResumableUploadRequest(
      uploadId: uploadId, options: options)
    let (queryData, queryResponse): (Data, HTTPURLResponse)
    do {
      (queryData, queryResponse) = try await httpClient.data(for: queryRequest)
    } catch {
      throw RequestError.io(error)
    }

    if queryResponse.statusCode == 200 || queryResponse.statusCode == 201 {
      let object = try httpClient.handleObjectResponse(data: queryData, response: queryResponse)
      return (.done(object), nil)
    } else if queryResponse.statusCode == 308 {
      let queryStatus = try httpClient.parseResumableUploadQueryStatus(from: queryResponse)
      return (.inprogress(UInt64(queryStatus.nextOffset)), queryStatus.crc32cSeed)
    } else if queryResponse.statusCode == 503 {
      throw HTTPClient.parseError(data: queryData, response: queryResponse)
    } else {
      throw UploadError.unexpectedServerResponse(
        statusCode: queryResponse.statusCode,
        message: String(data: queryData, encoding: .utf8) ?? "")
    }
  }

  fileprivate static func sendNextChunk<S: UploadSource>(
    httpClient: HTTPClient,
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

    let uploadRequest = try await httpClient.buildUploadChunkRequest(
      uploadId: uploadId,
      data: chunk,
      offset: Int64(committedBytes),
      totalSize: effectiveTotalSize,
      options: options,
      checksum: checksum
    )

    let (uploadData, uploadResponse): (Data, HTTPURLResponse)
    do {
      (uploadData, uploadResponse) = try await httpClient.data(for: uploadRequest)
    } catch {
      throw RequestError.io(error)
    }

    if uploadResponse.statusCode == 200 || uploadResponse.statusCode == 201 {
      let object = try httpClient.handleObjectResponse(data: uploadData, response: uploadResponse)
      continuation.yield(
        UploadStatus(
          bytesUploaded: Int64(committedBytes) + Int64(chunk.count),
          totalBytes: effectiveTotalSize,
          uploadId: uploadId
        )
      )
      return (.done(object), nil)
    } else if uploadResponse.statusCode == 308 {
      let nextOffset: Int64
      if let rangeHeader = uploadResponse.value(forHTTPHeaderField: "Range") {
        nextOffset = Int64(try HttpRange.parseNextRangeStart(rangeHeader))
      } else {
        nextOffset = Int64(committedBytes) + Int64(chunk.count)
      }
      var crc32cSeed: UInt32? = nil
      if let runningHashHeader = uploadResponse.value(forHTTPHeaderField: "x-goog-running-hash") {
        crc32cSeed = httpClient.parseCRC32CFromRunningHash(runningHashHeader)
      }
      continuation.yield(
        UploadStatus(
          bytesUploaded: nextOffset,
          totalBytes: totalSize,
          uploadId: uploadId
        )
      )
      return (.inprogress(UInt64(nextOffset)), crc32cSeed)
    } else if uploadResponse.statusCode == 503 {
      throw HTTPClient.parseError(data: uploadData, response: uploadResponse)
    } else {
      _ = try httpClient.handleObjectResponse(data: uploadData, response: uploadResponse)
      throw UploadError.unexpectedServerResponse(
        statusCode: uploadResponse.statusCode,
        message: String(data: uploadData, encoding: .utf8) ?? ""
      )
    }
  }

  fileprivate static func continueStreamingUpload<S: UploadSource>(
    httpClient: HTTPClient,
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
    retryLoop: _RetryLoop
  ) async throws -> Object {
    var options = options
    var uploadStatus = initialStatus
    var currentUploadId = uploadId
    var checksummedSource: ChecksummedSource<S>? = nil
    var lastCommittedBytes: UInt64 = 0

    return try await retryLoop.run { _ in
      while true {
        let activeUploadId: String
        if let id = currentUploadId {
          activeUploadId = id
        } else {
          guard let bucket = bucket, let objectName = objectName else {
            throw UploadError.internalError(
              "Missing bucket or object name to start resumable upload")
          }
          let location = try await startResumableSession(
            httpClient: httpClient,
            bucket: bucket,
            objectName: objectName,
            metadata: metadata,
            options: options
          )
          currentUploadId = location
          activeUploadId = location
          continuation.yield(
            UploadStatus(
              bytesUploaded: 0, totalBytes: totalSize, uploadId: location))
        }

        if case .unknown = uploadStatus {
          let queryResult = try await queryUploadStatus(
            httpClient: httpClient, uploadId: activeUploadId, options: options)
          uploadStatus = queryResult.status
          if case .inprogress(let committedBytes) = uploadStatus {
            continuation.yield(
              UploadStatus(
                bytesUploaded: Int64(committedBytes), totalBytes: totalSize,
                uploadId: activeUploadId))
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
          let chunkResult = try await sendNextChunk(
            httpClient: httpClient,
            checksummedSource: &checksummedSource!,
            uploadId: activeUploadId,
            committedBytes: committedBytes,
            chunkSize: chunkSize,
            totalSize: totalSize,
            options: options,
            continuation: continuation
          )
          if case .done(let object) = chunkResult.status {
            return object
          }
          uploadStatus = chunkResult.status
          if case .inprogress(let nextBytes) = chunkResult.status {
            lastCommittedBytes = nextBytes
          }
        }
      }
    }
  }

  fileprivate static func continueResumableSeekableUpload<S: SeekableUploadSource>(
    httpClient: HTTPClient,
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
    retryLoop: _RetryLoop
  ) async throws -> Object {
    var options = options
    var uploadStatus = initialStatus
    var currentUploadId = uploadId
    var crc32cSeed = initialCrc32cSeed
    var checksummedSource: ChecksummedSource<S>? = nil

    return try await retryLoop.run { _ in
      while true {
        let activeUploadId: String
        if let id = currentUploadId {
          activeUploadId = id
        } else {
          guard let bucket = bucket, let objectName = objectName else {
            throw UploadError.internalError(
              "Missing bucket or object name to start resumable upload")
          }
          let location = try await startResumableSession(
            httpClient: httpClient,
            bucket: bucket,
            objectName: objectName,
            metadata: metadata,
            options: options
          )
          currentUploadId = location
          activeUploadId = location
          continuation.yield(
            UploadStatus(
              bytesUploaded: 0, totalBytes: totalSize, uploadId: location))
        }

        if case .unknown = uploadStatus {
          let queryResult = try await queryUploadStatus(
            httpClient: httpClient, uploadId: activeUploadId, options: options)
          uploadStatus = queryResult.status
          if let seed = queryResult.crc32cSeed {
            crc32cSeed = seed
          }
          if case .inprogress(let committedBytes) = uploadStatus {
            continuation.yield(
              UploadStatus(
                bytesUploaded: Int64(committedBytes), totalBytes: totalSize,
                uploadId: activeUploadId))
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
          let chunkResult = try await sendNextChunk(
            httpClient: httpClient,
            checksummedSource: &checksummedSource!,
            uploadId: activeUploadId,
            committedBytes: committedBytes,
            chunkSize: chunkSize,
            totalSize: totalSize,
            options: options,
            continuation: continuation
          )
          if case .done(let object) = chunkResult.status {
            return object
          }
          uploadStatus = chunkResult.status
          if let seed = chunkResult.crc32cSeed {
            crc32cSeed = seed
          }
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
    let effectiveRetryPolicy =
      options.retryPolicy ?? self.options.upload.retryPolicy
      ?? clientOptions.retryPolicy
    let effectiveBackoffPolicy =
      options.backoffPolicy ?? self.options.upload.backoffPolicy ?? clientOptions.backoffPolicy
    let retryLoop = _RetryLoop(
      retryPolicy: effectiveRetryPolicy,
      backoffPolicy: effectiveBackoffPolicy,
      retryThrottler: clientOptions.retryThrottler,
      idempotent: true
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
        retryLoop: retryLoop
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

extension HTTPClient {
  fileprivate func buildSimpleUploadRequest(
    bucket: String,
    objectName: String,
    data: Data,
    metadata: UploadMetadata?,
    options: UploadOptions,
    checksum: String? = nil
  ) async throws -> URLRequest {
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

    var request = try await self.Request(
      path: "/upload/storage/v1/b/\(bucket)/o", query: queryItems)
    request.httpMethod = "POST"

    if let checksum = checksum {
      request.setValue(checksum, forHTTPHeaderField: "x-goog-hash")
    }

    request.applyCustomerSuppliedEncryptionHeaders(options.customerEncryptionKey)

    let boundary = "Boundary-\(UUID().uuidString)"
    request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

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

    request.httpBody = body
    return request
  }

  fileprivate func buildStartResumableUploadRequest(
    bucket: String,
    objectName: String,
    metadata: UploadMetadata?,
    options: UploadOptions
  ) async throws -> URLRequest {
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

    var request = try await self.Request(
      path: "/upload/storage/v1/b/\(bucket)/o", query: queryItems)
    request.httpMethod = "POST"
    request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

    request.applyCustomerSuppliedEncryptionHeaders(options.customerEncryptionKey)

    let metadataJson = try JSONEncoder().encode(metadata ?? UploadMetadata())
    request.httpBody = metadataJson
    return request
  }

  fileprivate func buildQueryResumableUploadRequest(
    uploadId: String,
    options: UploadOptions? = nil
  ) async throws -> URLRequest {
    guard let url = URL(string: uploadId),
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw UploadError.internalError("Invalid upload ID: \(uploadId)")
    }
    let queryItems = components.queryItems ?? []
    var request = try await self.Request(
      path: components.path, query: queryItems)
    request.httpMethod = "PUT"
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.setValue("bytes */*", forHTTPHeaderField: "Content-Range")
    request.setValue("0", forHTTPHeaderField: "Content-Length")

    request.applyCustomerSuppliedEncryptionHeaders(options?.customerEncryptionKey)

    return request
  }

  fileprivate func buildUploadChunkRequest(
    uploadId: String,
    data: Data,
    offset: Int64,
    totalSize: Int64?,
    options: UploadOptions,
    checksum: String? = nil
  ) async throws -> URLRequest {
    guard let url = URL(string: uploadId),
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw UploadError.internalError("Invalid upload ID: \(uploadId)")
    }
    var request = try await self.Request(
      path: components.path, query: components.queryItems ?? [])
    request.httpMethod = "PUT"
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

    if let checksum = checksum {
      request.setValue(checksum, forHTTPHeaderField: "x-goog-hash")
    }

    request.applyCustomerSuppliedEncryptionHeaders(options.customerEncryptionKey)

    let totalStr = totalSize.map { String($0) } ?? "*"
    if data.isEmpty {
      request.setValue("bytes */\(totalStr)", forHTTPHeaderField: "Content-Range")
    } else {
      let end = offset + Int64(data.count) - 1
      request.setValue("bytes \(offset)-\(end)/\(totalStr)", forHTTPHeaderField: "Content-Range")
    }
    request.httpBody = data
    return request
  }

  internal func parseResumableUploadQueryStatus(from response: HTTPURLResponse) throws
    -> ResumableUploadQueryStatus
  {
    var nextOffset: Int64 = 0
    if let rangeHeader = response.value(forHTTPHeaderField: "Range") {
      nextOffset = Int64(try HttpRange.parseNextRangeStart(rangeHeader))
    }

    var crc32cSeed: UInt32? = nil
    if let runningHashHeader = response.value(forHTTPHeaderField: "x-goog-running-hash") {
      crc32cSeed = parseCRC32CFromRunningHash(runningHashHeader)
    }

    return ResumableUploadQueryStatus(nextOffset: nextOffset, crc32cSeed: crc32cSeed)
  }

  internal func parseCRC32CFromRunningHash(_ headerValue: String) -> UInt32? {
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

  fileprivate func handleObjectResponse(data: Data, response: HTTPURLResponse) throws
    -> Object
  {
    guard (200..<300).contains(response.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? ""
      throw UploadError.unexpectedServerResponse(
        statusCode: response.statusCode, message: message)
    }
    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1Object = try decoder.decode(ObjectV1Response.self, from: data)
    return v1Object.toObject()
  }
}

extension StorageClient {
  fileprivate static func computeSimpleChecksum(_ data: Data, options: ChecksumOptions) throws
    -> String?
  {
    var parts = [String]()

    if let crcOption = options.crc32c {
      switch crcOption {
      case .auto:
        let crc = _CRC32C.compute(data)
        let bigEndian = crc.bigEndian
        var bytes = [UInt8]()
        withUnsafeBytes(of: bigEndian) {
          bytes = Array($0)
        }
        parts.append("crc32c=" + Data(bytes).base64EncodedString())
      case .value(let val):
        let formatted = val.hasPrefix("crc32c=") ? val : "crc32c=" + val
        parts.append(formatted)
      }
    }

    if let md5Option = options.md5 {
      switch md5Option {
      case .auto:
        let digest = Insecure.MD5.hash(data: data)
        parts.append("md5=" + Data(digest).base64EncodedString())
      case .value(let val):
        let formatted = val.hasPrefix("md5=") ? val : "md5=" + val
        parts.append(formatted)
      }
    }

    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }
}

extension URLRequest {
  package mutating func applyCustomerSuppliedEncryptionHeaders(
    _ key: CustomerEncryptionKeyOptions?
  ) {
    guard let key else { return }
    setValue(key.algorithm.rawValue, forHTTPHeaderField: "x-goog-encryption-algorithm")
    setValue(key.keyBase64, forHTTPHeaderField: "x-goog-encryption-key")
    setValue(key.keyHashBase64, forHTTPHeaderField: "x-goog-encryption-key-sha256")
  }
}
