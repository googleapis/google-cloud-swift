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

public import Foundation
@_spi(GoogleCloudInternal) package import GoogleGax
import NIOCore

/// A handle to an in-progress or deferred object download returned by ``StorageClient/readObject(from:object:options:)``.
///
/// `ReadObjectHandle` provides access to both the object's initial response metadata (``metadata``)
/// and its streaming payload (``body``). The network request is started lazily when either
/// ``metadata`` or ``body`` is first awaited.
///
/// The download automatically participates in structured concurrency cancellation: cancelling the
/// enclosing Swift `Task` while awaiting ``metadata`` or iterating ``body`` cancels the underlying
/// download and throws `CancellationError`. You can also call ``cancel()`` to terminate the
/// download early (for example, after inspecting ``metadata`` without consuming ``body``).
///
/// ```swift
/// let download = client.readObject(from: "my-bucket", object: "file.txt")
/// let metadata = try await download.metadata
/// for try await chunk in download.body {
///   // Process ByteChunk chunk
/// }
/// ```
public struct ReadObjectHandle: Sendable {
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

/// Metadata attributes for an object returned in response headers during a download.
public struct ReadObjectMetadata: Sendable, Hashable, Equatable {
  /// Name of the bucket containing the object.
  public var bucket: String = ""

  /// Name of the object.
  public var object: String = ""

  /// Content size of the object payload in bytes.
  public var size: UInt64 = 0

  /// Stored content length of the object before decompressive transcoding (if applicable).
  public var storedContentLength: UInt64?

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

/// An asynchronous sequence of `ByteChunk` chunks representing an object payload being downloaded.
public struct ReadObjectSequence: AsyncSequence, Sendable {
  public typealias Element = ByteChunk

  private let coordinator: ReadObjectCoordinator

  package init(coordinator: ReadObjectCoordinator) {
    self.coordinator = coordinator
  }

  /// An asynchronous iterator for iterating over chunks of downloaded object payload data.
  public struct AsyncIterator: AsyncIteratorProtocol {
    public typealias Element = ByteChunk

    private let coordinator: ReadObjectCoordinator

    package init(coordinator: ReadObjectCoordinator) {
      self.coordinator = coordinator
    }

    /// Advances to the next `ByteChunk` chunk in the downloaded object payload stream.
    public mutating func next() async throws -> ByteChunk? {
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
  let httpClient: GoogleGax._HTTPClient
  let resumeLoop: _ResumeLoop<ReadObjectDetails>

  private let lock = NSLock()
  private var isInitialFetched: Bool = false
  private var initialFetchTask: Task<ReadObjectMetadata, Error>?
  private var metadata: ReadObjectMetadata?
  private var bodyIterator: _HTTPResponseBody.AsyncIterator?
  private var streamIterator: AsyncThrowingStream<NIOCore.ByteBuffer, Error>.AsyncIterator?
  private var bytesReceived: UInt64 = 0
  private var resumeState: ResumeState<ReadObjectDetails>
  private var isFinished: Bool = false
  private var isCancelled: Bool = false
  private var crc32cCalculator: CRC32CCalculator?
  private var md5Calculator: MD5Calculator?
  private var hasValidatedChecksums: Bool = false

  package init(
    bucket: String,
    object: String,
    options: ReadObjectOptions,
    httpClient: GoogleGax._HTTPClient,
    resumeLoop: _ResumeLoop<ReadObjectDetails>
  ) {
    self.bucket = bucket
    self.object = object
    self.options = options
    self.httpClient = httpClient
    self.resumeLoop = resumeLoop
    self.resumeState = ResumeState(details: ReadObjectDetails())
    if options.checksums.crc32c != nil {
      self.crc32cCalculator = CRC32CCalculator()
    }
    if options.checksums.md5 != nil {
      self.md5Calculator = MD5Calculator()
    }
  }

  private var cancelled: Bool {
    lock.withLock { isCancelled }
  }

  private func ensureInitialFetch() async throws -> ReadObjectMetadata {
    let task = lock.withLock { () -> Task<ReadObjectMetadata, Error>? in
      if self.isCancelled {
        return nil
      }
      if let existing = self.initialFetchTask {
        return existing
      }
      let newTask = Task { () throws -> ReadObjectMetadata in
        let (response, metadata) = try await Self.fetchInitial(
          httpClient: self.httpClient,
          bucket: self.bucket,
          object: self.object,
          options: self.options,
          resumeLoop: self.resumeLoop,
          resumeState: self.resumeState
        )
        try self.lock.withLock {
          if self.isCancelled {
            throw CancellationError()
          }
          self.metadata = metadata
          self.bodyIterator = response.body.makeAsyncIterator()
          self.isInitialFetched = true
        }
        return metadata
      }
      self.initialFetchTask = newTask
      return newTask
    }
    guard let task else {
      throw CancellationError()
    }
    return try await task.value
  }

  package func getMetadata() async throws -> ReadObjectMetadata {
    try await withTaskCancellationHandler {
      if cancelled || Task.isCancelled {
        throw CancellationError()
      }
      return try await ensureInitialFetch()
    } onCancel: {
      self.cancel()
    }
  }

  package func nextChunk() async throws -> ByteChunk? {
    try await withTaskCancellationHandler {
      try await nextChunkImpl()
    } onCancel: {
      self.cancel()
    }
  }

  private func nextChunkImpl() async throws -> ByteChunk? {
    if cancelled || Task.isCancelled {
      throw CancellationError()
    }
    guard !lock.withLock({ isFinished }) else { return nil }

    if case .prefix(0) = options.range {
      lock.withLock { isFinished = true }
      return nil
    }
    if case .suffix(0) = options.range {
      lock.withLock { isFinished = true }
      return nil
    }

    _ = try await ensureInitialFetch()

    while !lock.withLock({ isFinished }) {
      if cancelled || Task.isCancelled {
        throw CancellationError()
      }
      do {
        let nextStreamIt = lock.withLock { self.streamIterator }
        let nextBodyIt = lock.withLock { self.bodyIterator }
        if var it = nextStreamIt {
          let chunk = try await it.next()
          if cancelled || Task.isCancelled {
            throw CancellationError()
          }
          lock.withLock { self.streamIterator = it }
          if let chunk {
            let storage = ByteChunk(chunk)
            bytesReceived += UInt64(storage.count)
            resumeState.details.bytesRead = bytesReceived
            resumeLoop.onProgress(state: &resumeState)
            updateChecksums(with: storage)
            return storage
          } else {
            try validateChecksumsAtEOF()
            lock.withLock { isFinished = true }
            return nil
          }
        } else if var it = nextBodyIt {
          let chunk = try await it.next()
          if cancelled || Task.isCancelled {
            throw CancellationError()
          }
          lock.withLock { self.bodyIterator = it }
          if let chunk {
            let storage = ByteChunk(chunk)
            bytesReceived += UInt64(storage.count)
            resumeState.details.bytesRead = bytesReceived
            resumeLoop.onProgress(state: &resumeState)
            updateChecksums(with: storage)
            return storage
          } else {
            try validateChecksumsAtEOF()
            lock.withLock { isFinished = true }
            return nil
          }
        } else {
          try validateChecksumsAtEOF()
          lock.withLock { isFinished = true }
          return nil
        }
      } catch {
        if error is CancellationError || cancelled || Task.isCancelled {
          lock.withLock { isFinished = true }
          throw CancellationError()
        }
        if error is ReadObjectError {
          lock.withLock { isFinished = true }
          throw error
        }

        let reqError = (error as? RequestError) ?? .io(error)
        do {
          try await resumeLoop.handleError(state: &resumeState, error: reqError)
        } catch let err as RequestError {
          lock.withLock { isFinished = true }
          if case .http = err {
            throw ReadObjectError.requestError(err)
          } else if case .service = err {
            throw ReadObjectError.requestError(err)
          }
          throw ReadObjectError.resumeFailed(
            bytesReceived: bytesReceived, underlyingError: err)
        } catch {
          lock.withLock { isFinished = true }
          throw error
        }

        try await resumeDownload(underlyingError: reqError)
      }
    }

    if cancelled || Task.isCancelled {
      throw CancellationError()
    }
    return nil
  }

  private func updateChecksums(with chunk: ByteChunk) {
    guard crc32cCalculator != nil || md5Calculator != nil else { return }
    chunk.withUnsafeBytes { buffer in
      crc32cCalculator?.update(buffer)
      md5Calculator?.update(buffer)
    }
  }

  private func validateChecksumsAtEOF() throws {
    guard !hasValidatedChecksums else { return }
    hasValidatedChecksums = true

    let currentMetadata = lock.withLock { self.metadata } ?? ReadObjectMetadata()
    let isRangedRead = (options.range != .entire)
    let isDecompressedTranscoding =
      (currentMetadata.storedContentLength != nil && currentMetadata.contentEncoding == nil)

    if let crcOption = options.checksums.crc32c, let calc = crc32cCalculator {
      let actual = calc.finalize()
      switch crcOption {
      case .auto:
        if !isRangedRead && !isDecompressedTranscoding, let expected = currentMetadata.crc32c {
          if actual != expected {
            throw ReadObjectError.checksumMismatch(
              expected: expected,
              actual: actual,
              algorithm: calc.algorithmName
            )
          }
        }
      case .value(let expected):
        if actual != expected {
          throw ReadObjectError.checksumMismatch(
            expected: expected,
            actual: actual,
            algorithm: calc.algorithmName
          )
        }
      }
    }

    if let md5Option = options.checksums.md5, let calc = md5Calculator {
      let actual = calc.finalize()
      switch md5Option {
      case .auto:
        if !isRangedRead && !isDecompressedTranscoding, let expected = currentMetadata.md5Hash {
          if actual != expected {
            throw ReadObjectError.checksumMismatch(
              expected: expected,
              actual: actual,
              algorithm: calc.algorithmName
            )
          }
        }
      case .value(let expected):
        if actual != expected {
          throw ReadObjectError.checksumMismatch(
            expected: expected,
            actual: actual,
            algorithm: calc.algorithmName
          )
        }
      }
    }
  }

  private func resumeDownload(underlyingError: Error) async throws {
    let currentMetadata = lock.withLock { self.metadata } ?? ReadObjectMetadata()
    guard
      let resumeRange = calculateResumeRange(
        originalRange: options.range,
        bytesReceived: bytesReceived,
        totalSize: currentMetadata.size > 0 ? currentMetadata.size : nil
      )
    else {
      lock.withLock { isFinished = true }
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
      let response = try await resumeLoop.run(state: &resumeState) { _ in
        let request = try await httpClient.buildReadObjectRequest(
          bucket: bucket, object: object, options: resumeOptions)
        let resp: _HTTPClientResponse
        do {
          resp = try await request.execute()
        } catch {
          if error is CancellationError || Task.isCancelled {
            throw CancellationError()
          }
          if let reqError = error as? RequestError {
            throw reqError
          }
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
        throw ReadObjectError.unexpectedServerResponse(
          statusCode: statusCode, message: message)
      }
      try lock.withLock {
        if self.isCancelled {
          throw CancellationError()
        }
        self.bodyIterator = response.body.makeAsyncIterator()
        self.streamIterator = nil
      }
    } catch {
      lock.withLock { isFinished = true }
      if error is CancellationError || cancelled || Task.isCancelled {
        throw CancellationError()
      }
      if let downloadError = error as? ReadObjectError {
        throw downloadError
      }
      let reqError = (error as? RequestError) ?? .io(error)
      if case .http = reqError {
        throw ReadObjectError.requestError(reqError)
      } else if case .service = reqError {
        throw ReadObjectError.requestError(reqError)
      }
      throw ReadObjectError.resumeFailed(
        bytesReceived: bytesReceived, underlyingError: reqError)
    }
  }

  package func cancel() {
    let taskToCancel = lock.withLock { () -> Task<ReadObjectMetadata, Error>? in
      isCancelled = true
      isFinished = true
      bodyIterator = nil
      streamIterator = nil
      return initialFetchTask
    }
    taskToCancel?.cancel()
  }

  fileprivate static func fetchInitial(
    httpClient: GoogleGax._HTTPClient,
    bucket: String,
    object: String,
    options: ReadObjectOptions,
    resumeLoop: _ResumeLoop<ReadObjectDetails>,
    resumeState: ResumeState<ReadObjectDetails>
  ) async throws -> (_HTTPClientResponse, ReadObjectMetadata) {
    do {
      return try await resumeLoop.run(state: resumeState) { _ in
        let request = try await httpClient.buildReadObjectRequest(
          bucket: bucket, object: object, options: options)
        let response: _HTTPClientResponse
        do {
          response = try await request.execute()
        } catch {
          if error is CancellationError || Task.isCancelled {
            throw CancellationError()
          }
          if let reqError = error as? RequestError {
            throw reqError
          }
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
        throw ReadObjectError.unexpectedServerResponse(
          statusCode: statusCode, message: message)
      }
    } catch let error as ReadObjectError {
      throw error
    } catch let error as RequestError {
      throw ReadObjectError.requestError(error)
    } catch {
      throw ReadObjectError.requestError(.io(error))
    }
  }
}
