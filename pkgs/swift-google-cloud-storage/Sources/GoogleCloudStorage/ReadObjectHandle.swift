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
@_spi(GoogleCloudInternal) import GoogleGax
public import GoogleWKT
import NIOCore
import NIOHTTP1

/// A handle to an in-progress or deferred object download returned by ``StorageProtocol/readObject(from:object:options:)``.
///
/// `ReadObjectHandleProtocol` provides access to both the object's initial response metadata (``metadata``)
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
public protocol ReadObjectHandleProtocol: Sendable {
  /// Object metadata extracted from initial HTTP response headers.
  var metadata: ReadObjectMetadata { get async throws }

  /// Asynchronous sequence yielding chunks of binary data payload.
  ///
  /// - Important: This sequence is single-pass and can only be iterated once. Creating a second
  ///   iterator and advancing it throws a ``ReadObjectError``.
  var body: any AsyncSequence<ByteChunk, any Error> & Sendable { get }

  /// Cancels the ongoing download.
  func cancel()
}

extension ReadObjectHandleProtocol {
  /// Object metadata extracted from initial HTTP response headers.
  public var metadata: ReadObjectMetadata {
    get async throws {
      throw GoogleGax.RequestError.unimplemented
    }
  }

  /// Asynchronous sequence yielding chunks of binary data payload.
  public var body: any AsyncSequence<ByteChunk, any Error> & Sendable {
    AsyncThrowingStream { continuation in
      continuation.finish(throwing: GoogleGax.RequestError.unimplemented)
    }
  }

  /// Cancels the ongoing download.
  public func cancel() {}
}

struct ReadObjectHandle: ReadObjectHandleProtocol, Sendable {
  private let coordinator: ReadObjectCoordinator

  init(coordinator: ReadObjectCoordinator) {
    self.coordinator = coordinator
  }

  var metadata: ReadObjectMetadata {
    get async throws {
      try await coordinator.getMetadata()
    }
  }

  var body: any AsyncSequence<ByteChunk, any Error> & Sendable {
    ReadObjectSequence(coordinator: coordinator)
  }

  func cancel() {
    coordinator.cancel()
  }
}

/// Metadata attributes for an object returned in response headers during a download.
public struct ReadObjectMetadata: Sendable, Hashable, Equatable {
  /// Name of the bucket containing the object.
  public var bucket: String = ""

  /// Name of the object.
  public var name: String = ""

  /// Content size of the object payload in bytes.
  public var size: UInt64 = 0

  /// Stored content length of the object before decompressive transcoding (if applicable).
  public var storedContentLength: UInt64?

  /// Generation revision number of the object.
  public var generation: Int64 = 0

  /// Metageneration revision number of the object metadata.
  public var metageneration: Int64?

  /// HTTP ETag representing the object's entity state.
  public var etag: String?

  /// Hashes for the data of the object.
  public var checksums: ObjectChecksums? = nil

  /// Content-Type MIME type of the object data (e.g., "text/plain", "image/png").
  public var contentType: String?

  /// Content-Encoding header of the object data (e.g., "gzip").
  public var contentEncoding: String?

  /// Content-Disposition header of the object data (e.g., "inline", "attachment; filename=...").
  public var contentDisposition: String?

  /// Storage class of the object (e.g., "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE").
  public var storageClass: String?

  /// Modification timestamp of the object.
  public var updateTime: GoogleWKT.WKTTimestamp? = nil

  /// Creates a new `ReadObjectMetadata` instance.
  public init() {}

  /// Builder pattern helper to modify configuration in place.
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(bucket)
    hasher.combine(name)
    hasher.combine(size)
    hasher.combine(storedContentLength)
    hasher.combine(generation)
    hasher.combine(metageneration)
    hasher.combine(etag)
    hasher.combine(checksums != nil)
    hasher.combine(checksums?.crc32C)
    hasher.combine(checksums?.md5Hash)
    hasher.combine(contentType)
    hasher.combine(contentEncoding)
    hasher.combine(contentDisposition)
    hasher.combine(storageClass)
    hasher.combine(updateTime)
  }
}

struct ReadObjectBodyAlreadyConsumedError: Error, Sendable, CustomStringConvertible {
  var description: String {
    "ReadObjectHandle.body is a single-pass stream and cannot be iterated more than once."
  }
}

/// An asynchronous sequence of `ByteChunk` chunks representing an object payload being downloaded.
struct ReadObjectSequence: AsyncSequence, Sendable {
  typealias Element = ByteChunk

  private let coordinator: ReadObjectCoordinator

  init(coordinator: ReadObjectCoordinator) {
    self.coordinator = coordinator
  }

  /// An asynchronous iterator for iterating over chunks of downloaded object payload data.
  struct AsyncIterator: AsyncIteratorProtocol {
    typealias Element = ByteChunk

    private let coordinator: ReadObjectCoordinator
    private let isOwner: Bool

    init(coordinator: ReadObjectCoordinator, isOwner: Bool) {
      self.coordinator = coordinator
      self.isOwner = isOwner
    }

    /// Advances to the next `ByteChunk` chunk in the downloaded object payload stream.
    mutating func next() async throws -> ByteChunk? {
      guard isOwner else {
        throw ReadObjectError.requestError(.io(ReadObjectBodyAlreadyConsumedError()))
      }
      return try await coordinator.nextChunk()
    }
  }

  /// Creates an asynchronous iterator for iterating over object payload chunks.
  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(coordinator: coordinator, isOwner: coordinator.claimIterator())
  }
}

/// Coordinates the deferred initial request, metadata resolution, and streaming body consumption.
final class ReadObjectCoordinator: @unchecked Sendable {
  let bucket: String
  let object: String
  let options: ReadObjectOptions
  let httpClient: GoogleGax._HTTPClient
  let resumeLoop: _ResumeLoop<ReadObjectDetails>

  private struct State {
    var hasCreatedIterator: Bool = false
    var isReading: Bool = false
    var isInitialFetched: Bool = false
    var initialFetchTask: Task<ReadObjectMetadata, any Error>?
    var metadata: ReadObjectMetadata?
    var expectedCrc32c: String?
    var expectedMd5: String?
    var bodyIterator: _HTTPResponseBody.AsyncIterator?
    var streamIterator: AsyncThrowingStream<NIOCore.ByteBuffer, any Error>.AsyncIterator?
    var bytesReceived: UInt64 = 0
    var resumeState: ResumeState<ReadObjectDetails>
    var isFinished: Bool = false
    var isCancelled: Bool = false
    var crc32cCalculator: CRC32CCalculator?
    var md5Calculator: MD5Calculator?
    var hasValidatedChecksums: Bool = false

    init(options: ReadObjectOptions) {
      self.resumeState = ResumeState(details: ReadObjectDetails())
      if options.checksums?.crc32c != nil {
        self.crc32cCalculator = CRC32CCalculator()
      }
      if options.checksums?.md5 != nil {
        self.md5Calculator = MD5Calculator()
      }
    }
  }

  private let lock = NSLock()
  private var state: State

  init(
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
    self.state = State(options: options)
  }

  func claimIterator() -> Bool {
    lock.withLock {
      guard !state.hasCreatedIterator else { return false }
      state.hasCreatedIterator = true
      return true
    }
  }

  private var cancelled: Bool {
    lock.withLock { state.isCancelled }
  }

  private func ensureInitialFetch() async throws -> ReadObjectMetadata {
    let task = lock.withLock { () -> Task<ReadObjectMetadata, any Error>? in
      if self.state.isCancelled {
        return nil
      }
      if let existing = self.state.initialFetchTask {
        return existing
      }
      let initialResumeState = self.state.resumeState
      let newTask = Task { () throws -> ReadObjectMetadata in
        let (response, metadata) = try await Self.fetchInitial(
          httpClient: self.httpClient,
          bucket: self.bucket,
          object: self.object,
          options: self.options,
          resumeLoop: self.resumeLoop,
          resumeState: initialResumeState
        )
        let (rawCrc, rawMd5) = StorageClient.extractExpectedChecksums(from: response.headers)
        try self.lock.withLock {
          if self.state.isCancelled {
            throw CancellationError()
          }
          self.state.metadata = metadata
          self.state.expectedCrc32c = rawCrc
          self.state.expectedMd5 = rawMd5
          self.state.bodyIterator = response.body.makeAsyncIterator()
          self.state.isInitialFetched = true
        }
        return metadata
      }
      self.state.initialFetchTask = newTask
      return newTask
    }
    guard let task else {
      throw CancellationError()
    }
    return try await task.value
  }

  func getMetadata() async throws -> ReadObjectMetadata {
    try await withTaskCancellationHandler {
      if cancelled || Task.isCancelled {
        throw CancellationError()
      }
      return try await ensureInitialFetch()
    } onCancel: {
      self.cancel()
    }
  }

  func nextChunk() async throws -> ByteChunk? {
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
    let canStartRead = lock.withLock { () -> Bool? in
      guard !state.isReading else { return nil }
      guard !state.isFinished else { return false }
      if options.range?.isZeroBytes == true {
        state.isFinished = true
        return false
      }
      state.isReading = true
      return true
    }
    guard let canStartRead else {
      throw ReadObjectError.requestError(.io(ReadObjectBodyAlreadyConsumedError()))
    }
    guard canStartRead else { return nil }
    defer {
      lock.withLock { state.isReading = false }
    }

    _ = try await ensureInitialFetch()

    while !lock.withLock({ state.isFinished }) {
      if cancelled || Task.isCancelled {
        throw CancellationError()
      }
      do {
        let (nextStreamIt, nextBodyIt) = lock.withLock {
          (self.state.streamIterator, self.state.bodyIterator)
        }
        if var it = nextStreamIt {
          let chunk = try await it.next()
          if cancelled || Task.isCancelled {
            throw CancellationError()
          }
          if let chunk {
            let storage = ByteChunk(chunk)
            lock.withLock {
              self.state.streamIterator = it
              recordReceivedChunkLocked(storage)
            }
            return storage
          } else {
            try lock.withLock {
              self.state.streamIterator = it
              try validateChecksumsAtEOFLocked()
              self.state.isFinished = true
            }
            return nil
          }
        } else if var it = nextBodyIt {
          let chunk = try await it.next()
          if cancelled || Task.isCancelled {
            throw CancellationError()
          }
          if let chunk {
            let storage = ByteChunk(chunk)
            lock.withLock {
              self.state.bodyIterator = it
              recordReceivedChunkLocked(storage)
            }
            return storage
          } else {
            try lock.withLock {
              self.state.bodyIterator = it
              try validateChecksumsAtEOFLocked()
              self.state.isFinished = true
            }
            return nil
          }
        } else {
          try lock.withLock {
            try validateChecksumsAtEOFLocked()
            self.state.isFinished = true
          }
          return nil
        }
      } catch {
        if error is CancellationError || cancelled || Task.isCancelled {
          lock.withLock { state.isFinished = true }
          throw CancellationError()
        }
        if error is ReadObjectError {
          lock.withLock { state.isFinished = true }
          throw error
        }

        let reqError = (error as? RequestError) ?? .io(error)
        var localResumeState = lock.withLock { state.resumeState }
        do {
          try await resumeLoop.handleError(state: &localResumeState, error: reqError)
          lock.withLock { state.resumeState = localResumeState }
        } catch let err as RequestError {
          let received = lock.withLock { () -> UInt64 in
            state.resumeState = localResumeState
            state.isFinished = true
            return state.bytesReceived
          }
          if case .http = err {
            throw ReadObjectError.requestError(err)
          } else if case .service = err {
            throw ReadObjectError.requestError(err)
          }
          throw ReadObjectError.resumeFailed(
            bytesReceived: received, underlyingError: err)
        } catch {
          lock.withLock {
            state.resumeState = localResumeState
            state.isFinished = true
          }
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

  private func recordReceivedChunkLocked(_ chunk: ByteChunk) {
    state.bytesReceived += UInt64(chunk.count)
    state.resumeState.details.bytesRead = state.bytesReceived
    resumeLoop.onProgress(state: &state.resumeState)
    state.crc32cCalculator?.update(chunk)
    state.md5Calculator?.update(chunk)
  }

  private func validateChecksumsAtEOFLocked() throws {
    guard !state.hasValidatedChecksums else { return }
    state.hasValidatedChecksums = true

    let currentMetadata = state.metadata ?? ReadObjectMetadata()
    let rawCrc = state.expectedCrc32c
    let rawMd5 = state.expectedMd5
    let isRangedRead = (options.range ?? .entire) != .entire
    let isDecompressedTranscoding =
      (currentMetadata.storedContentLength != nil && currentMetadata.contentEncoding == nil)

    if let crcOption = options.checksums?.crc32c, let calc = state.crc32cCalculator {
      let actual = calc.finalize()
      switch crcOption {
      case .auto:
        let expected =
          currentMetadata.checksums?.crc32C.map(crc32cBase64) ?? rawCrc
        if !isRangedRead && !isDecompressedTranscoding, let expected {
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

    if let md5Option = options.checksums?.md5, let calc = state.md5Calculator {
      let actual = calc.finalize()
      switch md5Option {
      case .auto:
        let expected =
          currentMetadata.checksums.flatMap({
            $0.md5Hash.isEmpty ? nil : $0.md5Hash.base64EncodedString()
          }) ?? rawMd5
        if !isRangedRead && !isDecompressedTranscoding, let expected {
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

  private func resumeDownload(underlyingError: any Error) async throws {
    let (currentMetadata, currentBytesReceived, initialResumeState) = lock.withLock {
      (
        self.state.metadata ?? ReadObjectMetadata(), self.state.bytesReceived,
        self.state.resumeState
      )
    }
    guard
      let resumeRange = calculateResumeRange(
        originalRange: options.range ?? .entire,
        bytesReceived: currentBytesReceived,
        totalSize: currentMetadata.size > 0 ? currentMetadata.size : nil
      )
    else {
      lock.withLock { state.isFinished = true }
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
    var localResumeState = initialResumeState

    do {
      let response = try await resumeLoop.run(state: &localResumeState) { _ in
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
        self.state.resumeState = localResumeState
        if self.state.isCancelled {
          throw CancellationError()
        }
        self.state.bodyIterator = response.body.makeAsyncIterator()
        self.state.streamIterator = nil
      }
    } catch {
      let received = lock.withLock { () -> UInt64 in
        self.state.resumeState = localResumeState
        self.state.isFinished = true
        return self.state.bytesReceived
      }
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
        bytesReceived: received, underlyingError: reqError)
    }
  }

  func cancel() {
    let taskToCancel = lock.withLock { () -> Task<ReadObjectMetadata, any Error>? in
      state.isCancelled = true
      state.isFinished = true
      state.bodyIterator = nil
      state.streamIterator = nil
      return state.initialFetchTask
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
