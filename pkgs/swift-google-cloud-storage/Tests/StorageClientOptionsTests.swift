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

import GoogleCloudStorage
import Testing

@Suite struct StorageClientOptionsTests {
  @Test func publicPoolDefaultsAndMutation() {
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
}
