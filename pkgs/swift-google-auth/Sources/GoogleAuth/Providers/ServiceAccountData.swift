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

/// Represents the parsed contents of a Google Cloud Service Account JSON key file.
///
/// A [Service Account](https://cloud.google.com/iam/docs/service-account-overview) key file contains
/// cryptographic identity material including the service account's client email and RSA private key.
struct ServiceAccountData: Decodable, Sendable {
  /// The service account email address (e.g. `service-account@project.iam.gserviceaccount.com`).
  let clientEmail: String
  /// The unique identifier of the private key.
  let privateKeyID: String
  /// The PKCS#8 or PKCS#1 PEM-encoded RSA private key.
  let privateKey: String
  /// The Google Cloud project ID associated with the service account.
  let projectID: String
  /// An optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  let quotaProjectID: String?
  /// An optional universe domain override (defaults to `googleapis.com` if nil).
  let universeDomain: String?

  enum CodingKeys: String, CodingKey {
    case clientEmail = "client_email"
    case privateKeyID = "private_key_id"
    case privateKey = "private_key"
    case projectID = "project_id"
    case quotaProjectID = "quota_project_id"
    case universeDomain = "universe_domain"
  }
}

extension ServiceAccountData: CustomStringConvertible, CustomDebugStringConvertible {
  var description: String {
    debugDescription
  }

  var debugDescription: String {
    let quotaDescription = quotaProjectID.map(String.init(reflecting:)) ?? "nil"
    let universeDescription = universeDomain.map(String.init(reflecting:)) ?? "nil"
    return
      "ServiceAccountData(clientEmail: \(String(reflecting: clientEmail)), privateKeyID: \(String(reflecting: privateKeyID)), privateKey: \"[censored]\", projectID: \(String(reflecting: projectID)), quotaProjectID: \(quotaDescription), universeDomain: \(universeDescription))"
  }
}
