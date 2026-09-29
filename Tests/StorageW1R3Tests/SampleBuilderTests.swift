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
@testable import StorageW1R3
import Testing

@Suite struct SampleBuilderTests {
  @Test func sampleHeaderFormat() {
    #expect(
      Sample.header
        == "Task,Iteration,IterationStart,Operation,Size,TransferSize,ElapsedMicroseconds,Object,Crc32cEnabled,Result,Details"
    )
  }

  @Test func operationNames() {
    #expect(Operation.resumable.name == "RESUMABLE")
    #expect(Operation.singleShot.name == "SINGLE_SHOT")
    #expect(Operation.read(0).name == "READ[0]")
    #expect(Operation.read(3).name == "READ[3]")
    #expect(Operation.delete.name == "DELETE")
  }

  @Test func experimentResultNames() {
    #expect(ExperimentResult.ok.name == "OK")
    #expect(ExperimentResult.err.name == "ERR")
    #expect(ExperimentResult.int.name == "INT")
  }

  @Test func sampleBuilderSuccess() {
    let now = ContinuousClock.now
    let iterId = IterationId(task: 1, taskStartInstant: now, iteration: 2)
    let builder = SampleBuilder(
      iterationId: iterId,
      op: .singleShot,
      targetSize: 1024,
      object: "obj-1",
      crc32cEnabled: true
    )

    let sample = builder.success()
    #expect(sample.task == 1)
    #expect(sample.iteration == 2)
    #expect(sample.size == 1024)
    #expect(sample.transferSize == 1024)
    #expect(sample.object == "obj-1")
    #expect(sample.crc32cEnabled == true)
    #expect(sample.result == .ok)
    #expect(sample.details == "")

    let row = sample.toRow()
    #expect(row.contains("1,2,"))
    #expect(row.contains(",SINGLE_SHOT,1024,1024,"))
    #expect(row.contains(",obj-1,true,OK,"))
  }

  @Test func sampleBuilderError() {
    let now = ContinuousClock.now
    let iterId = IterationId(task: 0, taskStartInstant: now, iteration: 0)
    let builder = SampleBuilder(
      iterationId: iterId,
      op: .read(1),
      targetSize: 2048,
      object: "obj-2",
      crc32cEnabled: false
    )

    let sample = builder.error(details: "code=404,message=Not Found")
    #expect(sample.result == .err)
    #expect(sample.transferSize == 0)
    #expect(sample.details == "code=404;message=Not Found")
  }

  @Test func sampleBuilderInterrupted() {
    let now = ContinuousClock.now
    let iterId = IterationId(task: 2, taskStartInstant: now, iteration: 1)
    let builder = SampleBuilder(
      iterationId: iterId,
      op: .read(0),
      targetSize: 4096,
      object: "obj-3",
      crc32cEnabled: true
    )

    let sample = builder.interrupted(transferSize: 1024, details: "network dropped")
    #expect(sample.result == .int)
    #expect(sample.transferSize == 1024)
    #expect(sample.details == "network dropped")
  }
}
