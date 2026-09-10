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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension URLRequest {
  /// Resolves the raw body payload data from either `httpBody` or `httpBodyStream`.
  /// Used to ensure portability of request assertions across platforms (macOS/Linux).
  var bodyData: Data? {
    if let httpBody = httpBody {
      return httpBody
    }
    guard let stream = httpBodyStream else {
      return nil
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while true {
      let read = stream.read(buffer, maxLength: bufferSize)
      if read > 0 {
        data.append(buffer, count: read)
      } else {
        break
      }
    }
    return data
  }
}
