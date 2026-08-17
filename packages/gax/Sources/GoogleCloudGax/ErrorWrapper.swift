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
import struct AsyncHTTPClient.HTTPClientResponse
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
@_spi(GoogleCloudInternal) import GoogleCloudWkt
import GoogleRpc

/// The services send errors using this structure.
@_spi(GoogleCloudInternal) public struct _ErrorWrapper: Decodable {
  public init?(data: Data) {
    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    guard let w = try? decoder.decode(Self.self, from: data) else {
      return nil
    }
    self = w
  }

  let error: WrappedStatus

  struct WrappedStatus: Decodable {
    /// The HTTP status code.
    let code: Int32
    /// The gRPC status code in string form.
    let status: String?
    /// The error message, if any.
    let message: String
    /// The sequence of error details, wrapped as anys. May be empty or omitted.
    let details: [GoogleCloudWkt.`Any`]
  }
}

@_spi(GoogleCloudInternal) extension ServiceError {
  /// Create a a new `ServiceDetails`.
  public init(
    wrapper: _ErrorWrapper,
  ) {
    if let s = wrapper.error.status {
      self.code = GoogleRpc.Code.init(stringValue: s)
    } else {
      self.code = .unknown
    }
    self.message = wrapper.error.message
    self.details = wrapper.error.details.map { StatusDetail(from: $0) }
  }
}
