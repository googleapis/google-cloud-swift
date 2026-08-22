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

/// A recorded measurement sample representing the result and timing of a single operation.
public struct Sample: Sendable {
  public static let header =
    "Task,Iteration,IterationStart,Operation,Size,TransferSize,ElapsedMicroseconds,Object,Result,Details"

  public let task: Int
  public let iteration: Int
  public let iterationStartMicros: Int64
  public let operation: Operation
  public let size: Int
  public let transferSize: Int
  public let elapsedMicros: Int64
  public let object: String
  public let result: ExperimentResult
  public let details: String

  public func toRow() -> String {
    "\(task),\(iteration),\(iterationStartMicros),\(operation.name),\(size),\(transferSize),\(elapsedMicros),\(object),\(result.name),\(details)"
  }
}
