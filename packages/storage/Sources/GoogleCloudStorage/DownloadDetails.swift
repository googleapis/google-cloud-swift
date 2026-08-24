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

/// Progress and size details for an ongoing download operation.
public struct DownloadDetails: Sendable, Equatable {
  /// The total number of bytes successfully downloaded so far.
  public var bytesDownloaded: UInt64

  /// The total size of the object to download in bytes, if known.
  public var totalBytes: Int64?

  /// Creates a new `DownloadDetails` instance.
  ///
  /// - Parameters:
  ///   - bytesDownloaded: Initial bytes downloaded. Defaults to 0.
  ///   - totalBytes: Total object size in bytes if known. Defaults to `nil`.
  public init(
    bytesDownloaded: UInt64 = 0,
    totalBytes: Int64? = nil
  ) {
    self.bytesDownloaded = bytesDownloaded
    self.totalBytes = totalBytes
  }
}
