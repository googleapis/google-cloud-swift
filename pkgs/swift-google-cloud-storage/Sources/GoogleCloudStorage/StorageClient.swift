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
import GoogleAuth
@_spi(GoogleCloudInternal) public import GoogleGax

/// A client for the [Cloud Storage] data-plane operations.
///
/// Use this client to write (upload) and read (download) objects in the Cloud Storage service.
///
/// ``StorageClient`` is thread-safe (`Sendable`). It is recommended to initialize it at application
/// startup and reuse it across requests.
///
/// [Cloud Storage]: https://docs.cloud.google.com/storage
public final class StorageClient: StorageProtocol, Sendable {
  public static let defaultEndpoint = "https://storage.googleapis.com"

  let inner: GoogleGax._HTTPClient
  let options: StorageClientOptions

  /// Creates a new ``StorageClient`` instance.
  ///
  /// When ``StorageClientOptions/client`` does not specify custom credentials, this initializer
  /// resolves Application Default Credentials synchronously (including reading local credential
  /// files from disk). Prefer initializing the client at application startup and reusing it across
  /// requests.
  public convenience init(_ options: StorageClientOptions = .init()) throws {
    try self.init(options, environment: ProcessInfo.processInfo.environment)
  }

  init(
    _ options: StorageClientOptions = .init(),
    environment: [String: String]
  ) throws {
    let universeDomain = GoogleGax._Host.resolveUniverseDomain(
      options: options.client,
      environment: environment
    )
    let credentials = try options.client.credentials ?? GoogleAuth.Credentials()
    let endpoint = try GoogleGax._Host.endpoint(
      endpoint: options.client.endpoint,
      defaultEndpoint: Self.defaultEndpoint,
      universeDomain: universeDomain
    )
    _ = try GoogleGax._HTTPClient.validateEndpoint(endpoint)
    let poolSize = StorageClientOptions.resolveConnectionPoolSize(options.connectionPoolSize)
    let clients = (0..<poolSize).map { _ in StorageHTTPClientHolder() }
    let transport = Self.makeTransport(clients: clients, loadBalancer: options.loadBalancer)
    self.options = options
    self.inner = try GoogleGax._HTTPClient(
      transport,
      endpoint: endpoint,
      credentials: credentials,
      logger: options.client.logger,
      quotaProject: options.client.quotaProject,
      defaultEndpoint: Self.defaultEndpoint,
      universeDomain: universeDomain,
      clientHeader: .veneer(packageVersion: PackageVersion.version)
    )
  }

  @_spi(GoogleCloudInternal) public convenience init(
    _ options: StorageClientOptions = .init(),
    mock: any _HTTPClientProtocol
  ) throws {
    try self.init(
      options,
      mock: mock,
      environment: ProcessInfo.processInfo.environment
    )
  }

  convenience init(
    _ options: StorageClientOptions = .init(),
    mock: any _HTTPClientProtocol,
    environment: [String: String]
  ) throws {
    try self.init(
      options,
      mocks: [mock],
      environment: environment
    )
  }

  init(
    _ options: StorageClientOptions = .init(),
    mocks: [any _HTTPClientProtocol],
    seed: UInt64? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    precondition(!mocks.isEmpty, "StorageClient requires at least one mock HTTP client")
    let universeDomain = GoogleGax._Host.resolveUniverseDomain(
      options: options.client,
      environment: environment
    )
    let endpoint = try GoogleGax._Host.endpoint(
      endpoint: options.client.endpoint,
      defaultEndpoint: Self.defaultEndpoint,
      universeDomain: universeDomain
    )
    _ = try GoogleGax._HTTPClient.validateEndpoint(endpoint)
    let poolSize = StorageClientOptions.resolveConnectionPoolSize(options.connectionPoolSize)
    let selectedMocks = Array(mocks.prefix(poolSize))
    let transport = Self.makeTransport(
      clients: selectedMocks,
      loadBalancer: options.loadBalancer,
      seed: seed
    )
    self.options = options
    self.inner = try GoogleGax._HTTPClient(
      transport,
      endpoint: endpoint,
      credentials: options.client.credentials,
      logger: options.client.logger,
      quotaProject: options.client.quotaProject,
      defaultEndpoint: Self.defaultEndpoint,
      universeDomain: universeDomain,
      clientHeader: .veneer(packageVersion: PackageVersion.version)
    )
  }

  @_spi(GoogleCloudInternal) public init(
    _ options: StorageClientOptions = .init(),
    client: GoogleGax._HTTPClient
  ) {
    self.options = options
    self.inner = client
  }

  static func makeTransport(
    clients: [any _HTTPClientProtocol],
    loadBalancer: StorageLoadBalancer,
    seed: UInt64? = nil
  ) -> any _HTTPClientProtocol {
    precondition(!clients.isEmpty, "StorageClient requires at least one HTTP client")
    if clients.count == 1 {
      return clients[0]
    }
    switch loadBalancer {
    case .p2c:
      if let seed {
        return P2CHTTPClient(clients: clients, seed: seed)
      }
      return P2CHTTPClient(clients: clients)
    case .roundRobin:
      return RoundRobinHTTPClient(clients: clients)
    }
  }
}
