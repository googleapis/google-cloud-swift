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

/// A BigQuery job: a query, load, extract, or copy that runs asynchronously.
///
/// ```swift
/// let job = try await client.createJob(.copy(CopyJobConfiguration(
///   sourceTable: TableID(datasetID: "d", tableID: "src"),
///   destinationTable: TableID(datasetID: "d", tableID: "dst"))))
/// let done = try await client.waitForJob(job.id)
/// ```
public struct Job: Sendable, Equatable {
  /// The job's ID, including its project and location.
  public var id: JobID

  /// What the job does, or `nil` if the job type is unknown to this library or the field was
  /// not selected.
  public var configuration: JobConfiguration?

  /// The state of the job and any errors.
  ///
  /// A finished job may still have failed: check ``JobStatus/errorResult``.
  public var status: JobStatus

  /// Timing and resource statistics, or `nil` if the field was not selected.
  public var statistics: JobStatistics?

  /// The email address of the user who ran the job.
  public var userEmail: String?

  /// The HTTP ETag of the job resource.
  public var etag: String?

  /// The URL of the job resource.
  public var selfLink: String?

  /// Creates a job, for example as a test double.
  public init(
    id: JobID,
    configuration: JobConfiguration? = nil,
    status: JobStatus,
    statistics: JobStatistics? = nil,
    userEmail: String? = nil,
    etag: String? = nil,
    selfLink: String? = nil
  ) {
    self.id = id
    self.configuration = configuration
    self.status = status
    self.statistics = statistics
    self.userEmail = userEmail
    self.etag = etag
    self.selfLink = selfLink
  }
}

extension Job {
  init(wire: GoogleCloudBigQueryV2.Job) {
    self.init(
      id: wire.jobReference.map(JobID.init(wire:)) ?? JobID(jobID: ""),
      configuration: wire.configuration.flatMap(JobConfiguration.init(wire:)),
      status: wire.status.map(JobStatus.init(wire:)) ?? JobStatus(state: JobState(rawValue: "")),
      statistics: wire.statistics.map(JobStatistics.init(wire:)),
      userEmail: wire.userEmail.nonEmpty,
      etag: wire.etag.nonEmpty,
      selfLink: wire.selfLink.nonEmpty)
  }

  init(wire: GoogleCloudBigQueryV2.ListFormatJob) {
    // `jobs.list` reports the state and error both at the top level and in `status`.
    var status = wire.status.map(JobStatus.init(wire:)) ?? JobStatus(state: JobState(rawValue: ""))
    if status.state.rawValue.isEmpty { status.state = JobState(rawValue: wire.state) }
    if status.errorResult == nil {
      status.errorResult = wire.errorResult.map(BigQueryError.Detail.init(wire:))
    }
    self.init(
      id: wire.jobReference.map(JobID.init(wire:)) ?? JobID(jobID: ""),
      configuration: wire.configuration.flatMap(JobConfiguration.init(wire:)),
      status: status,
      statistics: wire.statistics.map(JobStatistics.init(wire:)),
      userEmail: wire.userEmail.nonEmpty)
  }

  /// The job's error as a ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/job``,
  /// or `nil` if the job has not failed.
  var failure: BigQueryError? { self.status.failure(jobID: self.id) }
}
