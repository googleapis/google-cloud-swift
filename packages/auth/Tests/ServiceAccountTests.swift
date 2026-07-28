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
import Testing
import JWTKit

@testable import GoogleCloudAuth

@Suite("Service Account Key & Credentials Tests")
struct ServiceAccountTests {
  // Returns a mock Service Account JSON key string containing a statically embedded 2048-bit PKCS#8 RSA key for determinism.
  private static func generateMockKeyJSON() throws -> Data {
    let validPKCS8PEM = """
      -----BEGIN PRIVATE KEY-----
      MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCcPLcw48+yRt5f
      CXKKIHnvNZHuiriD1nrP17OQpHDTkWTq5+ynEDusFXkauFCbUJHrSOTokXDFHZlu
      3HRWM2tRxg8IZODpExgKtqYhS5peJ5iY8Q6Ur1+WvhBln4M5VMtjW2YiN+zrkiCY
      p04KygGo1UZ92ocBpiSOSkqqXoQj+AqBHRGLK3GPmCLqxgzMk2VGGmpTU1mTLN6O
      2CtFkqPmcadypG0vlEbkUYunQud/MhyDb6ArhwrJQa6X6iOvbar7yxaOy0xix/Xk
      s/hcMyVySrjv2/K/LbaVuEOhhseL/gcI0bP8qvn0dZ8c5l9KcdX/fr6aFcrTcqlu
      u4wdNMv5AgMBAAECggEAMTB2dqiK2DSyx1Yony9ZZIRHtUQskqmA0hY13SjAswOY
      M9MgMXsNZoD+N3jnO/cScfLpywUbbZwDliFHaWpX9A945Sopm4gc7iaSSHJOoC00
      QJbIgexzGnktnWkqve6h+F6q2cQkzggcRiOKkSAHhLndLzuRfOXrpXbjah9G2DG9
      5CIWjY/VdZQrwWrmzkY2WJVoW52Cfj5TBmCbpNk0Rdbv5q1957TGscQKELxp3wt9
      ash4KGg2NlAP/fjRLs+X+9/dSxV8RHnovxPnXVy5XDcGisSX8rHjsjV3rZTs2Nls
      ug1kJcAgg9i51wgsvE8Fu3lzLC3ewYmpilI5O8XA9wKBgQDafd7Hu7LMP9UisX4y
      FTuxLZUoeN7erutAWzO8deyTFM/BW1blzQBHCAUA1cMPftdFaFPfgBaz6CkikhMv
      0ySPjyyKsVDVObKCKo0XxISrdiuqE1K62Yn/gfyh8ZdEv+qkJvz1XaBb8DrlbpqK
      EAXeLsckPV6lUqcv7BhojdeTmwKBgQC3Duy9rw8yxWpvfRubsuT7CQ7p6YTM1KAx
      egNiKBGx6sj3KWGVcJPCPZkaD1+XJO6zhOqyL5/syviFTDuyEIWYBaY0odJwb7Vg
      KVXdBa5UwI6DYmsZAAAOP1wywwQrYuqwuVhy3+09iKPkGOJ4I32Kw5HYvJ79qL19
      sRE0/e3p+wKBgFG/8MAYuaB0bcHKWWZRzYDQhlObTgBRwFHXDfeAw+CQU9+L1mqr
      FmR9WqniUVaV5ePhUih424W64tE9iJJHVRGlx0upZo4xRVowo5P2ApHI6DN9gWHK
      DTkdoLHTG/8sM5XxxInl2x8rNk4r4QSxVBC6veYQVD5VO5rRopxUHgnrAoGAeHZq
      1hw4PSnqc7l5jIk54/S/CrDwAja9wDFRvqstkc42N2fU3pl5sq4EbUDGn9je9+W0
      6FMsw4+B4X4cHn5+216EVEhVCkaIreIlrc/KO92HKvB+F7KHVtjdHE53FPIADRG7
      IcU4AnFDoJu7lGGOgN1Xwa/GVJhRMkBuWVfs0zcCgYEAlP9KCxjRXtcJEnB81uHx
      sjUYPwyP5KbyYnl9LRbqfvZPIMgV2BIl+wOLUhSFYpxsDK3Otf/SyKm3qkifT4E2
      TEsACTOH4L3aH53EIDbugMPAyMbsTZfR4EK2zGi1QOl0hjZ+kUSNcPlDAUK9vXfF
      1ARUsyX+ffQ++dMyCItdcEg=
      -----END PRIVATE KEY-----
      """

    let escapedPEM = validPKCS8PEM.replacingOccurrences(of: "\n", with: "\\n")

    let json = """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(escapedPEM)",
        "client_email": "test-client-email@gserviceaccount.com",
        "universe_domain": "test-universe-domain"
      }
      """
    return Data(json.utf8)
  }

  @Test("Service Account Key debug representation censors the private key")
  func dataDebugRepresentation() throws {
    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()
    let key = try JSONDecoder().decode(ServiceAccountData.self, from: mockKeyJSON)
    let debugDescription = String(reflecting: key)
    #expect(!debugDescription.contains("MIIEvQIBADANBgkq"))
    #expect(debugDescription.contains("[censored]"))
  }

  @Test("Service Account Credentials returns standard headers successfully")
  func successWithoutQuotaProject() async throws {
    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()
    let credentials = try ServiceAccountCredentials(keyJSON: mockKeyJSON)
    let headers = try await credentials.headers()

    #expect(headers.count == 1)
    #expect(headers[0].0 == "Authorization")
    #expect(headers[0].1.hasPrefix("Bearer "))
  }

  @Test("Service Account Credentials injects custom billing quota project header")
  func headersSuccessWithQuotaProject() async throws {
    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()
    let credentials = try ServiceAccountCredentials(
      keyJSON: mockKeyJSON, quotaProjectID: "quota-proj-123")
    let headers = try await credentials.headers()

    #expect(headers.count == 2)
    #expect(headers.contains { $0.0 == "Authorization" && $0.1.hasPrefix("Bearer ") })
    #expect(headers.contains { $0.0 == "x-goog-user-project" && $0.1 == "quota-proj-123" })
  }

  @Test(
    "ServiceAccount initialization successfully accepts PKCS#1 private keys natively")
  func pkcs1KeyBuildSucceeds() async throws {
    let pkcs1PEM = """
      -----BEGIN RSA PRIVATE KEY-----
      MIIEowIBAAKCAQEAo5bIphEnhUMJwrj0fgIFfdMfFcCu45iwbiGcRQj+DNcCAhA3
      Yf5N/HXEeEhEs1npMzD2wx4v96eZ8KtItMJDtd1v1hUeoRmRK14zPABy28uIO1AS
      kRSdSkKAskTe8FuIOBBwih9w8JWefOIiBj2EgH2V80hukvTTdSn8ShZ17GuDp8eu
      E01Va181a1nqzWRddi1Jbok74IMvDLzyVzT+AmND1sPyqPOZjFaZihybVeheIKXk
      wg6vFiP1WHF2jI9pZ0wG9u4s16k7uSLRyG8N2ePMlzrr1nVWi5zQ+I8BPZbuXqwt
      v+hyZhpGswpiiNCOTvtfTEGEr1546XL4QqKIrwIDAQABAoIBAAzx55rMjLYM4f7Y
      p/A4tLqKNFGCV9SGxp9QZY9I8OGPOgdzxQ4qE33Ay/VAsr8GhF+apkw2XVFZn+Ld
      ivlSzgzcIvdr4GqbHVOzNpau6mfeKT+YTH/Sg8fWj1yL+qBGffcBxgYICuXe0RXM
      xyh7QbrxNSZ1OtrCKOGCmwY51McKcoz1iKsKdqGCor7g3ojNsK3kqIwtSbNslkbK
      IeNvuVcrJ4v9iNZwD88EwxOi5595dy5RzN88hJNSEBQ146LCSb4wlOKeO5bFVLUW
      p4kUSfzlkFdYHfh+W5e1yoW6JFyeAiYM9dnyZaPM650EWbUyDaq3S6iNtiMCNkvD
      QhbDWjECgYEA1Ng0H+dduEfs4snPwYKxzPF1bP4cLqRp8LLVTh7EggAwi4+r/kMg
      eDKVLIQ8RFj1C2OkNT+xOqPgSIdEE7kOs/yYvmGQhCkn4wbXB6SnX7f8E9bp4qsq
      1BQAi6Q74iBj9YphXkDi8gdSM0svX+o5JrSs92i/wk9EQsw6A7R9qb0CgYEAxMHy
      pe/BU6/GOneAOASwUb+Xp3rmMjjs1L5jnAwhREhFJYMqRu9n/7rgBtILnnKtsCUd
      kQzPl8x4Okem1AjRvTFS32EuwNIAby+Dii12xRPPLRsfgi2+Nr1w6wSFLAKGQpNf
      pZdL0NLCLlyA72PcRhihODX5rc33/ME7CTAu5NsCgYEApKvhKA3I5JpBG/UnV3/W
      L8lgIEM5apypmh/CB/6l6i5bYJ53YvBsXpJD930XY4mvjHA6yzfL1qKTE4oTkW7L
      gVUcl67EMHvm8C6Kjs9E7zlZPcA4k7X6HLqc8WzPJ9QHgiDd1B4/dyFS53xz2rFM
      JjYC3CeetKa/GS8Ic3VhA8ECgYBxQaLG2YdTAK7+IKNxm2FS7RICmb+/0PyiSSVV
      QbY0c9U5jpLbWhtnHM6vnmCJyEEqT3MBd3pXSp86DNx+2MTCPo4RfwNGgps1ZQg2
      lYz0TD7JG/+7E1GWeN1yqptthdZ6pBI+YySFA4w624xsP/MfdjX3ATrDTPgeSawN
      0epsWQKBgBKtcgcDMPmU6u5K4mDWP6UmGkx6Op6CltYMTLUztYcNnYGdSWe0koVD
      qKujOPHbJYqjTJxrkUltv/uzkG8wU/lDNLxnDki1LXk8A8rTDaTORzjNfpZmelJU
      Z9TAOg3RmWJPYvfJWUBWWwUBBe0VpDtwaOnyJzApHW/c49sDqvr7
      -----END RSA PRIVATE KEY-----
      """
    let escapedPEM = pkcs1PEM.replacingOccurrences(of: "\n", with: "\\n")

    let pkcs1KeyJSON = Data(
      """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(escapedPEM)",
        "client_email": "test-client-email@gserviceaccount.com",
        "universe_domain": "test-universe-domain"
      }
      """.utf8)

    let credentials = try ServiceAccountCredentials(keyJSON: pkcs1KeyJSON)
    do {
      let _ = try await credentials.headers()
    }
  }

  @Test(
    "JWS JWT Token assertion is generated successfully with correct RS256 headers and strict 3600s lifetime"
  )
  func pkcs8KeyGenerationSuccess() async throws {
    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()
    let credentials = try ServiceAccountCredentials(keyJSON: mockKeyJSON)
    let headers = try await credentials.headers()

    guard
      let token = headers.first(where: { $0.0 == "Authorization" })?.1.replacingOccurrences(
        of: "Bearer ", with: "")
    else {
      Issue.record("Authorization header missing")
      return
    }

    let key = try JSONDecoder().decode(ServiceAccountData.self, from: mockKeyJSON)
    let privateKey = try Insecure.RSA.PrivateKey(pem: key.privateKey)
    let keys = JWTKeyCollection()
    await keys.add(rsa: privateKey, digestAlgorithm: .sha256)
    let decodedClaims = try await keys.verify(token, as: ServiceAccountClaims.self)

    #expect(decodedClaims.iss.value == "test-client-email@gserviceaccount.com")
    #expect(decodedClaims.sub.value == "test-client-email@gserviceaccount.com")
    #expect(decodedClaims.scope == "https://www.googleapis.com/auth/cloud-platform")
    #expect(
      decodedClaims.aud == nil, "Audience claim MUST be omitted/null when scopes are configured!")
    #expect(
      decodedClaims.exp.value.timeIntervalSince(decodedClaims.iat.value) == 3600,
      "JWT token claims expiration MUST be exactly 3600 seconds after iat!")
  }

  @Test("Access tokens are successfully cached in memory to prevent redundant regenerations")
  func tokenAndHeaderCaching() async throws {
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()

    let provider = ServiceAccountTokenProvider(
      key: try JSONDecoder().decode(ServiceAccountData.self, from: mockKeyJSON)
    )
    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(240),
      shortRefreshSlack: .seconds(10)
    )

    // First request triggers a fetch on provider
    let token1 = try await cache.token()
    #expect(!token1.accessToken.isEmpty)

    // Wait for background loop to sleep
    await clock.sleeperWaiting()

    // Second request instantly returns cached token
    let token2 = try await cache.token()
    #expect(token2.accessToken == token1.accessToken)
  }

  @Test("Universe domain parses correctly from key JSON and respects explicit overrides")
  func universeDomainParsingAndOverrides() async throws {
    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()

    // Default universe domain resolving from key JSON
    let credsDefault = try ServiceAccountCredentials(keyJSON: mockKeyJSON)
    let udDefault = await credsDefault.universeDomain()
    #expect(udDefault == "test-universe-domain")

    // Universe domain explicitly overridden
    let credsOverride = try ServiceAccountCredentials(
      keyJSON: mockKeyJSON, universeDomain: "custom.universe.domain")
    let udOverride = await credsOverride.universeDomain()
    #expect(udOverride == "custom.universe.domain")
  }

  @Test("Service Account JWS signing fails gracefully when given invalid private key PEM format")
  func invalidKeySigningFailure() async throws {
    let badKeyJSON = Data(
      """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "this-is-completely-invalid-garbage-pem-string",
        "client_email": "test-client-email@gserviceaccount.com",
        "universe_domain": "test-universe-domain"
      }
      """.utf8)

    let credentials = try ServiceAccountCredentials(keyJSON: badKeyJSON)
    do {
      let _ = try await credentials.headers()
      Issue.record("Expected CredentialsError")
    } catch is CredentialsError {
      // Success
    }
  }

  @Test("Service Account credentials initialization throws decoding error when given invalid JSON")
  func invalidJSONParsingFailure() async throws {
    let invalidJSON = Data("{ \"invalid\": \"json\" }".utf8)
    let error = #expect(throws: CredentialsError.self) {
      _ = try ServiceAccountCredentials(keyJSON: invalidJSON)
    }
    guard case .parseError = error else {
      Issue.record("Expected parseError, got \(error)")
      return
    }
  }

  @Test(
    "JWS assertion contains correct audience claim and omits scopes claim when configured with custom target audience"
  )
  func jwsAssertionWithAudience() async throws {
    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()
    let customAud = "https://pubsub.googleapis.com/"
    let credentials = try ServiceAccountCredentials(
      keyJSON: mockKeyJSON, accessSpecifier: .audience(customAud))
    let headers = try await credentials.headers()

    guard
      let token = headers.first(where: { $0.0 == "Authorization" })?.1.replacingOccurrences(
        of: "Bearer ", with: "")
    else {
      Issue.record("Authorization header missing")
      return
    }

    let key = try JSONDecoder().decode(ServiceAccountData.self, from: mockKeyJSON)
    let privateKey = try Insecure.RSA.PrivateKey(pem: key.privateKey)
    let keys = JWTKeyCollection()
    await keys.add(rsa: privateKey, digestAlgorithm: .sha256)
    let decodedClaims = try await keys.verify(token, as: ServiceAccountClaims.self)

    #expect(decodedClaims.aud?.value.first == "https://pubsub.googleapis.com/")
    #expect(
      decodedClaims.scope == nil, "Scopes claim MUST be omitted/null when audience is configured!")
  }

  @Test(
    "JWS assertion contains space-separated scope claim and omits audience claim when configured with scopes list"
  )
  func jwsAssertionWithCustomScopes() async throws {
    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()
    let credentials = try ServiceAccountCredentials(
      keyJSON: mockKeyJSON, accessSpecifier: .scopes(["scopeA", "scopeB"]))
    let headers = try await credentials.headers()

    guard
      let token = headers.first(where: { $0.0 == "Authorization" })?.1.replacingOccurrences(
        of: "Bearer ", with: "")
    else {
      Issue.record("Authorization header missing")
      return
    }

    let key = try JSONDecoder().decode(ServiceAccountData.self, from: mockKeyJSON)
    let privateKey = try Insecure.RSA.PrivateKey(pem: key.privateKey)
    let keys = JWTKeyCollection()
    await keys.add(rsa: privateKey, digestAlgorithm: .sha256)
    let decodedClaims = try await keys.verify(token, as: ServiceAccountClaims.self)

    #expect(decodedClaims.scope == "scopeA scopeB")
    #expect(
      decodedClaims.aud == nil, "Audience claim MUST be omitted/null when scopes are configured!")
  }

  @Test("Service Account Token Provider returns token with correct expiration date")
  func serviceAccountTokenVerifyExpiryTime() async throws {
    let mockKeyJSON = try ServiceAccountTests.generateMockKeyJSON()
    let key = try JSONDecoder().decode(ServiceAccountData.self, from: mockKeyJSON)

    let mockDate = Date(timeIntervalSince1970: 1700000000)
    let timeSource = MockTimeSource(currentDate: mockDate)

    let provider = ServiceAccountTokenProvider(key: key, timeSource: timeSource)
    let token = try await provider.fetchToken()

    // iat is now - 10s. exp is iat + 3600s.
    // So exp is now - 10s + 3600s = now + 3590s.
    let expectedExpiry = mockDate.addingTimeInterval(-10).addingTimeInterval(3600)

    #expect(
      token.expirationDate == expectedExpiry,
      "Expected expiration date \(expectedExpiry), got \(token.expirationDate)")
  }
}
