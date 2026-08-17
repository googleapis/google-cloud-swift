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
private import ExtrasBase64

/// Helper functions to encode and decode using the base64url.
///
/// Discovery-based services use a URL and filename safe alphabet, as described in:
///   <https://developers.google.com/discovery/v1/type-format>
///   <https://datatracker.ietf.org/doc/html/rfc4648#section-5>
///
/// We use an external dependency because, on macOS < 26, Swift does not support url-safe encoding.
@_spi(GoogleCloudInternal) public enum _DiscoveryBase64 {
  /// Encodes `input` into a base64url string.
  public static func encode(_ input: Data) -> String {
    return String(
      base64Encoding: input.map { UInt8($0) }, options: [.base64UrlAlphabet, .omitPaddingCharacter])
  }

  /// Decodes `input` returning `nil` if the decoding fails.
  public static func decode(_ input: String) -> Data? {
    do {
      let bytes = try input.base64decoded(options: [.base64UrlAlphabet, .omitPaddingCharacter])
      return Data(bytes)
    } catch {
      return nil
    }
  }
}
