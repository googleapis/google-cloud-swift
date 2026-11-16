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

/// Load-balancing strategy used by ``StorageClient`` to distribute HTTP requests across its
/// internal connection pool.
///
/// In our experiments, the ``StorageLoadBalancer/p2c`` load balancer improves median latency for
/// uploads, and the tail latency for both uploads and downloads. The
/// ``StorageLoadBalancer/roundRobin`` load balancer offers better median latency for downloads.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an
///   `@unknown default:` clause in `switch` statements.
public enum StorageLoadBalancer: Sendable, Hashable {
  /// Distributes requests sequentially across pooled HTTP connections in round-robin order
  /// (the default).
  case roundRobin

  /// Power of Two Random Choices (`P2C`): samples two distinct connections at random and routes
  /// the request to the one with fewer active in-flight requests (including streaming response
  /// bodies).
  case p2c
}
