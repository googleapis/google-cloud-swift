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
import GoogleCloudWkt

extension Object {
  private enum CodingKeys: Swift.String, CodingKey {
    case name
    case bucket
    case etag
    case generation
    case restoreToken
    case metageneration
    case storageClass
    case size
    case contentEncoding
    case contentDisposition
    case cacheControl
    case acl
    case contentLanguage
    case deleteTime
    case timeDeleted
    case finalizeTime
    case contentType
    case createTime
    case timeCreated
    case componentCount
    case checksums
    case crc32c
    case md5Hash
    case updateTime
    case updated
    case kmsKey
    case updateStorageClassTime
    case timeStorageClassUpdated
    case temporaryHold
    case retentionExpireTime
    case retentionExpirationTime
    case metadata
    case contexts
    case eventBasedHold
    case owner
    case customerEncryption
    case customTime
    case softDeleteTime
    case hardDeleteTime
    case retention
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.name = (try? container.decode(Swift.String.self, forKey: .name)) ?? ""
    self.bucket = (try? container.decode(Swift.String.self, forKey: .bucket)) ?? ""
    self.etag = (try? container.decode(Swift.String.self, forKey: .etag)) ?? ""

    if let genStr = try? container.decode(String.self, forKey: .generation), let gen = Int64(genStr) {
      self.generation = gen
    } else {
      self.generation = (try? container.decode(Swift.Int64.self, forKey: .generation)) ?? 0
    }

    self.restoreToken = try? container.decode(Swift.String.self, forKey: .restoreToken)

    if let metaStr = try? container.decode(String.self, forKey: .metageneration), let meta = Int64(metaStr) {
      self.metageneration = meta
    } else {
      self.metageneration = (try? container.decode(Swift.Int64.self, forKey: .metageneration)) ?? 0
    }

    self.storageClass = (try? container.decode(Swift.String.self, forKey: .storageClass)) ?? ""

    if let sizeStr = try? container.decode(String.self, forKey: .size), let s = Int64(sizeStr) {
      self.size = s
    } else {
      self.size = (try? container.decode(Swift.Int64.self, forKey: .size)) ?? 0
    }

    self.contentEncoding = (try? container.decode(Swift.String.self, forKey: .contentEncoding)) ?? ""
    self.contentDisposition = (try? container.decode(Swift.String.self, forKey: .contentDisposition)) ?? ""
    self.cacheControl = (try? container.decode(Swift.String.self, forKey: .cacheControl)) ?? ""
    self.acl = (try? container.decode([ObjectAccessControl].self, forKey: .acl)) ?? []
    self.contentLanguage = (try? container.decode(Swift.String.self, forKey: .contentLanguage)) ?? ""
    self.deleteTime = (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .deleteTime))
      ?? (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .timeDeleted))
    self.finalizeTime = try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .finalizeTime)
    self.contentType = (try? container.decode(Swift.String.self, forKey: .contentType)) ?? ""
    self.createTime = (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .createTime))
      ?? (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .timeCreated))

    if let compStr = try? container.decode(String.self, forKey: .componentCount), let c = Int32(compStr) {
      self.componentCount = c
    } else {
      self.componentCount = (try? container.decode(Swift.Int32.self, forKey: .componentCount)) ?? 0
    }

    if let checksums = try? container.decode(ObjectChecksums.self, forKey: .checksums) {
      self.checksums = checksums
    } else {
      var parsedChecksums = ObjectChecksums()
      var hasChecksums = false

      if let crc32cVal = try? container.decode(Swift.UInt32.self, forKey: .crc32c) {
        parsedChecksums.crc32C = crc32cVal
        hasChecksums = true
      } else if let crcStr = try? container.decode(String.self, forKey: .crc32c) {
        if let val = UInt32(crcStr) {
          parsedChecksums.crc32C = val
          hasChecksums = true
        } else if let data = Data(base64Encoded: crcStr), data.count == 4 {
          let val = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
          parsedChecksums.crc32C = val
          hasChecksums = true
        }
      }

      if let md5Data = try? container.decode(Foundation.Data.self, forKey: .md5Hash) {
        parsedChecksums.md5Hash = md5Data
        hasChecksums = true
      } else if let md5Str = try? container.decode(String.self, forKey: .md5Hash) {
        if let data = Data(base64Encoded: md5Str) {
          parsedChecksums.md5Hash = data
          hasChecksums = true
        }
      }

      if hasChecksums {
        self.checksums = parsedChecksums
      } else {
        self.checksums = nil
      }
    }

    self.updateTime = (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .updateTime))
      ?? (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .updated))
    self.kmsKey = (try? container.decode(Swift.String.self, forKey: .kmsKey)) ?? ""
    self.updateStorageClassTime = (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .updateStorageClassTime))
      ?? (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .timeStorageClassUpdated))
    self.temporaryHold = (try? container.decode(Swift.Bool.self, forKey: .temporaryHold)) ?? false
    self.retentionExpireTime = (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .retentionExpireTime))
      ?? (try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .retentionExpirationTime))
    self.metadata = (try? container.decode([Swift.String: Swift.String].self, forKey: .metadata)) ?? [:]
    self.contexts = try? container.decode(ObjectContexts.self, forKey: .contexts)
    self.eventBasedHold = try? container.decode(Swift.Bool.self, forKey: .eventBasedHold)
    self.owner = try? container.decode(Owner.self, forKey: .owner)
    self.customerEncryption = try? container.decode(CustomerEncryption.self, forKey: .customerEncryption)
    self.customTime = try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .customTime)
    self.softDeleteTime = try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .softDeleteTime)
    self.hardDeleteTime = try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .hardDeleteTime)
    self.retention = try? container.decode(Object.Retention.self, forKey: .retention)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.name, forKey: .name)
    try container.encode(self.bucket, forKey: .bucket)
    try container.encode(self.etag, forKey: .etag)
    try container.encode(self.generation, forKey: .generation)
    try container.encodeIfPresent(self.restoreToken, forKey: .restoreToken)
    try container.encode(self.metageneration, forKey: .metageneration)
    try container.encode(self.storageClass, forKey: .storageClass)
    try container.encode(self.size, forKey: .size)
    try container.encode(self.contentEncoding, forKey: .contentEncoding)
    try container.encode(self.contentDisposition, forKey: .contentDisposition)
    try container.encode(self.cacheControl, forKey: .cacheControl)
    try container.encode(self.acl, forKey: .acl)
    try container.encode(self.contentLanguage, forKey: .contentLanguage)
    try container.encodeIfPresent(self.deleteTime, forKey: .deleteTime)
    try container.encodeIfPresent(self.finalizeTime, forKey: .finalizeTime)
    try container.encode(self.contentType, forKey: .contentType)
    try container.encodeIfPresent(self.createTime, forKey: .createTime)
    try container.encode(self.componentCount, forKey: .componentCount)
    try container.encodeIfPresent(self.checksums, forKey: .checksums)
    try container.encodeIfPresent(self.updateTime, forKey: .updateTime)
    try container.encode(self.kmsKey, forKey: .kmsKey)
    try container.encodeIfPresent(self.updateStorageClassTime, forKey: .updateStorageClassTime)
    try container.encode(self.temporaryHold, forKey: .temporaryHold)
    try container.encodeIfPresent(self.retentionExpireTime, forKey: .retentionExpireTime)
    try container.encode(self.metadata, forKey: .metadata)
    try container.encodeIfPresent(self.contexts, forKey: .contexts)
    try container.encodeIfPresent(self.eventBasedHold, forKey: .eventBasedHold)
    try container.encodeIfPresent(self.owner, forKey: .owner)
    try container.encodeIfPresent(self.customerEncryption, forKey: .customerEncryption)
    try container.encodeIfPresent(self.customTime, forKey: .customTime)
    try container.encodeIfPresent(self.softDeleteTime, forKey: .softDeleteTime)
    try container.encodeIfPresent(self.hardDeleteTime, forKey: .hardDeleteTime)
    try container.encodeIfPresent(self.retention, forKey: .retention)
  }
}
