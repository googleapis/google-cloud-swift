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
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct ResumePolicyTests {
  @Test func resumeStateDefaults() {
    let state = ResumeState()
    #expect(state.bytesTransferred == 0)
    #expect(state.totalBytes == nil)
    #expect(state.consecutiveErrorCount == 0)
    #expect(state.totalResumeCount == 0)
  }

  @Test func resumeStateCustomInitializationAndBuilder() {
    let now = ContinuousClock.now
    let state = ResumeState(bytesTransferred: 1024, totalBytes: 4096, start: now).with {
      $0.consecutiveErrorCount = 2
      $0.totalResumeCount = 5
    }

    #expect(state.bytesTransferred == 1024)
    #expect(state.totalBytes == 4096)
    #expect(state.consecutiveErrorCount == 2)
    #expect(state.totalResumeCount == 5)
    #expect(state.start == now)
  }

  @Test func resumePolicyProgressUpdatesState() {
    let policy = StopOnConsecutiveErrors()
    var state = ResumeState(bytesTransferred: 0, totalBytes: 1000).with {
      $0.consecutiveErrorCount = 3
    }

    policy.onProgress(state: &state, bytesAdvanced: 250)
    #expect(state.bytesTransferred == 250)
    #expect(state.consecutiveErrorCount == 0)

    policy.onProgress(state: &state, bytesAdvanced: 250)
    #expect(state.bytesTransferred == 500)
    #expect(state.consecutiveErrorCount == 0)
  }

  @Test func stopOnConsecutiveErrorsPolicy() {
    let policy = StopOnConsecutiveErrors(maxConsecutiveErrors: 2)
    var state = ResumeState()

    let transientError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let permanentError = RequestError.http(HTTPDetails(http_status_code: 404, headers: [:]))
    let authError = RequestError.http(HTTPDetails(http_status_code: 401, headers: [:]))
    let ioError = RequestError.io(NSError(domain: "test", code: -1))

    // Permanent errors halt immediately
    if case .permanent = policy.onError(state: state, error: permanentError) {
    } else {
      Issue.record("Expected .permanent for 404")
    }
    if case .permanent = policy.onError(state: state, error: authError) {
    } else {
      Issue.record("Expected .permanent for 401")
    }

    // 1st transient error resumes
    state.consecutiveErrorCount = 1
    state.totalResumeCount = 1
    if case .resume = policy.onError(state: state, error: transientError) {
    } else {
      Issue.record("Expected .resume for 1st consecutive transient error")
    }

    // Progress resets consecutive errors
    policy.onProgress(state: &state, bytesAdvanced: 500)
    #expect(state.consecutiveErrorCount == 0)

    // Consecutive error 1 after progress resumes
    state.consecutiveErrorCount = 1
    if case .resume = policy.onError(state: state, error: ioError) {
    } else {
      Issue.record("Expected .resume for io error")
    }

    // Consecutive error 2 reaches threshold and exhausts
    state.consecutiveErrorCount = 2
    if case .exhausted = policy.onError(state: state, error: transientError) {
    } else {
      Issue.record("Expected .exhausted after reaching maxConsecutiveErrors")
    }
  }

  @Test func limitedTotalResumesPolicy() {
    let policy = LimitedTotalResumes(maxTotalResumes: 2)
    var state = ResumeState()

    let transientError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let permanentError = RequestError.http(HTTPDetails(http_status_code: 403, headers: [:]))

    // Permanent error
    if case .permanent = policy.onError(state: state, error: permanentError) {
    } else {
      Issue.record("Expected .permanent for 403")
    }

    // 1st resume
    state.totalResumeCount = 1
    if case .resume = policy.onError(state: state, error: transientError) {
    } else {
      Issue.record("Expected .resume for 1st resume attempt")
    }

    // Making progress doesn't reset total resume count
    policy.onProgress(state: &state, bytesAdvanced: 500)
    #expect(state.totalResumeCount == 1)

    // 2nd resume hits max and exhausts
    state.totalResumeCount = 2
    if case .exhausted = policy.onError(state: state, error: transientError) {
    } else {
      Issue.record("Expected .exhausted after maxTotalResumes reached")
    }
  }

  @Test func neverResumePolicy() {
    let policy = NeverResume()
    let state = ResumeState()
    let transientError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let ioError = RequestError.io(NSError(domain: "test", code: -1))

    if case .permanent = policy.onError(state: state, error: transientError) {
    } else {
      Issue.record("Expected .permanent for NeverResume")
    }
    if case .permanent = policy.onError(state: state, error: ioError) {
    } else {
      Issue.record("Expected .permanent for NeverResume on IO error")
    }
  }

  @Test func alwaysResumePolicy() {
    let policy = AlwaysResume()
    var state = ResumeState()
    let transientError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let permanentError = RequestError.http(HTTPDetails(http_status_code: 400, headers: [:]))

    if case .permanent = policy.onError(state: state, error: permanentError) {
    } else {
      Issue.record("Expected .permanent for 400")
    }

    state.consecutiveErrorCount = 100
    state.totalResumeCount = 500
    if case .resume = policy.onError(state: state, error: transientError) {
    } else {
      Issue.record("Expected .resume for AlwaysResume even with high attempt counts")
    }
  }

  @Test func uploadWithOptionsCustomResumePolicy() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-resume-policy")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    // Return 503 on chunk upload
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: nil),
      for: chunkUrl)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry)

    // With NeverResume, chunk upload 503 must fail immediately without query/retry
    let uploadOptions = UploadOptions().with {
      $0.resumePolicy = NeverResume()
    }
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    let error = await expectError(RequestError.self) {
      try await task.value
    }
    if case .http(let details) = error {
      #expect(details.http_status_code == 503)
    } else {
      Issue.record("Expected .http 503 RequestError, got \(String(describing: error))")
    }
  }

  @Test func downloadWithOptionsCustomResumePolicy() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let object = "test-object"

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(object)?alt=media")
    // Register initial failure with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Unavailable".utf8),
        headers: nil),
      for: downloadUrl)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    let client = try StorageClient(options, mock: registry)

    let downloadOptions = ReadObjectOptions().with {
      $0.resumePolicy = NeverResume()
      $0.retryPolicy = NeverRetry()
    }
    let task = client.readObject(from: bucket, object: object, options: downloadOptions)

    do {
      _ = try await task.metadata
      Issue.record("Expected download with NeverRetry to throw on 503")
    } catch {}
  }

  private func expectError<E: Error>(
    _ expectedType: E.Type,
    operation: () async throws -> some Any
  ) async -> E? {
    do {
      _ = try await operation()
      Issue.record("Expected operation to throw \(expectedType), but it succeeded.")
      return nil
    } catch let error as E {
      return error
    } catch {
      Issue.record("Expected operation to throw \(expectedType), but it threw \(error).")
      return nil
    }
  }
}
