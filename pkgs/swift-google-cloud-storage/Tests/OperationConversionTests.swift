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

import GoogleGax
import GoogleLongRunning
import StorageControlProtos
import SwiftProtobuf
import Testing

@testable import GoogleCloudStorage

@Suite struct OperationConversionTests {
  // Builds the `Operation` the service returns for a completed `renameFolder()`.
  private func renameFolderOperation() throws
    -> StorageControlProtos.Google_Longrunning_Operation
  {
    var metadata = StorageControlProtos.Google_Storage_Control_V2_RenameFolderMetadata()
    metadata.sourceFolderID = "example-folder-id/"
    metadata.destinationFolderID = "renamed-folder-id/"

    var folder = StorageControlProtos.Google_Storage_Control_V2_Folder()
    folder.name = "projects/_/buckets/test-bucket/folders/renamed-folder-id/"
    folder.metageneration = 1

    var operation = StorageControlProtos.Google_Longrunning_Operation()
    operation.name = "projects/_/buckets/test-bucket/operations/test-operation"
    operation.metadata = try .init(message: metadata)
    operation.done = true
    operation.response = try .init(message: folder)
    return operation
  }

  // An `Any` built in this process holds its payload as a message.
  @Test func operationConvertsWhenAnyHoldsAMessage() throws {
    let operation = try renameFolderOperation()

    let native = try GoogleLongRunning.Operation(proto: operation)

    #expect(native.name == operation.name)
    let metadata = try RenameFolderMetadata(fromAny: #require(native.metadata))
    #expect(metadata.destinationFolderId == "renamed-folder-id/")
  }

  // An `Any` parsed from the wire holds its payload as bytes, so converting it
  // means decoding the payload from its type URL. This is the case that failed
  // before the generated converter existed, because the only way to resolve a
  // type URL was SwiftProtobuf's global type registry, which nothing populates.
  @Test func operationConvertsWhenAnyArrivesFromTheWire() throws {
    let sent = try renameFolderOperation()
    let bytes: [UInt8] = try sent.serializedBytes()
    let received = try StorageControlProtos.Google_Longrunning_Operation(serializedBytes: bytes)

    let native = try GoogleLongRunning.Operation(proto: received)

    #expect(native.name == sent.name)
    let metadata = try RenameFolderMetadata(fromAny: #require(native.metadata))
    #expect(metadata.destinationFolderId == "renamed-folder-id/")
  }

  // A payload that serializes to zero bytes decodes to a default-initialized
  // message, so an operation carrying one round-trips to its native form.
  @Test func operationConvertsWhenAnyPayloadIsEmpty() throws {
    var sent = StorageControlProtos.Google_Longrunning_Operation()
    sent.name = "projects/_/buckets/test-bucket/operations/test-operation"
    sent.metadata = try .init(
      message: StorageControlProtos.Google_Storage_Control_V2_RenameFolderMetadata())
    sent.done = true

    let bytes: [UInt8] = try sent.serializedBytes()
    let received = try StorageControlProtos.Google_Longrunning_Operation(serializedBytes: bytes)

    let native = try GoogleLongRunning.Operation(proto: received)

    #expect(native.name == sent.name)
    let metadata = try RenameFolderMetadata(fromAny: #require(native.metadata))
    #expect(metadata.destinationFolderId == "")
  }

  // Converting an operation back to its Protobuf form takes the same route in
  // reverse, so the payload survives a round trip.
  @Test func operationRoundTrips() throws {
    let sent = try renameFolderOperation()
    let bytes: [UInt8] = try sent.serializedBytes()
    let received = try StorageControlProtos.Google_Longrunning_Operation(serializedBytes: bytes)

    let native = try GoogleLongRunning.Operation(proto: received)
    let proto = try native.toProto()

    #expect(proto.name == sent.name)
    let folder = try StorageControlProtos.Google_Storage_Control_V2_Folder(
      serializedBytes: proto.response.value)
    #expect(folder.name == "projects/_/buckets/test-bucket/folders/renamed-folder-id/")
  }

  // A payload the converter cannot decode is reported, and the error names the
  // type URL. Asserting the converter's own error matters: the generic
  // fallback fails with SwiftProtobuf's `anyTranscodeFailure`, which names
  // nothing useful.
  @Test func operationRejectsUnknownTypeUrl() throws {
    // A payload under a type URL this client does not know, which is what
    // version skew looks like on the wire. It has to be non-empty: with
    // nothing to decode the conversion succeeds instead, as the test below
    // shows. The contents are never read — resolving the type URL fails first.
    var payload = StorageControlProtos.Google_Storage_Control_V2_Folder()
    payload.name = "projects/_/buckets/test-bucket/folders/renamed-folder-id/"

    var sent = StorageControlProtos.Google_Longrunning_Operation()
    sent.name = "projects/_/buckets/test-bucket/operations/test-operation"
    sent.metadata.typeURL = "type.googleapis.com/google.storage.control.v2.NotAThing"
    sent.metadata.value = try payload.serializedBytes()

    #expect(
      throws: ProtobufConversionError.unknownTypeUrl(
        typeUrl: "type.googleapis.com/google.storage.control.v2.NotAThing")
    ) {
      try GoogleLongRunning.Operation(proto: sent)
    }
  }

  // An unknown type URL with an empty payload has nothing to decode, so the
  // generic fallback keeps it as an opaque `Any` rather than failing the whole
  // response over a field the caller may not even read.
  @Test func operationConvertsWhenUnknownTypeUrlHasEmptyPayload() throws {
    let typeUrl = "type.googleapis.com/google.storage.control.v2.NotAThing"
    var sent = StorageControlProtos.Google_Longrunning_Operation()
    sent.name = "projects/_/buckets/test-bucket/operations/test-operation"
    sent.metadata.typeURL = typeUrl

    let native = try GoogleLongRunning.Operation(proto: sent)

    #expect(try #require(native.metadata).typeUrl == typeUrl)
  }

  // An `Any` with no type URL has nothing to resolve, and `GoogleWKT.WKTAny`
  // has no empty representation to map it to, so it is reported too. The Rust
  // codec maps this case to a default `Any`; Swift deliberately does not.
  @Test func operationRejectsAnyWithNoTypeUrl() throws {
    var sent = StorageControlProtos.Google_Longrunning_Operation()
    sent.name = "projects/_/buckets/test-bucket/operations/test-operation"
    sent.metadata = SwiftProtobuf.Google_Protobuf_Any()

    #expect(throws: ProtobufConversionError.unknownTypeUrl(typeUrl: "")) {
      try GoogleLongRunning.Operation(proto: sent)
    }
  }
}
