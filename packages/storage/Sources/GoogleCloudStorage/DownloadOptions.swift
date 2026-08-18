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
@_spi(GoogleCloudInternal) import GoogleCloudGax
import struct NIOCore.ByteBuffer

/// Specifies a byte range for ranged reads.
public enum ReadObjectRange: Sendable, Hashable, Equatable {
  /// Read the entire object (default).
  case entire

  /// Read all bytes starting from `offset` to the end of the object (HTTP `bytes=N-`).
  case fromOffset(UInt64)

  /// Read the first `count` bytes of the object (HTTP `bytes=0-N`).
  case prefix(UInt64)

  /// Read the last `count` bytes of the object (HTTP `bytes=-N`).
  case suffix(UInt64)

  /// Read a bounded range of bytes from `start` to `end` inclusive (HTTP `bytes=start-end`).
  case bounded(start: UInt64, end: UInt64)

  /// Convenience initializer for Swift `ClosedRange<UInt64>`.
  public init(_ range: ClosedRange<UInt64>) {
    self = .bounded(start: range.lowerBound, end: range.upperBound)
  }

  /// Converts the range specification to an HTTP `Range` header value string.
  public var headerValue: String? {
    switch self {
    case .entire:
      return nil
    case .fromOffset(let offset):
      return "bytes=\(offset)-"
    case .prefix(let count):
      return count > 0 ? "bytes=0-\(count - 1)" : "bytes=0-0"
    case .suffix(let count):
      return "bytes=-\(count)"
    case .bounded(let start, let end):
      return "bytes=\(start)-\(end)"
    }
  }
}

/// Represents a parsed HTTP `Content-Range` response header.
struct HttpContentRange: Sendable, Hashable, Equatable {
  let start: UInt64
  let end: UInt64
  let totalSize: UInt64?

  init(start: UInt64, end: UInt64, totalSize: UInt64? = nil) {
    self.start = start
    self.end = end
    self.totalSize = totalSize
  }

  /// Parses an HTTP `Content-Range` header value (e.g., `"bytes 0-499/1000"`).
  static func parse(_ header: String) throws -> HttpContentRange {
    let trimmed = header.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("bytes ") else {
      throw DownloadError.invalidRangeHeader(header)
    }
    let spec = trimmed.dropFirst("bytes ".count).trimmingCharacters(in: .whitespaces)
    let parts = spec.split(separator: "/")
    guard parts.count == 2 else {
      throw DownloadError.invalidRangeHeader(header)
    }
    let rangeParts = parts[0].split(separator: "-")
    guard rangeParts.count == 2,
      let start = UInt64(rangeParts[0]),
      let end = UInt64(rangeParts[1])
    else {
      throw DownloadError.invalidRangeHeader(header)
    }
    guard start <= end else {
      throw DownloadError.invalidRangeHeader(header)
    }
    let totalSizeStr = parts[1]
    let totalSize: UInt64?
    if totalSizeStr == "*" {
      totalSize = nil
    } else if let total = UInt64(totalSizeStr) {
      totalSize = total
    } else {
      throw DownloadError.invalidRangeHeader(header)
    }
    return HttpContentRange(start: start, end: end, totalSize: totalSize)
  }
}

/// Configuration options for object download (`readObject`) requests.
///
/// Use `ReadObjectOptions` to customize download behaviors when calling `StorageClient.readObject(...)`.
/// Options include specifying byte ranges for partial reads, object generation revisions, preconditions,
/// Customer-Supplied Encryption Keys (CSEK), checksum validation, decompressive transcoding, and auto-resumption.
///
/// ## Configuration Styles
///
/// Configure `ReadObjectOptions` using the `.with` closure builder.
///
/// ```swift
/// let options = ReadObjectOptions().with {
///   $0.range = .bounded(start: 0, end: 1024)
///   $0.autoResume = true
/// }
/// ```
///
/// ## Key Configuration Features
///
/// ### Customer-Supplied Encryption Keys (CSEK)
///
/// Download objects encrypted with a Customer-Supplied Encryption Key (CSEK) by providing `CustomerEncryptionKeyOptions`:
///
/// ```swift
/// let csek = try CustomerEncryptionKeyOptions(keyBase64: "your-base64-encoded-256bit-key==")
/// let options = ReadObjectOptions().with {
///   $0.customerEncryptionKey = csek
/// }
///
/// let response = try await client.readObject(from: "my-bucket", object: "encrypted.bin", options: options)
/// ```
///
/// ### Ranged Reads
///
/// Read specific byte ranges using `ReadObjectRange`:
///
/// ```swift
/// let options = ReadObjectOptions().with {
///   $0.range = .fromOffset(1024) // Read from byte 1024 to the end
/// }
/// ```
///
/// ### Preconditions
///
/// Apply preconditions to the download operation:
///
/// ```swift
/// let options = ReadObjectOptions().with {
///   $0.preconditions = StoragePreconditions().with {
///     $0.ifGenerationMatch = 12345
///   }
/// }
/// ```
public struct ReadObjectOptions: Sendable {
  /// Object generation (`UInt64?`) to read a specific revision of an object.
  public var generation: UInt64?

  /// Preconditions to ensure operations execute only when condition constraints pass.
  public var preconditions: StoragePreconditions?

  /// Options for Customer-Supplied Encryption Keys (CSEK).
  public var customerEncryptionKey: CustomerEncryptionKeyOptions?

  /// Byte range for partial/ranged reads. Defaults to `.entire`.
  public var range: ReadObjectRange = .entire

  /// Flag to enable automatic decompressive transcoding by GCS. Defaults to `true`.
  public var enableDecompressiveTranscoding: Bool = true

  /// Checksum options for validating data integrity.
  public var checksums: ChecksumOptions = .default

  /// Flag to enable transparent auto-resumption on transient network failures. Defaults to `true`.
  public var autoResume: Bool = true

  /// Overrides the retry policy for this download.
  public var retryPolicy: (any RetryPolicy)? = nil

  /// Overrides the backoff policy for this download.
  public var backoffPolicy: (any BackoffPolicy)? = nil

  /// Default configuration options.
  public static var `default`: ReadObjectOptions { ReadObjectOptions() }

  /// Creates a new `ReadObjectOptions` instance.
  public init() {}

  /// Builder pattern helper to modify configuration in place.
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// Calculates the remaining range to request when resuming an interrupted download.
///
/// - Parameters:
///   - originalRange: The range requested in the original download operation.
///   - bytesReceived: The number of bytes successfully received and yielded so far.
///   - totalSize: The total size of the object if known from metadata or headers.
/// - Returns: The adjusted `ReadObjectRange` to request, or `nil` if all requested bytes have been received.
package func calculateResumeRange(
  originalRange: ReadObjectRange,
  bytesReceived: UInt64,
  totalSize: UInt64?
) -> ReadObjectRange? {
  switch originalRange {
  case .entire:
    return .fromOffset(bytesReceived)
  case .fromOffset(let offset):
    return .fromOffset(offset + bytesReceived)
  case .prefix(let count):
    guard count > bytesReceived else { return nil }
    return .bounded(start: bytesReceived, end: count - 1)
  case .bounded(let start, let end):
    let newStart = start + bytesReceived
    guard newStart <= end else { return nil }
    return .bounded(start: newStart, end: end)
  case .suffix(let count):
    guard let totalSize = totalSize, totalSize > 0 else {
      return .fromOffset(bytesReceived)
    }
    let startOffset = totalSize > count ? (totalSize - count) : 0
    let newStart = startOffset + bytesReceived
    guard newStart < totalSize else { return nil }
    return .bounded(start: newStart, end: totalSize - 1)
  }
}

/// Metadata attributes for an object returned in response headers during a download.
public struct ReadObjectMetadata: Sendable, Hashable, Equatable {
  /// Name of the bucket containing the object.
  public var bucket: String = ""

  /// Name of the object.
  public var object: String = ""

  /// Content size of the object payload in bytes.
  public var size: UInt64 = 0

  /// Generation revision number of the object.
  public var generation: UInt64 = 0

  /// Metageneration revision number of the object metadata.
  public var metageneration: UInt64?

  /// HTTP ETag representing the object's entity state.
  public var etag: String?

  /// Base64-encoded CRC32C checksum of the object content.
  public var crc32c: String?

  /// Base64-encoded MD5 hash of the object content.
  public var md5Hash: String?

  /// Content-Type MIME type of the object data (e.g., "text/plain", "image/png").
  public var contentType: String?

  /// Content-Encoding header of the object data (e.g., "gzip").
  public var contentEncoding: String?

  /// Content-Disposition header of the object data (e.g., "inline", "attachment; filename=...").
  public var contentDisposition: String?

  /// Storage class of the object (e.g., "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE").
  public var storageClass: String?

  /// Modification timestamp of the object.
  public var updated: Date?

  /// Creates a new `ReadObjectMetadata` instance.
  public init() {}

  /// Builder pattern helper to modify configuration in place.
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// An asynchronous sequence of `ByteBuffer` chunks representing an object payload being downloaded.
public struct ReadObjectSequence: AsyncSequence, Sendable {
  public typealias Element = NIOCore.ByteBuffer

  private let coordinator: ReadObjectCoordinator

  package init(coordinator: ReadObjectCoordinator) {
    self.coordinator = coordinator
  }

  /// An asynchronous iterator for iterating over chunks of downloaded object payload data.
  public struct AsyncIterator: AsyncIteratorProtocol {
    public typealias Element = NIOCore.ByteBuffer

    private let coordinator: ReadObjectCoordinator

    package init(coordinator: ReadObjectCoordinator) {
      self.coordinator = coordinator
    }

    /// Advances to the next `ByteBuffer` chunk in the downloaded object payload stream.
    public mutating func next() async throws -> NIOCore.ByteBuffer? {
      try await coordinator.nextChunk()
    }
  }

  /// Creates an asynchronous iterator for iterating over object payload chunks.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(coordinator: coordinator)
  }
}

/// Coordinates the deferred initial request, metadata resolution, and streaming body consumption.
package final class ReadObjectCoordinator: @unchecked Sendable {
  let bucket: String
  let object: String
  let options: ReadObjectOptions
  let httpClient: GoogleCloudGax._HTTPClient
  let retryLoop: _RetryLoop

  private let lock = NSLock()
  private var isInitialFetched: Bool = false
  private var initialFetchTask: Task<ReadObjectMetadata, Error>?
  private var metadata: ReadObjectMetadata?
  private var bodyIterator: _HTTPResponseBody.AsyncIterator?
  private var streamIterator: AsyncThrowingStream<NIOCore.ByteBuffer, Error>.AsyncIterator?
  private var bytesReceived: UInt64 = 0
  private var isFinished: Bool = false
  private var isCancelled: Bool = false

  package init(
    bucket: String,
    object: String,
    options: ReadObjectOptions,
    httpClient: GoogleCloudGax._HTTPClient,
    retryLoop: _RetryLoop
  ) {
    self.bucket = bucket
    self.object = object
    self.options = options
    self.httpClient = httpClient
    self.retryLoop = retryLoop
  }

  private func ensureInitialFetch() async throws -> ReadObjectMetadata {
    if isCancelled {
      throw CancellationError()
    }
    let task = lock.withLock {
      if let existingTask = initialFetchTask {
        return existingTask
      }
      let newTask = Task { () -> ReadObjectMetadata in
        let (response, metadata) = try await Self.fetchInitial(
          httpClient: self.httpClient,
          bucket: self.bucket,
          object: self.object,
          options: self.options,
          retryLoop: self.retryLoop
        )
        self.lock.withLock {
          self.metadata = metadata
          self.bodyIterator = response.body.makeAsyncIterator()
          self.isInitialFetched = true
        }
        return metadata
      }
      self.initialFetchTask = newTask
      return newTask
    }
    return try await task.value
  }

  package func getMetadata() async throws -> ReadObjectMetadata {
    if isCancelled {
      throw CancellationError()
    }
    return try await ensureInitialFetch()
  }

  package func nextChunk() async throws -> NIOCore.ByteBuffer? {
    guard !isFinished && !isCancelled else { return nil }

    if case .prefix(0) = options.range {
      isFinished = true
      return nil
    }
    if case .suffix(0) = options.range {
      isFinished = true
      return nil
    }

    _ = try await ensureInitialFetch()

    while !isFinished && !isCancelled {
      do {
        if var it = streamIterator {
          let chunk = try await it.next()
          self.streamIterator = it
          if let chunk {
            bytesReceived += UInt64(chunk.readableBytes)
            return chunk
          } else {
            isFinished = true
            return nil
          }
        } else if var it = bodyIterator {
          let chunk = try await it.next()
          self.bodyIterator = it
          if let chunk {
            bytesReceived += UInt64(chunk.readableBytes)
            return chunk
          } else {
            isFinished = true
            return nil
          }
        } else {
          isFinished = true
          return nil
        }
      } catch {
        guard options.autoResume else {
          isFinished = true
          throw error
        }

        try await resumeDownload(underlyingError: error)
      }
    }

    return nil
  }

  private func resumeDownload(underlyingError: Error) async throws {
    let currentMetadata = self.metadata ?? ReadObjectMetadata()
    guard
      let resumeRange = calculateResumeRange(
        originalRange: options.range,
        bytesReceived: bytesReceived,
        totalSize: currentMetadata.size > 0 ? currentMetadata.size : nil
      )
    else {
      isFinished = true
      return
    }

    var resumeOptions = options
    resumeOptions.range = resumeRange
    if resumeOptions.generation == nil && currentMetadata.generation > 0 {
      resumeOptions.generation = currentMetadata.generation
    }

    let httpClient = self.httpClient
    let bucket = self.bucket
    let object = self.object

    do {
      let response = try await retryLoop.run { _ in
        let request = try await httpClient.buildReadObjectRequest(
          bucket: bucket, object: object, options: resumeOptions)
        let resp: _HTTPClientResponse
        do {
          resp = try await request.execute()
        } catch {
          throw RequestError.io(error)
        }
        let statusCode = Int(resp.status.code)
        if (200..<300).contains(statusCode) {
          return resp
        }
        if resp.isError() {
          throw await resp.decodeError()
        }
        let data = try await resp.data()
        let message = String(data: data, encoding: .utf8) ?? ""
        throw DownloadError.unexpectedServerResponse(
          statusCode: statusCode, message: message)
      }
      self.bodyIterator = response.body.makeAsyncIterator()
      self.streamIterator = nil
    } catch {
      isFinished = true
      if let downloadError = error as? DownloadError {
        throw downloadError
      }
      if let reqError = error as? RequestError {
        if case .http(let details) = reqError {
          let message = String(data: details.payload, encoding: .utf8) ?? ""
          throw DownloadError.unexpectedServerResponse(
            statusCode: details.http_status_code, message: message)
        }
      }
      throw DownloadError.resumeFailed(
        bytesReceived: bytesReceived, message: error.localizedDescription)
    }
  }

  package func cancel() {
    isCancelled = true
    isFinished = true
    initialFetchTask?.cancel()
  }

  fileprivate static func fetchInitial(
    httpClient: GoogleCloudGax._HTTPClient,
    bucket: String,
    object: String,
    options: ReadObjectOptions,
    retryLoop: _RetryLoop
  ) async throws -> (_HTTPClientResponse, ReadObjectMetadata) {
    if case .bounded(let start, let end) = options.range {
      guard start <= end else {
        throw DownloadError.invalidRangeHeader("Range start (\(start)) must be <= end (\(end)).")
      }
    }
    do {
      return try await retryLoop.run { _ in
        let request = try await httpClient.buildReadObjectRequest(
          bucket: bucket, object: object, options: options)
        let response: _HTTPClientResponse
        do {
          response = try await request.execute()
        } catch {
          throw RequestError.io(error)
        }
        let statusCode = Int(response.status.code)
        if (200..<300).contains(statusCode) {
          let metadata = try StorageClient.parseReadObjectMetadata(
            from: response.headers, bucket: bucket, object: object)
          return (response, metadata)
        }
        if response.isError() {
          throw await response.decodeError()
        }
        let data = try await response.data()
        let message = String(data: data, encoding: .utf8) ?? ""
        throw DownloadError.unexpectedServerResponse(
          statusCode: statusCode, message: message)
      }
    } catch let error as RequestError {
      if case .http(let details) = error {
        let message = String(data: details.payload, encoding: .utf8) ?? ""
        throw DownloadError.unexpectedServerResponse(
          statusCode: details.http_status_code, message: message)
      } else if case .service(let details) = error {
        throw DownloadError.unexpectedServerResponse(
          statusCode: 500, message: details.message)
      } else {
        throw error
      }
    }
  }
}

/// Container object returned by `readObject` containing metadata and the streaming body sequence.
public struct ReadObjectTask: Sendable {
  private let coordinator: ReadObjectCoordinator

  package init(coordinator: ReadObjectCoordinator) {
    self.coordinator = coordinator
  }

  /// Object metadata extracted from initial HTTP response headers.
  public var metadata: ReadObjectMetadata {
    get async throws {
      try await coordinator.getMetadata()
    }
  }

  /// Asynchronous sequence yielding chunks of binary data payload.
  public var body: ReadObjectSequence {
    ReadObjectSequence(coordinator: coordinator)
  }

  /// Cancels the ongoing download.
  public func cancel() {
    coordinator.cancel()
  }
}
