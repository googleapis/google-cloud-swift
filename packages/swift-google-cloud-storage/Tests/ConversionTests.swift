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

import GoogleCloudGax
import GoogleCloudWKT
import GoogleType
import StorageControlProtos
import Testing
@testable import GoogleCloudStorage

@Suite struct ConversionTests {
  @Test func findingCategoryKnownValueRoundtrip() throws {
    // Round-trip .dataManagement
    let native = FindingCategory.dataManagement
    let proto = try native.toProto()
    #expect(proto == .dataManagement)

    let roundtripped = FindingCategory(proto: proto)
    #expect(roundtripped == native)
  }

  @Test func findingCategoryProtoToNativeUnknownInteger() throws {
    // Proto UNRECOGNIZED(42) -> Native .unknownIntValue(42)
    let proto = StorageControlProtos.Google_Storage_Control_V2_FindingCategory.UNRECOGNIZED(42)
    let native = FindingCategory(proto: proto)
    #expect(native == .unknownIntValue(42))
  }

  @Test func findingCategoryNativeToProtoUnknownInteger() throws {
    // Native .unknownIntValue(42) -> Proto UNRECOGNIZED(42)
    let native = FindingCategory.unknownIntValue(42)
    let proto = try native.toProto()
    #expect(proto == .UNRECOGNIZED(42))
  }

  @Test func findingCategoryNativeToProtoUnknownStringThrows() throws {
    // Native .unknownStringValue("NEW_CATEGORY") -> throws noIntegerValue
    let native = FindingCategory.unknownStringValue("NEW_CATEGORY")
    #expect(
      throws: ProtobufConversionError.noIntegerValue(
        enumType: "FindingCategory", stringValue: "NEW_CATEGORY")
    ) {
      _ = try native.toProto()
    }
  }

  @Test func pendingRenameInfoRoundtrip() throws {
    let original = PendingRenameInfo().with {
      $0.operation = "projects/_/buckets/my-bucket/operations/12345"
    }

    let proto = try original.toProto()
    #expect(proto.operation == "projects/_/buckets/my-bucket/operations/12345")

    let roundtripped = try PendingRenameInfo(proto: proto)
    #expect(original == roundtripped)
  }

  @Test func getFolderRequestOptionalPresence() throws {
    // 1. All optional fields nil
    var request = GetFolderRequest().with {
      $0.name = "projects/_/buckets/b/folders/f"
    }
    var proto = try request.toProto()
    #expect(proto.name == "projects/_/buckets/b/folders/f")
    #expect(!proto.hasIfMetagenerationMatch)
    #expect(!proto.hasIfMetagenerationNotMatch)

    var roundtripped = try GetFolderRequest(proto: proto)
    #expect(roundtripped.ifMetagenerationMatch == nil)
    #expect(roundtripped.ifMetagenerationNotMatch == nil)

    // 2. Optional fields set
    request = GetFolderRequest().with {
      $0.name = "projects/_/buckets/b/folders/f"
      $0.ifMetagenerationMatch = 123
      $0.ifMetagenerationNotMatch = 456
    }
    proto = try request.toProto()
    #expect(proto.ifMetagenerationMatch == 123)
    #expect(proto.ifMetagenerationNotMatch == 456)

    roundtripped = try GetFolderRequest(proto: proto)
    #expect(roundtripped.ifMetagenerationMatch == 123)
    #expect(roundtripped.ifMetagenerationNotMatch == 456)
  }

  @Test func folderNestedMessageAndWkt() throws {
    let timestamp = try GoogleCloudWKT.Timestamp(seconds: 12345, nanos: 6789)

    // 1. Nested message and timestamps set
    let renameInfo = PendingRenameInfo().with {
      $0.operation = "op"
    }
    let folder = Folder().with {
      $0.name = "my-folder"
      $0.createTime = timestamp
      $0.pendingRenameInfo = renameInfo
    }

    let proto = try folder.toProto()
    #expect(proto.name == "my-folder")
    #expect(proto.hasCreateTime)
    #expect(proto.hasPendingRenameInfo)

    let roundtripped = try Folder(proto: proto)
    #expect(roundtripped.name == "my-folder")
    #expect(roundtripped.createTime == timestamp)
    #expect(roundtripped.pendingRenameInfo == renameInfo)

    // 2. Nested message and timestamps nil
    let folderNil = Folder().with {
      $0.name = "my-folder"
    }
    let protoNil = try folderNil.toProto()
    #expect(!protoNil.hasCreateTime)
    #expect(!protoNil.hasPendingRenameInfo)

    let roundtrippedNil = try Folder(proto: protoNil)
    #expect(roundtrippedNil.createTime == nil)
    #expect(roundtrippedNil.pendingRenameInfo == nil)
  }

  @Test func googleTypeInterval() throws {
    let startTime = try GoogleCloudWKT.Timestamp(seconds: 12345, nanos: 6789)
    let endTime = try GoogleCloudWKT.Timestamp(seconds: 18134, nanos: 6789)

    let interval = GoogleType.Interval().with {
      $0.startTime = startTime
      $0.endTime = endTime
    }

    let proto = try interval.toProto()
    #expect(proto.hasStartTime)
    #expect(proto.hasEndTime)
    #expect(proto.startTime.seconds == startTime.seconds)

    let roundtripped = try GoogleType.Interval(proto: proto)
    #expect(roundtripped.startTime == startTime)
    #expect(roundtripped.endTime == endTime)
  }

  @Test func intelligenceFindingRepeatedFields() throws {
    let bucketContribution1 = IntelligenceFinding.StorageGrowthAboveTrend.BucketContribution().with
    {
      $0.bucket = "projects/_/buckets/bucket-1"
      $0.totalStorageGrowthBytes = 1024
      $0.percentageIncrease = 15.5
    }
    let bucketContribution2 = IntelligenceFinding.StorageGrowthAboveTrend.BucketContribution().with
    {
      $0.bucket = "projects/_/buckets/bucket-2"
      $0.totalStorageGrowthBytes = 2048
      $0.percentageIncrease = 30.0
    }
    let growthTrend = IntelligenceFinding.StorageGrowthAboveTrend().with {
      $0.totalStorageGrowthBytes = 3072
      $0.percentageIncrease = 22.0
      $0.topBuckets = [bucketContribution1, bucketContribution2]
    }

    let finding = IntelligenceFinding().with {
      $0.name = "projects/my-project/locations/us-central1/findings/finding-1"
      $0.associatedResources = ["resource-a", "resource-b", "resource-c"]
    }

    // Test repeated primitive fields roundtrip
    let findingProto = try finding.toProto()
    #expect(findingProto.associatedResources == ["resource-a", "resource-b", "resource-c"])

    let roundtrippedFinding = try IntelligenceFinding(proto: findingProto)
    #expect(roundtrippedFinding.associatedResources == ["resource-a", "resource-b", "resource-c"])

    // Test repeated message fields roundtrip
    let growthProto = try growthTrend.toProto()
    #expect(growthProto.topBuckets.count == 2)
    #expect(growthProto.topBuckets[0].bucket == "projects/_/buckets/bucket-1")
    #expect(growthProto.topBuckets[1].bucket == "projects/_/buckets/bucket-2")

    let roundtrippedGrowth = try IntelligenceFinding.StorageGrowthAboveTrend(proto: growthProto)
    #expect(roundtrippedGrowth == growthTrend)
  }

  @Test func intelligenceFindingOneOfFields() throws {
    let growthTrend = IntelligenceFinding.StorageGrowthAboveTrend().with {
      $0.totalStorageGrowthBytes = 3072
      $0.percentageIncrease = 22.0
    }
    var finding = IntelligenceFinding().with {
      $0.name = "projects/my-project/locations/us-central1/findings/finding-oneof"
      $0.intelligenceFindingDetails = .storageGrowthAboveTrend(growthTrend)
    }

    // Verify top-level oneof roundtrip
    let findingProto = try finding.toProto()
    guard case .storageGrowthAboveTrend(let protoGrowth)? = findingProto.intelligenceFindingDetails
    else {
      Issue.record("Expected storageGrowthAboveTrend case in proto")
      return
    }
    #expect(protoGrowth.totalStorageGrowthBytes == 3072)

    let roundtrippedFinding = try IntelligenceFinding(proto: findingProto)
    #expect(roundtrippedFinding == finding)

    // Verify nested oneof in BucketContribution roundtrip
    let prefixContribution = IntelligenceFinding.ColdlineAndArchivalStorageOperationsSpike
      .BucketContribution.Contribution.PrefixContribution().with {
        $0.totalOperationsCount = 500
        $0.percentageIncrease = 10.0
        $0.prefix = "test/"
      }
    let contribution = IntelligenceFinding.ColdlineAndArchivalStorageOperationsSpike
      .BucketContribution.Contribution().with {
        $0.topPrefixes = [prefixContribution]
      }
    let bucketContribution = IntelligenceFinding.ColdlineAndArchivalStorageOperationsSpike
      .BucketContribution().with {
        $0.bucket = "projects/_/buckets/test-bucket"
        $0.details = .contribution(contribution)
      }

    let contributionProto = try bucketContribution.toProto()
    guard case .contribution(let protoContribution)? = contributionProto.details else {
      Issue.record("Expected contribution case in proto")
      return
    }
    #expect(protoContribution.topPrefixes[0].totalOperationsCount == 500)

    let roundtrippedContribution = try IntelligenceFinding.ColdlineAndArchivalStorageOperationsSpike
      .BucketContribution(proto: contributionProto)
    #expect(roundtrippedContribution == bucketContribution)

    // Verify mutual exclusion (setting one case replaces the previous case)
    let coldlineSpike = IntelligenceFinding.ColdlineAndArchivalStorageOperationsSpike().with {
      $0.totalOperationsCount = 1000
    }
    finding.intelligenceFindingDetails = .coldlineAndArchivalStorageOperationsSpike(coldlineSpike)
    let replacedProto = try finding.toProto()
    guard
      case .coldlineAndArchivalStorageOperationsSpike(let protoColdline)? = replacedProto
        .intelligenceFindingDetails
    else {
      Issue.record(
        "Expected coldlineAndArchivalStorageOperationsSpike case in proto after replacement")
      return
    }
    #expect(protoColdline.totalOperationsCount == 1000)

    let roundtrippedReplaced = try IntelligenceFinding(proto: replacedProto)
    #expect(roundtrippedReplaced == finding)
  }

  @Test func managedFolderMapFields() throws {
    let policy1 = ManagedFolder.RapidCacheConfig.RapidCachePolicy().with {
      $0.rapidCacheId = "cache-1"
      $0.ingestOnWrite = .enabled
    }
    let policy2 = ManagedFolder.RapidCacheConfig.RapidCachePolicy().with {
      $0.rapidCacheId = "cache-2"
      $0.ingestOnWrite = .unspecified
    }
    let rapidCacheConfig = ManagedFolder.RapidCacheConfig().with {
      $0.policies = [
        "policy-a": policy1,
        "policy-b": policy2,
      ]
    }

    let proto = try rapidCacheConfig.toProto()
    #expect(proto.policies.count == 2)
    #expect(proto.policies["policy-a"]?.rapidCacheID == "cache-1")
    #expect(proto.policies["policy-b"]?.rapidCacheID == "cache-2")

    let roundtripped = try ManagedFolder.RapidCacheConfig(proto: proto)
    #expect(roundtripped == rapidCacheConfig)
  }
}
