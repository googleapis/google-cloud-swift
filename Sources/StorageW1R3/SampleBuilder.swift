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

/// Helper to measure operation duration and build `Sample` instances with relative timestamps.
public struct SampleBuilder: Sendable {
  public let task: Int
  public let relativeStartMicros: Int64
  public let iteration: Int
  public let clock: ContinuousClock
  public let startInstant: ContinuousClock.Instant
  public let op: Operation
  public let targetSize: Int
  public let object: String
  public let crc32cEnabled: Bool
  public let chunkSize: Int?

  public init(
    iterationId: IterationId,
    op: Operation,
    targetSize: Int,
    object: String,
    crc32cEnabled: Bool,
    chunkSize: Int? = nil
  ) {
    self.task = iterationId.task
    self.clock = ContinuousClock()
    let now = clock.now
    let relDuration = iterationId.taskStartInstant.duration(to: now)
    self.relativeStartMicros =
      relDuration.components.seconds * 1_000_000 + relDuration.components.attoseconds
      / 1_000_000_000_000
    self.iteration = iterationId.iteration
    self.startInstant = now
    self.op = op
    self.targetSize = targetSize
    self.object = object
    self.crc32cEnabled = crc32cEnabled
    self.chunkSize = chunkSize
  }

  private var elapsedMicroseconds: Int64 {
    let duration = startInstant.duration(to: clock.now)
    return duration.components.seconds * 1_000_000 + duration.components.attoseconds
      / 1_000_000_000_000
  }

  private func formatDetails(_ rawDetails: String) -> String {
    let sanitized = rawDetails.replacingOccurrences(of: ",", with: ";")
    if let chunkSize {
      if sanitized.isEmpty {
        return "chunkSize=\(chunkSize)"
      }
      return "chunkSize=\(chunkSize);\(sanitized)"
    }
    return sanitized
  }

  public func success(transferSize: Int? = nil) -> Sample {
    Sample(
      task: task,
      iteration: iteration,
      iterationStartMicros: relativeStartMicros,
      operation: op,
      size: targetSize,
      transferSize: transferSize ?? targetSize,
      elapsedMicros: elapsedMicroseconds,
      object: object,
      crc32cEnabled: crc32cEnabled,
      result: .ok,
      details: formatDetails("")
    )
  }

  public func error(details: String = "") -> Sample {
    Sample(
      task: task,
      iteration: iteration,
      iterationStartMicros: relativeStartMicros,
      operation: op,
      size: targetSize,
      transferSize: 0,
      elapsedMicros: elapsedMicroseconds,
      object: object,
      crc32cEnabled: crc32cEnabled,
      result: .err,
      details: formatDetails(details)
    )
  }

  public func interrupted(transferSize: Int, details: String = "") -> Sample {
    Sample(
      task: task,
      iteration: iteration,
      iterationStartMicros: relativeStartMicros,
      operation: op,
      size: targetSize,
      transferSize: transferSize,
      elapsedMicros: elapsedMicroseconds,
      object: object,
      crc32cEnabled: crc32cEnabled,
      result: .int,
      details: formatDetails(details)
    )
  }
}
