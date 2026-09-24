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

/// A type conforming to the `_AnyPackable` protocol can be packed into and unpacked from ``WKTAny``.
///
/// This protocol is an implementation detail of the Google Cloud client libraries for Swift.
/// Do not use it directly.
///
/// For `google-cloud-swift` developers: while it would be desirable to make this type `@_spi()` we
/// cannot because then normal types like ``WKTApi`` cannot use it.
public protocol _AnyPackable: Sendable {
  static var _anyTypeUrl: String { get }
  init(fromAny any: WKTAny) throws
  func _pack() throws -> WKTStruct
}

// Deserializes a message of type `M` from a `WKTAny`.
@_spi(GoogleCloudInternal)
public func _slowAnyDeserialize<M: Decodable & _AnyPackable>(
  _ type: M.Type, from: WKTAny
) throws -> M {
  if M._anyTypeUrl != from._type {
    throw WKTAnyError.mismatchedTypeUrl
  }
  let encoder = _ProtoJSONEncoder()
  let data = try encoder.encode(from.fields)
  let decoder = _ProtoJSONDecoder()
  return try decoder.decode(M.self, from: data)
}

// Serializes a message of type `M` into a `WKTAny`.
@_spi(GoogleCloudInternal)
public func _slowAnySerialize<M: Encodable>(message: M) throws -> WKTStruct {
  let encoder = _ProtoJSONEncoder()
  let data = try encoder.encode(message)
  let decoder = _ProtoJSONDecoder()
  return try decoder.decode(WKTStruct.self, from: data)
}
