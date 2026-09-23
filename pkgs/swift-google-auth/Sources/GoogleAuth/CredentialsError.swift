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

/// Represents any error occurring during credentials resolution or initialization.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum CredentialsError: Error, Sendable {
  /// Indicates that the requested operation or credential type is not supported by the current backend.
  ///
  /// Examples include attempting to use Authorized User credentials in a custom universe domain
  /// (user accounts are only supported in the default `googleapis.com` universe), requesting unsupported
  /// external credential source types, or attempting to use service account impersonation before backend support is enabled.
  case notSupported(String)

  /// Indicates a failure while parsing, decoding, or validating configuration data.
  ///
  /// Examples include malformed Service Account or Authorized User JSON key files, missing required fields
  /// (such as `client_email` or `private_key`), invalid RSA private key PEM formatting, or invalid STS response payloads.
  case parseError(String)

  /// The credentials could not obtain an access token.
  ///
  /// ## Troubleshooting
  ///
  /// The `message` value explains how the credentials were configured and what to verify next. The
  /// `source` value is the underlying failure, such as a transport error or an unsuccessful
  /// response from the token endpoint.
  ///
  /// Credentials may be configured to use a metadata server implicitly: Application Default
  /// Credentials fall back to the metadata server when no other credentials are found. In most
  /// Google Cloud environments (GCE, GKE, Cloud Run) the metadata server is always available and
  /// issues the access tokens that authenticate the workload. Outside those environments, the
  /// fallback fails.
  ///
  /// To set up local credentials, run `gcloud auth application-default login`. More information
  /// on how to authenticate client libraries can be found at
  /// https://cloud.google.com/docs/authentication/client-libraries
  ///
  /// - Important: The `message` wording is intended for humans and may change between releases.
  ///   Do not parse it or branch on its contents.
  case cannotFetchToken(message: String, source: any Error)
}

extension CredentialsError: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .notSupported(let detail):
      return "Operation not supported: \(detail)"
    case .parseError(let detail):
      return "Configuration parse error: \(detail)"
    case .cannotFetchToken(let message, let error):
      return
        """
        \(message)
        Underlying error: \(error)
        """
    }
  }
}
