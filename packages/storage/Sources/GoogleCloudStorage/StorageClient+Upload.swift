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
// See the License for theing specific language governing permissions and
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
          continuation: continuation
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
    continuation: AsyncStream<UploadStatus>.Continuation
  ) async throws -> StorageObject {
    let startRequest = try await httpClient.buildStartResumableUploadRequest(
      bucket: bucket, objectName: objectName, metadata: metadata, options: options)
    let (startData, startResponse) = try await httpClient.data(for: startRequest)
    guard startResponse.statusCode == 200,
      let location = startResponse.value(forHTTPHeaderField: "Location")
    else {
      throw UploadError.unexpectedServerResponse(
        statusCode: startResponse.statusCode,
        message: String(data: startData, encoding: .utf8) ?? "")
    }
    let uploadId = location

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
      continuation: continuation
    )
  }

  fileprivate static func continueResumableUpload(
    httpClient: HTTPClient,
    source: inout some UploadSource,
    uploadId: String,
    offset: Int64,
    chunkSize: Int,
    totalSize: Int64?,
    options: UploadOptions,
    continuation: AsyncStream<UploadStatus>.Continuation
  ) async throws -> StorageObject {
    let initialOffset = offset
    var offset = offset
    var checksummedSource = ChecksummedSource(source: source, options: options.checksums)
    while true {
      guard let chunkInfo = try await checksummedSource.readChunk(maxBytes: chunkSize),
        !chunkInfo.data.isEmpty
      else {
        break
      }
      let chunk = chunkInfo.data
      let isLast = chunkInfo.isLast
      let checksum =
        (isLast && (initialOffset == 0 || options.checksums.hasUserProvidedChecksum))
        ? chunkInfo.checksum : nil

      let uploadRequest = try await httpClient.buildUploadChunkRequest(
        uploadId: uploadId, data: chunk, offset: offset, totalSize: totalSize, options: options,
        checksum: checksum)
      let (uploadData, uploadResponse) = try await httpClient.data(for: uploadRequest)

      if uploadResponse.statusCode == 200 || uploadResponse.statusCode == 201 {
        let object = try httpClient.handleObjectResponse(
          data: uploadData, response: uploadResponse)
        continuation.yield(
          UploadStatus(
            bytesUploaded: offset + Int64(chunk.count),
            totalBytes: totalSize, uploadId: uploadId))
        return object
      } else if uploadResponse.statusCode == 308 {
        if let rangeHeader = uploadResponse.value(forHTTPHeaderField: "Range") {
          offset = try httpClient.parseNextRangeStart(rangeHeader)
        } else {
          offset += Int64(chunk.count)
        }
        continuation.yield(
          UploadStatus(
            bytesUploaded: offset, totalBytes: totalSize, uploadId: uploadId))
      } else {
        _ = try httpClient.handleObjectResponse(data: uploadData, response: uploadResponse)
      }
    }

    throw UploadError.internalError("Upload completed but object not returned")
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
    return UploadTask.create { continuation in
      let httpClient = try HTTPClient(
        from: clientOptions, withDefaultEndpoint: Self.defaultEndpoint)
      var source = source
      let totalSize = source.totalSize

      // 1. Query GCS for current status
      let queryRequest = try await httpClient.buildQueryResumableUploadRequest(
        uploadId: uploadId, options: options)
      let (queryData, queryResponse) = try await httpClient.data(for: queryRequest)

      var offset: Int64 = 0
      if queryResponse.statusCode == 200 || queryResponse.statusCode == 201 {
        let object = try httpClient.handleObjectResponse(data: queryData, response: queryResponse)
        continuation.yield(
          UploadStatus(
            bytesUploaded: totalSize ?? 0, totalBytes: totalSize,
            uploadId: uploadId))
        return object
      } else if queryResponse.statusCode == 308 {
        if let rangeHeader = queryResponse.value(forHTTPHeaderField: "Range") {
          offset = try httpClient.parseNextRangeStart(rangeHeader)
        }
      } else {
        throw UploadError.unexpectedServerResponse(
          statusCode: queryResponse.statusCode,
          message: String(data: queryData, encoding: .utf8) ?? "")
      }

      // 2. Seek source to GCS offset
      try await source.seek(to: offset)

      continuation.yield(
        UploadStatus(
          bytesUploaded: offset, totalBytes: totalSize, uploadId: uploadId))

      // 3. Continue upload
      let chunkSize = options.chunkSize
      return try await Self.continueResumableUpload(
        httpClient: httpClient,
        source: &source,
        uploadId: uploadId,
        offset: offset,
        chunkSize: chunkSize,
        totalSize: totalSize,
        options: options,
        continuation: continuation
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

    let end = offset + Int64(data.count) - 1
    let totalStr = totalSize.map { String($0) } ?? "*"
    request.setValue("bytes \(offset)-\(end)/\(totalStr)", forHTTPHeaderField: "Content-Range")
    request.httpBody = data
    return request
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
      if response.statusCode == 400 {
        if let match = StorageClient.parseChecksumMismatch(message) {
          throw UploadError.checksumMismatch(
            localChecksum: match.local, serverChecksum: match.server)
        }
      }
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

  internal static func parseChecksumMismatch(_ message: String) -> (local: String, server: String)?
  {
    let crcRegex = try? NSRegularExpression(
      pattern: "Provided CRC32C \\\\?\"([^\"]+?)\\\\?\".*calculated CRC32C \\\\?\"([^\"]+?)\\\\?\"",
      options: .caseInsensitive)
    if let match = crcRegex?.firstMatch(
      in: message, options: [], range: NSRange(message.startIndex..., in: message))
    {
      if let localRange = Range(match.range(at: 1), in: message),
        let serverRange = Range(match.range(at: 2), in: message)
      {
        let local = String(message[localRange])
        let server = String(message[serverRange])
        return ("crc32c=" + local, "crc32c=" + server)
      }
    }

    let md5Regex = try? NSRegularExpression(
      pattern: "Provided MD5 \\\\?\"([^\"]+?)\\\\?\".*calculated MD5 \\\\?\"([^\"]+?)\\\\?\"",
      options: .caseInsensitive)
    if let match = md5Regex?.firstMatch(
      in: message, options: [], range: NSRange(message.startIndex..., in: message))
    {
      if let localRange = Range(match.range(at: 1), in: message),
        let serverRange = Range(match.range(at: 2), in: message)
      {
        let local = String(message[localRange])
        let server = String(message[serverRange])
        return ("md5=" + local, "md5=" + server)
      }
    }

    return nil
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
