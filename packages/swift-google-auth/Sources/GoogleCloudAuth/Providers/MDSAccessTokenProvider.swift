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

struct MDSAccessTokenProvider: TokenProvider, Sendable {
  let endpoint: URL?
  let quotaProjectID: String?
  let scopes: [String]?
  let client: AuthHTTPClient
  let fromADC: Bool
  let retryConfiguration: RetryConfiguration?
  let environment: [String: String]

  static let defaultEndpoint = "http://metadata.google.internal"

  init(
    endpoint: URL? = nil,
    quotaProjectID: String? = nil,
    scopes: [String]? = nil,
    retryConfiguration: RetryConfiguration? = nil,
    client: AuthHTTPClient = AuthHTTPClient(),
    fromADC: Bool = false,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.endpoint = endpoint
    self.quotaProjectID = quotaProjectID
    self.scopes = scopes
    self.retryConfiguration = retryConfiguration
    self.client = client
    self.fromADC = fromADC
    self.environment = environment
  }

  static func isRetryable(_ error: Error) -> Bool {
    if let authError = error as? AuthHTTPError, let status = authError.statusCode {
      return status >= 500 || status == 429 || status == 408
    }
    return true
  }

  func fetchToken() async throws -> Token {
    let hostEnv = self.environment["GCE_METADATA_HOST"]

    let baseEndpoint: URL
    if let endpoint = self.endpoint {
      baseEndpoint = endpoint
    } else if let hostEnv = hostEnv, !hostEnv.isEmpty {
      let hostString = hostEnv.hasPrefix("http") ? hostEnv : "http://\(hostEnv)"
      baseEndpoint = URL(string: hostString)!
    } else {
      baseEndpoint = URL(string: Self.defaultEndpoint)!
    }

    var urlComponents = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false)!
    urlComponents.path = "/computeMetadata/v1/instance/service-accounts/default/token"

    if let scopes = self.scopes, !scopes.isEmpty {
      urlComponents.queryItems = [
        URLQueryItem(name: "scopes", value: scopes.joined(separator: ","))
      ]
    }

    guard let url = urlComponents.url else {
      throw URLError(.badURL)
    }

    let headers = ["Metadata-Flavor": "Google"]

    struct TokenResponse: Decodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }

    let fetchOperation: @Sendable () async throws -> Token = {
      let response: TokenResponse = try await self.client.get(url: url, headers: headers)
      let expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn))
      return Token(accessToken: response.accessToken, expirationDate: expiration)
    }

    do {
      if self.fromADC && hostEnv == nil {
        return try await fetchOperation()
      } else {
        return try await RetryEngine.retry(
          configuration: self.retryConfiguration ?? .defaultConfiguration,
          isRetryable: Self.isRetryable,
          operation: fetchOperation
        )
      }
    } catch {
      throw CredentialsError.cannotFetchToken(adc: self.fromADC, env: hostEnv, source: error)
    }
  }
}
