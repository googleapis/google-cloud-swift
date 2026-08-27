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
@testable import GoogleCloudStorage
import Testing

@Suite struct UploadStatusTests {
  @Test func uploadStatusFractionCompleted() {
    // nil totalBytes
    let statusNilTotal = UploadStatus(bytesUploaded: 10, totalBytes: nil)
    #expect(statusNilTotal.fractionCompleted == nil)

    // zero totalBytes
    let statusZeroTotal = UploadStatus(bytesUploaded: 0, totalBytes: 0)
    #expect(statusZeroTotal.fractionCompleted == nil)

    // non-nil, positive totalBytes
    let statusPartial = UploadStatus(bytesUploaded: 25, totalBytes: 100)
    #expect(statusPartial.fractionCompleted == 0.25)

    let statusComplete = UploadStatus(bytesUploaded: 100, totalBytes: 100)
    #expect(statusComplete.fractionCompleted == 1.0)

    let statusZeroBytes = UploadStatus(bytesUploaded: 0, totalBytes: 100)
    #expect(statusZeroBytes.fractionCompleted == 0.0)
  }
}
