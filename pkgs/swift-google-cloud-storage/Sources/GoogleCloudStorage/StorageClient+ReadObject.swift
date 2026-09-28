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
@_spi(GoogleCloudInternal) package import GoogleGax
import GoogleWKT
import NIOHTTP1

extension StorageClient {
  /// Starts an object download from Cloud Storage.
  ///
  /// Iterate over ``ReadObjectHandleProtocol/body`` on the returned ``ReadObjectHandleProtocol`` to stream the
  /// object's content as an asynchronous sequence of ``ByteChunk`` chunks, or `await`
  /// ``ReadObjectHandleProtocol/metadata`` to inspect the object's metadata.
  ///
  /// ```swift
  /// let download = client.readObject(from: "my-bucket", object: "file.txt")
  /// for try await chunk in download.body {
  ///   // Process ByteChunk chunk
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - bucket: The GCS bucket name.
  ///   - object: The GCS object name.
  ///   - options: Configuration options for the read operation.
  /// - Returns: A ``ReadObjectHandleProtocol`` providing access to the object's ``ReadObjectHandleProtocol/metadata`` and streaming ``ReadObjectHandleProtocol/body``.
  public func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions = .init()
  ) -> any ReadObjectHandleProtocol {
    let effectiveOptions = options.withDefaults(self.options.readObject)
    let resumeLoop = _ResumeLoop(
      resumePolicy: effectiveOptions.resumePolicy
        ?? StorageResumePolicy<ReadObjectDetails>.defaultPolicy,
      backoffPolicy: effectiveOptions.backoffPolicy ?? self.options.client.backoffPolicy
    )

    let coordinator = ReadObjectCoordinator(
      bucket: bucket,
      object: object,
      options: effectiveOptions,
      httpClient: inner,
      resumeLoop: resumeLoop
    )
    return ReadObjectHandle(coordinator: coordinator)
  }

  internal static func parseReadObjectMetadata(
    from headers: NIOHTTP1.HTTPHeaders,
    bucket: String,
    object: String
  ) throws -> ReadObjectMetadata {
    var metadata = ReadObjectMetadata()
    metadata.bucket = BucketName.formatResourceName(bucket)
    metadata.name = object

    if let contentRangeHeader = headers.first(name: "Content-Range") {
      let contentRange = try HttpContentRange.parse(contentRangeHeader)
      if let total = contentRange.totalSize {
        metadata.size = total
      }
    } else if let sizeStr = headers.first(name: "x-goog-stored-content-length")
      ?? headers.first(name: "Content-Length"),
      let size = UInt64(sizeStr)
    {
      metadata.size = size
    }

    if let storedLengthStr = headers.first(name: "x-goog-stored-content-length"),
      let storedLength = UInt64(storedLengthStr)
    {
      metadata.storedContentLength = storedLength
    }

    if let genStr = headers.first(name: "x-goog-generation"),
      let gen = Int64(genStr)
    {
      metadata.generation = gen
    }

    if let metaGenStr = headers.first(name: "x-goog-metageneration"),
      let metaGen = Int64(metaGenStr)
    {
      metadata.metageneration = metaGen
    }

    metadata.etag = headers.first(name: "ETag")
    metadata.contentType = headers.first(name: "Content-Type")
    metadata.contentEncoding = headers.first(name: "Content-Encoding")
    metadata.contentDisposition = headers.first(name: "Content-Disposition")
    metadata.storageClass = headers.first(name: "x-goog-storage-class")

    let (rawCrc, rawMd5) = extractExpectedChecksums(from: headers)
    var checksums = ObjectChecksums()
    var hasChecksums = false
    if let rawCrc, let data = Data(base64Encoded: rawCrc), data.count == 4 {
      let idx = data.startIndex
      let val =
        (UInt32(data[idx]) << 24)
        | (UInt32(data[idx + 1]) << 16)
        | (UInt32(data[idx + 2]) << 8)
        | UInt32(data[idx + 3])
      checksums.crc32C = val
      hasChecksums = true
    }
    if let rawMd5, let data = Data(base64Encoded: rawMd5), !data.isEmpty {
      checksums.md5Hash = data
      hasChecksums = true
    }
    if hasChecksums {
      metadata.checksums = checksums
    }

    if let dateStr = headers.first(name: "Last-Modified")
      ?? headers.first(name: "Date")
      ?? headers.first(name: "x-goog-date")
    {
      metadata.updateTime = parseHTTPDate(dateStr)
    }

    return metadata
  }

  internal static func extractExpectedChecksums(
    from headers: NIOHTTP1.HTTPHeaders
  ) -> (crc32c: String?, md5: String?) {
    var crc32c: String?
    var md5: String?
    if let hashHeader = headers.first(name: "x-goog-hash") {
      (crc32c, md5) = parseGoogHash(hashHeader)
    }
    if md5 == nil, let contentMd5 = headers.first(name: "Content-MD5") {
      md5 = contentMd5
    }
    return (crc32c, md5)
  }

  fileprivate static func parseGoogHash(_ headerValue: String) -> (crc32c: String?, md5: String?) {
    var crc32c: String?
    var md5: String?
    let parts = headerValue.split(separator: ",")
    for part in parts {
      let trimmed = part.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("crc32c=") {
        crc32c = String(trimmed.dropFirst("crc32c=".count))
      } else if trimmed.hasPrefix("md5=") {
        md5 = String(trimmed.dropFirst("md5=".count))
      }
    }
    return (crc32c, md5)
  }

  fileprivate static func parseHTTPDate(_ string: String) -> GoogleWKT.WKTTimestamp? {
    let date: Date?
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let parsed = formatter.date(from: string) {
      date = parsed
    } else {
      let isoFormatter = ISO8601DateFormatter()
      isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let parsed = isoFormatter.date(from: string) {
        date = parsed
      } else {
        isoFormatter.formatOptions = [.withInternetDateTime]
        date = isoFormatter.date(from: string)
      }
    }

    guard let date else { return nil }
    let interval = date.timeIntervalSince1970
    let wholeSeconds = floor(interval)
    var seconds = Int64(wholeSeconds)
    var nanos = Int32(((interval - wholeSeconds) * 1_000_000_000).rounded())
    if nanos >= 1_000_000_000 {
      seconds += 1
      nanos -= 1_000_000_000
    }
    return try? GoogleWKT.WKTTimestamp(seconds: seconds, nanos: nanos)
  }
}

extension GoogleGax._HTTPClient {
  package func buildReadObjectRequest(
    bucket: String,
    object: String,
    options: ReadObjectOptions
  ) async throws -> GoogleGax._HTTPClientRequest {
    var queryItems = [URLQueryItem(name: "alt", value: "media")]

    if let generation = options.generation {
      queryItems.append(URLQueryItem(name: "generation", value: String(generation)))
    }
    if let preconditions = options.preconditions {
      queryItems.append(contentsOf: preconditions.queryItems)
    }

    let allowedObjectCharacters = CharacterSet.urlPathAllowed.subtracting(
      CharacterSet(charactersIn: "/"))
    let encodedObject =
      object.addingPercentEncoding(withAllowedCharacters: allowedObjectCharacters) ?? object
    let bucketId = BucketName.extractBucketName(bucket)
    let encodedBucket =
      bucketId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bucketId
    var request = try await self.newRequest(
      percentEncodedPath: "/storage/v1/b/\(encodedBucket)/o/\(encodedObject)",
      query: queryItems,
      options: options.requestOptions)
    request.setMethod(.GET)

    if let rangeHeader = options.range?.headerValue {
      request.setHeader(name: "Range", value: rangeHeader)
    }

    if options.enableDecompressiveTranscoding != true {
      request.setHeader(name: "Accept-Encoding", value: "gzip")
    }

    request.applyCustomerSuppliedEncryptionHeaders(options.customerEncryptionKey)

    return request
  }
}

extension GoogleGax._HTTPClientRequest {
  package mutating func applyCustomerSuppliedEncryptionHeaders(
    _ key: CustomerEncryptionKeyOptions?
  ) {
    guard let key else { return }
    setHeader(name: "x-goog-encryption-algorithm", value: key.algorithm.rawValue)
    setHeader(name: "x-goog-encryption-key", value: key.keyBase64)
    setHeader(name: "x-goog-encryption-key-sha256", value: key.keyHashBase64)
  }
}
