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

@testable import StorageW1R3
import Testing

@Suite struct CountersTests {
  @Test func benchmarkCountersOperations() async {
    let counters = BenchmarkCounters()

    #expect(await counters.sampleCount == 0)
    #expect(await counters.readCount == 0)
    #expect(await counters.writeCount == 0)
    #expect(await counters.deleteCount == 0)
    #expect(await counters.activeTasks == 0)

    await counters.taskStarted()
    #expect(await counters.activeTasks == 1)

    await counters.incrementSample()
    await counters.incrementWrite()
    await counters.incrementWriteError()
    await counters.incrementRead()
    await counters.incrementReadError()
    await counters.incrementDelete()
    await counters.incrementDeleteError()

    #expect(await counters.sampleCount == 1)
    #expect(await counters.writeCount == 1)
    #expect(await counters.writeError == 1)
    #expect(await counters.readCount == 1)
    #expect(await counters.readError == 1)
    #expect(await counters.deleteCount == 1)
    #expect(await counters.deleteError == 1)

    await counters.taskFinished()
    #expect(await counters.activeTasks == 0)

    let snapshot = await counters.snapshot()
    let map = Dictionary(uniqueKeysWithValues: snapshot)
    #expect(map["SAMPLE_COUNT"] == 1)
    #expect(map["WRITE_COUNT"] == 1)
    #expect(map["WRITE_ERROR"] == 1)
    #expect(map["READ_COUNT"] == 1)
    #expect(map["READ_ERROR"] == 1)
    #expect(map["DELETE_COUNT"] == 1)
    #expect(map["DELETE_ERROR"] == 1)
    #expect(map["TASK_COUNT"] == 0)

    let desc = await counters.formattedDescription()
    #expect(desc.contains("\"SAMPLE_COUNT\": 1"))
    #expect(desc.contains("\"WRITE_COUNT\": 1"))

    enum TestError: Error, CustomStringConvertible {
      case testFailure
      var description: String { "testFailure,details" }
    }

    let errorDetails = await counters.errorDetails(error: TestError.testFailure)
    #expect(errorDetails.contains("SAMPLE_COUNT=1"))
    #expect(errorDetails.contains("error=testFailure;details"))
  }

  @Test func policyCounterAtomicIncrements() {
    let counter = PolicyCounter()
    #expect(counter.value == 0)
    counter.increment()
    counter.increment()
    #expect(counter.value == 2)
  }
}
