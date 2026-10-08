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
import GoogleCloudBigQueryV2

/// An error reported by BigQuery, or detected by the client before sending a request.
///
/// BigQuery reports errors in three ways, all represented by this type:
/// - The service rejects a request with an HTTP error status (``Kind-swift.struct/service``).
/// - A job or query runs and fails (``Kind-swift.struct/job``). ``jobID`` identifies the job.
/// - The client rejects an argument before sending anything
///   (``Kind-swift.struct/invalidArgument``).
///
/// An HTTP error status is reported as a service error whichever retry limit stopped the retry
/// loop. Transport and authentication failures, and retry exhaustion after I/O errors, are
/// reported as `GoogleGax.RequestError`, and cancellation as `CancellationError`.
public struct BigQueryError: Error, Sendable, Hashable, CustomStringConvertible {
  /// The category of a ``BigQueryError``.
  public struct Kind: Sendable, Hashable, CustomStringConvertible {
    let name: String

    /// The service returned an HTTP error status.
    public static let service = Kind(name: "service")

    /// A job or query failed.
    ///
    /// This covers a job that completed with an error and a query that the service rejected
    /// before it ran, for example for a syntax error or a missing table. In the latter case
    /// ``BigQueryError/httpStatusCode`` is set.
    public static let job = Kind(name: "job")

    /// The client rejected an argument before sending a request.
    public static let invalidArgument = Kind(name: "invalidArgument")

    /// A wait deadline passed while the job was still running. The job is not cancelled;
    /// ``BigQueryError/jobID`` identifies it so the caller can keep waiting or cancel it.
    public static let timeout = Kind(name: "timeout")

    public var description: String { self.name }
  }

  /// One entry of the error list reported by BigQuery.
  ///
  /// See [BigQuery error messages] for the meaning of each ``reason``.
  ///
  /// [BigQuery error messages]: https://cloud.google.com/bigquery/docs/error-messages
  public struct Detail: Sendable, Hashable {
    /// A short code, for example `notFound`, `invalidQuery`, or `rateLimitExceeded`.
    public var reason: String?

    /// Where the error occurred, if known, for example a column name.
    public var location: String?

    /// A human-readable description.
    public var message: String?

    /// Debugging information. Not intended for end users.
    public var debugInfo: String?

    /// Creates a detail.
    public init(
      reason: String? = nil, location: String? = nil, message: String? = nil,
      debugInfo: String? = nil
    ) {
      self.reason = reason
      self.location = location
      self.message = message
      self.debugInfo = debugInfo
    }
  }

  /// The category of the error.
  public var kind: Kind

  /// A human-readable description of the error.
  public var message: String

  /// The HTTP status code, for service errors.
  public var httpStatusCode: Int?

  /// The canonical status name, for example `NOT_FOUND`, for service errors.
  public var status: String?

  /// All the errors reported by the service, in order.
  ///
  /// For job errors the first entry is the job's `errorResult`.
  public var errors: [Detail]

  /// The job that failed, for job errors.
  public var jobID: JobID?

  /// Creates an error.
  public init(
    kind: Kind,
    message: String,
    httpStatusCode: Int? = nil,
    status: String? = nil,
    errors: [Detail] = [],
    jobID: JobID? = nil
  ) {
    self.kind = kind
    self.message = message
    self.httpStatusCode = httpStatusCode
    self.status = status
    self.errors = errors
    self.jobID = jobID
  }

  /// The reason of the first reported error, for example `notFound`.
  public var reason: String? { self.errors.first?.reason }

  /// The location of the first reported error.
  public var location: String? { self.errors.first?.location }

  /// `true` if the error means a resource does not exist.
  ///
  /// This is `true` for HTTP 404 service errors and for any error whose first reason is
  /// `notFound`, including job errors such as a query that references a missing table.
  public var isNotFound: Bool { self.httpStatusCode == 404 || self.reason == "notFound" }

  public var description: String {
    var text = "BigQueryError(\(self.kind)"
    if let code = self.httpStatusCode { text += ", http \(code)" }
    if let reason = self.reason { text += ", reason: \(reason)" }
    if let jobID = self.jobID { text += ", job: \(jobID)" }
    return text + "): \(self.message)"
  }
}

extension BigQueryError {
  /// Creates an ``Kind-swift.struct/invalidArgument`` error.
  static func invalidArgument(_ message: String) -> BigQueryError {
    BigQueryError(kind: .invalidArgument, message: message)
  }

  /// Creates a service error from an HTTP error response.
  ///
  /// BigQuery error bodies have the form
  /// `{"error": {"code": 404, "message": "...", "status": "NOT_FOUND", "errors": [...]}}`.
  /// Bodies that do not match are reported verbatim in ``message``.
  init(httpStatusCode: Int, payload: Data) {
    let body = ErrorBody.parse(payload)
    let fallback = String(decoding: payload, as: UTF8.self)
    self.init(
      kind: .service,
      message: body?.error.message ?? (fallback.isEmpty ? "HTTP \(httpStatusCode)" : fallback),
      httpStatusCode: httpStatusCode,
      status: body?.error.status,
      errors: body?.error.errors?.map(\.detail) ?? []
    )
  }

  /// Creates a job error from the `errorResult` and `errors` of a job or query response.
  ///
  /// Returns `nil` if there is no error.
  init?(
    job jobID: JobID?, errorResult: GoogleCloudBigQueryV2.ErrorProto?,
    errors: [GoogleCloudBigQueryV2.ErrorProto]
  ) {
    var details: [Detail] = []
    if let errorResult { details.append(Detail(wire: errorResult)) }
    for error in errors {
      let detail = Detail(wire: error)
      if !details.contains(detail) { details.append(detail) }
    }
    guard let first = details.first else { return nil }
    self.init(
      kind: .job, message: first.message ?? first.reason ?? "job failed", errors: details,
      jobID: jobID)
  }
}

extension BigQueryError.Detail {
  init(wire: GoogleCloudBigQueryV2.ErrorProto) {
    self.init(
      reason: wire.reason.nonEmpty, location: wire.location.nonEmpty,
      message: wire.message.nonEmpty, debugInfo: wire.debugInfo.nonEmpty)
  }
}

/// The JSON body of a BigQuery HTTP error response.
struct ErrorBody: Codable {
  struct Status: Codable {
    var code: Int?
    var message: String?
    var status: String?
    var errors: [Item]?
  }

  struct Item: Codable {
    var reason: String?
    var location: String?
    var message: String?
    var debugInfo: String?

    var detail: BigQueryError.Detail {
      BigQueryError.Detail(
        reason: reason, location: location, message: message, debugInfo: debugInfo)
    }
  }

  var error: Status

  static func parse(_ payload: Data) -> ErrorBody? {
    try? JSONDecoder().decode(ErrorBody.self, from: payload)
  }
}

extension String {
  /// `nil` if the string is empty, which is how proto3 represents an unset string.
  var nonEmpty: String? { self.isEmpty ? nil : self }
}
