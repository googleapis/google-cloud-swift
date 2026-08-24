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

/// The state of an ongoing download operation.
///
/// Tracks the number of bytes successfully downloaded from Cloud Storage, the total object size,
/// and consecutive errors and resume counts managed by the ``ResumePolicy``.
public final class DownloadResumeState: ResumeState, @unchecked Sendable {
  /// The total number of bytes successfully downloaded so far.
  public var bytesDownloaded: UInt64

  /// The total size of the object to download in bytes, if known.
  public var totalBytes: Int64?

  /// Creates a new `DownloadResumeState` instance.
  ///
  /// - Parameters:
  ///   - bytesDownloaded: Initial bytes downloaded. Defaults to 0.
  ///   - totalBytes: Total object size in bytes if known. Defaults to `nil`.
  ///   - start: The clock instant when the operation started. Defaults to `.now`.
  public init(
    bytesDownloaded: UInt64 = 0,
    totalBytes: Int64? = nil,
    start: ContinuousClock.Instant = .now
  ) {
    self.bytesDownloaded = bytesDownloaded
    self.totalBytes = totalBytes
    super.init(start: start)
  }

  /// Override specific values using the `Then` idiom.
  ///
  /// ## Example
  /// ```
  /// let state = DownloadResumeState().with { $0.bytesDownloaded = 1024 }
  /// ```
  @discardableResult
  public func with(_ config: (DownloadResumeState) -> Void) -> Self {
    config(self)
    return self
  }
}
