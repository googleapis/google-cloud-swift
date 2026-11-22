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

import GoogleCloudPubSub
import PubSubLocalBenchmarkCore
import Testing

@Suite struct PubSubLocalBenchmarkTests {
  @Test func publishAndStreamingPullSmokeBenchmark() async throws {
    let cfg = LocalBenchmarkConfig(payloadBytes: 256, totalMessages: 200, batchSize: 50, trials: 1)
    let pubRow = try await PubSubLocalBenchmarkRunner.benchmarkPublish(config: cfg)
    let pullRow = try await PubSubLocalBenchmarkRunner.benchmarkStreamingPull(config: cfg)
    let hedging = try await PubSubLocalBenchmarkRunner.benchmarkHedging(messageCount: 16)

    #expect(pubRow.rawMessagesPerSec > 0)
    #expect(pubRow.veneerMessagesPerSec > 0)
    #expect(pullRow.rawMessagesPerSec > 0)
    #expect(pullRow.veneerMessagesPerSec > 0)
    #expect(hedging.hedgedP99Millis < hedging.unhedgedP99Millis)
  }
}
