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

// [START storage_generate_encryption_key]
import Foundation
import GoogleCloudStorage

public func generateEncryptionKey() throws -> CustomerEncryptionKeyOptions {
  // Generates a 256-bit (32-byte) AES encryption key and prints the base64 representation.
  //
  // This is included for demonstration purposes. You should generate your own key.
  // Please remember that encryption keys should be handled with a comprehensive security policy.
  var rng = SystemRandomNumberGenerator()
  let rawKeyBytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &rng) }
  let key = try CustomerEncryptionKeyOptions(keyBytes: rawKeyBytes)
  print("Sample encryption key: \(key.keyBase64)")
  return key
}
// [END storage_generate_encryption_key]
