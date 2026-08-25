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
  private func isResume(_ result: ResumeResult) -> Bool {
    if case .resume = result { true } else { false }
  }

  private func isPermanent(_ result: ResumeResult) -> Bool {
    if case .permanent = result { true } else { false }
  }

  private func isExhausted(_ result: ResumeResult) -> Bool {
    if case .exhausted = result { true } else { false }
  }

  @Test func uploadDetailsDefaults() {
    let details = UploadDetails()
    #expect(details.bytesUploaded == 0)
    #expect(details.totalBytes == nil)

    let state = ResumeState(details: details)
    #expect(state.details.bytesUploaded == 0)
    #expect(state.details.totalBytes == nil)
    #expect(state.consecutiveErrorCount == 0)
    #expect(state.totalResumeCount == 0)
  }

  @Test func uploadDetailsCustomInitializationAndBuilder() {
    let now = ContinuousClock.now
    let details = UploadDetails(bytesUploaded: 1024, totalBytes: 4096)
    let state = ResumeState(details: details, start: now).with {
      $0.consecutiveErrorCount = 2
      $0.totalResumeCount = 5
    }

    #expect(state.details.bytesUploaded == 1024)
    #expect(state.details.totalBytes == 4096)
    #expect(state.consecutiveErrorCount == 2)
    #expect(state.totalResumeCount == 5)
    #expect(state.start == now)
  }

  @Test func downloadDetailsDefaults() {
    let details = DownloadDetails()
    #expect(details.bytesDownloaded == 0)
    #expect(details.totalBytes == nil)

    let state = ResumeState(details: details)
    #expect(state.details.bytesDownloaded == 0)
    #expect(state.details.totalBytes == nil)
    #expect(state.consecutiveErrorCount == 0)
    #expect(state.totalResumeCount == 0)
  }

  @Test func downloadDetailsCustomInitializationAndBuilder() {
    let now = ContinuousClock.now
    let details = DownloadDetails(bytesDownloaded: 2048, totalBytes: 8192)
    let state = ResumeState(details: details, start: now).with {
      $0.consecutiveErrorCount = 1
      $0.totalResumeCount = 3
    }

    #expect(state.details.bytesDownloaded == 2048)
    #expect(state.details.totalBytes == 8192)
    #expect(state.consecutiveErrorCount == 1)
    #expect(state.totalResumeCount == 3)
    #expect(state.start == now)
  }

  @Test func resumePolicyProgressUpdatesState() {
    let policy = StorageResumePolicy<UploadDetails>()
    var state = ResumeState(details: UploadDetails(bytesUploaded: 0, totalBytes: 1000)).with {
      $0.consecutiveErrorCount = 3
    }

    state.details.bytesUploaded = 250
    policy.onProgress(state: &state)
    #expect(state.details.bytesUploaded == 250)
    #expect(state.consecutiveErrorCount == 0)

    state.details.bytesUploaded = 500
    state.consecutiveErrorCount = 2
    policy.onProgress(state: &state)
    #expect(state.details.bytesUploaded == 500)
    #expect(state.consecutiveErrorCount == 0)
  }

  @Test func storageResumePolicy() {
    let policy = StorageResumePolicy<Void>()
    let state = ResumeState()

    // Recoverable HTTP status codes
    let err408 = RequestError.http(HTTPDetails(http_status_code: 408, headers: [:]))
    let err429 = RequestError.http(HTTPDetails(http_status_code: 429, headers: [:]))
    let err502 = RequestError.http(HTTPDetails(http_status_code: 502, headers: [:]))
    let err503 = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let err504 = RequestError.http(HTTPDetails(http_status_code: 504, headers: [:]))
    let errIO = RequestError.io(NSError(domain: "test", code: -1))

    #expect(isResume(policy.onError(state: state, error: err408)))
    #expect(isResume(policy.onError(state: state, error: err429)))
    #expect(isResume(policy.onError(state: state, error: err502)))
    #expect(isResume(policy.onError(state: state, error: err503)))
    #expect(isResume(policy.onError(state: state, error: err504)))
    #expect(isResume(policy.onError(state: state, error: errIO)))

    // Permanent HTTP status codes
    let err400 = RequestError.http(HTTPDetails(http_status_code: 400, headers: [:]))
    let err401 = RequestError.http(HTTPDetails(http_status_code: 401, headers: [:]))
    let err403 = RequestError.http(HTTPDetails(http_status_code: 403, headers: [:]))
    let err404 = RequestError.http(HTTPDetails(http_status_code: 404, headers: [:]))
    let err412 = RequestError.http(HTTPDetails(http_status_code: 412, headers: [:]))
    let err500 = RequestError.http(HTTPDetails(http_status_code: 500, headers: [:]))

    #expect(isPermanent(policy.onError(state: state, error: err400)))
    #expect(isPermanent(policy.onError(state: state, error: err401)))
    #expect(isPermanent(policy.onError(state: state, error: err403)))
    #expect(isPermanent(policy.onError(state: state, error: err404)))
    #expect(isPermanent(policy.onError(state: state, error: err412)))
    #expect(isPermanent(policy.onError(state: state, error: err500)))
  }

  @Test func storageResumePolicyConsecutiveErrors() {
    let policy = StorageResumePolicy<Void>().stopOnConsecutiveErrors(2)
    var state = ResumeState()

    let transientError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let permanentError = RequestError.http(HTTPDetails(http_status_code: 404, headers: [:]))
    let authError = RequestError.http(HTTPDetails(http_status_code: 401, headers: [:]))
    let ioError = RequestError.io(NSError(domain: "test", code: -1))

    // Permanent errors halt immediately
    #expect(isPermanent(policy.onError(state: state, error: permanentError)))
    #expect(isPermanent(policy.onError(state: state, error: authError)))

    // 1st transient error resumes
    state.consecutiveErrorCount = 1
    state.totalResumeCount = 1
    #expect(isResume(policy.onError(state: state, error: transientError)))

    // Progress resets consecutive errors
    policy.onProgress(state: &state)
    #expect(state.consecutiveErrorCount == 0)

    // Consecutive error 1 after progress resumes
    state.consecutiveErrorCount = 1
    #expect(isResume(policy.onError(state: state, error: ioError)))

    // Consecutive error 2 reaches threshold and exhausts
    state.consecutiveErrorCount = 2
    #expect(isExhausted(policy.onError(state: state, error: transientError)))
  }

  @Test func limitedTotalResumesPolicy() {
    let policy = StorageResumePolicy<Void>().withTotalResumeLimit(2)
    var state = ResumeState()

    let transientError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let permanentError = RequestError.http(HTTPDetails(http_status_code: 403, headers: [:]))

    // Permanent error
    #expect(isPermanent(policy.onError(state: state, error: permanentError)))

    // 1st resume
    state.totalResumeCount = 1
    #expect(isResume(policy.onError(state: state, error: transientError)))

    // Making progress doesn't reset total resume count
    policy.onProgress(state: &state)
    #expect(state.totalResumeCount == 1)

    // 2nd resume hits max and exhausts
    state.totalResumeCount = 2
    #expect(isExhausted(policy.onError(state: state, error: transientError)))
  }

  @Test func neverResumePolicy() {
    let policy = NeverResume<Void>()
    let state = ResumeState()
    let transientError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let ioError = RequestError.io(NSError(domain: "test", code: -1))

    #expect(isPermanent(policy.onError(state: state, error: transientError)))
    #expect(isPermanent(policy.onError(state: state, error: ioError)))
  }

  @Test func alwaysResumePolicy() {
    let policy = AlwaysResume<Void>()
    var state = ResumeState()
    let transientError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let permanentError = RequestError.http(HTTPDetails(http_status_code: 400, headers: [:]))

    #expect(isResume(policy.onError(state: state, error: permanentError)))

    state.consecutiveErrorCount = 100
    state.totalResumeCount = 500
    #expect(isResume(policy.onError(state: state, error: transientError)))
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
    }
    let task = client.readObject(from: bucket, object: object, options: downloadOptions)

    do {
      _ = try await task.metadata
      Issue.record("Expected download with NeverResume to throw on 503")
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
