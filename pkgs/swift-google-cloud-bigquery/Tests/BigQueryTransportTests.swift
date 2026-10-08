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
import GoogleGax
import Testing

@testable import GoogleCloudBigQuery

@Suite struct BigQueryErrorTests {
  // Baseline: U.BigQueryError.01
  @Test func parsesServiceErrorBody() {
    let payload = Data(
      #"""
      {"error": {"code": 400, "message": "Bad table", "status": "INVALID_ARGUMENT",
        "errors": [{"reason": "invalid", "location": "table", "message": "Bad table",
                    "debugInfo": "x"}, {"reason": "other"}]}}
      """#.utf8)
    let error = BigQueryError(httpStatusCode: 400, payload: payload)
    #expect(error.kind == .service)
    #expect(error.message == "Bad table")
    #expect(error.httpStatusCode == 400)
    #expect(error.status == "INVALID_ARGUMENT")
    #expect(error.reason == "invalid")
    #expect(error.location == "table")
    #expect(error.errors.count == 2)
    #expect(error.errors[0].debugInfo == "x")
    #expect(!error.isNotFound)
  }

  // Design: §4.3
  @Test func keepsNonJSONBodyAsMessage() {
    let error = BigQueryError(httpStatusCode: 502, payload: Data("<html>bad gateway</html>".utf8))
    #expect(error.message == "<html>bad gateway</html>")
    #expect(error.errors.isEmpty)
    #expect(BigQueryError(httpStatusCode: 503, payload: Data()).message == "HTTP 503")
  }

  // Design: §4.3
  @Test func notFoundFromStatusOrReason() {
    #expect(BigQueryError(httpStatusCode: 404, payload: Data()).isNotFound)
    #expect(
      BigQueryError(kind: .job, message: "m", errors: [.init(reason: "notFound")]).isNotFound)
  }

  // Baseline: U.BigQueryError.02
  @Test func jobErrorPutsErrorResultFirstAndDeduplicates() throws {
    let errorResult = GoogleCloudBigQueryV2.ErrorProto().with {
      $0.reason = "invalidQuery"
      $0.message = "Syntax error"
      $0.location = "query"
    }
    let other = GoogleCloudBigQueryV2.ErrorProto().with { $0.reason = "stopped" }
    let id = JobID(projectID: "p", jobID: "j", location: "US")
    let error = try #require(
      BigQueryError(job: id, errorResult: errorResult, errors: [errorResult, other]))
    #expect(error.kind == .job)
    #expect(error.jobID == id)
    #expect(error.message == "Syntax error")
    #expect(error.errors.map(\.reason) == ["invalidQuery", "stopped"])
    #expect(BigQueryError(job: id, errorResult: nil, errors: []) == nil)
  }

  // Design: §4.3
  @Test func descriptionIncludesKindStatusReasonAndJob() {
    let error = BigQueryError(
      kind: .job, message: "boom", httpStatusCode: 400, errors: [.init(reason: "invalid")],
      jobID: JobID(projectID: "p", jobID: "j"))
    #expect(error.description == "BigQueryError(job, http 400, reason: invalid, job: p:j): boom")
  }
}

@Suite struct BigQueryRetryPolicyTests {
  private func http(_ status: Int, reasons: [String] = []) -> RequestError {
    let errors = reasons.map { #"{"reason": "\#($0)"}"# }.joined(separator: ",")
    return .http(
      HTTPDetails(
        statusCode: status,
        payload: Data(#"{"error": {"code": \#(status), "errors": [\#(errors)]}}"#.utf8)))
  }

  // Baseline: U.BigQueryException.01
  @Test(arguments: [429, 500, 502, 503, 504])
  func retriesTransientStatusCodes(status: Int) {
    #expect(BigQueryRetryErrors().isRetryable(self.http(status)))
  }

  // Baseline: U.BigQueryException.01
  @Test(arguments: [400, 401, 403, 404, 409, 412, 501])
  func doesNotRetryPermanentStatusCodes(status: Int) {
    #expect(!BigQueryRetryErrors().isRetryable(self.http(status)))
  }

  // Design: §5.2
  @Test(arguments: ["rateLimitExceeded", "backendError", "internalError", "badGateway"])
  func retriesTransientReasonsWhateverTheStatus(reason: String) {
    #expect(BigQueryRetryErrors().isRetryable(self.http(403, reasons: ["other", reason])))
  }

  // Design: §5.2
  @Test func doesNotRetryOtherReasons() {
    #expect(!BigQueryRetryErrors().isRetryable(self.http(403, reasons: ["quotaExceeded"])))
    #expect(!BigQueryRetryErrors().isRetryable(.malformedResponse("x")))
  }

  // Design: §5.2
  @Test func retriesOnlyIdempotentRequests() {
    let policy = BigQueryRetryPolicy()
    let idempotent = RetryState(idempotent: true)
    let nonIdempotent = RetryState(idempotent: false)
    guard case .retry = policy.onError(state: idempotent, error: self.http(503)) else {
      Issue.record("expected retry for an idempotent request")
      return
    }
    guard case .permanent = policy.onError(state: nonIdempotent, error: self.http(503)) else {
      Issue.record("expected permanent for a non-idempotent request")
      return
    }
    guard case .retry = policy.onError(state: idempotent, error: .io(URLError(.timedOut))) else {
      Issue.record("expected retry for an I/O error")
      return
    }
  }
}

@Suite struct BigQueryTransportTests {
  private func get(_ path: String = "/bigquery/v2/projects/p/datasets/d") -> HTTPRequest {
    HTTPRequest(method: .get, path: path)
  }

  // Design: §5.1
  @Test func addsPrettyPrintFalseToPathRequests() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: #"{"datasetId": "d", "projectId": "p"}"#)
    let reference: GoogleCloudBigQueryV2.DatasetReference = try await fake.transport().json(
      self.get(), idempotent: true)
    #expect(reference.datasetId == "d")
    #expect(fake.requests.first?.queryValue("prettyPrint") == "false")
    #expect(fake.requests.first?.path == "/bigquery/v2/projects/p/datasets/d")
  }

  // Design: §5.1
  @Test func leavesAbsoluteURLsAlone() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(status: 200, json: "")
    _ = try await fake.transport().send(
      HTTPRequest(method: .put, url: "https://upload.example.com/session"), idempotent: false)
    #expect(fake.requests.first?.query.isEmpty == true)
  }

  // Design: §7 (x-goog-api-client)
  @Test func sendsVeneerApiClientHeader() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "{}")
    fake.enqueue(status: 200, json: "")
    _ = try await fake.transport().send(self.get(), idempotent: true)
    _ = try await fake.transport().send(
      HTTPRequest(method: .put, url: "https://upload.example.com/session"), idempotent: false)
    #expect(fake.requests.count == 2)
    for request in fake.requests {
      let header = try #require(request.headers["x-goog-api-client"])
      #expect(header.hasPrefix("gl-swift/"))
      #expect(header.hasSuffix(" gccl/\(PackageVersion.version)"))
    }
  }

  // Baseline: U.BigQueryException.01, U.BigQueryImpl.15
  @Test func retriesIdempotentRequestUntilSuccess() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503)
    fake.enqueueError(status: 400, reasons: ["backendError"])
    fake.enqueue(.error(URLError(.networkConnectionLost)))
    fake.enqueue(json: #"{"datasetId": "d"}"#)
    let reference: GoogleCloudBigQueryV2.DatasetReference = try await fake.transport().json(
      self.get(), idempotent: true)
    #expect(reference.datasetId == "d")
    #expect(fake.requests.count == 4)
  }

  // Design: §5.2
  @Test func doesNotRetryNonIdempotentRequest() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503, message: "unavailable")
    fake.enqueue(json: "{}")
    let error = await #expect(throws: BigQueryError.self) {
      let _: GoogleCloudBigQueryV2.DatasetReference = try await fake.transport().json(
        HTTPRequest(method: .post, path: "/bigquery/v2/projects/p/datasets"), idempotent: false)
    }
    #expect(error?.httpStatusCode == 503)
    #expect(error?.message == "unavailable")
    #expect(fake.requests.count == 1)
  }

  // Baseline: U.BigQueryException.03
  @Test func defaultPolicyStopsAfterSixAttempts() async throws {
    let fake = FakeHTTPTransport()
    for _ in 0..<7 { fake.enqueue(.error(URLError(.networkConnectionLost))) }
    await #expect(throws: RequestError.self) {
      let _: GoogleCloudBigQueryV2.DatasetReference = try await fake.transport().json(
        self.get(), idempotent: true)
    }
    #expect(fake.requests.count == 6)
  }

  // Design: §4.3
  @Test func attemptLimitExhaustionSurfacesAsServiceError() async throws {
    let fake = FakeHTTPTransport()
    for _ in 0..<3 { fake.enqueueError(status: 503, reasons: ["backendError"]) }
    let policy = BigQueryRetryPolicy.unbounded().withAttemptLimit(3)
    let error = await #expect(throws: BigQueryError.self) {
      let _: GoogleCloudBigQueryV2.DatasetReference = try await fake.transport(policy).json(
        self.get(), idempotent: true)
    }
    #expect(error?.kind == .service)
    #expect(error?.httpStatusCode == 503)
    #expect(error?.reason == "backendError")
    #expect(fake.requests.count == 3)
  }

  // Design: §4.3
  @Test func elapsedTimeExhaustionSurfacesAsServiceError() async throws {
    let wrapped = RequestError.exhausted(
      .elapsedTime(
        maximumDuration: .seconds(1),
        source: .http(HTTPDetails(statusCode: 500, payload: Data()))))
    let mapped = BigQueryTransport.map(wrapped)
    let error = try #require(mapped as? BigQueryError)
    #expect(error.kind == .service)
    #expect(error.httpStatusCode == 500)
    #expect(BigQueryTransport.map(.exhausted(.attemptCount(maximumAttempts: 2))) is RequestError)
  }

  // Design: §5.3
  @Test func jsonOrNilReturnsNilOnNotFound() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 404, reasons: ["notFound"])
    let missing = try await fake.transport().jsonOrNil(
      self.get(), as: GoogleCloudBigQueryV2.DatasetReference.self)
    #expect(missing == nil)
  }

  // Design: §5.3
  @Test func jsonOrNilDecodesFoundResource() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: #"{"id": "p:d", "creationTime": "1700000000000"}"#)
    let dataset = try await fake.transport().jsonOrNil(
      self.get(), as: GoogleCloudBigQueryV2.Dataset.self)
    #expect(dataset?.creationTime == 1_700_000_000_000)
  }

  // Design: §5.3
  @Test func jsonOrNilThrowsOtherErrors() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 403, reasons: ["accessDenied"])
    await #expect(throws: BigQueryError.self) {
      _ = try await fake.transport().jsonOrNil(
        self.get(), as: GoogleCloudBigQueryV2.DatasetReference.self)
    }
  }

  // Design: §5.3
  @Test func deleteOrFalseMapsNotFound() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(status: 204, json: "")
    fake.enqueueError(status: 404)
    let transport = fake.transport()
    let request = HTTPRequest(method: .delete, path: "/bigquery/v2/projects/p/datasets/d")
    #expect(try await transport.deleteOrFalse(request))
    #expect(try await !transport.deleteOrFalse(request))
  }

  // Design: §5.1
  @Test func emptyBodyDecodesAsEmptyMessage() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(status: 200, json: "")
    let reference: GoogleCloudBigQueryV2.DatasetReference = try await fake.transport().json(
      self.get(), idempotent: true)
    #expect(reference.datasetId == "")
  }

  // Baseline: U.BigQueryImpl.60
  // Design: §5.1
  @Test func malformedBodyIsMalformedResponse() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "not json")
    await #expect {
      let _: GoogleCloudBigQueryV2.DatasetReference = try await fake.transport().json(
        self.get(), idempotent: true)
    } throws: { error in
      guard case .malformedResponse = error as? RequestError else { return false }
      return true
    }
  }

  // Design: §5.2
  @Test func perAttemptRequestAndValidation() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: #"{"jobId": "first"}"#)
    fake.enqueue(json: #"{"jobId": "second"}"#)
    var attempts: [Int] = []
    let reference: GoogleCloudBigQueryV2.JobReference = try await fake.transport().json(
      idempotent: true, options: .init(),
      request: { attempt in
        attempts.append(attempt)
        return HTTPRequest(method: .post, path: "/attempt/\(attempt)")
      },
      validate: { (reference: GoogleCloudBigQueryV2.JobReference) in
        if reference.jobId == "first" {
          throw RequestError.jobRateLimited([
            GoogleCloudBigQueryV2.ErrorProto().with {
              $0.reason = "jobRateLimitExceeded"
              $0.message = "slow down"
            }
          ])
        }
      })
    #expect(reference.jobId == "second")
    #expect(attempts == [1, 2])
    #expect(fake.requests.map(\.path) == ["/attempt/1", "/attempt/2"])
  }

  // Design: §5.2
  @Test func jobRateLimitedExhaustionKeepsDetails() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "{}")
    let error = await #expect(throws: BigQueryError.self) {
      let _: GoogleCloudBigQueryV2.JobReference = try await fake.transport(
        BigQueryRetryPolicy.unbounded().withAttemptLimit(1)
      ).json(
        idempotent: true, options: .init(),
        request: { _ in HTTPRequest(method: .post, path: "/q") },
        validate: { (_: GoogleCloudBigQueryV2.JobReference) in
          throw RequestError.jobRateLimited([
            GoogleCloudBigQueryV2.ErrorProto().with {
              $0.reason = "rateLimitExceeded"
              $0.message = "too many"
            }
          ])
        })
    }
    #expect(error?.httpStatusCode == 429)
    #expect(error?.reason == "rateLimitExceeded")
    #expect(error?.message == "too many")
  }

  // Design: §6.4
  @Test func sendOnceReturnsAnyStatusWithoutRetry() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(status: 308, json: "", headers: ["Range": "bytes=0-99"])
    let response = try await fake.transport().sendOnce(
      HTTPRequest(method: .put, url: "https://upload.example.com/s"))
    #expect(response.statusCode == 308)
    #expect(response.header("range") == "bytes=0-99")
    #expect(fake.requests.count == 1)
  }

  // Baseline: U.BigQueryException.04
  @Test func perCallRetryPolicyOverridesClientDefault() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503)
    fake.enqueue(json: "{}")
    var options = RequestOptions()
    options.retryPolicy = BigQueryRetryPolicy.unbounded().withAttemptLimit(1)
    await #expect(throws: BigQueryError.self) {
      let _: GoogleCloudBigQueryV2.DatasetReference = try await fake.transport().json(
        HTTPRequest(method: .get, path: "/x", options: options), idempotent: true)
    }
    #expect(fake.requests.count == 1)
  }
}
