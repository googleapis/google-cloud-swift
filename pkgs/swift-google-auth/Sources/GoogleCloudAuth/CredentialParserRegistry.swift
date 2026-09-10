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

import Synchronization

internal protocol CredentialSourceParser: Sendable {
  static var type: String { get }
  init()
  func parse(
    config: [String: Any],
    quotaProjectID: String?,
    universeDomain: String?,
    scopes: [String],
    environment: [String: String]
  ) throws -> any CredentialsProvider
}

internal final class CredentialParserRegistry: Sendable {
  internal static let shared = CredentialParserRegistry()

  private let parsers = Mutex<[String: any CredentialSourceParser.Type]>([:])

  private init() {}

  internal func register(parser: any CredentialSourceParser.Type) {
    parsers.withLock { $0[parser.type] = parser }
  }

  internal func parse(
    type: String,
    config: [String: Any],
    quotaProjectID: String?,
    universeDomain: String?,
    scopes: [String],
    environment: [String: String]
  ) throws -> (any CredentialsProvider)? {
    return try parsers.withLock { parsers in
      guard let parserType = parsers[type] else { return nil }
      return try parserType.init().parse(
        config: config,
        quotaProjectID: quotaProjectID,
        universeDomain: universeDomain,
        scopes: scopes,
        environment: environment
      )
    }
  }
}
