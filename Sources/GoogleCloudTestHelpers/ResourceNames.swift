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

/// The environment variable used to get the GOOGLE_CLOUD_PROJECT
fileprivate let googleCloudProject = "GOOGLE_CLOUD_PROJECT"
/// The environment variable used to get the GOOGLE_CLOUD_PROJECT
fileprivate let serviceAccountVar = "GOOGLE_CLOUD_SWIFT_TEST_SERVICE_ACCOUNT"
/// The environment variable to set the default location
fileprivate let locationVar = "GOOGLE_CLOUD_LOCATION"
fileprivate let defaultLocation = "us-central1"

/// The maximum length for a secret ID.
fileprivate let secretIdLength = 64

/// The maximum length for a VM ID.
fileprivate let vmIdLength = 63

/// A common prefix for resource ids.
///
/// Where possible, we use this prefix for randomly generated resource ids.
fileprivate let prefix = "swift-sdk-testing-"

fileprivate let alphanumeric = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
fileprivate let lowerCaseAlphanumeric = "abcdefghijklmnopqrstuvwxyz0123456789"

/// Fetches the project id to use in the tests.
///
/// - Throws: a `ResourceNameError` if the project id is not set.
public func projectId() throws -> String {
  guard let id = ProcessInfo.processInfo.environment[googleCloudProject] else {
    throw ResourceNameError.unsetEnvironmentVariable(googleCloudProject)
  }
  return id
}

/// Fetches the location to use in the tests. Defaults to `us-central1`.
public func locationId() -> String {
  guard let id = ProcessInfo.processInfo.environment[locationVar] else {
    return defaultLocation
  }
  return id
}

/// Fetches the test service account to use in the tests.
///
/// - Throws: a `ResourceNameError` if the project id is not set.
public func testServiceAccount() throws -> String {
  guard let account = ProcessInfo.processInfo.environment[serviceAccountVar] else {
    throw ResourceNameError.unsetEnvironmentVariable(serviceAccountVar)
  }
  return account
}

/// Generates a random secret ID.
public func randomSecretId() -> String {
  assert(prefix.count < secretIdLength)
  let length = secretIdLength - prefix.count
  let suffix = String((0..<length).map { _ in alphanumeric.randomElement()! })
  return prefix + suffix
}

/// Generates a random VM id.
public func randomVMId() -> String {
  assert(prefix.count < vmIdLength)
  let length = vmIdLength - prefix.count
  let suffix = String((0..<length).map { _ in lowerCaseAlphanumeric.randomElement()! })
  return prefix + suffix
}

/// Defines errors trying
public enum ResourceNameError: Error {
  case unsetEnvironmentVariable(String)
}
