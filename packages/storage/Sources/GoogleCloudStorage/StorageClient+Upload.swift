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
      ?? defaultUploadRetryPolicy()
    let effectiveBackoffPolicy =
      options.backoffPolicy ?? self.options.upload.backoffPolicy ?? clientOptions.backoffPolicy

    return UploadTask.create { continuation in
      let httpClient = try HTTPClient(
        from: clientOptions, withDefaultEndpoint: StorageClient.defaultEndpoint)
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
          continuation: continuation
        )
      } else {
        return try await Self.performResumableUpload(
          httpClient: httpClient,
          source: &source,
          bucket: bucket,
          objectName: objectName,
          metadata: options.metadata,
          options: options,
          totalSize: totalSize,
          continuation: continuation,
          retryPolicy: effectiveRetryPolicy,
          backoffPolicy: effectiveBackoffPolicy
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
    continuation: AsyncStream<UploadStatus>.Continuation
  ) async throws -> StorageObject {
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
    let (responseData, response) = try await httpClient.data(for: request)
    let object = try httpClient.handleObjectResponse(data: responseData, response: response)
    continuation.yield(
      UploadStatus(
        bytesUploaded: Int64(data.count), totalBytes: totalSize))
    return object
  }

  fileprivate static func performResumableUpload(
    httpClient: HTTPClient,
    source: inout some UploadSource,
    bucket: String,
    objectName: String,
    metadata: UploadMetadata?,
    options: UploadOptions,
    totalSize: Int64?,
    continuation: AsyncStream<UploadStatus>.Continuation,
    retryPolicy: any RetryPolicy,
    backoffPolicy: any BackoffPolicy
  ) async throws -> StorageObject {
    let retryLoop = _RetryLoop(
      retryPolicy: retryPolicy,
      backoffPolicy: backoffPolicy,
      retryThrottler: AdaptiveThrottler(),
      idempotent: true
    )

    let uploadId: String
    do {
      uploadId = try await retryLoop.run { _ in
        let startRequest = try await httpClient.buildStartResumableUploadRequest(
          bucket: bucket, objectName: objectName, metadata: metadata, options: options)
        let (startData, startResponse) = try await httpClient.sendRequestWithMappedError(
          startRequest)
        guard startResponse.statusCode == 200,
          let location = startResponse.value(forHTTPHeaderField: "Location")
        else {
          throw RequestError.http(
            HTTPDetails(
              http_status_code: startResponse.statusCode,
              headers: [:],
              payload: startData
            ))
        }
        return location
      }
    } catch {
      throw mapToPublicError(error)
    }

    continuation.yield(
      UploadStatus(
        bytesUploaded: 0, totalBytes: totalSize, uploadId: uploadId))

    let chunkSize = options.chunkSize
    return try await Self.continueResumableUpload(
      httpClient: httpClient,
      source: &source,
      uploadId: uploadId,
      offset: 0,
      chunkSize: chunkSize,
      totalSize: totalSize,
      options: options,
      continuation: continuation,
      retryPolicy: retryPolicy,
      backoffPolicy: backoffPolicy
    )
  }

  fileprivate static func continueStreamingUpload<S: UploadSource>(
    httpClient: HTTPClient,
    checksummedSource: inout ChecksummedSource<S>,
    uploadId: String,
    offset: Int64,
    chunkSize: Int,
    totalSize: Int64?,
    options: UploadOptions,
    continuation: AsyncStream<UploadStatus>.Continuation,
    retryPolicy: any RetryPolicy,
    backoffPolicy: any BackoffPolicy
  ) async throws -> StorageObject {
    var offset = offset
    let retryLoop = _RetryLoop(
      retryPolicy: retryPolicy,
      backoffPolicy: backoffPolicy,
      retryThrottler: AdaptiveThrottler(),
      idempotent: true
    )

    while true {
      guard let initialChunkInfo = try await checksummedSource.readChunk(maxBytes: chunkSize),
        !initialChunkInfo.data.isEmpty
      else {
        break
      }

      var currentChunkInfo = initialChunkInfo
      var attempt = 0
      let res: ChunkUploadResult
      do {
        res = try await retryLoop.run { _ in
          attempt += 1
          if attempt > 1 {
            let queryRequest = try await httpClient.buildQueryResumableUploadRequest(
              uploadId: uploadId, options: options)
            let (qData, qResponse) = try await httpClient.sendRequestWithMappedError(queryRequest)
            if qResponse.statusCode == 200 || qResponse.statusCode == 201 {
              return ChunkUploadResult(
                responseData: qData, response: qResponse, chunkCount: 0,
                effectiveTotalSize: totalSize)
            } else if qResponse.statusCode == 308 {
              let status = try httpClient.parseResumableUploadQueryStatus(from: qResponse)
              offset = status.nextOffset
              if var seekable = checksummedSource.source as? SeekableUploadSource {
                try await seekable.seek(to: offset)
                checksummedSource.source = seekable as! S
              }
              if let reReadInfo = try await checksummedSource.readChunk(maxBytes: chunkSize) {
                currentChunkInfo = reReadInfo
              }
            } else {
              throw RequestError.http(
                HTTPDetails(
                  http_status_code: qResponse.statusCode,
                  headers: [:],
                  payload: qData
                ))
            }
          }

          let chunk = currentChunkInfo.data
          let isLast = currentChunkInfo.isLast
          let checksum = isLast ? currentChunkInfo.checksum : nil
          let effectiveTotalSize =
            (isLast && totalSize == nil) ? (offset + Int64(chunk.count)) : totalSize

          let uploadRequest = try await httpClient.buildUploadChunkRequest(
            uploadId: uploadId, data: chunk, offset: offset, totalSize: effectiveTotalSize,
            options: options, checksum: checksum)
          let (uData, uResponse) = try await httpClient.sendRequestWithMappedError(uploadRequest)
          if uResponse.statusCode == 200 || uResponse.statusCode == 201
            || uResponse.statusCode == 308
          {
            return ChunkUploadResult(
              responseData: uData, response: uResponse, chunkCount: Int64(chunk.count),
              effectiveTotalSize: effectiveTotalSize)
          } else {
            throw RequestError.http(
              HTTPDetails(
                http_status_code: uResponse.statusCode,
                headers: [:],
                payload: uData
              ))
          }
        }
      } catch {
        throw mapToPublicError(error)
      }

      if res.response.statusCode == 204 {
        break
      }

      if res.response.statusCode == 200 || res.response.statusCode == 201 {
        let object = try httpClient.handleObjectResponse(
          data: res.responseData, response: res.response)
        continuation.yield(
          UploadStatus(
            bytesUploaded: offset + res.chunkCount,
            totalBytes: res.effectiveTotalSize ?? (offset + res.chunkCount), uploadId: uploadId))
        return object
      } else if res.response.statusCode == 308 {
        if let rangeHeader = res.response.value(forHTTPHeaderField: "Range") {
          offset = try httpClient.parseNextRangeStart(rangeHeader)
        } else {
          offset += res.chunkCount
        }
        continuation.yield(
          UploadStatus(
            bytesUploaded: offset, totalBytes: totalSize, uploadId: uploadId))
      }
    }

    // Finalize upload with an empty chunk if the stream finished without returning an object
    let finalTotalSize = totalSize ?? offset
    let checksum = checksummedSource.finalizeChecksum()

    let finalResult: (Data, HTTPURLResponse)
    do {
      finalResult = try await retryLoop.run { _ in
        let uploadRequest = try await httpClient.buildUploadChunkRequest(
          uploadId: uploadId, data: Data(), offset: offset, totalSize: finalTotalSize,
          options: options,
          checksum: checksum)
        let (uData, uResponse) = try await httpClient.sendRequestWithMappedError(uploadRequest)
        if uResponse.statusCode == 200 || uResponse.statusCode == 201 {
          return (uData, uResponse)
        } else {
          throw RequestError.http(
            HTTPDetails(
              http_status_code: uResponse.statusCode,
              headers: [:],
              payload: uData
            ))
        }
      }
    } catch {
      throw mapToPublicError(error)
    }

    let object = try httpClient.handleObjectResponse(
      data: finalResult.0, response: finalResult.1)
    continuation.yield(
      UploadStatus(
        bytesUploaded: offset, totalBytes: finalTotalSize, uploadId: uploadId))
    return object
  }

  fileprivate static func continueResumableUpload<S: UploadSource>(
    httpClient: HTTPClient,
    source: inout S,
    uploadId: String,
    offset: Int64,
    chunkSize: Int,
    totalSize: Int64?,
    options: UploadOptions,
    continuation: AsyncStream<UploadStatus>.Continuation,
    retryPolicy: any RetryPolicy,
    backoffPolicy: any BackoffPolicy
  ) async throws -> StorageObject {
    var options = options
    if offset > 0 && options.checksums.md5 == .auto {
      options.checksums.md5 = nil
    }
    var checksummedSource = ChecksummedSource(source: source, options: options.checksums)
    return try await continueStreamingUpload(
      httpClient: httpClient,
      checksummedSource: &checksummedSource,
      uploadId: uploadId,
      offset: offset,
      chunkSize: chunkSize,
      totalSize: totalSize,
      options: options,
      continuation: continuation,
      retryPolicy: retryPolicy,
      backoffPolicy: backoffPolicy
    )
  }

  fileprivate static func continueResumableUpload<S: SeekableUploadSource>(
    httpClient: HTTPClient,
    source: inout S,
    uploadId: String,
    offset: Int64,
    crc32cSeed: UInt32? = nil,
    chunkSize: Int,
    totalSize: Int64?,
    options: UploadOptions,
    continuation: AsyncStream<UploadStatus>.Continuation,
    retryPolicy: any RetryPolicy,
    backoffPolicy: any BackoffPolicy
  ) async throws -> StorageObject {
    var options = options
    if offset > 0 && options.checksums.md5 == .auto {
      options.checksums.md5 = nil
    }
    var checksummedSource = ChecksummedSource(source: source, options: options.checksums)
    if let seed = crc32cSeed {
      checksummedSource.seedCRC32C(seed: seed, bytesHashed: offset)
    }
    if offset > 0 {
      try await checksummedSource.seek(to: offset)
    }
    return try await continueStreamingUpload(
      httpClient: httpClient,
      checksummedSource: &checksummedSource,
      uploadId: uploadId,
      offset: offset,
      chunkSize: chunkSize,
      totalSize: totalSize,
      options: options,
      continuation: continuation,
      retryPolicy: retryPolicy,
      backoffPolicy: backoffPolicy
    )
  }

  public func resumeUpload(
    _ source: some SeekableUploadSource,
    uploadId: String,
    options: UploadOptions = .default
  ) -> UploadTask {
    let clientOptions = self.options.client
    let effectiveRetryPolicy =
      options.retryPolicy ?? self.options.upload.retryPolicy
      ?? defaultUploadRetryPolicy()
    let effectiveBackoffPolicy =
      options.backoffPolicy ?? self.options.upload.backoffPolicy ?? clientOptions.backoffPolicy

    return UploadTask.create { continuation in
      let httpClient = try HTTPClient(
        from: clientOptions, withDefaultEndpoint: Self.defaultEndpoint)
      var source = source
      let totalSize = source.totalSize

      let retryLoop = _RetryLoop(
        retryPolicy: effectiveRetryPolicy,
        backoffPolicy: effectiveBackoffPolicy,
        retryThrottler: AdaptiveThrottler(),
        idempotent: true
      )

      let result: Either<StorageObject, ResumableUploadQueryStatus>
      do {
        result = try await retryLoop.run { _ in
          let queryRequest = try await httpClient.buildQueryResumableUploadRequest(
            uploadId: uploadId, options: options)
          let (queryData, queryResponse) = try await httpClient.sendRequestWithMappedError(
            queryRequest)

          if queryResponse.statusCode == 200 || queryResponse.statusCode == 201 {
            let object = try httpClient.handleObjectResponse(
              data: queryData, response: queryResponse)
            return .left(object)
          } else if queryResponse.statusCode == 308 {
            let status = try httpClient.parseResumableUploadQueryStatus(from: queryResponse)
            return .right(status)
          } else {
            throw RequestError.http(
              HTTPDetails(
                http_status_code: queryResponse.statusCode,
                headers: [:],
                payload: queryData
              ))
          }
        }
      } catch {
        throw mapToPublicError(error)
      }

      switch result {
      case .left(let object):
        continuation.yield(
          UploadStatus(
            bytesUploaded: totalSize ?? 0, totalBytes: totalSize, uploadId: uploadId))
        return object
      case .right(let status):
        continuation.yield(
          UploadStatus(
            bytesUploaded: status.nextOffset, totalBytes: totalSize, uploadId: uploadId))

        return try await Self.continueResumableUpload(
          httpClient: httpClient,
          source: &source,
          uploadId: uploadId,
          offset: status.nextOffset,
          crc32cSeed: status.crc32cSeed,
          chunkSize: options.chunkSize,
          totalSize: totalSize,
          options: options,
          continuation: continuation,
          retryPolicy: effectiveRetryPolicy,
          backoffPolicy: effectiveBackoffPolicy
        )
      }
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
      nextOffset = try parseNextRangeStart(rangeHeader)
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

  internal func parseNextRangeStart(_ rangeHeader: String) throws -> Int64 {
    let range = try parseRangeHeader(rangeHeader)
    guard let end = range.end else {
      throw UploadError.invalidRangeHeader(rangeHeader)
    }
    return end + 1
  }

  internal func parseRangeHeader(_ rangeHeader: String) throws -> (start: Int64?, end: Int64?) {
    guard rangeHeader.hasPrefix("bytes=") else {
      throw UploadError.invalidRangeHeader(rangeHeader)
    }
    let rangeStr = rangeHeader.dropFirst(6)
    let parts = rangeStr.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
      throw UploadError.invalidRangeHeader(rangeHeader)
    }

    let startStr = parts[0]
    let endStr = parts[1]

    let start = startStr.isEmpty ? nil : Int64(startStr)
    let end = endStr.isEmpty ? nil : Int64(endStr)

    if start == nil && end == nil {
      throw UploadError.invalidRangeHeader(rangeHeader)
    }

    if let s = start, let e = end, s > e {
      throw UploadError.invalidRangeHeader(rangeHeader)
    }

    return (start, end)
  }

  fileprivate func handleObjectResponse(data: Data, response: HTTPURLResponse) throws
    -> StorageObject
  {
    guard (200..<300).contains(response.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? ""
      throw UploadError.unexpectedServerResponse(
        statusCode: response.statusCode, message: message)
    }
    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    return try decoder.decode(StorageObject.self, from: data)
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

fileprivate enum Either<L, R> {
  case left(L)
  case right(R)
}

fileprivate struct ChunkUploadResult: Sendable {
  let responseData: Data
  let response: HTTPURLResponse
  let chunkCount: Int64
  let effectiveTotalSize: Int64?
}

extension HTTPClient {
  fileprivate func sendRequestWithMappedError(_ request: URLRequest) async throws -> (
    Data, HTTPURLResponse
  ) {
    do {
      let (data, response) = try await self.data(for: request)
      return (data, response)
    } catch let e as RequestError {
      throw e
    } catch let e {
      throw RequestError.io(e)
    }
  }
}

fileprivate func mapToPublicError(_ error: Error) -> Error {
  if let reqErr = error as? RequestError {
    switch reqErr {
    case .http(let details):
      return UploadError.unexpectedServerResponse(
        statusCode: details.http_status_code,
        message: String(data: details.payload, encoding: .utf8) ?? ""
      )
    case .io(let inner):
      return inner
    case .exhausted(let limitErr):
      return mapToPublicError(limitErr.source)
    default:
      return reqErr
    }
  }
  return error
}
