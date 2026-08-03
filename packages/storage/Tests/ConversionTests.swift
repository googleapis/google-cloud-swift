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
import GoogleCloudWkt
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
    let timestamp = try GoogleCloudWkt.Timestamp(seconds: 12345, nanos: 6789)

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
    let startTime = try GoogleCloudWkt.Timestamp(seconds: 12345, nanos: 6789)
    let endTime = try GoogleCloudWkt.Timestamp(seconds: 18134, nanos: 6789)

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
}
