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
import GoogleCloudWKT

package struct StringOrInt64: Decodable, Sendable {
  package let value: Int64

  package init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let intVal = try? container.decode(Int64.self) {
      self.value = intVal
    } else if let strVal = try? container.decode(String.self), let parsed = Int64(strVal) {
      self.value = parsed
    } else {
      self.value = 0
    }
  }
}

package struct StringOrInt32: Decodable, Sendable {
  package let value: Int32

  package init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let intVal = try? container.decode(Int32.self) {
      self.value = intVal
    } else if let strVal = try? container.decode(String.self), let parsed = Int32(strVal) {
      self.value = parsed
    } else {
      self.value = 0
    }
  }
}

package struct RetentionV1: Decodable, Sendable {
  package var mode: String?
  package var retainUntilTime: GoogleCloudWKT.Timestamp?
}

package struct ObjectV1Response: Decodable, Sendable {
  package var name: String?
  package var bucket: String?
  package var etag: String?
  package var generation: StringOrInt64?
  package var metageneration: StringOrInt64?
  package var storageClass: String?
  package var size: StringOrInt64?
  package var contentEncoding: String?
  package var contentDisposition: String?
  package var cacheControl: String?
  package var acl: [ObjectAccessControl]?
  package var contentLanguage: String?
  package var contentType: String?
  package var timeCreated: GoogleCloudWKT.Timestamp?
  package var componentCount: StringOrInt32?
  package var crc32c: String?
  package var md5Hash: String?
  package var updated: GoogleCloudWKT.Timestamp?
  package var kmsKeyName: String?
  package var timeStorageClassUpdated: GoogleCloudWKT.Timestamp?
  package var temporaryHold: Bool?
  package var retentionExpirationTime: GoogleCloudWKT.Timestamp?
  package var metadata: [String: String]?
  package var contexts: ObjectContexts?
  package var eventBasedHold: Bool?
  package var owner: Owner?
  package var customerEncryption: CustomerEncryption?
  package var customTime: GoogleCloudWKT.Timestamp?
  package var retention: RetentionV1?

  package init() {}

  package func toObject() -> Object {
    var obj = Object()
    obj.name = name ?? ""
    obj.bucket = BucketName.formatResourceName(bucket ?? "")
    obj.etag = etag ?? ""
    obj.generation = generation?.value ?? 0
    obj.metageneration = metageneration?.value ?? 0
    obj.storageClass = storageClass ?? ""
    obj.size = size?.value ?? 0
    obj.contentEncoding = contentEncoding ?? ""
    obj.contentDisposition = contentDisposition ?? ""
    obj.cacheControl = cacheControl ?? ""
    obj.acl = acl ?? []
    obj.contentLanguage = contentLanguage ?? ""
    obj.contentType = contentType ?? ""
    obj.createTime = timeCreated
    obj.componentCount = componentCount?.value ?? 0

    var checksums = ObjectChecksums()
    var hasChecksums = false
    if let crc32c = crc32c {
      if let val = UInt32(crc32c) {
        checksums.crc32C = val
        hasChecksums = true
      } else if let data = Data(base64Encoded: crc32c), data.count == 4 {
        let val = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        checksums.crc32C = val
        hasChecksums = true
      }
    }
    if let md5Hash = md5Hash {
      if let data = Data(base64Encoded: md5Hash) {
        checksums.md5Hash = data
        hasChecksums = true
      }
    }
    if hasChecksums {
      obj.checksums = checksums
    }

    obj.updateTime = updated
    obj.kmsKey = kmsKeyName ?? ""
    obj.updateStorageClassTime = timeStorageClassUpdated
    obj.temporaryHold = temporaryHold ?? false
    obj.retentionExpireTime = retentionExpirationTime
    obj.metadata = metadata ?? [:]
    obj.contexts = contexts
    obj.eventBasedHold = eventBasedHold
    obj.owner = owner
    obj.customerEncryption = customerEncryption
    obj.customTime = customTime

    if let retention = retention {
      var r = Object.Retention()
      if let modeStr = retention.mode {
        r.mode = Object.Retention.Mode(stringValue: modeStr.uppercased())
      }
      r.retainUntilTime = retention.retainUntilTime
      obj.retention = r
    }

    return obj
  }
}
