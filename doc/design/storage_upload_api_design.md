# Design Document: GCS Swift Client Library Upload API

This document outlines the API design for uploading files using the Google Cloud Storage (GCS) Swift client library.

## Goal

Provide a language-idiomatic, memory-safe, and resilient API for uploading data to GCS.

## 1. Unified Upload API

We want to expose a single `upload` surface to the developer, abstracting away the decision of whether to use GCS Simple Upload or Resumable Upload.

### Decision
The library will automatically choose the upload protocol:
*   **Known Size (e.g., `URL`, `Data`):**
    *   If size is below a threshold (TBD, e.g., 8MB), use **Simple Upload**.
    *   If size is above or equal to the threshold, use **Resumable Upload**.
*   **Unknown Size (e.g., Streams):**
    *   Default to **Resumable Upload** (Option A).

### Alternatives Considered for Size Detection

#### Option B: Buffer the first X MB of a stream
*   *Description:* Read the stream into memory up to the threshold. If the stream ends before the threshold, use Simple Upload. If it exceeds, switch to Resumable.
*   *Why Rejected:* Violates memory safety. We want to avoid loading unknown amounts of data into RAM.

#### Option C: Require size hint for streams
*   *Description:* Force the developer to provide a size estimate when using streams.
*   *Why Rejected:* Poor developer experience when the size truly cannot be known (e.g., streaming live audio/video encoding).

## 2. Input Sources & Chunking

To support diverse data sources (files, memory buffers, streams) while enforcing capabilities like seekability at compile time, we use a protocol-oriented design inspired by `google-cloud-rust`.

### The `UploadSource` Abstraction
Instead of overloading the client with many concrete types, we define a unified input abstraction:
*   **`UploadSource` Protocol:** Defines a sequential, chunk-based read operation. Used for all uploads.
*   **`SeekableUploadSource` Protocol:** Inherits from `UploadSource` and adds a `seek(to:)` operation. This is required for persistent resumption.

Concrete implementations are provided for common types:
1.  **`FileSource`** (Seekable): Reads from a local `URL` and supports seeking.
2.  **`BytesSource`** (Seekable): Slices in-memory `Data`.
3.  **`StreamSource`** (Non-Seekable): Wraps an `AsyncSequence<Data>`.

### Decision: Protocol-Based Inputs
By requiring `SeekableUploadSource` for resumption, we prevent runtime errors when trying to resume non-seekable streams at compile time.
The library handles GCS 256 KiB chunk alignment internally by buffering reads from the source.

### Alternatives Considered for Input Types

#### Option A: Direct Concrete Type Overloads (Without Protocols)
*   *Description:* Expose `upload(_ fileURL: URL)`, `upload(_ data: Data)`, and `upload(_ stream: AsyncSequence)` directly on the client.
*   *Why Rejected:*
    1.  **Resumption Safety:** We could not easily enforce at compile time that only file-based uploads can be resumed. The developer could pass a stream to `resumeUpload`, leading to runtime failures.
    2.  **Extensibility:** Developers could not easily plug in custom data sources (e.g., encrypted streams, custom database reader) without us adding more overloads.

#### Option B: `AsyncSequence<UInt8>` for Streaming
*   *Description:* Accept a sequence of individual bytes for streaming.
*   *Why Rejected:* **Severe performance bottleneck.** Technical review confirmed that byte-by-byte async iteration in Swift introduces unacceptable performance degradation due to the overhead of async function calls for every single byte.

#### Option C: Decoupled Protocols with Dynamic Runtime Detection
*   *Description:* Define `UploadSource` and `Seekable` as independent protocols (no inheritance). Accept `UploadSource` everywhere and cast to `Seekable` at runtime to check if seek is supported.
*   *Why Rejected:*
    1.  **Value Semantics Bug:** In Swift, casting a mutating protocol on a value type (struct) using `as?` creates a copy. Mutating the casted interface (calling `seek()`) mutates the copy, not the original source, leading to silent bugs.
    2.  **Runtime vs. Compile-time Safety:** We lose compile-time safety. A developer could pass a non-seekable stream to `resumeUpload` and it would compile, only to fail at runtime.

#### Option D: Decoupled Protocols with Protocol Composition
*   *Description:* Define `UploadSource` and `Seekable` independently, but use protocol composition (`some UploadSource & Seekable` or generic constraints `<S: UploadSource & Seekable>`) in the method signatures where seekability is required.
*   *Why Rejected:* While this solves the value semantics bug and maintains compile-time safety, it adds syntactic noise to the API signatures (e.g., `resumeUpload(_ source: some UploadSource & Seekable, ...)`). Inheriting `SeekableUploadSource: UploadSource` provides a cleaner, more self-documenting API hierarchy for this specific domain.

### 3. Return Type & Resumability

### Direct Return Type (`Object`)

The `upload` and `resumeUpload` APIs directly return the created `GoogleCloudStorage.Object` asynchronously (`async throws -> Object`) rather than returning an `UploadTask` handle or stream wrapper. This provides a simple, clean, and idiomatic async Swift API for object uploads:

```swift
let object = try await storageClient.upload(fileURL, to: "my-bucket", as: "file.txt")
```

Observability into individual upload chunks is omitted from the return type for simplicity. If chunk progress or status events are needed in the future, they can be implemented using an observer pattern (e.g., passing a progress handler/delegate in `UploadOptions`).

### Resumability Strategy: Persistent vs. Transient

We differentiate support for resumption based on the input source:

1.  **Persistent Resumption (Process-Level):**
    *   **Supported for:** Sources conforming to `SeekableUploadSource` (e.g., `FileSource`, `BytesSource`).
    *   **Mechanism:** If an upload fails with a resumable session established, the caller can resume the upload using `client.resumeUpload(source, uploadId: uploadId)`.
    *   **How it works:** The library queries GCS using the `uploadId` (session URI) with a `bytes */*` status query. GCS returns the received byte range in the `Range` header (or 200 OK if already completed). The library seeks the source to align with GCS and resumes uploading the remaining chunks.
2.  **Transient Resumption (In-Memory/Active Session):**
    *   **Supported for:** All `UploadSource` types.
    *   **Mechanism:** Automatic retries by the library's internal retry and resume loop during an active upload session.
    *   **Limitation for Streams:** Non-seekable streams (`StreamSource`) cannot be "rewound" if the process terminates, so process-level resumption is not supported for them.

### Robustness & Error Handling

To ensure high reliability, the library handles several critical edge cases during upload and resumption:

#### 1. File Truncation / Mutation on Resume
If a file is truncated on disk after an upload is interrupted, its size may be smaller than the offset GCS claims to have received. Attempting to seek to the GCS-reported offset would fail.
*   **Mitigation:** Before resuming, the library compares the current local file size against the GCS-reported offset. If `localSize < gcsOffset`, the library aborts the resume and throws `UploadError.localSourceTooSmall`.

#### 2. Session Expiration
GCS Resumable Session URIs expire after 7 days. If a developer attempts to resume using an expired URI, GCS returns a `404 Not Found` or `400 Bad Request`.
*   **Mitigation:** The library catches these specific GCS error codes during the session query phase and maps them to `UploadError.sessionExpired`.

#### 3. Data Integrity (Checksums)
To prevent network corruption, GCS supports MD5 and CRC32C checksum validation.
*   **Mitigation:** The library supports automatic client-side checksumming. By default, it calculates CRC32C (or MD5) and includes the hashes in `x-goog-hash` headers. GCS validates this against the received data and rejects the upload if there is a mismatch. This is configured via `UploadOptions.checksums`.

## 4. Proposed Swift Interface

Here is the proposed public API surface for the GCS Swift upload feature.

### `UploadSource` Protocols

```swift
/// Represents a data source that can be read from sequentially.
public protocol UploadSource: Sendable {
    /// Reads the next chunk of data, up to `maxBytes`.
    /// Returns `nil` when the source is exhausted.
    mutating func read(maxBytes: Int) async throws -> Data?

    /// The total size of the source, if known.
    var totalSize: Int64? { get }
}

/// Represents an upload source that supports seeking (rewinding/skipping).
/// Conformance to this protocol enables persistent resumption.
public protocol SeekableUploadSource: UploadSource {
    /// Seeks to a specific byte offset.
    mutating func seek(to offset: Int64) async throws
}
```

### Concrete `UploadSource` Implementations

```swift
/// An upload source that reads from a local file.
public struct FileSource: SeekableUploadSource {
    public let fileURL: URL
    public var totalSize: Int64? { get }

    public init(fileURL: URL)

    public mutating func read(maxBytes: Int) async throws -> Data?
    public mutating func seek(to offset: Int64) async throws
}

/// An upload source that wraps in-memory Data.
public struct BytesSource: SeekableUploadSource {
    public let data: Data
    public var totalSize: Int64? { get }

    public init(data: Data)

    public mutating func read(maxBytes: Int) async throws -> Data?
    public mutating func seek(to offset: Int64) async throws
}

/// An upload source that wraps an arbitrary AsyncSequence of Data chunks.
///
/// - Note: The provided `AsyncSequence` is expected to yield chunks of reasonable size. By
///   necessity, the library may need to buffer data (e.g., when slicing a large chunk to fit
///   `maxBytes`), so the sequence should not return enormous amounts of data in a single
///   `next()` call to avoid memory bloat.
public struct StreamSource<S: AsyncSequence>: UploadSource where S.Element == Data, S: Sendable {
    public var totalSize: Int64? { return nil }

    public init(sequence: S)

    public mutating func read(maxBytes: Int) async throws -> Data?
}
```

### `UploadError`
Errors thrown by the upload API.

```swift
public enum UploadError: Error, Sendable {
    /// The local source is smaller than the offset reported by GCS.
    /// Indicates the source was modified or truncated.
    case localSourceTooSmall(localSize: Int64, gcsOffset: Int64)

    /// The resumable session has expired (usually after 7 days) or was not found.
    case sessionExpired(sessionURI: URL, underlyingError: Error?)

    /// GCS returned an unexpected response.
    case unexpectedServerResponse(statusCode: Int, message: String)
}
```

### `ChecksumOptions`
Strategy for data integrity validation.

```swift
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

### `UploadMetadata`
Represents the metadata of the object to be created.

```swift
public struct UploadMetadata: Sendable {
    public var contentType: String?
    public var contentEncoding: String?
    public var contentDisposition: String?
    public var contentLanguage: String?
    public var cacheControl: String?
    public var customMetadata: [String: String]?

    public init(
        contentType: String? = nil,
        contentEncoding: String? = nil,
        contentDisposition: String? = nil,
        contentLanguage: String? = nil,
        cacheControl: String? = nil,
        customMetadata: [String: String]? = nil
    )
}
```

### `CustomerEncryptionKeyOptions`
Options for Customer-Supplied Encryption Keys (CSEK).

```swift
public struct CustomerEncryptionKeyOptions: Sendable {
    public let algorithm: String
    public let keyBase64: String
    public let keyHashBase64: String

    public init(algorithm: String = "AES256", keyBase64: String, keyHashBase64: String)
}
```

### `UploadOptions`
Configuration options for the upload request/session.

```swift
public struct UploadOptions: Sendable {
    public var chunkSize: Int
    public var preconditions: StoragePreconditions?
    public var kmsKeyName: String?
    public var customerEncryptionKey: CustomerEncryptionKeyOptions?
    public var checksums: ChecksumOptions
    public var resumableUploadThreshold: Int
    public var resumePolicy: (any ResumePolicy<UploadDetails>)?
    public var backoffPolicy: (any BackoffPolicy)?

    public static var `default`: UploadOptions { UploadOptions() }

    public init(...)
}
```

### `StorageClient` Extensions
The main entry points for triggering uploads.

```swift
extension StorageClient {
    /// Core upload method accepting any upload source.
    ///
    /// - Parameters:
    ///   - source: The upload source containing the data.
    ///   - bucket: The destination GCS bucket name.
    ///   - objectName: The destination GCS object name.
    ///   - metadata: Optional metadata to associate with the object.
    ///   - options: Configuration options for the upload.
    /// - Returns: The created GCS `Object`.
    public func upload(
        _ source: some UploadSource,
        to bucket: String,
        as objectName: String,
        metadata: UploadMetadata? = nil,
        options: UploadOptions = .default
    ) async throws -> Object

    /// Resumes a previously interrupted file upload using a saved upload ID or session URI.
    ///
    /// - Parameters:
    ///   - source: The seekable upload source (must match the original source).
    ///   - uploadId: The saved GCS Session URI or upload ID.
    ///   - options: Configuration options for the upload.
    /// - Returns: The created GCS `Object`.
    public func resumeUpload(
        _ source: some SeekableUploadSource,
        uploadId: String,
        options: UploadOptions = .default
    ) async throws -> Object

    // --- Convenience Overloads ---

    /// Convenience upload method for a local file URL.
    public func upload(
        _ fileURL: URL,
        to bucket: String,
        as objectName: String,
        metadata: UploadMetadata? = nil,
        options: UploadOptions = .default
    ) async throws -> Object

    /// Convenience upload method for in-memory Data.
    public func upload(
        _ data: Data,
        to bucket: String,
        as objectName: String,
        metadata: UploadMetadata? = nil,
        options: UploadOptions = .default
    ) async throws -> Object
}
```

## 5. Concurrency & Cancellation

In modern Swift, APIs are designed with Swift Concurrency and data-race safety in mind.

### Asynchronous Execution & Sendability
All upload operations are `async throws` functions that execute within the caller's Swift Concurrency context. Input parameters, sources, and options conform to `Sendable`, allowing uploads to be initiated across concurrency domains without data races.

### Cooperative Cancellation
Upload operations support standard Swift Concurrency cancellation. If the calling `Task` is cancelled, the internal upload loops check `Task.isCancelled` between chunks and abort active network requests with `CancellationError`.

Note: Client-side cancellation leaves any in-progress resumable session on GCS until it expires (typically after 7 days). GCS automatically cleans up expired sessions at no additional storage charge.
