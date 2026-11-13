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

public import GoogleGax
import NIOCore

/// Configuration options for ``StorageClient``.
///
/// ```swift
/// let options = StorageClientOptions().with {
///   $0.connectionPoolSize = 8
///   $0.loadBalancer = .p2c
/// }
/// let client = try StorageClient(options)
/// ```
public struct StorageClientOptions: Sendable {
  /// Common options used by all Google Swift SDK clients.
  public var client: GoogleGax.ClientOptions

  /// Default configuration inherited by `writeObject` operations.
  public var writeObject: WriteObjectOptions

  /// Default configuration inherited by `readObject` operations.
  public var readObject: ReadObjectOptions

  /// Optional override for the number of underlying HTTP connection pools managed by ``StorageClient``.
  ///
  /// When `nil`, ``StorageClient`` defaults to `max(1, log2(coreCount))` based on the host CPU
  /// core count. Values less than `1` are clamped to `1`.
  public var connectionPoolSize: Int? = nil

  /// Load-balancing strategy used to distribute requests across pooled HTTP connections.
  ///
  /// Defaults to ``StorageLoadBalancer/roundRobin``. In our experiments, the
  /// ``StorageLoadBalancer/p2c`` load balancer improves median latency for uploads, and the tail
  /// latency for both uploads and downloads. The ``StorageLoadBalancer/roundRobin`` load balancer
  /// offers better median latency for downloads.
  public var loadBalancer: StorageLoadBalancer = .roundRobin

  public init(
    client: GoogleGax.ClientOptions = .init(),
    writeObject: WriteObjectOptions = .default,
    readObject: ReadObjectOptions = .default
  ) {
    self.client = client
    self.writeObject = writeObject
    self.readObject = readObject
  }

  /// Override specific values using closure modification.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }

  static func resolveConnectionPoolSize(
    _ configured: Int?,
    coreCount: Int = NIOCore.System.coreCount
  ) -> Int {
    if let configured {
      return max(1, configured)
    }
    guard coreCount > 1 else {
      return 1
    }
    // Fast integer floor(log2(coreCount)) via FixedWidthInteger's hardware leading-zero count.
    return Int.bitWidth - 1 - coreCount.leadingZeroBitCount
  }
}
