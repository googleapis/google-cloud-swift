# Design Document: GCS Swift Client Library Download API

This document outlines the API design for downloading objects using the Google Cloud Storage (GCS) Swift client library.

## Goal

Provide a language-idiomatic, memory-safe, high-performance, and resilient API for reading and downloading object contents from Cloud Storage in Swift.

---

## 1. Client Surface & Async Streaming Interface

We want to expose a simple, intuitive client interface for reading object contents while leveraging Swift Concurrency's `AsyncSequence` for streaming data and immediately returning initial object metadata.

### Decision
The primary client method for downloading object content is `readObject`:

```swift
func readObject(
  from bucket: String,
  object: String,
  options: ReadObjectOptions = .init()
) -> ReadObjectTask
```

- **Return Task Struct (`ReadObjectTask`):** `readObject` returns immediately with a `ReadObjectTask` struct holding both the object metadata and the streaming body:
  ```swift
  public struct ReadObjectTask: Sendable {
    /// Object metadata populated from response headers upon request initiation.
    public var metadata: ReadObjectMetadata { get async throws }

    /// An asynchronous sequence of `ByteBuffer` chunks for the object payload.
    public var body: ReadObjectSequence { get }

    /// Cancels the ongoing download.
    public func cancel()
  }
  ```

- **Immediate Metadata Availability:** Upon `await client.readObject(...)` returning, response headers (`Content-Length`, `x-goog-generation`, `x-goog-hash`, `Content-Type`, etc.) are parsed and made available in `response.metadata` before the application consumes the payload stream.
- **Lazy Payload Consumption:** The `response.body` (`ReadObjectSequence`) streams raw data chunks lazily as the caller iterates over it.

### Example Usage

#### Basic download with metadata access:

```swift
let response = try await client.readObject(from: "my-bucket", object: "file.txt")

print("File Size: \(response.metadata.size) bytes")
print("Generation: \(response.metadata.generation)")
print("Content Type: \(response.metadata.contentType ?? "unknown")")

for try await chunk in response.body {
  // process Data chunk
}
```

#### Custom download options with ranged reads:

```swift
let options = ReadObjectOptions().with {
  $0.range = .bounded(start: 0, end: 1024)
  $0.autoResume = true
}

let response = try await client.readObject(from: "my-bucket", object: "file.txt", options: options)

print("Downloaded range size: \(response.metadata.size) bytes")

for try await chunk in response.body {
  // process Data chunk
}
```

---

## 2. Target Object & Read Options

Developers need full control over target object selection, precondition checks, and encryption options.

### Key Options in `ReadObjectOptions`
1. **Target Object Identification:**
   - `bucket`: Bucket name containing the object.
   - `object`: Object name/path within the bucket.
   - `generation`: Optional object generation (`UInt64?`) to read a specific revision of an object.
2. **Preconditions:**
   - Leverages `StoragePreconditions` (`ifGenerationMatch`, `ifGenerationNotMatch`, `ifMetagenerationMatch`, `ifMetagenerationNotMatch`) to ensure operations execute only when condition constraints pass.
3. **Customer-Supplied Encryption Keys (CSEK):**
   - Leverages `CustomerEncryptionKeyOptions` to send required encryption headers (`x-goog-encryption-algorithm`, `x-goog-encryption-key`, `x-goog-encryption-key-sha256`) when reading customer-encrypted objects.

---

## 3. Ranged Reads & Byte Ranges

To support partial object downloads, parallel chunk downloads, or reading file footers (e.g. Parquet metadata), the API must support flexible ranged reads.

### The `ReadObjectRange` Abstraction

Ranged reads are configured via the `ReadObjectRange` enum:

```swift
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
    case .suffix(let count):
      return "bytes=-\(count)"
    case .bounded(let start, let end):
      return "bytes=\(start)-\(end)"
    }
  }
}
```

---

## 4. Decompressive Transcoding & Compressed Objects

Objects uploaded to GCS with `Content-Encoding: gzip` are automatically decompressed by GCS during download (decompressive transcoding) unless the client explicitly disables it.

### Decision
The `ReadObjectOptions` struct provides an `enableDecompressiveTranscoding: Bool` flag (default `true`):
- When `true` (default): GCS decompresses the object on-the-fly before sending payload bytes to the client.
- When `false`: The client adds `Accept-Encoding: gzip` to request headers. GCS delivers the raw compressed bytes without decompressing.

---

## 5. Checksum Validation (CRC32C & MD5)

To guarantee data integrity during transfer, Cloud Storage provides CRC32C and MD5 hashes in response headers (`x-goog-hash` or `ETag`).

### Rules & Defaults
1. **CRC32C (Default Enabled):** When performing full object reads (without ranged bounds or decompressive transcoding), the client automatically accumulates CRC32C checksums of received chunks on-the-fly and compares against `x-goog-hash` upon stream completion.
2. **MD5 (Optional):** Applications can explicitly enable MD5 validation in `DownloadChecksumOptions`.
3. **Automatic Bypass:** Checksum validation is automatically skipped when performing partial/ranged reads or when decompressive transcoding is active, because GCS header hashes reflect the entire raw object payload.

### Reusing `ChecksumOptions`

The download API reuses the existing `ChecksumOptions` struct defined in `UploadOptions.swift` to ensure a single, consistent checksum options surface across both uploads and downloads:

```swift
/// Configuration options for checksum validation (reused from `UploadOptions.swift`).
public struct ChecksumOptions: Sendable, Hashable {
  public var crc32c: ChecksumValue?
  public var md5: ChecksumValue?

  public enum ChecksumValue: Sendable, Hashable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    case auto
    case value(String)

    public init(stringLiteral value: String)
    public init(_ intValue: UInt32)
    public init(integerLiteral value: UInt64)
  }

  public init(crc32c: ChecksumValue? = .auto, md5: ChecksumValue? = nil)

  public static var `default`: ChecksumOptions { ChecksumOptions(crc32c: .auto, md5: nil) }
  public static var none: ChecksumOptions { ChecksumOptions(crc32c: nil, md5: nil) }
}
```

When downloading:
- `checksums.crc32c = .auto` (or `.default`): Automatically validates the received CRC32C stream against `x-goog-hash` upon download completion.
- `checksums.crc32c = .value("...")` (or `.value(12345)`): Validates the downloaded stream against a specific user-expected CRC32C value.
- `checksums.md5 = .auto` (or `.value("...")`): Validates MD5 against `x-goog-hash` or a user-provided expected value.
- `checksums = .none`: Disables client-side checksum validation for the download.

---

## 6. Resumability & Error Handling

Transient network failures during large object downloads should not require restarting the entire transfer from byte 0.

### Resumption Protocol Strategy
1. **Offset Tracking:** As chunks of `Data` are yielded by the `AsyncIterator`, the iterator tracks total `bytesReceived`.
2. **Re-connection Range:** On a transient connection drop or socket error, if `autoResume` is enabled (default `true`), the iterator transparently initiates a new HTTP GET request requesting range `bytes={rangeStart + bytesReceived}-`.
3. **Generation Pinning (`generation=X`):** Upon receiving the initial HTTP response, the client captures the object's exact `generation` (`X`) from response headers (or `metadata.generation`). If a transient failure occurs and resumption is triggered, all subsequent range requests explicitly set the `generation=X` parameter. This guarantees that even if the object is overwritten, updated, or soft-deleted in GCS mid-download, the client continues downloading the original version `X` seamlessly without encountering `412 Precondition Failed` errors.
4. **Failure Handling:** If resumption fails (e.g., generation `X` expired/purged, non-retryable status), a `DownloadError.resumeFailed` error is thrown through the stream.

---

## 7. Proposed Swift Interface

Below is the complete proposed public API surface for object downloads in `GoogleCloudStorage`.

### Options & Range Types

```swift
/// Specifies a byte range for ranged reads.
public enum ReadObjectRange: Sendable, Hashable, Equatable {
  case entire
  case fromOffset(UInt64)
  case suffix(UInt64)
  case bounded(start: UInt64, end: UInt64)

  public init(_ range: ClosedRange<UInt64>)
  public var headerValue: String? { get }
}

/// Configuration options for object download (`readObject`) requests.
public struct ReadObjectOptions: Sendable {
  public var generation: UInt64?
  public var preconditions: StoragePreconditions?
  public var customerEncryptionKey: CustomerEncryptionKeyOptions?
  public var range: ReadObjectRange = .entire

  public var enableDecompressiveTranscoding: Bool = true
  public var checksums: ChecksumOptions = .default
  public var autoResume: Bool = true

  public static var `default`: ReadObjectOptions { ReadObjectOptions() }

  public init() {}

  public func with(_ config: (inout Self) -> Void) -> Self
}
```

### Errors

```swift
/// Errors thrown by object read and download operations.
public enum DownloadError: Error, Sendable, Equatable {
  case checksumMismatch(expected: String, actual: String, algorithm: String)
  case invalidRange(String)
  case resumeFailed(bytesReceived: UInt64, message: String)
  case unexpectedServerResponse(statusCode: Int, message: String)
}
```

### Stream Sequence & Response Container

```swift
/// Metadata attributes for an object returned in response headers during a download.
public struct ReadObjectMetadata: Sendable, Hashable, Equatable {
  public var bucket: String = ""
  public var object: String = ""
  public var size: Int64 = 0
  public var generation: Int64 = 0
  public var metageneration: Int64?
  public var etag: String?
  public var crc32c: String?
  public var md5Hash: String?
  public var contentType: String?
  public var contentEncoding: String?
  public var contentDisposition: String?
  public var storageClass: String?
  public var updated: Date?

  public init() {}

  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}


/// An asynchronous sequence of `Data` chunks representing an object payload being downloaded.
public struct ReadObjectSequence: AsyncSequence, Sendable {
  public typealias Element = Data

  public let bucket: String
  public let object: String
  public let options: ReadObjectOptions

  public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
    public typealias Element = Data
    public mutating func next() async throws -> Data?
  }

  public func makeAsyncIterator() -> AsyncIterator
}

/// Container object returned by `readObject` containing metadata and the streaming body sequence.
public struct ReadObjectTask: Sendable {
  /// Object metadata extracted from initial HTTP response headers.
  public var metadata: ReadObjectMetadata { get async throws }

  /// Asynchronous sequence yielding chunks of binary data payload.
  public var body: ReadObjectSequence { get }

  /// Cancels the ongoing download.
  public func cancel()
}
```

### StorageClient Extensions & Protocols

```swift
public protocol StorageClientProtocol {
  func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions
  ) -> ReadObjectTask
}

extension StorageClientProtocol {
  public func readObject(
    from bucket: String,
    object: String
  ) -> ReadObjectTask {
    readObject(from: bucket, object: object, options: .init())
  }
}

extension StorageClient {
  public func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions = .init()
  ) -> ReadObjectTask {
    // Return ReadObjectTask backed by coordinator
  }
}
```


---

## 8. Alternatives Considered

### Option A: `AsyncSequence<UInt8>` for Streaming
- *Description:* Yield byte-by-byte values (`UInt8`) in `AsyncSequence`.
- *Why Rejected:* **Severe performance overhead.** Technical evaluation confirmed that yielding single bytes over Swift async iteration introduces excessive context-switching and task scheduling overhead. Streaming `Data` chunks (buffer blocks) provides vastly higher throughput.

### Option B: Synchronous Download `readObject(...) -> Data`
- *Description:* Download the entire object payload into memory and return a single `Data` value.
- *Why Rejected:* **High memory consumption.** Large GCS objects (e.g. gigabytes in size) would cause memory exhaustion. Callers requiring in-memory data can easily accumulate chunks from `readObject` into `Data` when appropriate.

### Option C: Explicit Resume Token / Manual Handshake
- *Description:* Require developers to catch errors and manually initiate resume downloads with an offset token.
- *Why Rejected:* Unnecessary boilerplate for developers. Encapsulating transparent auto-resumption inside `ReadObjectSequence.AsyncIterator` ensures high reliability out of the box while allowing manual control when `autoResume = false`.

### Option D: Opaque Return Type (`some AsyncSequence<Data, any Error> & Sendable`)
- *Description:* Use Swift 5.7+ opaque return types (`func readObject(...) -> some AsyncSequence<Data, any Error> & Sendable`) instead of exposing `ReadObjectSequence`.
- *Trade-offs:*
  - *Pros:* Hides internal implementation details and allows changing the underlying stream implementation in future releases without breaking API signature compatibility.
  - *Cons:* In Swift protocol declarations (`StorageClientProtocol`), returning `some` forces all conforming implementations (including test mocks) to use the exact same underlying concrete type, or requires adding an `associatedtype` requirement to the protocol.
- *Recommendation:* If `StorageClientProtocol` needs flexibility across different mock implementations without complex protocol generic constraints, returning `ReadObjectSequence` or `any AsyncSequence<Data, any Error> & Sendable` (or an `AsyncThrowingStream<Data, Error>`) is preferable.

### Option E: Returning `ReadObjectSequence` Directly (Without Metadata Container)
- *Description:* Return `ReadObjectSequence` directly from `readObject` non-asynchronously without an initial handshake, deferring HTTP connection until iteration starts.
- *Why Rejected:* **Delayed Metadata Access.** Returning `ReadObjectSequence` directly prevents developers from inspecting object metadata (`size`, `generation`, `contentType`, `etag`) before starting payload iteration. Returning `ReadObjectResponse` via `await client.readObject(...)` (matching Rust's `(metadata, stream)` container pattern) performs the initial HTTP response header handshake immediately, allowing callers to inspect `response.metadata` prior to body iteration.
