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

/// Creates credentials backed by an API key.
///
/// An API key is a simple encrypted string that you can use when calling Google Cloud APIs. When you use API keys in
/// your applications, ensure that they are kept secure during both storage and transmission.
///
/// API keys associate the request with a Google Cloud project for billing and quota purposes. Note that only some
/// Cloud APIs support API keys. Consult the documentation of the API you intend to use before attempting to use
/// API keys with it.
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

  func universeDomain() async -> String? {
    return nil
  }

  // MARK: - CustomDebugStringConvertible

  var debugDescription: String {
    return "ApiKeyCredentials(apiKey: \"[redacted]\")"
  }
}
