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
import GoogleCloudGax

/// The state of an ongoing upload operation.
///
/// Tracks the number of bytes successfully uploaded/committed to Cloud Storage, the total object size,
/// and consecutive errors and resume counts managed by the ``ResumePolicy``.
public final class UploadResumeState: ResumeState, @unchecked Sendable {
  /// The total number of bytes successfully uploaded or committed so far.
  public var bytesUploaded: UInt64

  /// The total size of the object to upload in bytes, if known.
  public var totalBytes: Int64?

  /// Creates a new `UploadResumeState` instance.
  ///
  /// - Parameters:
  ///   - bytesUploaded: Initial bytes uploaded. Defaults to 0.
  ///   - totalBytes: Total object size in bytes if known. Defaults to `nil`.
  ///   - start: The clock instant when the operation started. Defaults to `.now`.
  public init(
    bytesUploaded: UInt64 = 0,
    totalBytes: Int64? = nil,
    start: ContinuousClock.Instant = .now
  ) {
    self.bytesUploaded = bytesUploaded
    self.totalBytes = totalBytes
    super.init(start: start)
  }

  /// Override specific values on this upload state.
  @discardableResult
  public func configure(_ config: (UploadResumeState) -> Void) -> Self {
    config(self)
    return self
  }
}
