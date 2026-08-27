# Design Specification - Swift Service Account Authentication

This document defines the design and implementation specifications for the native Swift **Service Account Authentication** feature in the `GoogleCloudAuth` package (`packages/swift-google-auth`). This feature enables applications to authenticate using a Google Service Account JSON key file natively in Swift, eliminating the existing Rust FFI bridge while retaining 100% feature and test parity with the Rust SDK.

---

## 1. Objective & Scope

### Objective
To implement a secure, unified, and thread-safe native Swift Service Account Authentication engine inside `google-cloud-swift` (`packages/swift-google-auth`), supporting access token generation (self-signed JWTs) and 1-to-1 test parity.

### In-Scope
1.  **Access Token Credentials**: Generating OAuth2 access tokens (self-signed JWS/JWT assertions) natively in Swift using a unified, cross-platform cryptographic library.
2.  **Universal Platform Support**: Functional parity on macOS and Linux out-of-the-box, with a single pure-Swift codebase. (Note: iOS is not a requirement for this phase).
3.  **Thread Safety**: Secure state management and caching via structured concurrency and the `TokenCache` actor.
4.  **Test Parity**: Complete implementation of all validated Rust access-token-specific unit and integration tests in native Swift.

### Out-of-Scope
The following features are explicitly out-of-scope for this phase and are deferred to future work:
1.  **OIDC ID Tokens**: Obtaining OpenID Connect (OIDC) ID tokens for service-to-service authentication (e.g., Cloud Run, IAP) via exchanging signed assertions with the token server.
2.  **Blob Signing / Signer**: Cryptographic RSA-SHA256 signing of arbitrary data payloads locally (e.g., GCS Signed URLs).
3.  **Impersonated Credentials**: Exchanging source credentials for target service account credentials via remote IAM APIs.
4.  **Workload Identity Federation**: Exchanging AWS or OIDC identity tokens for Google access tokens.
5.  **API Keys**: Handling of static raw Google API keys.

---

## 2. Background

Google Cloud client libraries require a unified, thread-safe, and performant authentication mechanism to inject credentials into outgoing HTTP requests. Currently, the `google-cloud-swift` SDK bridges to a shared Rust core `rust_auth_core` via FFI. While functional, this bridge introduces binary bloat, dynamic linking complexities, and toolchain friction in developer environments, particularly on Linux.

To address this, we are transitioning `GoogleCloudAuth` to a pure Swift architecture, utilizing modern language features—such as Structured Concurrency (`async/await`) and Actors—to handle caching natively. This design specification details how to implement the **Service Account Authentication** module natively in Swift, replacing the existing FFI targets while retaining full compatibility with [DESIGN.md](DESIGN.md).

To achieve a highly maintainable, cross-platform, and compile-ready architecture without platform-specific FFI dynamic linking, we adopt a unified cryptographic strategy using Vapor's `jwt-kit` library for RSA-SHA256 signing. Since standard Google Service Account keys are issued in PKCS#8 format, `jwt-kit` seamlessly integrates native JWT payload serialization, JSON encoding, Base64URL padding, and robust RSA cryptographic signing bindings natively out-of-the-box.

---

## 3. Requirements

We define functional and non-functional requirements using a binary classification (either required or out-of-scope/deferred). Vague modifiers are avoided to ensure all criteria are testable and clear.

### Functional Requirements
*   **Key Parsing & Format Compatibility**: The library MUST parse Google Service Account JSON keys and load PEM-encoded private keys on macOS and Linux. The private key MUST be formatted in a PEM format natively supported by the platform (PKCS#8). 
*   **Access Token Generation (Self-Signed JWT)**: The library MUST natively generate RS256 self-signed JWS assertions and utilize them directly as Bearer tokens for Google Cloud API calls, without performing unnecessary token-exchange network roundtrips.
*   **Proactive Caching**: The library MUST cache access tokens in memory and proactively refresh them in the background before they expire to prevent API request latency spikes.

### Non-Functional Requirements
*   **JWS Signing Latency**: Local cryptographic signature computation for JWS assertions MUST have reasonable performance suitable for a one-off operation (as tokens are cached and refreshed hourly). Sub-millisecond signing latency is not a requirement.
*   **Thread Safety**: All stateful token operations, caching, and background refreshing MUST be completely thread-safe and free of data races, implemented natively via Swift structured concurrency and Actor isolation.
*   **GAX Backward Compatibility**: The library MUST maintain complete public API compatibility with GAX `HTTPClient` and generated mono-repo libraries, preserving `AuthHeaders` as duplicate-supporting arrays of key-value tuples.
*   **Acyclic Dependency Boundaries**: The authentication library MUST remain completely independent of `GoogleCloudGax`.

---

## 4. Public API Surface

We will expand the public API defined in the parent [DESIGN.md](DESIGN.md) with explicit configuration options and types for Service Accounts.

### A. Access Token Configuration ([Credentials.swift](../Sources/GoogleCloudAuth/Credentials.swift))

We will add the `serviceAccount` case to `CredentialsConfiguration` inside the actual [Credentials.swift](../Sources/GoogleCloudAuth/Credentials.swift) enum. Note that we do not expose a `serviceAccountKeyFile` case, as reading files is a trivial task that application developers can perform on their own prior to loading credentials.

To ensure compiler safety for the existing FFI backend during the transition/experimental phase, the `RustCredentialsSource.swift` target MUST be modified to explicitly reject the new configuration by throwing `.notSupported`. See the actual implementation inside [RustCredentialsSource.swift](../Sources/GoogleCloudAuth/Providers/RustCredentialsSource.swift).

To support this compilation path, we also modified the `CredentialsError` enum to add the new `notSupported` error case. See the actual implementation inside [MDSCredentials.swift](../Sources/GoogleCloudAuth/Providers/MDSCredentials.swift).

---

## 5. Detailed Architecture & Implementation

### A. Service Account Credentials ([ServiceAccountCredentials.swift](../Sources/GoogleCloudAuth/Providers/ServiceAccountCredentials.swift))

This conforms to `CredentialsSource` inside [ServiceAccountCredentials.swift](../Sources/GoogleCloudAuth/Providers/ServiceAccountCredentials.swift). It manages token fetching and caching for Service Account access tokens. It integrates with the generic `TokenCache` actor from the codebase, explicitly specifying `ContinuousClock` as its generic type argument.

The complete thread-safe, generic `TokenCache`-backed credentials source implementation resides inside [ServiceAccountCredentials.swift](../Sources/GoogleCloudAuth/Providers/ServiceAccountCredentials.swift).

### B. Service Account Key ([ServiceAccountKey.swift](../Sources/GoogleCloudAuth/Providers/ServiceAccountKey.swift))

Represents the parsed JSON key file, encapsulates key loading, and safely censors the private key for logging. We omit the manual `init(from:)` implementation to allow the compiler to automatically synthesize both the decodable JSON initializer and the default memberwise initializer required by the tests.

The complete decodable model and debug description censor logic resides inside [ServiceAccountKey.swift](../Sources/GoogleCloudAuth/Providers/ServiceAccountKey.swift).

### C. Self-Signed JWT Generation ([ServiceAccountTokenProvider.swift](../Sources/GoogleCloudAuth/Providers/ServiceAccountTokenProvider.swift))

Natively generates JWS structures inside [JWS.swift](../Sources/GoogleCloudAuth/Crypto/JWS.swift) and performs local RSA signing using a unified, pure-Swift cryptographic utility.

#### 1. JWS Types ([JWS.swift](../Sources/GoogleCloudAuth/Crypto/JWS.swift))

The formal JWS claim payload and header specifications reside inside [JWS.swift](../Sources/GoogleCloudAuth/Crypto/JWS.swift).

#### 2. JWS Claims Serialization & Mapping Rules

To ensure GCP compatibility, JWS claims must be serialized following these exact mapping rules:
*   **`iss` and `sub`**: MUST be set to the service account's `clientEmail` value.
*   **`iat` (Issued At)**: MUST be set to the current UNIX epoch timestamp minus `10 seconds` to accommodate slight clock skew between server and client.
*   **`exp` (Expiration)**: MUST be set strictly relative to `iat` as `iat + 3600` (exactly 60 minutes). **Setting `exp` relative to `now` (e.g. `now + 3600 + 10`) will create a token lifetime of 3610 seconds, which Google Cloud's IAM endpoint will reject with a token expiration lifecycle error.**
*   **Mutually Exclusive `scope` and `aud`**:
    *   *Scopes Flow*: If the configuration defines scopes, the JWS MUST include the `scope` claim containing space-separated OAuth2 scope strings (e.g., `"https://www.googleapis.com/auth/cloud-platform"`), and the `aud` claim MUST be serialized as `null` (or omitted entirely).
    *   *Audience Flow*: If the configuration defines an audience, the JWS MUST include the `aud` claim containing the target service name (e.g., `"https://pubsub.googleapis.com/"`), and the `scope` claim MUST be serialized as `null` (or omitted).

#### 3. Token Generation Flow

The full JWT generation, claim alignment, space-separated scopes compilation, and RSA signature delegate bindings reside inside [ServiceAccountTokenProvider.swift](../Sources/GoogleCloudAuth/Providers/ServiceAccountTokenProvider.swift).

---

## 6. Cryptographic Implementation Strategy ([ServiceAccountTokenProvider.swift](../Sources/GoogleCloudAuth/Providers/ServiceAccountTokenProvider.swift))

Implementing RSA-SHA256 signing natively in Swift across platforms is accomplished using Vapor's official open-source `jwt-kit` library. Specifically, we leverage the fully-supported `JWTSigner` and `JWTPayload` protocols which provide native robust support for RS256 hashing, JWT JSON claim serialization, and Base64URL encoding.

Standard Google Service Account private keys are predominantly issued in **PKCS#8** PEM containers, though older PKCS#1 formats exist. By utilizing `jwt-kit`, the token provider encapsulates the signing logic concisely:

```swift
struct ServiceAccountClaims: JWTPayload, Equatable, Sendable {
  let iss: IssuerClaim
  let sub: SubjectClaim
  let scope: String?
  let aud: AudienceClaim?
  let iat: IssuedAtClaim
  let exp: ExpirationClaim
  func verify(using algorithm: some JWTAlgorithm) async throws {}
}

// Inside fetchToken()
let claims = ServiceAccountClaims(...)
let privateKey = try Insecure.RSA.PrivateKey(pem: key.privateKey)

let keys = await JWTKeyCollection()
let kid = JWKIdentifier(string: key.privateKeyID)
await keys.add(rsa: privateKey, digestAlgorithm: .sha256, kid: kid)

let signedJWT = try await keys.sign(claims, kid: kid)
```

This immediately grants:
1.  **Native Multi-Format Parsing**: Seamless deserialization of both standard PKCS#8 and older PKCS#1 PEM strings natively.
2.  **ECDSA / Invalid Key Rejection**: Safely traps and throws on unsupported ECDSA formats or structurally malformed strings.
3.  **Strict Security Posture**: Operations execute across Apple's secure internal cryptographic boundaries (backed heavily by `swift-crypto` and `BoringSSL` on Linux), mitigating side-channel attacks inherently better than pure-Swift arithmetic alternatives.

---

## 7. Alternatives Considered

We originally evaluated three cryptographic alternatives for native RSA-SHA256 signing before finalizing the `jwt-kit` strategy:

*   We considered pure `apple/swift-crypto` directly because it offers native, BoringSSL-backed RSA signing and eliminates custom ASN.1 parsing constraints, but went with Vapor's `jwt-kit` because it seamlessly handles JWT claim serialization, Base64URL encoding, and safely wraps the `swift-crypto` RSA signatures out of the box without requiring manual header payload string interpolation.

*   We considered pure Swift `CryptoSwift` alongside `swift-asn1` because it provides a zero-dependency cryptography engine, but went with Vapor's `jwt-kit` because the `CryptoSwift` RSA implementation was buggy and immature, requiring complex manual modulo arithmetic (`phi(n)`) bypasses to process standard PKCS#8 keys, which expanded our testing surface area and introduced side-channel vulnerabilities.

## 8. Test Parity Strategy

To preserve safety, we map all verified Rust service-account-specific tests directly to native Swift tests using `import Testing`.

### A. Test Structure Example

The test suites conform to the modern Swift Testing framework. Refer to the test layouts inside [ServiceAccountTests.swift](../Tests/ServiceAccountTests.swift).

### B. Unit Test Parity ([ServiceAccountTests.swift](../Tests/ServiceAccountTests.swift))

1.  `debug_token_provider` -> `testServiceAccountKeyDebugRepresentation()`
    *   Verifies `CustomDebugStringConvertible` for `ServiceAccountKey` censors the private key.
2.  `headers_success_without_quota_project` -> `testHeadersSuccessWithoutQuotaProject()`
    *   Verifies `Authorization` header exists and `x-goog-user-project` is absent.
3.  `headers_success_with_quota_project` -> `testHeadersSuccessWithQuotaProject()`
    *   Verifies `x-goog-user-project` is present.
4.  `get_service_account_headers_pkcs1_private_key_failure` -> `testPKCS1KeyBuildSucceeds()`
    *   Verifies initialization natively accepts older PKCS#1 keys cleanly without manually bridging formats.
5.  `get_service_account_token_pkcs8_key_success` -> `testPKCS8KeyGenerationSuccess()`
    *   Decodes generated JWT, verifying JWS headers (`alg: RS256`, `typ: JWT`, `kid`), issuer, scope, and default lifetime.
6.  `header_caching` -> `testTokenAndHeaderCaching()`
    *   Validates that consecutive calls to `headers()` return the cached token instead of regenerating JWT and signing.
7.  `universe_domain` -> `testUniverseDomainParsingAndOverrides()`
    *   Verifies default `googleapis.com`, key-specific domains, and explicit overrides propagate correctly.
8.  `get_service_account_headers_invalid_key_failure` -> `testInvalidKeySigningFailure()`
    *   Asserts invalid PEM strings fail gracefully.
9.  `get_service_account_invalid_json_failure` -> `testInvalidJSONParsingFailure()`
    *   Asserts invalid JSON strings fail to build.
10. `get_service_account_headers_with_audience` -> `testJWSAssertionWithAudience()`
    *   Verifies JWS claims set `aud` and omit `scope` when built with audience.
11. `get_service_account_headers_with_custom_scopes` -> `testJWSAssertionWithCustomScopes()`
    *   Verifies JWS claims set space-separated `scope` and omit `aud` when built with scopes.

### C. Integration Test Parity ([IntegrationTests.swift](../Tests/IntegrationTests/IntegrationTests.swift))

1.  `create_access_token_credentials_adc_service_account_credentials` -> `testAdcResolvesServiceAccountCredentials()`
    *   Loads service account key into env, triggers ADC, and asserts `ServiceAccountCredentials` is resolved.
2.  `create_access_token_credentials_json_service_account_credentials` -> `testAdcResolvesServiceAccountWithQuota()`
    *   Asserts ADC resolves service account credentials with quota project.

---

## 9. Risks and Mitigation Strategies

We identify critical implementation risks and establish clear, strategic mitigations.

### A. Cryptographic Security Boundary Audits
*   **Risk**: Deploying a third-party cryptographic library (`jwt-kit` / `swift-crypto`) in production code involves a security risk regarding cryptographic implementation correctness, side-channel attacks, and overall package safety.
*   **Mitigation**:
    *   Lock and pin the `jwt-kit` dependency package version, monitor standard security advisories, and rely on `swift-crypto`'s official Apple-backed BoringSSL module for strict execution safety.

### B. Raw Key Memory Security
*   **Risk**: Parsing private keys into in-memory `String` or `Data` buffers creates a risk of key exposure via memory heap inspections.
*   **Mitigation**: Maintain extremely tight scope lifecycles for deserialized keys. Where supported, clear raw byte arrays (`[UInt8]`) or zero out private key structures immediately after cryptographic key load and signature operations.

---

# Corpus of information

*   [AIP-4110: Application Default Credentials](https://google.aip.dev/auth/4110)
*   [AIP-4111: Self-Signed JWTs](https://google.aip.dev/auth/4111)
*   [RFC 7519: JSON Web Token (JWT)](https://datatracker.ietf.org/doc/html/rfc7519)
*   [RFC 7523: JWT Profile for OAuth 2.0 Client Authentication](https://datatracker.ietf.org/doc/html/rfc7523)
*   [Apple Developer: SecKey Cryptographic Signing Docs](https://developer.apple.com/documentation/security/certificate_key_and_trust_services/keys/signing_and_verifying)
