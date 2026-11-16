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
@testable import StorageW1R3
import Testing

@Suite struct LoadBalancerOptionTests {
  @Test func parsesP2cVariants() {
    #expect(LoadBalancerOption(argument: "p2c") == .p2c)
    #expect(LoadBalancerOption(argument: "P2C") == .p2c)
  }

  @Test func parsesRoundRobinVariants() {
    #expect(LoadBalancerOption(argument: "round-robin") == .roundRobin)
    #expect(LoadBalancerOption(argument: "ROUND-ROBIN") == .roundRobin)
    #expect(LoadBalancerOption(argument: "roundrobin") == .roundRobin)
    #expect(LoadBalancerOption(argument: "round_robin") == .roundRobin)
  }

  @Test func parsesRandomVariants() {
    #expect(LoadBalancerOption(argument: "random") == .random)
    #expect(LoadBalancerOption(argument: "RANDOM") == .random)
    #expect(LoadBalancerOption(argument: "both") == .random)
    #expect(LoadBalancerOption(argument: "head-to-head") == .random)
  }

  @Test func rejectsInvalidArguments() {
    #expect(LoadBalancerOption(argument: "") == nil)
    #expect(LoadBalancerOption(argument: "least-loaded") == nil)
    #expect(LoadBalancerOption(argument: "1") == nil)
  }

  @Test func pickLoadBalancerAndTagFormatting() throws {
    let p2cParsed = try StorageW1R3.parseAsRoot([
      "--bucket-name=my-bucket",
      "--load-balancer=p2c",
    ])
    guard let p2cBenchmark = p2cParsed as? StorageW1R3 else {
      Issue.record("cannot convert to StorageW1R3")
      return
    }
    let p2cChoice = p2cBenchmark.pickLoadBalancer()
    #expect(p2cChoice == .p2c)
    #expect(StorageW1R3.loadBalancerTag(p2cChoice) == "p2c")

    let rrParsed = try StorageW1R3.parseAsRoot([
      "--bucket-name=my-bucket",
      "--load-balancer=round-robin",
    ])
    guard let rrBenchmark = rrParsed as? StorageW1R3 else {
      Issue.record("cannot convert to StorageW1R3")
      return
    }
    let rrChoice = rrBenchmark.pickLoadBalancer()
    #expect(rrChoice == .roundRobin)
    #expect(StorageW1R3.loadBalancerTag(rrChoice) == "round-robin")
  }
}
