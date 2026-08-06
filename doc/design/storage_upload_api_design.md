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

## 3. Progress & Resumability

To support progress reporting and resilience, the `upload` API returns an `UploadTask` rather than blocking until completion.

### `UploadStatus` Design
The `UploadTask` exposes a stream of `UploadStatus` objects:

```swift
public struct UploadStatus: Sendable {
    public let fractionCompleted: Double?
    public let bytesUploaded: Int64
    public let totalBytes: Int64?
    public let sessionURI: URL?
}
```

*   **`sessionURI`:** This is the GCS Resumable Upload session URI. It is `nil` for Simple Uploads. For Resumable Uploads, it is populated as soon as the session is established and remains constant.

### Alternatives Considered for Resumption

#### File Integrity Validation (Robustness vs. Consistency)
*   *Description:* Store file metadata (modification date and size) in a wrapper struct (e.g., `ResumableSession`) and validate it before resuming to prevent silent data corruption if the file was modified.
*   *Why Rejected:*
    1.  **Consistency:** Other Google Cloud Storage client libraries (Go, Java, Python, etc.) do not perform this validation; they rely on the developer to ensure the file has not changed. We should align with standard GCS SDK behavior.
    2.  **Complexity:** Adds extra complexity to the public API (introducing `ResumableSession` instead of a raw `URL` for the session).
    3.  **Developer Responsibility:** File integrity management is left to the developer if their use case requires it.

#### Explicit Abort/DELETE vs. Client-Side Cancellation
*   *Description:* GCS allows aborting a resumable upload by sending an HTTP `DELETE` request to the Session URI, which immediately discards the accumulated data on the server. We considered exposing an `abort()` method or an `abort` parameter on `cancel()` to trigger this.
*   *Why Rejected:*
    1.  **Consistency:** Other Google Cloud client libraries do not typically support this level of complexity for cancellation; they standardise on client-side cancellation (simply stopping the request).
    2.  **No Cost Impact:** Incomplete GCS resumable uploads are automatically cleaned up by GCS after 7 days, and users are not charged for the storage of incomplete uploads in the meantime.
    3.  **Simplicity:** Local-only cancellation (cancelling the Swift `Task` and aborting the active network connection) is simpler to implement and sufficient for most use cases.

#### iOS Background Transfer Service (Platform-Specific Resumability)
*   *Description:* iOS has a unique background execution model. If the app is suspended or terminated, standard Swift Concurrency tasks and network connections are killed. To support large uploads in the background, iOS uses a system daemon (`nsurlsessiond`) that takes over the transfer. This requires a decoupled, identifier-based API and a centralized event stream to allow "re-binding" to transfers after an app relaunch.
*   *Why Rejected:*
    1.  **Target Environment:** The current version of this SDK targets non-iOS environments (e.g., server-side Swift on Linux, macOS CLI tools) where process suspension by a mobile OS is not a factor.
    2.  **API Complexity:** Supporting iOS background transfers requires a completely different API paradigm (fire-and-forget identifier-based uploads + centralized event streams on the client) which would clutter the API for non-iOS developers.
*   *Future Design Path:* If iOS support is required in the future, we would introduce:
    *   `storageClient.uploadInBackground(_ fileURL: URL, withIdentifier: String, ...)`
    *   `storageClient.backgroundUploadEvents: AsyncStream<BackgroundUploadEvent>`
    *   A re-binding mechanism for the App Delegate: `storageClient.rebindBackgroundUpload(identifier:completionHandler:)`
    *   Background uploads would be strictly limited to `URL` (File) inputs.

### Robustness & Error Handling

To ensure high reliability, the library handles several critical edge cases during upload and resumption:

#### 1. File Truncation / Mutation on Resume
If a file is truncated on disk after an upload is interrupted, its size may be smaller than the offset GCS claims to have received. Attempting to seek to the GCS-reported offset would fail.
*   **Mitigation:** Before resuming, the library compares the current local file size against the GCS-reported offset. If `localSize < gcsOffset`, the library aborts the resume and throws `UploadError.localFileTooSmall`.

#### 2. Session Expiration
GCS Resumable Session URIs expire after 7 days. If a developer attempts to resume using an expired URI, GCS returns a `404 Not Found` or `400 Bad Request`.
*   **Mitigation:** The library catches these specific GCS error codes during the session query phase and maps them to `UploadError.sessionExpired`.

#### 3. Data Integrity (Checksums)
To prevent network corruption, GCS supports MD5 and CRC32C checksum validation.
*   **Mitigation:** The library supports automatic client-side checksumming. By default, it will calculate the CRC32C (or MD5) of the uploaded data and send it to GCS. GCS will validate this against the received data and reject the upload if there is a mismatch. This is configured via `UploadOptions.validation`.

### Multicasting Status Updates (Unicast Limitation)
Swift's `AsyncStream` is unicast by default. If multiple observers (e.g., a UI progress bar and a logger) try to consume the same stream, it will lead to unexpected behavior or missed events.

To support multiple observers, `UploadTask` does not expose a single public property stream. Instead, it exposes a factory method `makeStatusStream()`. Internally, the library will use a multicast broadcaster (backed by an actor) to distribute status updates to all active streams created by this method.

### Resumability Strategy: Persistent vs. Transient

We differentiate support for resumption based on the input source:

1.  **Persistent Resumption (Process-Level):**
    *   **Supported for:** Sources conforming to `SeekableUploadSource` (e.g., `FileSource`).
    *   **Mechanism:** The developer can save the `sessionURI` from `UploadStatus`. If the app crashes/terminates, they can call `client.resumeUpload(fileSource, withSession: sessionURI)`.
    *   **How it works:** The library queries GCS using the `sessionURI`. GCS returns the received byte range. The library calls `source.seek(to:)` to align the source with GCS and resumes.
2.  **Transient Resumption (In-Memory/Active Session):**
    *   **Supported for:** All `UploadSource` types.
    *   **Mechanism:** Automatic retries by the library during an active upload session.
    *   **Limitation for Streams:** Non-seekable streams (`StreamSource`) cannot be "rewound" if the process dies, so process-level resumption is not supported for them.

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

    /// The upload was cancelled by the user.
    case cancelled

    /// GCS returned an unexpected response.
    case unexpectedServerResponse(statusCode: Int, message: String)

    /// Network error during upload.
    case networkError(underlyingError: Error)
}
```

### `ChecksumValidation`
Strategy for data integrity validation.

```swift
public enum ChecksumValidation: Sendable {
    /// Do not perform client-side checksum validation.
    case none

    /// Automatically calculate and validate CRC32C (recommended).
    case crc32c

    /// Automatically calculate and validate MD5.
    case md5
}
```

### `UploadStatus`
Represents the current state of an ongoing upload.

```swift
public struct UploadStatus: Sendable {
    /// The fraction of the upload completed (0.0 to 1.0).
    /// This is `nil` if the total size is unknown (e.g., streaming).
    public let fractionCompleted: Double?

    /// The number of bytes successfully received by GCS.
    public let bytesUploaded: Int64

    /// The total bytes to upload. Nil if the size is unknown (streaming).
    public let totalBytes: Int64?

    /// The GCS Session URI.
    /// This is `nil` if the library chose a "Simple Upload".
    /// It becomes populated as soon as the Resumable Session is created.
    public let sessionURI: URL?
}
```

### `UploadTask`
A handle to an ongoing upload, allowing for progress monitoring, cancellation, and awaiting the final result.

```swift
public struct UploadTask: Sendable {
    /// Creates a new stream to observe the upload progress and status.
    /// Multiple observers can call this to get their own independent stream.
    /// The stream completes when the upload finishes or fails.
    public func makeStatusStream() -> AsyncStream<UploadStatus>

    /// The final result of the upload.
    /// Awaiting this will suspend until the upload is complete.
    public var value: Object {
        get async throws
    }

    /// Cancels the ongoing upload (client-side).
    /// If cancelled, `value` will throw a `CancellationError`.
    /// Note: The GCS resumable session on the server will remain active until it expires (usually 7 days).
    public func cancel()
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

### `CustomerEncryptionKey`
Options for Customer-Supplied Encryption Keys (CSEK).

```swift
public struct CustomerEncryptionKey: Sendable {
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
    public var customerEncryptionKey: CustomerEncryptionKey?
    public var validation: ChecksumValidation

    public static var `default`: UploadOptions { UploadOptions() }

    public init(
        chunkSize: Int = 8 * 1024 * 1024,
        preconditions: StoragePreconditions? = nil,
        kmsKeyName: String? = nil,
        customerEncryptionKey: CustomerEncryptionKey? = nil,
        validation: ChecksumValidation = .crc32c
    )
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
    /// - Returns: An `UploadTask` to monitor and control the upload.
    public func upload(
        _ source: some UploadSource,
        to bucket: String,
        as objectName: String,
        metadata: UploadMetadata? = nil,
        options: UploadOptions = .default
    ) -> UploadTask

    /// Resumes a previously interrupted file upload using a saved session URI.
    ///
    /// - Parameters:
    ///   - source: The seekable upload source (must match the original source).
    ///   - sessionURI: The saved GCS Session URI.
    ///   - options: Configuration options for the upload.
    /// - Returns: An `UploadTask` to monitor and control the resumed upload.
    public func resumeUpload(
        _ source: some SeekableUploadSource,
        withSession sessionURI: URL,
        options: UploadOptions = .default
    ) -> UploadTask

    // --- Convenience Overloads ---

    /// Convenience upload method for a local file URL.
    public func upload(
        _ fileURL: URL,
        to bucket: String,
        as objectName: String,
        metadata: UploadMetadata? = nil,
        options: UploadOptions = .default
    ) -> UploadTask {
        return self.upload(FileSource(fileURL: fileURL), to: bucket, as: objectName, metadata: metadata, options: options)
    }

    /// Convenience upload method for in-memory Data.
    public func upload(
        _ data: Data,
        to bucket: String,
        as objectName: String,
        metadata: UploadMetadata? = nil,
        options: UploadOptions = .default
    ) -> UploadTask {
        return self.upload(BytesSource(data: data), to: bucket, as: objectName, metadata: metadata, options: options)
    }
}
```

## 5. Concurrency & Thread Safety

In modern Swift, APIs must be designed with data-race safety in mind.

### `Sendable` Conformance
Even if developers do not intentionally share an `UploadTask` across threads, Swift Concurrency will likely jump threads (e.g., initiating the upload in a background context, observing progress on the `@MainActor` for UI updates, and calling `cancel()` from a UI action).

Therefore, `UploadTask` is designed to be `Sendable`.

### Implementation Strategy for thread-safety:
To keep `UploadTask` as a lightweight `struct` while ensuring thread safety:
1.  **Immutable Struct:** `UploadTask` will contain only `let` constants.
2.  **Cooperative Cancellation:** The `cancel()` method will not mutate the `UploadTask` struct itself. Instead, it will forward the cancellation to an internal, thread-safe reference (such as a native Swift `Task` handle or a thread-safe state machine).
    *   Calling `task.cancel()` will trigger cooperative cancellation on the underlying asynchronous operation, which the library's internal upload loop will detect and handle by aborting the HTTP requests.
