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
@testable import GoogleCloudStorage
import Testing

@Suite struct UploadOptionsTests {
  @Test func uploadOptionsDefaults() {
    #expect(UploadOptions.defaultResumableUploadThreshold == 8 * 1024 * 1024)
    #expect(UploadOptions.defaultChunkSize == 8 * 1024 * 1024)

    let options = UploadOptions.default
    #expect(options.resumableUploadThreshold == nil)
    #expect(options.chunkSize == UploadOptions.defaultChunkSize)
    #expect(options.preconditions == nil)
    #expect(options.kmsKeyName == nil)
    #expect(options.customerEncryptionKey == nil)
    #expect(options.checksums == .default)
    #expect(options.metadata == nil)
    #expect(options.predefinedAcl == nil)
    #expect(options.resumePolicy == nil)
    #expect(options.backoffPolicy == nil)
    #expect(options.quotaProject == nil)
  }

  @Test func uploadOptionsWithBuilder() throws {
    let preconditions = StoragePreconditions().with {
      $0.ifGenerationMatch = 100
    }
    let csek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x42, count: 32))
    let metadata = UploadMetadata().with {
      $0.contentType = "application/json"
    }

    let options = UploadOptions().with {
      $0.resumableUploadThreshold = 4 * 1024 * 1024
      $0.chunkSize = 16 * 1024 * 1024
      $0.preconditions = preconditions
      $0.kmsKeyName = "projects/p/locations/l/keyRings/r/cryptoKeys/k"
      $0.customerEncryptionKey = csek
      $0.checksums = .none
      $0.metadata = metadata
      $0.predefinedAcl = .publicRead
      $0.resumePolicy = NeverResume<UploadDetails>()
      $0.quotaProject = "upload-quota-project"
    }

    #expect(options.resumableUploadThreshold == 4 * 1024 * 1024)
    #expect(options.chunkSize == 16 * 1024 * 1024)
    #expect(options.preconditions?.ifGenerationMatch == 100)
    #expect(options.kmsKeyName == "projects/p/locations/l/keyRings/r/cryptoKeys/k")
    #expect(options.customerEncryptionKey == csek)
    #expect(options.checksums == .none)
    #expect(options.metadata?.contentType == "application/json")
    #expect(options.predefinedAcl == .publicRead)
    #expect(options.resumePolicy != nil)
    #expect(options.quotaProject == "upload-quota-project")
  }

  @Test(
    arguments: [
      (
        options: UploadOptions(),
        expectedThreshold: 16 * 1024 * 1024,
        expectedIsAlwaysResume: false,
        expectedQuotaProject: "default-upload-quota"
      ),
      (
        options: UploadOptions().with {
          $0.resumableUploadThreshold = 32 * 1024 * 1024
          $0.resumePolicy = AlwaysResume<UploadDetails>()
          $0.quotaProject = "override-upload-quota"
        },
        expectedThreshold: 32 * 1024 * 1024,
        expectedIsAlwaysResume: true,
        expectedQuotaProject: "override-upload-quota"
      ),
    ]
  )
  func uploadOptionsWithDefaults(
    options: UploadOptions,
    expectedThreshold: Int,
    expectedIsAlwaysResume: Bool,
    expectedQuotaProject: String
  ) {
    let defaults = UploadOptions().with {
      $0.resumableUploadThreshold = 16 * 1024 * 1024
      $0.resumePolicy = NeverResume<UploadDetails>()
      $0.backoffPolicy = ExponentialBackoff()
      $0.quotaProject = "default-upload-quota"
    }

    let resolved = options.withDefaults(defaults)
    #expect(resolved.resumableUploadThreshold == expectedThreshold)
    if expectedIsAlwaysResume {
      #expect(resolved.resumePolicy is AlwaysResume<UploadDetails>)
    } else {
      #expect(resolved.resumePolicy is NeverResume<UploadDetails>)
    }
    #expect(resolved.backoffPolicy is ExponentialBackoff)
    #expect(resolved.quotaProject == expectedQuotaProject)
    #expect(resolved.requestOptions.quotaProject == expectedQuotaProject)
  }
}
