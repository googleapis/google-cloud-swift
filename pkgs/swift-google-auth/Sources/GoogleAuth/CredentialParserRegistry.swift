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
import Synchronization

/// Parses a specific credential JSON format (identified by `type`) into a `CredentialsProvider`.
///
/// Conforming parsers receive the raw JSON `Data` read from the ADC file and decode their own
/// strongly-typed `Decodable` configuration models directly.
internal protocol CredentialSourceParser: Sendable {
  /// The `"type"` discriminator value in the credential JSON file (e.g., `"service_account"`).
  static var type: String { get }
  init()
  /// Parses raw credential JSON `Data` into a configured `CredentialsProvider`.
  func parse(
    data: Data,
    quotaProjectID: String?,
    universeDomain: String?,
    scopes: [String],
    environment: [String: String]
  ) throws -> any CredentialsProvider
}

/// A thread-safe registry mapping credential `"type"` identifiers to their `CredentialSourceParser` implementations.
internal final class CredentialParserRegistry: Sendable {
  internal static let shared = CredentialParserRegistry()

  private let parsers = Mutex<[String: any CredentialSourceParser.Type]>([:])

  private init() {}

  internal func register(parser: any CredentialSourceParser.Type) {
    parsers.withLock { $0[parser.type] = parser }
  }

  /// Dispatches the raw credential JSON `Data` to the parser registered for `type`,
  /// or returns `nil` if no parser is registered for that type.
  internal func parse(
    type: String,
    data: Data,
    quotaProjectID: String?,
    universeDomain: String?,
    scopes: [String],
    environment: [String: String]
  ) throws -> (any CredentialsProvider)? {
    return try parsers.withLock { parsers in
      guard let parserType = parsers[type] else { return nil }
      return try parserType.init().parse(
        data: data,
        quotaProjectID: quotaProjectID,
        universeDomain: universeDomain,
        scopes: scopes,
        environment: environment
      )
    }
  }
}
