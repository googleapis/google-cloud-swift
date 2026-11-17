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
import Synchronization
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
    let client = try StorageClient(options, mock: registry)
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
        $0.credentials = try Credentials(configuration: .apiKey("test-api-key"))
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
        $0.credentials = try Credentials(configuration: credentials)
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
        $0.credentials = try Credentials(configuration: .apiKey("test-api-key"))
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
    let client = try StorageClient(options, mock: registry)
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
      $0.client.credentials = try? Credentials(configuration: .apiKey("shared-test-key"))
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

  private final class SequencedAccessTokenProvider: AccessTokenProvider, Sendable {
    private struct State: Sendable {
      var results: [Result<AccessToken, any Error>]
      var callCount = 0
    }

    private let state: Mutex<State>

    init(_ results: [Result<AccessToken, any Error>]) {
      self.state = Mutex(State(results: results))
    }

    var callCount: Int {
      state.withLock { $0.callCount }
    }

    func accessToken() async throws -> AccessToken {
      let next = state.withLock { s -> Result<AccessToken, any Error> in
        s.callCount += 1
        if s.results.count > 1 {
          return s.results.removeFirst()
        }
        return s.results[0]
      }
      return try next.get()
    }
  }

  @Test func readObjectPermanentCredentialsErrorFailsWithoutResuming() async throws {
    struct PermanentAuthError: Error {}

    // 1. Initial download token fetch fails permanently -> 1 provider call, 0 HTTP requests.
    let initialRegistry = MockRegistry.create()
    let initialProvider = SequencedAccessTokenProvider([.failure(PermanentAuthError())])
    let initialOptions = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = initialRegistry.endpoint
        $0.credentials = try Credentials(
          configuration: .accessToken(AccessTokenConfig(provider: initialProvider))
        )
        $0.backoffPolicy = ZeroBackoff()
      }
    }
    let initialClient = try StorageClient(initialOptions, mock: initialRegistry, environment: [:])
    let initialHandle = initialClient.readObject(
      from: "test-bucket",
      object: "test-obj",
      options: ReadObjectOptions().with { $0.backoffPolicy = ZeroBackoff() }
    )
    let initialErr = await #expect(throws: ReadObjectError.self) {
      _ = try await initialHandle.metadata
    }
    #expect(initialProvider.callCount == 1)
    #expect(initialRegistry.recordedRequests().isEmpty)
    if let initialErr, case .requestError(.io(let underlying)) = initialErr {
      #expect(underlying is CredentialsError)
    } else {
      Issue.record(
        "Expected ReadObjectError.requestError(.io), got \(String(describing: initialErr))")
    }

    // 2. Mid-stream drop followed by permanent token refresh failure -> 2 provider calls total (no extra resumes).
    let streamRegistry = MockRegistry.create()
    let requestUrl = "\(streamRegistry.endpoint)/storage/v1/b/test-bucket/o/test-obj?alt=media"
    streamRegistry.register(
      response: .stream(
        statusCode: 200,
        chunks: [Data("hello ".utf8)],
        error: MockNetworkError(),
        headers: ["Content-Length": "11", "x-goog-generation": "1"]
      ),
      for: requestUrl
    )
    let midStreamProvider = SequencedAccessTokenProvider([
      .success(AccessToken(token: "initial-token")),
      .failure(PermanentAuthError()),
    ])
    let midStreamOptions = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = streamRegistry.endpoint
        $0.credentials = try Credentials(
          configuration: .accessToken(AccessTokenConfig(provider: midStreamProvider))
        )
        $0.backoffPolicy = ZeroBackoff()
      }
    }
    let midStreamClient = try StorageClient(
      midStreamOptions, mock: streamRegistry, environment: [:])
    let midStreamHandle = midStreamClient.readObject(
      from: "test-bucket",
      object: "test-obj",
      options: ReadObjectOptions().with { $0.backoffPolicy = ZeroBackoff() }
    )
    let resumeErr = await #expect(throws: ReadObjectError.self) {
      for try await _ in midStreamHandle.body {}
    }
    #expect(midStreamProvider.callCount == 2)
    #expect(streamRegistry.recordedRequests().count == 1)
    if let resumeErr, case .resumeFailed(let bytesReceived, .io(let underlying)) = resumeErr {
      #expect(bytesReceived == 6)
      #expect(underlying is CredentialsError)
    } else {
      Issue.record(
        "Expected ReadObjectError.resumeFailed(.io), got \(String(describing: resumeErr))")
    }
  }

  @Test func readObjectTransientCredentialsErrorResumesAndRecovers() async throws {
    let registry = MockRegistry.create()
    let initialUrl = "\(registry.endpoint)/storage/v1/b/test-bucket/o/test-obj?alt=media"
    let resumeUrl =
      "\(registry.endpoint)/storage/v1/b/test-bucket/o/test-obj?alt=media&generation=1"
    registry.register(
      response: .stream(
        statusCode: 200,
        chunks: [Data("hello ".utf8)],
        error: MockNetworkError(),
        headers: ["Content-Length": "11", "x-goog-generation": "1"]
      ),
      for: initialUrl
    )
    registry.register(
      response: .stream(
        statusCode: 206,
        chunks: [Data("world".utf8)],
        headers: [
          "Content-Length": "5",
          "Content-Range": "bytes 6-10/11",
          "x-goog-generation": "1",
        ]
      ),
      for: resumeUrl
    )

    let provider = SequencedAccessTokenProvider([
      .success(AccessToken(token: "token-1")),
      .failure(
        CredentialsError._transientCannotFetchToken(
          message: "temporary MDS 503",
          underlyingError: URLError(.timedOut)
        )
      ),
      .success(AccessToken(token: "token-2")),
    ])
    let clientOptions = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try Credentials(
          configuration: .accessToken(AccessTokenConfig(provider: provider))
        )
        $0.backoffPolicy = ZeroBackoff()
      }
    }
    let client = try StorageClient(clientOptions, mock: registry, environment: [:])
    let handle = client.readObject(
      from: "test-bucket",
      object: "test-obj",
      options: ReadObjectOptions().with {
        $0.backoffPolicy = ZeroBackoff()
        $0.checksums = .none
      }
    )

    var collected = Data()
    for try await chunk in handle.body {
      collected.append(chunk.data)
    }
    #expect(collected == Data("hello world".utf8))
    #expect(provider.callCount == 3)
    #expect(registry.recordedRequests().count == 2)
    #expect(
      registry.lastRequest(for: resumeUrl)?.value(forHTTPHeaderField: "Authorization")
        == "Bearer token-2")
  }

  @Test func writeObjectResumableCredentialsErrorRetryability() async throws {
    struct PermanentAuthError: Error {}
    let bucket = "test-bucket"
    let objectName = "test-obj"
    let payload = Data("resumable-payload".utf8)

    // 1. Permanent credential error on session start fails after 1 attempt without resuming.
    let permRegistry = MockRegistry.create()
    let permProvider = SequencedAccessTokenProvider([.failure(PermanentAuthError())])
    let permClientOptions = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = permRegistry.endpoint
        $0.credentials = try Credentials(
          configuration: .accessToken(AccessTokenConfig(provider: permProvider))
        )
        $0.backoffPolicy = ZeroBackoff()
      }
    }
    let permClient = try StorageClient(permClientOptions, mock: permRegistry, environment: [:])
    let writeOptions = WriteObjectOptions().with {
      $0.resumableUploadThreshold = 0
      $0.backoffPolicy = ZeroBackoff()
    }
    let permErr = await #expect(throws: WriteObjectError.self) {
      _ = try await permClient.writeObject(
        payload, to: bucket, as: objectName, options: writeOptions)
    }
    #expect(permProvider.callCount == 1)
    #expect(permRegistry.recordedRequests().isEmpty)
    if let permErr, case .requestError(.io(let underlying)) = permErr {
      #expect(underlying is CredentialsError)
    } else {
      Issue.record(
        "Expected WriteObjectError.requestError(.io), got \(String(describing: permErr))")
    }

    // 2. Transient credential error during chunk upload resumes and completes once token refresh recovers.
    let transRegistry = MockRegistry.create()
    let startUrl =
      "\(transRegistry.endpoint)/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)"
    let sessionUrl = "\(transRegistry.endpoint)/upload/storage/v1/b/\(bucket)/o?upload_id=session-1"
    transRegistry.register(
      response: .success(statusCode: 200, data: Data(), headers: ["Location": sessionUrl]),
      for: startUrl
    )
    // Status query after transient chunk credential failure returns 308 (0 bytes committed),
    // followed by 200 OK when the chunk is uploaded with the refreshed token.
    transRegistry.register(
      response: .success(statusCode: 308, data: Data(), headers: [:]),
      for: sessionUrl
    )
    transRegistry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: payload.count),
        headers: ["Content-Type": "application/json"]
      ),
      for: sessionUrl
    )

    let transProvider = SequencedAccessTokenProvider([
      .success(AccessToken(token: "session-token")),
      .failure(
        CredentialsError._transientCannotFetchToken(
          message: "temporary OAuth 503",
          underlyingError: URLError(.timedOut)
        )
      ),
      .success(AccessToken(token: "refreshed-token")),
    ])
    let transClientOptions = try StorageClientOptions().with {
      $0.client = try .init().with {
        $0.endpoint = transRegistry.endpoint
        $0.credentials = try Credentials(
          configuration: .accessToken(AccessTokenConfig(provider: transProvider))
        )
        $0.backoffPolicy = ZeroBackoff()
      }
    }
    let transClient = try StorageClient(transClientOptions, mock: transRegistry, environment: [:])
    let uploaded = try await transClient.writeObject(
      payload,
      to: bucket,
      as: objectName,
      options: writeOptions.with { $0.checksums = .none }
    )
    #expect(uploaded.name == objectName)
    #expect(transProvider.callCount == 4)
  }
}
