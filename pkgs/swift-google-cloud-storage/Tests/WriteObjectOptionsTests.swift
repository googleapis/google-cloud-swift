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
import GoogleGax
@testable import GoogleCloudStorage
import Testing

@Suite struct WriteObjectOptionsTests {
  @Test func writeObjectOptionsDefaults() {
    #expect(WriteObjectOptions.defaultResumableUploadThreshold == 8 * 1024 * 1024)
    #expect(WriteObjectOptions.defaultChunkSize == 8 * 1024 * 1024)

    let options = WriteObjectOptions.default
    #expect(options.resumableUploadThreshold == nil)
    #expect(options.chunkSize == nil)
    #expect(options.preconditions == nil)
    #expect(options.kmsKeyName == nil)
    #expect(options.customerEncryptionKey == nil)
    #expect(options.checksums == nil)
    #expect(options.metadata == nil)
    #expect(options.predefinedAcl == nil)
    #expect(options.resumePolicy == nil)
    #expect(options.backoffPolicy == nil)
    #expect(options.quotaProject == nil)
    #expect(options.idempotency == nil)

    let effectiveOptions = options.withDefaults(.default)
    #expect(
      effectiveOptions.resumableUploadThreshold
        == WriteObjectOptions.defaultResumableUploadThreshold
    )
    #expect(effectiveOptions.chunkSize == WriteObjectOptions.defaultChunkSize)
    #expect(effectiveOptions.checksums == .default)
  }

  @Test func writeObjectOptionsWithBuilder() throws {
    let preconditions = StoragePreconditions().with {
      $0.ifGenerationMatch = 100
    }
    let csek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x42, count: 32))
    let metadata = WriteObjectMetadata().with {
      $0.contentType = "application/json"
    }

    let options = WriteObjectOptions().with {
      $0.resumableUploadThreshold = 4 * 1024 * 1024
      $0.chunkSize = 16 * 1024 * 1024
      $0.preconditions = preconditions
      $0.kmsKeyName = "projects/p/locations/l/keyRings/r/cryptoKeys/k"
      $0.customerEncryptionKey = csek
      $0.checksums = .off
      $0.metadata = metadata
      $0.predefinedAcl = .publicRead
      $0.resumePolicy = NeverResume<WriteObjectDetails>()
      $0.quotaProject = "upload-quota-project"
    }

    #expect(options.resumableUploadThreshold == 4 * 1024 * 1024)
    #expect(options.chunkSize == 16 * 1024 * 1024)
    #expect(options.preconditions?.ifGenerationMatch == 100)
    #expect(options.kmsKeyName == "projects/p/locations/l/keyRings/r/cryptoKeys/k")
    #expect(options.customerEncryptionKey == csek)
    #expect(options.checksums == .off)
    #expect(options.metadata?.contentType == "application/json")
    #expect(options.predefinedAcl == .publicRead)
    #expect(options.resumePolicy != nil)
    #expect(options.quotaProject == "upload-quota-project")
  }

  @Test func writeObjectOptionsWithDefaultsInheritsAllProperties() throws {
    let defaultCsek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x11, count: 32))
    let defaults = WriteObjectOptions().with {
      $0.chunkSize = 4 * 1024 * 1024
      $0.resumableUploadThreshold = 16 * 1024 * 1024
      $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 1 }
      $0.kmsKeyName = "default-kms-key"
      $0.customerEncryptionKey = defaultCsek
      $0.checksums = .off
      $0.metadata = WriteObjectMetadata().with { $0.contentType = "text/plain" }
      $0.predefinedAcl = .private
      $0.resumePolicy = NeverResume<WriteObjectDetails>()
      $0.backoffPolicy = ExponentialBackoff()
      $0.quotaProject = "default-upload-quota"
      $0.idempotency = true
    }

    let resolved = WriteObjectOptions().withDefaults(defaults)
    #expect(resolved.chunkSize == 4 * 1024 * 1024)
    #expect(resolved.resumableUploadThreshold == 16 * 1024 * 1024)
    #expect(resolved.preconditions?.ifGenerationMatch == 1)
    #expect(resolved.kmsKeyName == "default-kms-key")
    #expect(resolved.customerEncryptionKey == defaultCsek)
    #expect(resolved.checksums == .off)
    #expect(resolved.metadata?.contentType == "text/plain")
    #expect(resolved.predefinedAcl == .private)
    #expect(resolved.resumePolicy is NeverResume<WriteObjectDetails>)
    #expect(resolved.backoffPolicy is ExponentialBackoff)
    #expect(resolved.quotaProject == "default-upload-quota")
    #expect(resolved.requestOptions.quotaProject == "default-upload-quota")
    #expect(resolved.idempotency == true)
  }

  @Test func writeObjectOptionsWithDefaultsOverridesAllProperties() throws {
    let defaultCsek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x11, count: 32))
    let overrideCsek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x22, count: 32))
    let defaults = WriteObjectOptions().with {
      $0.chunkSize = 4 * 1024 * 1024
      $0.resumableUploadThreshold = 16 * 1024 * 1024
      $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 1 }
      $0.kmsKeyName = "default-kms-key"
      $0.customerEncryptionKey = defaultCsek
      $0.checksums = .off
      $0.metadata = WriteObjectMetadata().with { $0.contentType = "text/plain" }
      $0.predefinedAcl = .private
      $0.resumePolicy = NeverResume<WriteObjectDetails>()
      $0.backoffPolicy = ExponentialBackoff()
      $0.quotaProject = "default-upload-quota"
      $0.idempotency = true
    }

    let options = WriteObjectOptions().with {
      $0.chunkSize = 8 * 1024 * 1024
      $0.resumableUploadThreshold = 32 * 1024 * 1024
      $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 2 }
      $0.kmsKeyName = "override-kms-key"
      $0.customerEncryptionKey = overrideCsek
      $0.checksums = .default
      $0.metadata = WriteObjectMetadata().with { $0.contentType = "application/octet-stream" }
      $0.predefinedAcl = .publicRead
      $0.resumePolicy = AlwaysResume<WriteObjectDetails>.unbounded()
      $0.quotaProject = "override-upload-quota"
      $0.idempotency = false
    }

    let resolved = options.withDefaults(defaults)
    #expect(resolved.chunkSize == 8 * 1024 * 1024)
    #expect(resolved.resumableUploadThreshold == 32 * 1024 * 1024)
    #expect(resolved.preconditions?.ifGenerationMatch == 2)
    #expect(resolved.kmsKeyName == "override-kms-key")
    #expect(resolved.customerEncryptionKey == overrideCsek)
    #expect(resolved.checksums == .default)
    #expect(resolved.metadata?.contentType == "application/octet-stream")
    #expect(resolved.predefinedAcl == .publicRead)
    #expect(resolved.resumePolicy is AlwaysResume<WriteObjectDetails>)
    #expect(resolved.backoffPolicy is ExponentialBackoff)
    #expect(resolved.quotaProject == "override-upload-quota")
    #expect(resolved.requestOptions.quotaProject == "override-upload-quota")
    #expect(resolved.idempotency == false)
  }
}
