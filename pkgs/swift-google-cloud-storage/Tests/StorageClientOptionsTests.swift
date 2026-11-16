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

@testable import GoogleCloudStorage
import Testing

@Suite struct StorageClientOptionsTests {
  @Test func poolOptionsDefaultsAndMutation() {
    let defaults = StorageClientOptions()
    #expect(defaults.connectionPoolSize == nil)
    #expect(defaults.loadBalancer == .roundRobin)

    let configured = defaults.with {
      $0.connectionPoolSize = 8
      $0.loadBalancer = .p2c
    }
    #expect(configured.connectionPoolSize == 8)
    #expect(configured.loadBalancer == .p2c)
  }

  @Test func loadBalancerHashableAndSwitchable() {
    let set: Set<StorageLoadBalancer> = [.roundRobin, .p2c, .roundRobin]
    #expect(set.count == 2)

    @Sendable func label(for lb: StorageLoadBalancer) -> String {
      switch lb {
      case .roundRobin:
        return "roundRobin"
      case .p2c:
        return "p2c"
      @unknown default:
        return "unknown"
      }
    }

    #expect(label(for: .roundRobin) == "roundRobin")
    #expect(label(for: .p2c) == "p2c")
  }

  @Test(arguments: [
    (coreCount: 0, expected: 1),
    (coreCount: 1, expected: 1),
    (coreCount: 2, expected: 1),
    (coreCount: 3, expected: 1),
    (coreCount: 4, expected: 2),
    (coreCount: 7, expected: 2),
    (coreCount: 8, expected: 3),
    (coreCount: 16, expected: 4),
    (coreCount: 64, expected: 6),
    (coreCount: 192, expected: 7),
  ])
  func resolveConnectionPoolSizeDefaults(coreCount: Int, expected: Int) {
    #expect(StorageClientOptions.resolveConnectionPoolSize(nil, coreCount: coreCount) == expected)
  }

  @Test(arguments: [
    (configured: -5, expected: 1),
    (configured: 0, expected: 1),
    (configured: 1, expected: 1),
    (configured: 3, expected: 3),
    (configured: 32, expected: 32),
  ])
  func resolveConnectionPoolSizeOverridesAndClamping(configured: Int, expected: Int) {
    #expect(
      StorageClientOptions.resolveConnectionPoolSize(configured, coreCount: 8) == expected
    )
  }
}
