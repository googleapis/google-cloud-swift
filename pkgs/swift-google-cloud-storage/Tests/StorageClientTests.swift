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
@_spi(GoogleCloudInternal) import GoogleAuth
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct StorageClientTests {
  @Test func initializationWithOptions() throws {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = "https://override.googleapis.com"
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options)
    #expect(client.options.client.endpoint == "https://override.googleapis.com")
    #expect(client.inner.clientHeader.build().contains("gccl/\(PackageVersion.version)"))
    #expect(client.inner.clientHeader.build().contains("rest/"))
  }

  static func assertSendable<T: Sendable>(_ type: T.Type) {}

  @Test func clientIsSendable() {
    Self.assertSendable(StorageClient.self)
  }

  @Test func protocolIsSendable() {
    Self.assertSendable((any StorageProtocol).self)
  }

  struct SendableStorageHolder: Sendable {
    let storage: any StorageProtocol
  }

  @Test func protocolCanBeStoredInSendableType() {
    let holder = SendableStorageHolder(storage: MockStorage())
    Self.assertSendable(type(of: holder))
  }

  @Test func mockStorageDefaultImplementationsThrowUnimplemented() async throws {
    let mock = MockStorage()
    let client: any StorageProtocol = mock
    let source = BytesSource(data: Data("test".utf8))

    await #expect(throws: GoogleGax.RequestError.self) {
      try await client.writeObject(source, to: "bucket", as: "object", options: .default)
    }

    // TODO(https://github.com/googleapis/google-cloud-swift/issues/1109) - restore this code.
    // await #expect(throws: GoogleGax.RequestError.self) {
    //   try await client.resumeWriteObject(source, uploadId: "session-id", options: .default)
    // }

    let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    await #expect(throws: GoogleGax.RequestError.self) {
      try await client.writeObject(tempFileURL, to: "bucket", as: "object", options: .default)
    }

    await #expect(throws: GoogleGax.RequestError.self) {
      try await client.writeObject(
        Data("test".utf8), to: "bucket", as: "object", options: .default)
    }

    let readHandle = client.readObject(from: "bucket", object: "object")
    readHandle.cancel()
    await #expect(throws: GoogleGax.RequestError.self) {
      _ = try await readHandle.metadata
    }
    await #expect(throws: GoogleGax.RequestError.self) {
      for try await _ in readHandle.body {}
    }
    #expect(mock.isExhausted)
  }

  @Test func mockStorageReadObjectDelegation() async throws {
    let mock = MockStorage(read: [
      { bucket, object, _ in
        let metadata = ReadObjectMetadata().with {
          $0.bucket = bucket
          $0.name = object
          $0.size = 11
        }
        return MockReadObjectHandle(
          metadata: metadata,
          chunks: [ByteChunk(Data("hello ".utf8)), ByteChunk(Data("world".utf8))]
        )
      }
    ])

    let client: any StorageProtocol = mock
    let download = client.readObject(from: "test-bucket", object: "test-object")
    let metadata = try await download.metadata
    #expect(metadata.bucket == "test-bucket")
    #expect(metadata.name == "test-object")
    #expect(metadata.size == 11)

    var received = Data()
    for try await chunk in download.body {
      received.append(chunk.data)
    }
    #expect(received == Data("hello world".utf8))
    #expect(mock.isExhausted)
  }

  @Test func mockStorageConvenienceOverloadDelegation() async throws {
    let expectBytes: MockStorage.WriteSeekableHandler = { source, bucket, objectName, _ in
      guard let bytesSource = source as? BytesSource else {
        Issue.record("Expected BytesSource, got \(type(of: source))")
        return Object()
      }
      #expect(Data(bytesSource.buffer) == Data("hello".utf8))
      #expect(bucket == "test-bucket")
      #expect(objectName == "test-object")
      var obj = Object()
      obj.name = objectName
      return obj
    }
    let expectFile: MockStorage.WriteSeekableHandler = { source, bucket, objectName, _ in
      guard let fileSource = source as? FileSource else {
        Issue.record("Expected FileSource, got \(type(of: source))")
        return Object()
      }
      #expect(fileSource.fileURL.lastPathComponent == "test-upload.txt")
      #expect(bucket == "test-bucket")
      #expect(objectName == "test-file-object")
      var obj = Object()
      obj.name = objectName
      return obj
    }
    let mock = MockStorage(writeSeekable: [
      expectBytes,
      expectFile,
      expectBytes,
      expectFile,
    ])

    let client: any StorageProtocol = mock
    let dataResult = try await client.writeObject(
      Data("hello".utf8), to: "test-bucket", as: "test-object")
    #expect(dataResult.name == "test-object")

    let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "test-upload.txt")
    let urlResult = try await client.writeObject(
      tempFileURL, to: "test-bucket", as: "test-file-object")
    #expect(urlResult.name == "test-file-object")

    func uploadGeneric<S: StorageProtocol>(_ storage: S) async throws {
      let r1 = try await storage.writeObject(
        Data("hello".utf8), to: "test-bucket", as: "test-object")
      #expect(r1.name == "test-object")
      let r2 = try await storage.writeObject(
        tempFileURL, to: "test-bucket", as: "test-file-object")
      #expect(r2.name == "test-file-object")
    }
    try await uploadGeneric(mock)
    #expect(mock.isExhausted)
  }

  @Test func mockStorageSeekableDelegatesToWriteObjectSourceByDefault() async throws {
    let mock = UnseekableMockStorage(write: [
      { _, bucket, objectName, _ in
        var obj = Object()
        obj.bucket = bucket
        obj.name = objectName
        return obj
      }
    ])

    let client: any StorageProtocol = mock
    let result = try await client.writeObject(
      Data("hello".utf8), to: "fallback-bucket", as: "fallback-object")
    #expect(result.bucket == "fallback-bucket")
    #expect(result.name == "fallback-object")
    #expect(mock.isExhausted)
  }

  @Test(arguments: [
    ("https://private.googleapis.com", "storage.googleapis.com"),
    ("https://my-psc.p.googleapis.com", "storage.googleapis.com"),
    ("https://restricted.googleapis.com", "storage.googleapis.com"),
    ("https://storage.us-central1.rep.googleapis.com", "storage.us-central1.rep.googleapis.com"),
    ("https://us-central1-storage.googleapis.com", "us-central1-storage.googleapis.com"),
    ("https://storage.googleapis.com", "storage.googleapis.com"),
  ]) func hostHeaderWithEndpoint(endpoint: String, expectedHost: String) async throws {
    let registry = MockRegistry.create()
    let requestUrl = "\(endpoint)/storage/v1/b/test-bucket/o/test-obj?alt=media"
    registry.register(
      response: .success(statusCode: 200, data: Data("data".utf8)),
      for: requestUrl
    )

    let options = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = endpoint
        $0.credentials = try Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry, environment: [:])
    let task = client.readObject(from: "test-bucket", object: "test-obj")
    _ = try await task.metadata

    let request = registry.lastRequest(for: requestUrl)
    #expect(request?.value(forHTTPHeaderField: "Host") == expectedHost)
  }

  @Test(arguments: [
    (
      optionUniverse: "my-universe.com" as String?,
      environment: [:] as [String: String],
      expectedDomain: "my-universe.com"
    ),
    (
      optionUniverse: nil,
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"],
      expectedDomain: "env.universe.com"
    ),
  ])
  func hostHeaderWithUniverseDomain(
    optionUniverse: String?,
    environment: [String: String],
    expectedDomain: String
  ) async throws {
    let registry = MockRegistry.create()
    let requestUrl =
      "https://storage.\(expectedDomain)/storage/v1/b/test-bucket/o/test-obj?alt=media"
    registry.register(
      response: .success(statusCode: 200, data: Data("data".utf8)),
      for: requestUrl
    )

    let options = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.universeDomain = optionUniverse
        $0.credentials = try Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry, environment: environment)
    let task = client.readObject(from: "test-bucket", object: "test-obj")
    _ = try await task.metadata

    let request = registry.lastRequest(for: requestUrl)
    #expect(request?.value(forHTTPHeaderField: "Host") == "storage.\(expectedDomain)")
  }

  @Test func badUniverseDomain() throws {
    let registry = MockRegistry.create()
    let credentials = try Credentials(configuration: .anonymous)
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.universeDomain = "invalid/domain"
        $0.credentials = credentials
      }
    }
    #expect(throws: ClientError.self) {
      _ = try StorageClient(options)
    }
    #expect(throws: ClientError.self) {
      _ = try StorageClient(options, mock: registry, environment: [:])
    }
  }

  private struct ZeroBackoff: BackoffPolicy {
    func backoffDelay(for state: RetryState) -> Duration { .zero }
  }

  private static func unwrapIOError(_ requestError: RequestError) -> (any Error)? {
    switch requestError {
    case .io(let underlying):
      return underlying
    case .exhausted(let exhausted):
      if case .io(let underlying) = exhausted.underlyingError {
        return underlying
      }
      return nil
    default:
      return nil
    }
  }

  @Test(arguments: [
    (
      optionUniverse: "my-universe.com" as String?,
      environment: [:] as [String: String],
      expectedDomain: "my-universe.com"
    ),
    (
      optionUniverse: nil,
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"],
      expectedDomain: "env.universe.com"
    ),
  ])
  func readObjectUniverseDomainMismatch(
    optionUniverse: String?,
    environment: [String: String],
    expectedDomain: String
  ) async throws {
    let registry = MockRegistry.create()
    let endpoint = "https://private.\(expectedDomain)"
    let requestUrl = "\(endpoint)/storage/v1/b/test-bucket/o/test-obj?alt=media"
    registry.register(
      response: .success(statusCode: 200, data: Data("data".utf8)),
      for: requestUrl
    )

    let options = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = endpoint
        $0.universeDomain = optionUniverse
        $0.credentials = try Credentials(configuration: .apiKey("test-api-key"), environment: [:])
        $0.backoffPolicy = ZeroBackoff()
      }
    }
    let client = try StorageClient(options, mock: registry, environment: environment)
    let task = client.readObject(from: "test-bucket", object: "test-obj")
    let error = await #expect(throws: ReadObjectError.self) {
      _ = try await task.metadata
    }
    guard let error, case .requestError(let reqError) = error,
      let underlying = Self.unwrapIOError(reqError)
    else {
      Issue.record(
        "Expected ReadObjectError.requestError wrapping .io, got \(String(describing: error))")
      return
    }
    #expect(underlying is CredentialsError)
    #expect(String(describing: underlying).contains(expectedDomain))
    #expect(registry.lastRequest(for: requestUrl) == nil)
  }

  @Test(arguments: [
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      credentials: CredentialsConfiguration.apiKey("test-api-key"),
      expectedHost: "storage.googleapis.com"
    ),
    (
      endpoint: "https://private.my-universe.com",
      universeDomain: "my-universe.com",
      credentials: .anonymous,
      expectedHost: "storage.my-universe.com"
    ),
  ])
  func readObjectUniverseDomainSuccess(
    endpoint: String,
    universeDomain: String,
    credentials: CredentialsConfiguration,
    expectedHost: String
  ) async throws {
    let registry = MockRegistry.create()
    let requestUrl = "\(endpoint)/storage/v1/b/test-bucket/o/test-obj?alt=media"
    registry.register(
      response: .success(statusCode: 200, data: Data("data".utf8)),
      for: requestUrl
    )

    let options = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = endpoint
        $0.universeDomain = universeDomain
        $0.credentials = try Credentials(configuration: credentials, environment: [:])
      }
    }
    let client = try StorageClient(options, mock: registry, environment: [:])
    let task = client.readObject(from: "test-bucket", object: "test-obj")
    _ = try await task.metadata
    let request = registry.lastRequest(for: requestUrl)
    #expect(request?.value(forHTTPHeaderField: "Host") == expectedHost)
  }

  @Test(arguments: [false, true])
  func writeObjectUniverseDomainMismatch(useResumable: Bool) async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-obj"
    let endpoint = "https://private.my-universe.com"
    let uploadType = useResumable ? "resumable" : "multipart"
    let uploadUrl =
      "\(endpoint)/upload/storage/v1/b/\(bucket)/o?uploadType=\(uploadType)&name=\(objectName)"
    registry.register(
      response: .success(
        statusCode: 200,
        data: Data("{\"name\":\"\(objectName)\"}".utf8),
        headers: [
          "Content-Type": "application/json",
          "Location": "\(uploadUrl)&upload_id=1",
        ]
      ),
      for: uploadUrl
    )

    let clientOptions = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = endpoint
        $0.universeDomain = "my-universe.com"
        $0.credentials = try Credentials(configuration: .apiKey("test-api-key"), environment: [:])
        $0.backoffPolicy = ZeroBackoff()
      }
    }
    let writeOptions = WriteObjectOptions().with {
      if useResumable {
        $0.resumableUploadThreshold = 0
      } else {
        $0.idempotent = true
      }
      $0.backoffPolicy = ZeroBackoff()
    }

    let client = try StorageClient(clientOptions, mock: registry, environment: [:])
    let error = await #expect(throws: WriteObjectError.self) {
      _ = try await client.writeObject(
        Data("hello world".utf8),
        to: bucket,
        as: objectName,
        options: writeOptions
      )
    }
    guard let error, case .requestError(let reqError) = error,
      let underlying = Self.unwrapIOError(reqError)
    else {
      Issue.record(
        "Expected WriteObjectError.requestError wrapping .io, got \(String(describing: error))")
      return
    }
    #expect(underlying is CredentialsError)
    #expect(registry.lastRequest(for: uploadUrl) == nil)
  }

  @Test(arguments: [
    (endpoint: nil as String?, expectedBase: "https://storage.my-universe.com"),
    (endpoint: "https://private.my-universe.com", expectedBase: "https://private.my-universe.com"),
  ])
  func writeObjectHostHeaderWithUniverseDomain(
    endpoint: String?,
    expectedBase: String
  ) async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-obj"
    let uploadUrl =
      "\(expectedBase)/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)"
    registry.register(
      response: .success(
        statusCode: 200,
        data: Data("{\"name\":\"\(objectName)\"}".utf8),
        headers: ["Content-Type": "application/json"]
      ),
      for: uploadUrl
    )

    let options = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = endpoint
        $0.universeDomain = "my-universe.com"
        $0.credentials = try Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry, environment: [:])
    _ = try await client.writeObject(Data("hello world".utf8), to: bucket, as: objectName)

    let request = registry.lastRequest(for: uploadUrl)
    #expect(request?.value(forHTTPHeaderField: "Host") == "storage.my-universe.com")
  }

  @Test func uploadHostHeaderWithOddEndpoint() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-obj"
    let endpoint = "https://private.googleapis.com"
    let uploadUrl =
      "\(endpoint)/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)"

    registry.register(
      response: .success(
        statusCode: 200, data: Data("{\"name\":\"\(objectName)\"}".utf8),
        headers: ["Content-Type": "application/json"]),
      for: uploadUrl
    )

    let options = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = endpoint
        $0.credentials = try Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry, environment: [:])
    let data = Data("hello world".utf8)
    _ = try await client.writeObject(data, to: bucket, as: objectName)

    let request = registry.lastRequest(for: uploadUrl)
    #expect(request?.value(forHTTPHeaderField: "Host") == "storage.googleapis.com")
  }

  @Test(arguments: [
    (StorageLoadBalancer.p2c, 0),
    (StorageLoadBalancer.p2c, -3),
    (StorageLoadBalancer.roundRobin, 0),
    (StorageLoadBalancer.roundRobin, -3),
  ])
  func connectionPoolSizeClampsNonPositiveToSingleSlot(
    loadBalancer: StorageLoadBalancer,
    configuredPoolSize: Int
  ) async throws {
    let endpoint = "http://clamped-pool-test"
    let uploadUrl = "\(endpoint)/upload/storage/v1/b/test-bucket/o?uploadType=multipart&name=obj"
    let m0 = MockRegistry.create()
    let m1 = MockRegistry.create()
    for _ in 0..<3 {
      m0.register(
        response: .success(
          statusCode: 200,
          data: makeObjectJSON(name: "obj", bucket: "test-bucket", size: 5),
          headers: ["Content-Type": "application/json"]
        ),
        for: uploadUrl
      )
    }

    let options = StorageClientOptions().with {
      $0.client.endpoint = endpoint
      $0.client.credentials = try? Credentials(configuration: .anonymous)
      $0.connectionPoolSize = configuredPoolSize
      $0.loadBalancer = loadBalancer
    }
    var requestedPoolSize: Int?
    let client = try StorageClient(
      options,
      credentials: options.client.credentials,
      environment: [:]
    ) { poolSize in
      requestedPoolSize = poolSize
      return (0..<poolSize).map { $0 == 0 ? m0 : m1 }
    }
    let writeOptions = WriteObjectOptions().with { $0.idempotent = true }

    for _ in 0..<3 {
      _ = try await client.writeObject(
        Data("hello".utf8),
        to: "test-bucket",
        as: "obj",
        options: writeOptions
      )
    }

    #expect(requestedPoolSize == 1)
    #expect(m0.recordedRequests().count == 3)
    #expect(m1.recordedRequests().isEmpty)
  }

  @Test func pooledClientSharesCredentialsAndDistributesRoundRobin() async throws {
    let endpoint = "http://rr-pool-test"
    let uploadUrl = "\(endpoint)/upload/storage/v1/b/test-bucket/o?uploadType=multipart&name=obj"
    let m0 = MockRegistry.create()
    let m1 = MockRegistry.create()
    for mock in [m0, m1] {
      for _ in 0..<2 {
        mock.register(
          response: .success(
            statusCode: 200,
            data: makeObjectJSON(name: "obj", bucket: "test-bucket", size: 5),
            headers: ["Content-Type": "application/json"]
          ),
          for: uploadUrl
        )
      }
    }

    let options = StorageClientOptions().with {
      $0.client.endpoint = endpoint
      $0.client.credentials = try? Credentials(
        configuration: .apiKey("shared-test-key"),
        environment: [:]
      )
      $0.connectionPoolSize = 2
      $0.loadBalancer = .roundRobin
    }
    let client = try StorageClient(options, mocks: [m0, m1], environment: [:])
    let writeOptions = WriteObjectOptions().with { $0.idempotent = true }

    for _ in 0..<4 {
      _ = try await client.writeObject(
        Data("hello".utf8),
        to: "test-bucket",
        as: "obj",
        options: writeOptions
      )
    }

    let reqs0 = m0.recordedRequests()
    let reqs1 = m1.recordedRequests()
    #expect(reqs0.count == 2)
    #expect(reqs1.count == 2)
    #expect(
      reqs0.allSatisfy { $0.value(forHTTPHeaderField: "x-goog-api-key") == "shared-test-key" })
    #expect(
      reqs1.allSatisfy { $0.value(forHTTPHeaderField: "x-goog-api-key") == "shared-test-key" })
  }

  @Test func pooledClientHandlesReadObjectCancelWithP2C() async throws {
    let endpoint = "http://p2c-read-test"
    let requestUrl = "\(endpoint)/storage/v1/b/test-bucket/o/test-obj?alt=media"
    let m0 = MockRegistry.create()
    let m1 = MockRegistry.create()
    for mock in [m0, m1] {
      mock.register(
        response: .stream(
          statusCode: 200,
          chunks: [Data("chunk-1".utf8), Data("chunk-2".utf8)],
          headers: ["Content-Length": "14"]
        ),
        for: requestUrl
      )
    }

    let options = StorageClientOptions().with {
      $0.client.endpoint = endpoint
      $0.client.credentials = try? Credentials(configuration: .anonymous)
      $0.connectionPoolSize = 2
      $0.loadBalancer = .p2c
    }
    let client = try StorageClient(options, mocks: [m0, m1], seed: 1234, environment: [:])

    let handle1 = client.readObject(from: "test-bucket", object: "test-obj")
    _ = try await handle1.metadata

    let handle2 = client.readObject(from: "test-bucket", object: "test-obj")
    var data = Data()
    for try await chunk in handle2.body {
      data.append(chunk.data)
    }
    #expect(data == Data("chunk-1chunk-2".utf8))
    #expect(m0.recordedRequests().count == 1)
    #expect(m1.recordedRequests().count == 1)

    handle1.cancel()
    await #expect(throws: CancellationError.self) {
      for try await _ in handle1.body {}
    }
  }

  @Test(arguments: [
    // VPC-SC endpoint: Location returns storage.<universe>, subsequent chunk PUT routes via private.<universe>
    (
      endpoint: "https://private.my-universe.com" as String?,
      universeDomain: "my-universe.com",
      expectedStartBase: "https://private.my-universe.com",
      locationBase: "https://storage.my-universe.com",
      expectedChunkBase: "https://private.my-universe.com",
      expectedStartHost: "storage.my-universe.com",
      expectedChunkHost: "storage.my-universe.com"
    ),
    // PSC endpoint: Location returns regional upload host, chunk PUT routes via PSC with regional Host header
    (
      endpoint: "https://my-psc.p.googleapis.com",
      universeDomain: "googleapis.com",
      expectedStartBase: "https://my-psc.p.googleapis.com",
      locationBase: "https://storage.us-central1.rep.googleapis.com",
      expectedChunkBase: "https://my-psc.p.googleapis.com",
      expectedStartHost: "storage.googleapis.com",
      expectedChunkHost: "storage.us-central1.rep.googleapis.com"
    ),
    // Default endpoint: Location returns regional upload host, chunk PUT connects to regional host with regional Host header
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      expectedStartBase: "https://storage.googleapis.com",
      locationBase: "https://storage.us-central1.rep.googleapis.com",
      expectedChunkBase: "https://storage.us-central1.rep.googleapis.com",
      expectedStartHost: "storage.googleapis.com",
      expectedChunkHost: "storage.us-central1.rep.googleapis.com"
    ),
    // Regional endpoint: Location matches regional host
    (
      endpoint: "https://storage.us-central1.rep.googleapis.com",
      universeDomain: "googleapis.com",
      expectedStartBase: "https://storage.us-central1.rep.googleapis.com",
      locationBase: "https://storage.us-central1.rep.googleapis.com",
      expectedChunkBase: "https://storage.us-central1.rep.googleapis.com",
      expectedStartHost: "storage.us-central1.rep.googleapis.com",
      expectedChunkHost: "storage.us-central1.rep.googleapis.com"
    ),
    // Custom HTTPS proxy: Location matches custom proxy origin
    (
      endpoint: "https://my-proxy.example.com:8443",
      universeDomain: "googleapis.com",
      expectedStartBase: "https://my-proxy.example.com:8443",
      locationBase: "https://my-proxy.example.com:8443",
      expectedChunkBase: "https://my-proxy.example.com:8443",
      expectedStartHost: "my-proxy.example.com",
      expectedChunkHost: "my-proxy.example.com"
    ),
  ])
  func resumableWriteObjectRoutingAndHostHeader(
    endpoint: String?,
    universeDomain: String,
    expectedStartBase: String,
    locationBase: String,
    expectedChunkBase: String,
    expectedStartHost: String,
    expectedChunkHost: String
  ) async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-obj"
    let startUrl =
      "\(expectedStartBase)/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)"
    let locationUrl =
      "\(locationBase)/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=session-1"
    let expectedChunkUrl =
      "\(expectedChunkBase)/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=session-1"

    registry.register(
      response: .success(
        statusCode: 200,
        data: Data(),
        headers: ["Location": locationUrl]
      ),
      for: startUrl
    )
    registry.register(
      response: .success(
        statusCode: 200,
        data: Data("{\"name\":\"\(objectName)\"}".utf8),
        headers: ["Content-Type": "application/json"]
      ),
      for: expectedChunkUrl
    )

    let clientOptions = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = endpoint
        $0.universeDomain = universeDomain
        $0.credentials = try Credentials(configuration: .anonymous)
      }
      $0.writeObject.resumableUploadThreshold = 0
    }
    let client = try StorageClient(clientOptions, mock: registry, environment: [:])
    let object = try await client.writeObject(
      Data("hello world".utf8), to: bucket, as: objectName)
    #expect(object.name == objectName)

    let startReq = registry.lastRequest(for: startUrl)
    #expect(startReq?.value(forHTTPHeaderField: "Host") == expectedStartHost)

    let chunkReq = registry.lastRequest(for: expectedChunkUrl)
    #expect(chunkReq != nil)
    #expect(chunkReq?.value(forHTTPHeaderField: "Host") == expectedChunkHost)
  }

  @Test func defaultADCValidatesEndpointBeforeADCAndForwardsEnvironment() async throws {
    let registry = MockRegistry.create()

    // Invalid endpoint/universe fails fast with ClientError.invalidEndpoint before ADC disk/MDS resolution.
    let badOptions = StorageClientOptions().with {
      $0.client = .init().with {
        $0.universeDomain = "invalid/domain"
      }
    }
    #expect(throws: ClientError.self) {
      _ = try StorageClient(
        badOptions,
        credentials: nil,
        resolveDefaultADC: true,
        environment: ["NO_GCE_CHECK": "1"],
        makeClients: { _ in [registry] }
      )
    }

    // Default ADC forwards environment to Credentials(environment:) and catches file mismatch on request.
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json"
    )
    defer { try? FileManager.default.removeItem(at: tempFile) }
    try Data(
      """
      {
        "type": "authorized_user",
        "client_id": "id",
        "client_secret": "secret",
        "refresh_token": "refresh",
        "universe_domain": "googleapis.com"
      }
      """.utf8
    ).write(to: tempFile)

    let mismatchOptions = StorageClientOptions().with {
      $0.client = .init().with {
        $0.backoffPolicy = ZeroBackoff()
      }
    }
    let mismatchClient = try StorageClient(
      mismatchOptions,
      credentials: nil,
      resolveDefaultADC: true,
      environment: [
        "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
        "GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com",
      ],
      makeClients: { _ in [registry] }
    )
    let task = mismatchClient.readObject(from: "test-bucket", object: "test-obj")
    let error = await #expect(throws: ReadObjectError.self) {
      _ = try await task.metadata
    }
    guard let error, case .requestError(let reqError) = error,
      let underlying = Self.unwrapIOError(reqError)
    else {
      Issue.record(
        "Expected ReadObjectError.requestError wrapping .io, got \(String(describing: error))"
      )
      return
    }
    #expect(underlying is CredentialsError)
  }
}
