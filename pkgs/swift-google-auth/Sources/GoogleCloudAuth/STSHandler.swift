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

/// Encapsulates the request parameters required for exchanging an external token
/// with Google Cloud's Secure Token Service (STS) according to [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693)
/// and [AIP-4117](https://google.aip.dev/auth/4117).
struct ExchangeTokenRequest: Sendable {
  /// The raw subject token issued by the external identity provider (e.g. an OIDC JWT).
  let subjectToken: String
  /// The type of the subject token (e.g., `urn:ietf:params:oauth:token-type:id_token` or `urn:ietf:params:oauth:token-type:jwt`).
  let subjectTokenType: String
  /// The target audience URI for the exchanged token (e.g. workforce or workload pool provider URI).
  let audience: String?
  /// The OAuth scopes requested for the exchanged token.
  let scopes: [String]
  /// The user project used for workforce pool billing and quota attribution (`x-goog-user-project`).
  let workforcePoolUserProject: String?
  /// Optional client authentication credentials when exchanging client-authenticated tokens via Basic Auth.
  let clientAuthentication: ClientAuthentication?

  init(
    subjectToken: String,
    subjectTokenType: String,
    audience: String? = nil,
    scopes: [String] = [],
    workforcePoolUserProject: String? = nil,
    clientAuthentication: ClientAuthentication? = nil
  ) {
    self.subjectToken = subjectToken
    self.subjectTokenType = subjectTokenType
    self.audience = audience
    self.scopes = scopes
    self.workforcePoolUserProject = workforcePoolUserProject
    self.clientAuthentication = clientAuthentication
  }
}

/// Represents OAuth client credentials used to authenticate token exchange requests via HTTP Basic Auth.
struct ClientAuthentication: Sendable {
  /// The OAuth client ID.
  let id: String
  /// The OAuth client secret.
  let secret: String?

  init(id: String, secret: String? = nil) {
    self.id = id
    self.secret = secret
  }
}

/// The response payload returned by Google Cloud's Secure Token Service (STS) following a token exchange.
struct TokenResponse: Codable, Sendable {
  /// The exchanged Google Cloud access token.
  let accessToken: String
  /// The type of the access token (typically `Bearer`).
  let tokenType: String
  /// The lifetime of the access token in seconds (typically 3600 seconds).
  let expiresIn: Int
  /// The type of the issued token (e.g. `urn:ietf:params:oauth:token-type:access_token`).
  let issuedTokenType: String?
  /// Recommended time to refresh the token before expiration, in seconds.
  let refreshBy: Int?
}

/// Specifies the serialization format used for the Security Token Service token exchange request body.
enum STSBodyEncoding: Sendable {
  /// Form-urlencoded request body (`application/x-www-form-urlencoded`), standard for RFC 8693 token exchange.
  case urlEncoded
  /// JSON request body (`application/json`).
  case json

  /// Encodes parameters into the request body data and corresponding content type header value.
  func encode(_ params: [String: String]) throws -> (body: Data, contentType: String) {
    switch self {
    case .json:
      let bodyData = try JSONEncoder().encode(params)
      return (bodyData, "application/json")
    case .urlEncoded:
      let formString = try params.map { key, value in
        guard
          let encodedValue = value.addingPercentEncoding(
            withAllowedCharacters: .rfc3986Allowed
          )
        else {
          throw CredentialsError.parseError(
            "Failed to percent-encode parameter value for key: \(key)"
          )
        }
        return "\(key)=\(encodedValue)"
      }.sorted().joined(separator: "&")
      return (Data(formString.utf8), "application/x-www-form-urlencoded")
    }
  }
}

/// Performs token exchange requests against Google's Secure Token Service (STS) ([RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693)).
struct STSHandler: Sendable {
  private let httpClient: AuthHTTPClient

  /// Initializes the handler with an HTTP client.
  ///
  /// - Parameter httpClient: The `AuthHTTPClient` used to execute requests.
  init(httpClient: AuthHTTPClient) {
    self.httpClient = httpClient
  }

  /// Exchanges an external identity provider token for a Google Cloud access token.
  ///
  /// Sends a token exchange request (`grant_type=urn:ietf:params:oauth:grant-type:token-exchange`)
  /// to the STS endpoint, returning the exchanged access token and expiration.
  ///
  /// - Parameters:
  ///   - request: The exchange request parameters.
  ///   - url: The STS endpoint URL (typically `https://sts.googleapis.com/v1/token`).
  ///   - encoding: The request body serialization format (default `.urlEncoded`).
  /// - Returns: A `TokenResponse` containing the exchanged access token.
  func exchangeToken(
    request: ExchangeTokenRequest,
    url: URL,
    encoding: STSBodyEncoding = .urlEncoded
  ) async throws -> TokenResponse {
    var params = [
      "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
      "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
      "subject_token": request.subjectToken,
      "subject_token_type": request.subjectTokenType,
    ]

    if !request.scopes.isEmpty {
      params["scope"] = request.scopes.joined(separator: " ")
    }
    if let audience = request.audience {
      params["audience"] = audience
    }

    var headers: [String: String] = [:]

    // Handle Client Authentication (Basic Auth if credentials exist)
    if let clientAuth = request.clientAuthentication {
      let credentialsString = "\(clientAuth.id):\(clientAuth.secret ?? "")"
      if let credentialsData = credentialsString.data(using: .utf8) {
        let base64Credentials = credentialsData.base64EncodedString()
        headers["Authorization"] = "Basic \(base64Credentials)"
      }
    }

    // Workforce pool user project options serialization.
    // The "options" string is a serialized JSON string. It remains a nested,
    // escaped JSON string even when the outer request body is encoded as JSON.
    // E.g., for userProject "my-project", the serialized value is "{\"userProject\":\"my-project\"}".
    if request.clientAuthentication == nil,
      let project = request.workforcePoolUserProject
    {
      let optionsDict = ["userProject": project]
      if let optionsData = try? JSONEncoder().encode(optionsDict),
        let optionsString = String(data: optionsData, encoding: .utf8)
      {
        params["options"] = optionsString
      }
    }

    let (bodyData, contentType) = try encoding.encode(params)

    return try await httpClient.postData(
      url: url,
      bodyData: bodyData,
      contentType: contentType,
      headers: headers
    )
  }
}

extension CharacterSet {
  static let rfc3986Allowed: CharacterSet = {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return allowed
  }()
}
