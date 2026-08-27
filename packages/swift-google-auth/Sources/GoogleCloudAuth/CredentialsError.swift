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
public enum CredentialsError: Error, Sendable {
  /// Indicates that the requested operation or credential type is not supported by the current backend.
  case notSupported(String)

  /// Indicates a failure while parsing or decoding configuration data (e.g., malformed JSON key).
  case parseError(String)

  /// Application Default Credentials (ADC) cannot retrieve an access token.
  ///
  /// ## Troubleshooting
  ///
  /// The credentials have been configured to retrieve access tokens from a metadata server but the
  /// token could not be retrieved. Sometimes the configuration is implicit: Application Default
  /// Credentials default to using a metadata service if no other source is found.
  ///
  /// In most Google Cloud environments (GCE, GKE, Cloud Run, etc.) the metadata service is always
  /// available and provides access tokens that, in effect, service as authentication credentials.
  ///
  /// There are basically four cases to consider:
  /// - `adc == true`, `env == nil`: the credentials were configured to use a default-initialized
  ///   ``CredentialsConfiguration``. The metadata server is just the fallback when no other
  ///   credentials are found. The `GCE_METADATA_HOST` environment is not set, so the library uses the
  ///   default metadata server endpoint (`http://metadata.google.internal`). The most common reason
  ///   for this problem is that the application is **not** running in a Google Cloud environment and
  ///   you have not configured local credentials for development and testing.
  /// - `adc == false`, `env == nil`: the credentials were configured to use the metadata server
  ///   explicitly. The GCE_METADATA_HOST environment is not set, so the library uses the default
  ///   metadata server endpoint (`http://metadata.google.internal`). The most common reason for this
  ///   problem is that the application is intended to run in a Google Cloud environment and you
  ///   attempted to run the application elsewhere. Rarely, your administrator has disabled the
  ///   metadata server. In this case consult with your system administrator about the recommended way
  ///   for applications to authenticate to Google Cloud.
  /// - `adc == true`, `env != nil`: the credentials were configured to use a default-initialized
  ///   ``CredentialsConfiguration``The metadata server is just the fallback when no other credentials
  ///   are found. The `GCE_METADATA_HOST` environment is set, the client library will try to use its
  ///   value as the metadata server endpoint. Most likely, you intended to run a test using a fake
  ///   metadata server and the fake is not running.
  /// - `adc == false`, `env != nil`: the credentials were configured to use the metadata server
  ///   explicitly. The `GCE_METADATA_HOST` environment is set, the client library will try to use its
  ///   value as the metadata server endpoint. Most likely, you intended to run a test using a fake
  ///   metadata server and the fake is not running.
  ///
  /// To setup local credentials, run `gcloud auth application-default login`. More information
  /// on how to authenticate client libraries can be found at
  /// https://cloud.google.com/docs/authentication/client-libraries
  ///
  case cannotFetchToken(adc: Bool, env: String?, source: any Error)
}

extension CredentialsError: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .notSupported(let detail):
      return "Operation not supported: \(detail)"
    case .parseError(let detail):
      return "Configuration parse error: \(detail)"
    case .cannotFetchToken(let adc, let env, let error):
      switch (adc, env) {
      case (true, nil):
        return
          """
          The credentials were configured to use `.adc()`, the default. The ADC (Application Default
          Credentials) discovery algorithm has fallen back on the metadata server, which indicates
          it could not find any other credentials.
          The GCE_METADATA_HOST environment variable is not set, therefore the library uses the
          default metadata server endpoint (\(MDSAccessTokenProvider.defaultEndpoint)).
          The most common reason for this problem is that the application is **not** running in a Google
          Cloud environment and you have not configured local credentials for development and testing.
          Underlying error: \(error)
          """
      case (false, nil):
        return
          """
          The credentials were configured to use `.mds()` that is,
          explicitly requested the metadata server.
          The GCE_METADATA_HOST environment variable is not set, therefore the library uses the
          default metadata server endpoint (\(MDSAccessTokenProvider.defaultEndpoint)).
          Verify the environment where the application is running has a metadata server.
          Underlying error: \(error)
          """
      case (true, let env):
        return
          """
          The credentials were configured to use `.adc()`, the default. The ADC (Application Default
          Credentials) discovery algorithm has fallen back on the metadata server, which indicates
          it could not find any other credentials.
          The GCE_METADATA_HOST environment variable is set to '\(env ?? "")', overriding the default.
          Verify the metadata service is running at that endpoint.
          Underlying error: \(error)
          """
      case (false, let env):
        return
          """
          The credentials were configured to use `.mds()` that is, explicitly requested the
          metadata server.
          The GCE_METADATA_HOST environment variable is set to '\(env ?? "")', overriding the default.
          Verify the metadata service is running at that endpoint.
          Underlying error: \(error)
          """
      }
    }
  }
}
