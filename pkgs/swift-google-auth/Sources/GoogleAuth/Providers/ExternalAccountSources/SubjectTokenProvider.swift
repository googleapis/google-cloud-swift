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

/// A type that provides third-party subject tokens for Workload and Workforce Identity Federation.
///
/// A **subject token** is a security credential (such as an OpenID Connect (OIDC) JSON Web Token (JWT)
/// or SAML 2.0 assertion) issued by an external identity provider that asserts the identity of a workload,
/// application, or user.
///
/// In [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) and
/// [Workforce Identity Federation](https://cloud.google.com/iam/docs/workforce-identity-federation)
/// flows ([AIP-4117](https://google.aip.dev/auth/4117)), applications authenticate to Google Cloud by
/// exchanging this subject token for a short-lived Google Cloud access token via Google Cloud's
/// Security Token Service (STS) ([RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693)).
/// This eliminates the need for long-lived, sensitive service account private keys.
///
/// Conforming types must be `Sendable` and provide a thread-safe implementation of `subjectToken()`.
/// Implementations may retrieve tokens dynamically from external metadata services, local identity
/// daemons, mobile keychain APIs, or third-party SDKs (e.g. Apple Account, AWS STS, Azure AD, GitHub Actions).
///
/// See [AIP-4117: External Account Credentials](https://google.aip.dev/auth/4117) and
/// [RFC 8693: OAuth 2.0 Token Exchange](https://datatracker.ietf.org/doc/html/rfc8693).
public protocol SubjectTokenProvider: Sendable {
  /// Asynchronously retrieves a fresh third-party subject token from the provider.
  ///
  /// This method is called whenever the authentication client needs to exchange an external
  /// token for a Google Cloud access token (such as during initialization or before cached token expiry).
  ///
  /// Implementations should return a valid, unexpired token string (typically a JWT or ID token).
  /// After the authentication library obtains the subject token, it is sent to the Security Token Service
  /// endpoint and immediately discarded from memory once exchanged.
  ///
  /// - Returns: A valid, raw subject token string.
  /// - Throws: Any error preventing the retrieval of the subject token. If the thrown error indicates
  ///   a transient network failure, the SDK's retry engine will automatically retry the operation.
  func subjectToken() async throws -> String
}
