# Troubleshooting Object Reads and Writes

Diagnose and recover from ``ReadObjectError`` and ``WriteObjectError`` failures when downloading and uploading objects with ``StorageClient``.

## Overview

``StorageClient`` uses dedicated error enumerations for data-plane transfers:

- ``ReadObjectError`` is thrown when awaiting ``ReadObjectHandleProtocol/metadata`` or iterating ``ReadObjectHandleProtocol/body`` from ``StorageClient/readObject(from:object:options:)``.
- ``WriteObjectError`` is thrown by `StorageClient.writeObject(_:to:as:options:)` and its overloads when uploading data from a ``SeekableWriteObjectSource`` or ``WriteObjectSource``.

Control-plane operations on ``StorageControlClient`` throw `GoogleGax.RequestError` directly. During object reads and writes, underlying service and transport errors are surfaced via ``ReadObjectError/requestError(_:)`` and ``WriteObjectError/requestError(_:)`` (or ``ReadObjectError/resumeFailed(bytesReceived:underlyingError:)`` when a streaming download cannot be resumed).

> Important: Both ``ReadObjectError`` and ``WriteObjectError`` may gain new cases in minor or patch releases. Always include an `@unknown default:` branch when switching over them.

---

## Handling Download Errors (`ReadObjectError`)

Because ``StorageClient/readObject(from:object:options:)`` starts the network request lazily, errors are thrown when your code awaits ``ReadObjectHandleProtocol/metadata`` or iterates over ``ReadObjectHandleProtocol/body``:

```swift
import GoogleCloudStorage
import GoogleGax
import GoogleRpc

func downloadObject(
  client: StorageClient,
  bucket: String,
  object: String
) async throws -> [ByteChunk] {
  var chunks: [ByteChunk] = []
  do {
    let download = client.readObject(from: bucket, object: object)
    let metadata = try await download.metadata
    print("Downloading \(metadata.name) (generation \(metadata.generation), \(metadata.size) bytes)")

    for try await chunk in download.body {
      chunks.append(chunk)
    }
    return chunks
  } catch let error as ReadObjectError {
    switch error {
    case .checksumMismatch(let expected, let actual, let algorithm):
      // Discard corrupted data and retry the download from the beginning.
      print("\(algorithm) mismatch (expected \(expected), got \(actual)); discard partial data.")
      throw error

    case .resumeFailed(let bytesReceived, let underlyingError):
      // Automatic resumption stopped after `bytesReceived` bytes.
      print("Download interrupted after \(bytesReceived) bytes: \(underlyingError)")
      throw error

    case .requestError(let requestError):
      if case .service(let serviceError) = requestError {
        switch serviceError.code {
        case .notFound:
          print("Bucket '\(bucket)' or object '\(object)' was not found.")
        case .failedPrecondition:
          print("Read precondition failed: \(serviceError.message)")
        case .permissionDenied:
          print("Permission denied (check IAM roles or quotaProject): \(serviceError.message)")
        default:
          print("Storage service error (\(serviceError.code)): \(serviceError.message)")
        }
      }
      throw error

    case .invalidRangeHeader(let header):
      print("Malformed Content-Range response header: \(header)")
      throw error

    case .unexpectedServerResponse(let statusCode, let message):
      print("Unexpected HTTP \(statusCode): \(message)")
      throw error

    @unknown default:
      throw error
    }
  }
}
```

### Checksum Mismatches

By default, ``ReadObjectOptions/checksums`` is set to ``ChecksumOptions/default``, which computes a CRC32C checksum over the downloaded stream and compares it against the server-supplied checksum when the stream reaches EOF. If the computed digest does not match, ``ReadObjectError/checksumMismatch(expected:actual:algorithm:)`` is thrown before the loop completes.

- **In-transit corruption**: Discard any bytes already collected from ``ReadObjectHandleProtocol/body`` and re-run the download.
- **Partial (ranged) reads and decompressive transcoding**: Automatic checksum validation (`.auto`) is automatically skipped for ranged reads and decompressively transcoded objects because Cloud Storage metadata checksums cover the full stored object. However, if you explicitly provide a pre-computed digest via `ChecksumOptions(crc32c: ...)` or `ChecksumOptions(md5: ...)`, it is always verified against the received bytes.
- **Concurrent overwrites**: When an interrupted download automatically resumes, `StorageClient` pins the object `generation` obtained from the initial response headers so subsequent range requests read the same object revision. If you perform manual multi-part ranged reads across separate `readObject` calls, pin ``ReadObjectOptions/generation`` or ``StoragePreconditions/ifGenerationMatch`` to avoid mixing bytes from different object generations.

### Interrupted Downloads and Resumption

When a transient error (such as a socket drop, HTTP 408, HTTP 429, or HTTP 5xx) interrupts iteration of ``ReadObjectHandleProtocol/body``, `StorageClient` automatically issues a ranged request for the remaining bytes using ``ReadObjectOptions/resumePolicy`` (which defaults to ``StorageResumePolicy/defaultPolicy``, stopping after 3 consecutive errors without byte progress).

If the error is non-resumable or the resume policy limit is reached, ``ReadObjectError/resumeFailed(bytesReceived:underlyingError:)`` is thrown with the total number of bytes already yielded to your loop.

To increase resilience on unstable networks, customize ``ReadObjectOptions/resumePolicy``:

```swift
let options = ReadObjectOptions().with {
  $0.resumePolicy = StorageResumePolicy<ReadObjectDetails>.unbounded()
    .stopOnConsecutiveErrors(5)
    .withTotalResumeLimit(20)
}
```

You can also manually resume from `bytesReceived` by requesting a ``ReadObjectRange`` starting at that offset and pinning the object's generation from the initial metadata:

```swift
if let resumeRange = ReadObjectRange(fromOffset: bytesReceived) {
  let resumeOptions = ReadObjectOptions().with {
    $0.range = resumeRange
    $0.generation = initialMetadata.generation
  }
  let resumedDownload = client.readObject(from: bucket, object: object, options: resumeOptions)
  for try await chunk in resumedDownload.body {
    // Append remaining chunks...
  }
}
```

### Common Service and Precondition Errors

When Cloud Storage returns an error response (either on the initial request or during resumption), ``ReadObjectError/requestError(_:)`` wraps a `GoogleGax.RequestError.service(ServiceError)`:

- **HTTP 404 (`.notFound`)**: The bucket or object (or the requested ``ReadObjectOptions/generation``) does not exist.
- **HTTP 412 (`.failedPrecondition`)**: A condition in ``ReadObjectOptions/preconditions`` (such as `ifGenerationMatch` or `ifMetagenerationMatch`) was not satisfied.
- **HTTP 403 (`.permissionDenied`)**: The caller lacks `storage.objects.get` permission, or the bucket has Requester Pays enabled and ``ReadObjectOptions/quotaProject`` was not set.
- **HTTP 400 (`.invalidArgument`)**: An option such as ``ReadObjectOptions/customerEncryptionKey`` (CSEK) does not match the key used to encrypt the object.

---

## Handling Upload Errors (`WriteObjectError`)

`StorageClient.writeObject(_:to:as:options:)` and its overloads throw ``WriteObjectError`` when an upload fails:

```swift
import Foundation
import GoogleCloudStorage
import GoogleGax
import GoogleRpc

func uploadFileAtomically(
  client: StorageClient,
  fileURL: URL,
  bucket: String,
  objectName: String
) async throws -> Object {
  let options = WriteObjectOptions().with {
    // Only succeed if the object does not already exist.
    $0.preconditions = StoragePreconditions().with {
      $0.ifGenerationMatch = 0
    }
  }

  do {
    return try await client.writeObject(
      fileURL,
      to: bucket,
      as: objectName,
      options: options
    )
  } catch let error as WriteObjectError {
    switch error {
    case .requestError(let requestError):
      if case .service(let serviceError) = requestError {
        switch serviceError.code {
        case .failedPrecondition:
          print("Object '\(objectName)' already exists (precondition failed).")
        case .permissionDenied:
          print("Permission denied (check IAM roles or quotaProject): \(serviceError.message)")
        case .notFound:
          print("Bucket '\(bucket)' not found or upload session expired.")
        default:
          print("Storage service error (\(serviceError.code)): \(serviceError.message)")
        }
      } else if case .exhausted(let exhaustedError) = requestError {
        print("Upload retry/resume policy exhausted: \(exhaustedError)")
      }
      throw error

    case .sourceError(let sourceError):
      print("Failed to read local upload source: \(sourceError)")
      throw error

    case .internalError(let message):
      print("Upload state error: \(message)")
      throw error

    case .invalidRangeHeader(let header):
      print("Malformed Range header from server: \(header)")
      throw error

    case .unexpectedServerResponse(let statusCode, let message):
      print("Unexpected HTTP \(statusCode): \(message)")
      throw error

    @unknown default:
      throw error
    }
  }
}
```

### Resuming Uploads: `SeekableWriteObjectSource` vs. `WriteObjectSource`

`StorageClient` provides two `writeObject` overloads for custom and built-in data sources:

1. **Seekable sources (``SeekableWriteObjectSource``)**: Includes ``FileSource`` (and `URL`), ``BytesSource`` (and `Data` or ``ByteChunk``), and custom types implementing `seek(to:)`.
2. **Non-seekable streaming sources (``WriteObjectSource``)**: Includes ``StreamSource`` (wrapping an `AsyncSequence`) and sequential streams whose content cannot be rewound.

During a resumable upload, if a network error interrupts a chunk transfer, the client queries Cloud Storage for the last durably committed byte offset:

- With a ``SeekableWriteObjectSource``, the client calls `seek(to: committedBytes)` to rewind or advance to the exact offset reported by the server, making resumption resilient across arbitrary chunk boundaries.
- With a non-seekable ``WriteObjectSource``, the client only buffers the single in-flight chunk currently being sent. If the server reports a committed offset within that in-flight chunk, the client slices the remaining bytes and continues. However, if the server reports an offset prior to the current chunk window, the stream cannot be rewound and `writeObject` throws ``WriteObjectError/internalError(_:)``.

> Tip: Prefer ``SeekableWriteObjectSource`` (such as uploading from a local file `URL`, ``FileSource``, `Data`, or ``BytesSource``) whenever possible so resumable uploads can recover from any server-reported byte offset.

### Single-Shot vs. Resumable Upload Idempotency

By default, uploads with a known `totalSize` strictly less than ``WriteObjectOptions/resumableUploadThreshold`` (8 MB) use a single-shot multipart upload request, while larger uploads (or streams with `totalSize == nil`) use a multi-chunk resumable upload session:

- **Resumable uploads** are always idempotent because the session URI guarantees the object is created at most once. Transient network and 5xx errors are automatically resumed according to ``WriteObjectOptions/resumePolicy``.
- **Single-shot uploads** are only treated as idempotent by default when ``WriteObjectOptions/preconditions`` specifies `ifGenerationMatch` or `ifMetagenerationMatch`. Without preconditions, a retried single-shot upload could overwrite a concurrent update or create duplicate object versions, so transient errors immediately fail with ``WriteObjectError/requestError(_:)``.

To make single-shot uploads safe to retry automatically:

- Set `ifGenerationMatch = 0` when creating a new object that must not overwrite an existing object:
  ```swift
  let options = WriteObjectOptions().with {
    $0.preconditions = StoragePreconditions().with {
      $0.ifGenerationMatch = 0
    }
  }
  ```
- Set `ifGenerationMatch = existingObject.generation` when updating a known object revision.
- Or, if overwriting without preconditions is acceptable for your workload, explicitly opt into retries by setting ``WriteObjectOptions/idempotency`` to `true`:
  ```swift
  let options = WriteObjectOptions().with {
    $0.idempotency = true
  }
  ```

### Local Data Source Errors (`sourceError`)

When the underlying ``WriteObjectSource`` or ``SeekableWriteObjectSource`` throws an error while reading or seeking, `writeObject` wraps it in ``WriteObjectError/sourceError(_:)``. Built-in sources (`FileSource`, `BytesSource`, `StreamSource`) throw ``WriteObjectSourceError``:

- ``WriteObjectSourceError/readFailed(underlyingError:)``: Opening or reading from the local file or `AsyncSequence` failed (for example, the file does not exist, permissions were denied, or the upstream sequence threw an error).
- ``WriteObjectSourceError/offsetOutOfBounds(offset:size:)``: A seek operation requested an offset beyond the end of the source (for example, if a local file was truncated while an upload was in progress).
