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

import Crypto
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import GoogleCloudGax
@testable import GoogleCloudStorage
import Testing

@Suite struct CustomerEncryptionKeyOptionsTests {
  /// Helper to create a sample 32-byte key and its expected Base64 and SHA-256 Base64 values.
  private func sampleKey() -> (data: Data, keyBase64: String, keyHashBase64: String) {
    let keyData = Data(repeating: 0x42, count: 32)
    let keyBase64 = keyData.base64EncodedString()
    let sha256Digest = SHA256.hash(data: keyData)
    let keyHashBase64 = Data(sha256Digest).base64EncodedString()
    return (keyData, keyBase64, keyHashBase64)
  }

  @Test func createFromData() throws {
    let sample = sampleKey()
    let csek = try CustomerEncryptionKeyOptions(key: sample.data)

    #expect(csek.algorithm == .aes256)
    #expect(csek.keyBase64 == sample.keyBase64)
    #expect(csek.keyHashBase64 == sample.keyHashBase64)
    let expectedDescription =
      "CustomerEncryptionKeyOptions(algorithm: AES256, keyHashBase64: \(sample.keyHashBase64))"
    #expect(csek.description == expectedDescription)
    #expect(csek.debugDescription == expectedDescription)
    #expect(!csek.description.contains(sample.keyBase64))
  }

  @Test func createFromByteArray() throws {
    let sample = sampleKey()
    let bytes = Array(sample.data)
    let csek = try CustomerEncryptionKeyOptions(keyBytes: bytes)

    #expect(csek.algorithm == .aes256)
    #expect(csek.keyBase64 == sample.keyBase64)
    #expect(csek.keyHashBase64 == sample.keyHashBase64)
  }

  @Test func createFromSymmetricKey() throws {
    let sample = sampleKey()
    let symKey = SymmetricKey(data: sample.data)
    let csek = try CustomerEncryptionKeyOptions(symmetricKey: symKey)

    #expect(csek.algorithm == .aes256)
    #expect(csek.keyBase64 == sample.keyBase64)
    #expect(csek.keyHashBase64 == sample.keyHashBase64)
  }

  @Test func createFromBase64String() throws {
    let sample = sampleKey()
    let csek = try CustomerEncryptionKeyOptions(keyBase64: sample.keyBase64)

    #expect(csek.algorithm == .aes256)
    #expect(csek.keyBase64 == sample.keyBase64)
    #expect(csek.keyHashBase64 == sample.keyHashBase64)
  }

  @Test func createFromPrecomputedValues() {
    let sample = sampleKey()
    let csek = CustomerEncryptionKeyOptions(
      algorithm: .aes256,
      keyBase64: sample.keyBase64,
      keyHashBase64: sample.keyHashBase64
    )
    #expect(csek.algorithm == .aes256)
    #expect(csek.keyBase64 == sample.keyBase64)
    #expect(csek.keyHashBase64 == sample.keyHashBase64)
  }

  @Test func invalidKeyLengthThrows() {
    let shortKey = Data(repeating: 0x01, count: 16)
    #expect(throws: CustomerEncryptionKeyError.invalidKeyLength(actual: 16, expected: 32)) {
      try CustomerEncryptionKeyOptions(key: shortKey)
    }

    let longKey = Data(repeating: 0x01, count: 33)
    #expect(throws: CustomerEncryptionKeyError.invalidKeyLength(actual: 33, expected: 32)) {
      try CustomerEncryptionKeyOptions(key: longKey)
    }
  }

  @Test func invalidBase64StringThrows() {
    #expect(throws: CustomerEncryptionKeyError.invalidBase64Key) {
      try CustomerEncryptionKeyOptions(keyBase64: "not-valid-base64!@#$")
    }
  }

  @Test func equatable() throws {
    let sample = sampleKey()
    let key1 = try CustomerEncryptionKeyOptions(key: sample.data)
    let key2 = try CustomerEncryptionKeyOptions(keyBase64: sample.keyBase64)
    #expect(key1 == key2)
  }
}
