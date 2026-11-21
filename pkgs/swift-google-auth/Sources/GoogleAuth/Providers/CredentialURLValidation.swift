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

/// Parses and validates an HTTPS credential endpoint URL.
///
/// Rejects empty strings, whitespace or control characters, non-HTTPS schemes, userinfo,
/// query parameters, fragments, explicit non-443 ports, missing or non-ASCII/percent-encoded
/// hosts, empty/relative paths, backslashes, percent-encoded slashes, and `.` / `..` path
/// segments.
func parseValidatedHTTPSCredentialURL(
  _ urlString: String,
  allowRootPath: Bool = false
) -> (url: URL, host: String, components: URLComponents)? {
  guard
    !urlString.isEmpty,
    !urlString.unicodeScalars.contains(where: {
      $0.value < 0x20 || $0.value == 0x7F || $0.properties.isWhitespace
    }),
    let components = URLComponents(string: urlString, encodingInvalidCharacters: false),
    components.scheme?.lowercased() == "https",
    components.user == nil,
    components.password == nil,
    components.query == nil,
    components.fragment == nil,
    components.port == nil || components.port == 443,
    let host = components.host,
    !host.isEmpty,
    components.encodedHost == host,
    host.utf8.allSatisfy({ $0 < 0x80 }),
    !components.path.isEmpty,
    components.path.hasPrefix("/"),
    allowRootPath || components.path != "/",
    !components.path.contains("\\"),
    !components.path.unicodeScalars.contains(where: {
      $0.value < 0x20 || $0.value == 0x7F || $0.properties.isWhitespace || $0 == "?" || $0 == "#"
    }),
    !components.percentEncodedPath.lowercased().contains("%2f"),
    components.path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
      $0 != "." && $0 != ".."
    }),
    let resolvedURL = components.url
  else {
    return nil
  }
  return (resolvedURL, host, components)
}

/// Returns `true` if `label` is a valid DNS label (`1...63` ASCII `[A-Za-z0-9-]` or
/// lowercase `[a-z0-9-]` characters, not starting or ending with `-`).
func isValidDNSLabel(_ label: Substring, allowUppercase: Bool) -> Bool {
  guard
    (1...63).contains(label.utf8.count),
    !label.hasPrefix("-"),
    !label.hasSuffix("-")
  else {
    return false
  }
  return label.utf8.allSatisfy { byte in
    (0x61...0x7A).contains(byte)
      || (allowUppercase && (0x41...0x5A).contains(byte))
      || (0x30...0x39).contains(byte)
      || byte == 0x2D
  }
}

/// Returns `true` if `domain` is a valid non-empty DNS domain (`1...253` ASCII characters,
/// at least two dot-separated `[A-Za-z0-9-]` labels of `1...63` characters not starting or
/// ending with `-`, and a top-level label containing at least one ASCII letter `[A-Za-z]`).
func isValidDNSDomain(_ domain: String) -> Bool {
  guard (1...253).contains(domain.utf8.count) else {
    return false
  }
  let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
  guard
    labels.count >= 2,
    labels.allSatisfy({ isValidDNSLabel($0, allowUppercase: true) }),
    let tld = labels.last,
    tld.utf8.contains(where: { (0x61...0x7A).contains($0) || (0x41...0x5A).contains($0) })
  else {
    return false
  }
  return true
}

/// Returns `true` if `host` matches one of the allowed IAM Credentials endpoints for
/// `universeDomain`:
/// - `iamcredentials.<universe>`
/// - `iamcredentials.<region>.rep.<universe>`
/// - `<region>-iamcredentials.<universe>`
/// where `<region>` is a single valid DNS label (`[a-z0-9-]`, not starting or ending with `-`).
func isValidIAMCredentialsHost(_ host: String, universeDomain: String) -> Bool {
  guard isValidDNSDomain(host), isValidDNSDomain(universeDomain) else {
    return false
  }
  let lowerHost = host.lowercased()
  let lowerUniverse = universeDomain.lowercased()
  let universeSuffix = ".\(lowerUniverse)"
  guard lowerHost.hasSuffix(universeSuffix) else {
    return false
  }
  let prefix = lowerHost.dropLast(universeSuffix.count)
  if prefix == "iamcredentials" {
    return true
  }
  let labels = prefix.split(separator: ".", omittingEmptySubsequences: false)
  if labels.count == 3, labels[0] == "iamcredentials", labels[2] == "rep" {
    return isValidDNSLabel(labels[1], allowUppercase: false)
  }
  if labels.count == 1 {
    let label = labels[0]
    let locationalSuffix = "-iamcredentials"
    guard
      label.hasSuffix(locationalSuffix),
      label.utf8.count <= 63
    else {
      return false
    }
    let region = label.dropLast(locationalSuffix.count)
    return isValidDNSLabel(region, allowUppercase: false)
  }
  return false
}

/// Returns `true` if `components` has a valid IAM Credentials `:generateAccessToken` path
/// (`/v1/projects/<project>/serviceAccounts/<account>:generateAccessToken`) without
/// percent-encoded slashes or empty/invalid segments.
func isValidIAMCredentialsGenerateAccessTokenPath(_ components: URLComponents) -> Bool {
  let methodSuffix = ":generateAccessToken"
  let percentEncodedPath = components.percentEncodedPath
  guard
    !percentEncodedPath.lowercased().contains("%2f"),
    percentEncodedPath.hasSuffix(methodSuffix)
  else {
    return false
  }
  let segments = components.path.split(separator: "/", omittingEmptySubsequences: false)
  guard
    segments.count == 6,
    segments[0].isEmpty,
    segments[1] == "v1",
    segments[2] == "projects",
    !segments[3].isEmpty,
    segments[3] != ".",
    segments[3] != "..",
    segments[4] == "serviceAccounts"
  else {
    return false
  }
  let project = segments[3]
  let actionSegment = segments[5]
  guard actionSegment.hasSuffix(methodSuffix) else {
    return false
  }
  let account = actionSegment.dropLast(methodSuffix.count)
  let hasDisallowedScalar: (Substring) -> Bool = { segment in
    segment.unicodeScalars.contains(where: {
      $0.value < 0x20 || $0.value == 0x7F || $0.properties.isWhitespace || $0 == "?" || $0 == "#"
        || $0 == ":"
    })
  }
  return !account.isEmpty
    && account != "."
    && account != ".."
    && !project.contains("..")
    && !account.contains("..")
    && !hasDisallowedScalar(project)
    && !hasDisallowedScalar(account)
}
