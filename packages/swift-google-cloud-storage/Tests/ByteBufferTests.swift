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
import GoogleCloudStorage
import NIOCore
import Testing

@Suite struct ByteBufferTests {
  @Test func initEmpty() {
    let empty = GoogleCloudStorage.ByteBuffer()
    #expect(empty.isEmpty)
    #expect(empty.count == 0)
    #expect(empty.byteArray.isEmpty)
    #expect(empty.data.isEmpty)
    #expect(empty.byteBuffer.readableBytes == 0)
  }

  @Test func initWithData() {
    let original = Data([0x01, 0x02, 0x03, 0x04])
    let storage = GoogleCloudStorage.ByteBuffer(original)
    #expect(!storage.isEmpty)
    #expect(storage.count == 4)
    #expect(storage.data == original)
    #expect(storage.byteArray == [0x01, 0x02, 0x03, 0x04])

    var buffer = storage.byteBuffer
    #expect(buffer.readableBytes == 4)
    #expect(buffer.readBytes(length: 4) == [0x01, 0x02, 0x03, 0x04])
  }

  @Test func initWithByteBuffer() {
    var buffer = ByteBufferAllocator().buffer(capacity: 8)
    buffer.writeBytes([0x0A, 0x0B, 0x0C, 0x0D])
    let storage = GoogleCloudStorage.ByteBuffer(buffer)
    #expect(!storage.isEmpty)
    #expect(storage.count == 4)
    #expect(storage.data == Data([0x0A, 0x0B, 0x0C, 0x0D]))
    #expect(storage.byteArray == [0x0A, 0x0B, 0x0C, 0x0D])
    #expect(storage.byteBuffer == buffer)
  }

  @Test func initWithByteArray() {
    let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
    let storage = GoogleCloudStorage.ByteBuffer(bytes)
    #expect(storage.count == 4)
    #expect(storage.byteArray == bytes)
    #expect(storage.data == Data(bytes))
  }

  @Test func initWithRawBufferPointer() {
    let bytes: [UInt8] = [10, 20, 30]
    bytes.withUnsafeBytes { rawBuffer in
      let storage = GoogleCloudStorage.ByteBuffer(rawBuffer)
      #expect(storage.count == 3)
      #expect(storage.byteArray == bytes)
    }
  }

  @Test func arrayLiteral() {
    let storage: GoogleCloudStorage.ByteBuffer = [1, 2, 3]
    #expect(storage.count == 3)
    #expect(storage.byteArray == [1, 2, 3])
  }

  @Test func withUnsafeBytes() throws {
    let expected: [UInt8] = [100, 101, 102]
    let dataStorage = GoogleCloudStorage.ByteBuffer(Data(expected))
    let dataResult = dataStorage.withUnsafeBytes { ptr in
      Array(ptr)
    }
    #expect(dataResult == expected)

    var buffer = ByteBufferAllocator().buffer(capacity: 3)
    buffer.writeBytes(expected)
    let bufferStorage = GoogleCloudStorage.ByteBuffer(buffer)
    let bufferResult = bufferStorage.withUnsafeBytes { ptr in
      Array(ptr)
    }
    #expect(bufferResult == expected)
  }

  @Test func collectionAccessWithDataOffset() {
    let baseData = Data([0, 1, 2, 3, 4, 5, 6, 7])
    let subData = baseData.subdata(in: 2..<6)  // contains [2, 3, 4, 5], startIndex may not be 0
    let storage = GoogleCloudStorage.ByteBuffer(subData)

    #expect(storage.count == 4)
    #expect(storage[0] == 2)
    #expect(storage[1] == 3)
    #expect(storage[2] == 4)
    #expect(storage[3] == 5)

    var collected: [UInt8] = []
    for byte in storage {
      collected.append(byte)
    }
    #expect(collected == [2, 3, 4, 5])
  }

  @Test func collectionAccessWithByteBufferOffset() {
    var buffer = ByteBufferAllocator().buffer(capacity: 16)
    buffer.writeBytes([99, 99, 10, 20, 30, 40])
    buffer.moveReaderIndex(forwardBy: 2)  // skip first 2 bytes

    let storage = GoogleCloudStorage.ByteBuffer(buffer)
    #expect(storage.count == 4)
    #expect(storage[0] == 10)
    #expect(storage[1] == 20)
    #expect(storage[2] == 30)
    #expect(storage[3] == 40)

    var collected: [UInt8] = []
    for byte in storage {
      collected.append(byte)
    }
    #expect(collected == [10, 20, 30, 40])
  }

  @Test func equalityAndHashing() {
    let bytes: [UInt8] = [1, 2, 3, 4, 5]
    let dataStorage = GoogleCloudStorage.ByteBuffer(Data(bytes))

    var buffer = ByteBufferAllocator().buffer(capacity: 5)
    buffer.writeBytes(bytes)
    let bufferStorage = GoogleCloudStorage.ByteBuffer(buffer)

    let arrayStorage = GoogleCloudStorage.ByteBuffer(bytes)
    let emptyStorage1 = GoogleCloudStorage.ByteBuffer()
    let emptyStorage2 = GoogleCloudStorage.ByteBuffer(Data())
    let differentStorage = GoogleCloudStorage.ByteBuffer([1, 2, 3, 4, 6])

    #expect(dataStorage == bufferStorage)
    #expect(dataStorage == arrayStorage)
    #expect(bufferStorage == arrayStorage)
    #expect(emptyStorage1 == emptyStorage2)
    #expect(dataStorage != differentStorage)
    #expect(dataStorage != emptyStorage1)

    var set = Set<GoogleCloudStorage.ByteBuffer>()
    set.insert(dataStorage)
    #expect(set.contains(bufferStorage))
    #expect(set.contains(arrayStorage))
    #expect(!set.contains(differentStorage))
    #expect(!set.contains(emptyStorage1))
  }

  @Test func description() {
    let dataStorage = GoogleCloudStorage.ByteBuffer(Data([1, 2, 3]))
    #expect(dataStorage.description == "3 bytes")
    #expect(dataStorage.debugDescription.contains("Data"))

    var buffer = ByteBufferAllocator().buffer(capacity: 2)
    buffer.writeBytes([1, 2])
    let bufferStorage = GoogleCloudStorage.ByteBuffer(buffer)
    #expect(bufferStorage.description == "2 bytes")
    #expect(bufferStorage.debugDescription.contains("NIOCore.ByteBuffer"))
  }
}
