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

import GoogleCloudBigQueryV2

/// The lifecycle state of a job.
public struct JobState: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  /// The wire value.
  public var rawValue: String

  /// Creates a value from its wire representation.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// The job is queued.
  public static let pending = JobState(rawValue: "PENDING")
  /// The job is running.
  public static let running = JobState(rawValue: "RUNNING")
  /// The job finished, successfully or not. Check ``JobStatus/errorResult``.
  public static let done = JobState(rawValue: "DONE")

  /// The wire value.
  public var description: String { self.rawValue }
}

/// The status of a job.
public struct JobStatus: Sendable, Hashable {
  /// The state of the job.
  public var state: JobState

  /// The error that made the job fail, or `nil` if it has not failed.
  ///
  /// A job can finish (``JobState/done``) and still have failed.
  public var errorResult: BigQueryError.Detail?

  /// All the errors encountered while running the job.
  ///
  /// These errors do not necessarily mean that the job failed or will fail.
  public var errors: [BigQueryError.Detail]

  /// Creates a job status.
  public init(
    state: JobState, errorResult: BigQueryError.Detail? = nil,
    errors: [BigQueryError.Detail] = []
  ) {
    self.state = state
    self.errorResult = errorResult
    self.errors = errors
  }

  /// `true` when the job finished, successfully or not.
  public var isDone: Bool { self.state == .done }
}

extension JobStatus {
  init(wire: GoogleCloudBigQueryV2.JobStatus) {
    self.init(
      state: JobState(rawValue: wire.state),
      errorResult: wire.errorResult.map(BigQueryError.Detail.init(wire:)),
      errors: wire.errors.map(BigQueryError.Detail.init(wire:)))
  }

  /// The error to throw for a failed job, or `nil` if the job did not fail.
  ///
  /// `errors` holds `errorResult` first, followed by the other entries of `status.errors`.
  func failure(jobID: JobID?) -> BigQueryError? {
    guard let errorResult else { return nil }
    let others = self.errors.filter { $0 != errorResult }
    return BigQueryError(
      kind: .job, message: errorResult.message ?? "The job failed.", httpStatusCode: nil,
      status: nil, errors: [errorResult] + others, jobID: jobID)
  }
}
