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
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax

/// A client for the [Cloud Storage] data-plane operations.
///
/// Use this client to write (upload) and read (download) objects in the Cloud Storage service.
///
/// [Cloud Storage]: https://docs.cloud.google.com/storage
public final class StorageClient: StorageProtocol, Sendable {
  public static let defaultEndpoint = "https://storage.googleapis.com"

  let inner: GoogleCloudGax._HTTPClient
  let options: StorageClientOptions

  public init(_ options: StorageClientOptions = .init()) throws {
    self.options = options
    self.inner = try GoogleCloudGax._HTTPClient(
      from: options.client, withDefaultEndpoint: Self.defaultEndpoint)
  }

  @_spi(GoogleCloudInternal) public init(
    _ options: StorageClientOptions = .init(),
    mock: any _HTTPClientProtocol
  ) throws {
    let endpoint = options.client.endpoint ?? Self.defaultEndpoint
    self.options = options
    self.inner = try GoogleCloudGax._HTTPClient(
      mock, endpoint: endpoint, credentials: options.client.credentials)
  }

  @_spi(GoogleCloudInternal) public init(
    _ options: StorageClientOptions = .init(),
    client: GoogleCloudGax._HTTPClient
  ) {
    self.options = options
    self.inner = client
  }
}
