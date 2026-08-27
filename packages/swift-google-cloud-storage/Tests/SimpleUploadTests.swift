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

import Crypto
import Foundation
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct SimpleUploadTests {
  private func sampleKey() -> (data: Data, keyBase64: String, keyHashBase64: String) {
    let keyData = Data(repeating: 0x42, count: 32)
    let keyBase64 = keyData.base64EncodedString()
    let sha256Digest = SHA256.hash(data: keyData)
    let keyHashBase64 = Data(sha256Digest).base64EncodedString()
    return (keyData, keyBase64, keyHashBase64)
  }

  private func makeClient(
    registry: MockRegistry,
    retryPolicy: (any RetryPolicy)? = nil,
    uploadResumePolicy: (any ResumePolicy<UploadDetails>)? = nil,
    uploadThreshold: Int? = nil
  ) throws -> StorageClient {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
        if let retryPolicy {
          $0.retryPolicy = retryPolicy
        }
      }
      if let uploadResumePolicy {
        $0.upload.resumePolicy = uploadResumePolicy
      }
      if let uploadThreshold {
        $0.upload.resumableUploadThreshold = uploadThreshold
      }
    }
    return try StorageClient(options, mock: registry)
  }

  /// Tests a successful simple (single-part) upload for payloads smaller than the 8MB resumable threshold.
  @Test func simpleUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: Data("{\"name\":\"\(objectName)\"}".utf8),
        headers: ["Content-Type": "application/json"]),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  /// Tests error propagation when the underlying `UploadSource` fails to read source data during a simple upload.
  @Test func simpleUploadSourceReadError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    struct DummyError: Error {}
    let source = MockUploadSource(data: data, readError: DummyError())

    let client = try makeClient(registry: registry)

    await expectError(DummyError.self) {
      try await client.upload(source, to: bucket, as: objectName)
    }
  }

  /// Tests handling of network failure (URLError) during a simple upload.
  @Test func simpleUploadNetworkFailure() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .failure(URLError(.cannotConnectToHost)),
      for: simpleUploadUrl)

    let client = try makeClient(
      registry: registry, uploadResumePolicy: NeverResume<UploadDetails>())

    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName)
    }
    if case .io(let underlying as URLError) = error {
      #expect(underlying.code == URLError.cannotConnectToHost)
    } else {
      Issue.record("Expected RequestError.io(URLError), got \(String(describing: error))")
    }
  }

  /// Tests handling of HTTP error responses (e.g., HTTP 500) during a simple upload.
  @Test func simpleUploadHTTPError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 500, data: Data("Internal Server Error".utf8),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)

    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName)
    }
    if case .http(let details) = error {
      #expect(details.http_status_code == 500)
    } else {
      Issue.record("Expected .http RequestError, got \(String(describing: error))")
    }
  }

  /// Tests handling of malformed/invalid JSON returned by GCS on a simple upload.
  @Test func simpleUploadInvalidJSONError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: Data("invalid json content".utf8),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)

    let error = await expectError(DecodingError.self) {
      try await client.upload(source, to: bucket, as: objectName)
    }
    #expect(error != nil)
  }

  /// Tests error handling when `UploadSource.read` unexpectedly returns `nil` before payload bytes are read.
  @Test func simpleUploadSourceReturnsNil() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let source = MockUploadSource(data: Data(), totalSize: 1024)

    let client = try makeClient(registry: registry)

    let error = await expectUploadError {
      try await client.upload(source, to: bucket, as: objectName)
    }
    if case .internalError(let message) = error {
      #expect(message == "Failed to read data from source")
    }
  }

  @Test func simpleUploadWithCSEKHeaders() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-csek-object"
    let data = Data(repeating: 1, count: 1024)
    let source = BytesSource(data: data)

    let sample = sampleKey()
    let csek = try CustomerEncryptionKeyOptions(key: sample.data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    let responseJSON = """
      {
        "name": "\(objectName)",
        "bucket": "\(bucket)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "application/octet-stream",
        "customerEncryption": {
          "encryptionAlgorithm": "AES256",
          "keySha256": "\(sample.keyHashBase64)"
        }
      }
      """

    registry.register(
      response: .success(
        statusCode: 200, data: responseJSON.data(using: .utf8)!,
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with { $0.customerEncryptionKey = csek }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.customerEncryption?.encryptionAlgorithm == "AES256")
    #expect(object.customerEncryption?.keySha256 == sample.keyHashBase64)

    let requests = registry.recordedRequests()
    #expect(!requests.isEmpty)
    let uploadReq = requests.first {
      $0.url?.path.contains("/upload/storage/v1/b/\(bucket)/o") == true
    }
    #expect(uploadReq != nil)
    #expect(uploadReq?.value(forHTTPHeaderField: "x-goog-encryption-algorithm") == "AES256")
    #expect(uploadReq?.value(forHTTPHeaderField: "x-goog-encryption-key") == sample.keyBase64)
    #expect(
      uploadReq?.value(forHTTPHeaderField: "x-goog-encryption-key-sha256") == sample.keyHashBase64)
  }

  /// Tests that a 503 (unavailable) response during simple upload is retryable and automatically handled by the retry loop.
  @Test func simpleUploadTransientFailureRetriesAndSucceeds() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-simple-retry"
    let data = Data(repeating: 0x42, count: 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    // 1. First attempt fails with 503 Service Unavailable
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: nil),
      for: simpleUploadUrl)

    // 2. Retry attempt succeeds with 200 OK
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(
      registry: registry,
      retryPolicy: BaseRetryPolicy().withAttemptLimit(3)
    )
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
  }

  /// Tests that a 503 error with NeverResume policy throws immediately without retrying.
  @Test func simpleUploadTransientFailureWithNeverResumeFails() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-simple-never-resume"
    let data = Data(repeating: 0x42, count: 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(
      registry: registry, uploadResumePolicy: NeverResume<UploadDetails>())

    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName)
    }
    #expect(error != nil)
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  /// Tests that configuring resumePolicy on UploadOptions overrides client-level retry policy for simple uploads.
  @Test func simpleUploadWithCustomUploadOptionsResumePolicyOverridesClient() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-simple-override-resume"
    let data = Data(repeating: 0x42, count: 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.resumePolicy = NeverResume()
    }

    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    }
    #expect(error != nil)
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  /// Tests that configuring a higher `resumableUploadThreshold` on `UploadOptions` allows a payload >= 8MB to use simple upload.
  @Test func simpleUploadWithCustomThresholdAboveDefault() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-simple-custom-threshold"
    let data = Data(repeating: 0xAB, count: 10 * 1024 * 1024)  // 10MB (> 8MB default threshold)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 16 * 1024 * 1024  // 16MB threshold
    }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.url?.absoluteString == simpleUploadUrl.absoluteString)
  }

  /// Tests that configuring `resumableUploadThreshold` on `StorageClientOptions.upload` (client level) allows a payload >= 8MB to use simple upload without specifying request options.
  @Test func simpleUploadWithClientUploadOptionsThresholdAboveDefault() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-simple-client-threshold"
    let data = Data(repeating: 0xAC, count: 10 * 1024 * 1024)  // 10MB (> 8MB default threshold)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry, uploadThreshold: 16 * 1024 * 1024)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.url?.absoluteString == simpleUploadUrl.absoluteString)
  }

  /// Tests that provided `UploadOptions.resumableUploadThreshold` overrides client-level threshold.
  @Test func simpleUploadWithProvidedOptionsOverridingClientUploadOptions() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-simple-override-client-threshold"
    let data = Data(repeating: 0xAD, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: simpleUploadUrl)

    // Client has lower threshold (4MB), but call-level options sets 16MB -> simple upload is chosen
    let client = try makeClient(registry: registry, uploadThreshold: 4 * 1024 * 1024)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 16 * 1024 * 1024
    }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.url?.absoluteString == simpleUploadUrl.absoluteString)
  }

  /// Tests a successful simple upload for a 0-byte payload using BytesSource.
  @Test func simpleUploadZeroByteSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-empty-object"
    let data = Data()
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: 0),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == 0)

    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
    let req = requests.first!
    #expect(req.value(forHTTPHeaderField: "x-goog-hash") == "crc32c=AAAAAA==")
  }

  /// Tests convenience upload of in-memory Data with 0 bytes and preconditions.
  @Test func simpleUploadZeroByteDataWithPreconditions() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-empty-data"
    let data = Data()

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)&ifGenerationMatch=0"
    )

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: 0),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let options = UploadOptions().with {
      $0.preconditions = StoragePreconditions().with {
        $0.ifGenerationMatch = 0
      }
    }
    let object = try await client.upload(data, to: bucket, as: objectName, options: options)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == 0)
  }

  /// Tests uploading an empty local file via FileSource.
  @Test func simpleUploadZeroByteFileSource() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
    let fileURL = tempDirectory.appendingPathComponent("empty_\(UUID().uuidString).txt")
    try Data().write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-empty-file"

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: 0),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let object = try await client.upload(fileURL, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == 0)
  }

  /// Tests that uploading using a bucket resource name (e.g. `projects/_/buckets/my-bucket`) extracts the bucket ID for the request and returns the resource name.
  @Test func simpleUploadWithBucketResourceName() async throws {
    let registry = MockRegistry.create()
    let rawBucket = "my-bucket"
    let bucketResource = "projects/_/buckets/\(rawBucket)"
    let objectName = "test-resource-bucket-object"
    let data = Data("Hello Resource Name".utf8)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(rawBucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: rawBucket, size: data.count),
        headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucketResource, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == bucketResource)
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.url?.absoluteString == simpleUploadUrl.absoluteString)
  }
}
