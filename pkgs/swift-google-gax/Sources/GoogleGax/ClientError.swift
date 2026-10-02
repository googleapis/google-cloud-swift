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

public import Foundation

/// Represents an error while trying to initialize a client.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum ClientError: Error, Sendable {
  /// The endpoint string does not represent a valid URL.
  ///
  /// ## Troubleshooting
  ///
  /// The most common cause for this error is an invalid value in the `endpoint` client
  /// option.
  ///
  /// Review the configuration for your client.
  case invalidEndpoint(String)
}

extension ClientError: Equatable {}

extension ClientError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidEndpoint(let endpoint):
      return "Invalid endpoint: \(endpoint)"
    }
  }
}

extension ClientError: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .invalidEndpoint(let endpoint):
      return "ClientError.invalidEndpoint(\(String(reflecting: endpoint)))"
    }
  }
}

extension ClientError: LocalizedError {
  public var errorDescription: String? {
    description
  }

  public var failureReason: String? {
    switch self {
    case .invalidEndpoint:
      return "The endpoint string does not represent a valid URL."
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .invalidEndpoint:
      return "Review the endpoint client option and ensure it is a valid URL."
    }
  }
}
