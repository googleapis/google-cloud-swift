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

/// An authentication provider backed by a Google Cloud API key.
///
/// An [API Key](https://cloud.google.com/docs/authentication/api-keys-use) is an encrypted string used
/// to authenticate calls into Google Cloud APIs. Unlike user or service account credentials, API keys do
/// not identify a [principal](https://cloud.google.com/iam/docs/overview#principals); instead, they attribute
/// requests to a specific Google Cloud project for billing and quota purposes.
///
/// When using API keys in your application:
/// - Keep API keys secure during storage and transmission.
/// - The key is sent to the service using the `x-goog-api-key` HTTP request header.
/// - Note that only select Google Cloud APIs support API keys; many require full OAuth 2.0 credentials.
///   Consult the documentation for the specific API before using API keys.
struct ApiKeyCredentials: CredentialsProvider, Sendable, CustomDebugStringConvertible {
  private let apiKey: String

  /// Initializes credentials with the provided API key.
  ///
  /// - Parameter apiKey: The Google Cloud API key.
  init(apiKey: String) {
    self.apiKey = apiKey
  }

  // MARK: - CredentialsProvider

  func headers() async throws -> AuthHeaders {
    return [("x-goog-api-key", self.apiKey)]
  }

  // MARK: - CustomDebugStringConvertible

  var debugDescription: String {
    return "ApiKeyCredentials(apiKey: \"[redacted]\")"
  }
}
