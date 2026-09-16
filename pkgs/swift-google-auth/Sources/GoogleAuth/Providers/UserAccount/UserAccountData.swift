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

/// Represents the raw `authorized_user` JSON credential file format.
///
/// An `authorized_user` credential represents a human developer or administrator who authenticated
/// locally using the Google Cloud CLI:
/// ```bash
/// gcloud auth application-default login
/// ```
///
/// User accounts are managed through [Google Accounts](https://myaccount.google.com/),
/// [Google Workspace](https://workspace.google.com/), or [Cloud Identity](https://cloud.google.com/identity).
/// Unlike service accounts, user accounts obtain short-lived access tokens by exchanging a long-lived
/// OAuth 2.0 refresh token using the [OAuth 2.0 Refresh Token grant](https://datatracker.ietf.org/doc/html/rfc6749#section-6).
///
/// - SeeAlso: [Google Cloud Authentication: User Accounts](https://cloud.google.com/docs/authentication#user-accounts)
/// - SeeAlso: [RFC 6749: OAuth 2.0 Authorization Framework](https://datatracker.ietf.org/doc/html/rfc6749)
struct UserAccountData: Sendable, Codable {
  /// The credential type identifier string, expected to be `"authorized_user"`.
  let type: String

  /// The OAuth 2.0 client ID registered in Google Cloud Console.
  let clientId: String

  /// The OAuth 2.0 client secret corresponding to `clientId`.
  let clientSecret: String

  /// The long-lived OAuth 2.0 refresh token used to obtain short-lived access tokens.
  let refreshToken: String

  /// The optional OAuth 2.0 token endpoint URL used to exchange the refresh token.
  ///
  /// Defaults to `https://oauth2.googleapis.com/token` when not specified in the credentials file.
  let tokenUri: String?

  /// The optional Google Cloud project ID to which API requests using these credentials
  /// are attributed for quota and billing purposes.
  ///
  /// - SeeAlso: [Google Cloud Quota Project](https://cloud.google.com/docs/quotas/quota-project)
  let quotaProjectId: String?

  /// Initializes a new `UserAccountData` instance with the specified parameters.
  ///
  /// - Parameters:
  ///   - type: Credential type string (typically `"authorized_user"`).
  ///   - clientId: OAuth 2.0 client ID.
  ///   - clientSecret: OAuth 2.0 client secret.
  ///   - refreshToken: OAuth 2.0 refresh token.
  ///   - tokenUri: Optional token endpoint URI.
  ///   - quotaProjectId: Optional quota project ID.
  init(
    type: String,
    clientId: String,
    clientSecret: String,
    refreshToken: String,
    tokenUri: String? = nil,
    quotaProjectId: String? = nil
  ) {
    self.type = type
    self.clientId = clientId
    self.clientSecret = clientSecret
    self.refreshToken = refreshToken
    self.tokenUri = tokenUri
    self.quotaProjectId = quotaProjectId
  }
}
