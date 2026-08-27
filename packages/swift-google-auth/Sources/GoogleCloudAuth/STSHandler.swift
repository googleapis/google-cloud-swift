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
/// with Google Cloud's Secure Token Service (STS).
struct ExchangeTokenRequest: Sendable {
  /// The raw subject token issued by the external identity provider.
  let subjectToken: String
  /// The type of the subject token (e.g., `urn:ietf:params:oauth:token-type:id_token`).
  let subjectTokenType: String
  /// The target audience for the exchanged token.
  let audience: String?
  /// The OAuth scopes requested for the exchanged token.
  let scopes: [String]
  /// The user project used for workforce pool billing/quota attribution.
  let workforcePoolUserProject: String?
  /// Optional basic authentication credentials when exchanging client-authenticated tokens.
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

/// Represents the client credentials used to authenticate token exchange requests.
struct ClientAuthentication: Sendable {
  /// The client ID.
  let id: String
  /// The client secret.
  let secret: String?

  init(id: String, secret: String? = nil) {
    self.id = id
    self.secret = secret
  }
}

/// The response payload returned by Google Cloud's Secure Token Service.
struct TokenResponse: Codable, Sendable {
  /// The exchanged access token.
  let accessToken: String
  /// The type of the access token (typically `Bearer`).
  let tokenType: String
  /// The lifetime of the access token in seconds.
  let expiresIn: Int
  /// The type of the issued token.
  let issuedTokenType: String?
  /// Recommended time to refresh the token, in seconds.
  let refreshBy: Int?
}

/// Specifies the format used to serialize the token exchange request body.
enum STSBodyEncoding: Sendable {
  /// Form-urlencoded request body (standard STS).
  case urlEncoded
  /// JSON request body.
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

/// Performs token exchange requests against Google's Secure Token Service (STS).
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
  /// - Parameters:
  ///   - request: The exchange request parameters.
  ///   - url: The STS endpoint URL.
  ///   - encoding: The request body serialization format.
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
