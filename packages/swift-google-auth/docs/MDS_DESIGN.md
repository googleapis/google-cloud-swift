# Objective

Implement Metadata Server (MDS) Authentication in the native
`google-cloud-swift` library. This implementation provides Google Cloud
environments (GCE, GKE, Cloud Run) with automatically resolved service account
credentials, ensuring robust token caching, retry mechanisms, and seamless
integration with GAX HTTP clients.

**Out of scope:**

-   OIDC ID token generation via MDS.
-   [SPIFFE](https://spiffe.io) MTLS certificate provisioning.
-   Per-attempt network timeouts (may be evaluated as a future enhancement).
-   Non-MDS credential sources (e.g., Service Account JSON keys, Authorized
    User).

# Background

Google Cloud applications often run in environments with a local Metadata
Service (MDS) at `http://metadata.google.internal`. This service allows
workloads to securely acquire OAuth2 access tokens for their attached default
service account without needing to manage static JSON credentials.

As part of the native Swift authentication engine, we are implementing an MDS
credential provider that integrates seamlessly with the `TokenCache` actor and
`AuthHTTPClient` infrastructure, as defined in the overarching native Auth
`DESIGN.md`.

# Requirements

-   **Requirement**: Implement the native `TokenProvider` protocol.
-   **Requirement**: Query the MDS `/token` endpoint using `AuthHTTPClient`.
-   **Requirement**: Append the `Metadata-Flavor: Google` header to all MDS
    requests.
-   **Requirement**: Parse the returned JSON response to extract the token and
    its expiration time.
-   **Requirement**: Support configuration overrides for endpoint URL, quota
    project ID, scopes, and retry parameters via the initializer.
-   **Requirement**: Integrate with the overarching structured exponential
    backoff retry engine for transient HTTP failures.
-   **Requirement**: Support `TokenCache` wrapping to handle token refresh loops
    and thundering herd protection.
-   **Requirement**: Achieve 100% test parity for transient retry, permanent
    failure, caching, ADC overrides, and quota project headers.
-   **Non-Requirement**: Generating OIDC ID tokens from the MDS endpoint.

# Overview

We will introduce a new `MDSCredentials` struct that conforms to
`CredentialsProvider`. It will encapsulate an `MDSAccessTokenProvider` which
handles the HTTP requests to
`http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token`.

When the user configures credentials, or when Application Default Credentials
(ADC) detects an MDS environment, an `MDSCredentials` instance is built and
wrapped in the `TokenCache` actor. This actor performs proactive background
refreshes and guards against concurrent network requests. `MDSCredentials`
itself will be internal to the package, with users interacting with it
exclusively through the public `Credentials` factory methods.

# Detailed Design

## Core Components

### `MDSCredentials`

The package-internal credential struct.

-   Exposes a configuration initializer directly without a separate
    configuration struct.
-   Conforms to `CredentialsProvider` to be consumed by `GoogleCloudGax`.

### `MDSAccessTokenProvider`

Conforms to `TokenProvider`.

-   **Endpoint**: Defaults to `http://metadata.google.internal`.
-   **Path**: `/computeMetadata/v1/instance/service-accounts/default/token`.
-   **Query Parameters**: Optionally appends `scopes` if provided.
-   **Headers**: Injects `Metadata-Flavor: Google`.
-   Uses `AuthHTTPClient` to execute the network request.
-   Decodes the JSON response using
    `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase`.
-   Constructs an `AccessToken` with the appropriate expiration time.

## Configuration

`MDSCredentials` is initialized directly via its initializer, accepting optional
overrides:

-   `endpoint`: Overrides the default MDS host. Used internally to support
    `GCE_METADATA_HOST`. It uses `URL` instead of `String` for robust parsing.
-   `quotaProjectID`: Sets the quota project ID.
-   `scopes`: Specific OAuth scopes. If omitted, default VM scopes are used.
-   `retryConfiguration`: Configures adaptive retry logic, exponential backoff,
    and limits mapping. (Note: per-attempt timeouts may be added in the future).

## ADC Integration

The ADC resolution engine initializes `MDSCredentials(fromADC: true)` as a
fallback. When running locally (outside of GCP), the MDS endpoint is
unreachable. The provider recognizes the connection failure (or lack of MDS
headers) and cleanly fails, returning actionable feedback for missing local
environment configurations, adhering to AIP-4110. It uses short timeouts without
retries to prevent hangs in developer environments.

## Error Handling & Retries

The provider leverages the native swift retry engine.

-   Transient errors (e.g., HTTP 500, 503, connection timeouts) trigger
    exponential backoff according to the `retryConfiguration`.
-   Permanent errors (e.g., HTTP 404, 403, 400) immediately fail without
    retries.

# Implementation details

### Files to Add:

-   `packages/swift-google-auth/Sources/GoogleCloudAuth/Providers/MDSCredentials.swift`:
    Contains `MDSCredentials` and `MDSAccessTokenProvider`.
-   `packages/swift-google-auth/Tests/GoogleCloudAuthTests/MDSCredentialsTests.swift`:
    Contains comprehensive unit tests for MDS retrieval logic.

### Modifications to Existing Files:

-   `packages/swift-google-auth/Sources/GoogleCloudAuth/ADC.swift`: Updated to probe MDS if
    other ADC methods fail.

### Code Structures:

```swift
package struct MDSCredentials: CredentialsProvider, Sendable {
    package init(
        endpoint: URL? = nil,
        quotaProjectID: String? = nil,
        scopes: [String]? = nil,
        retryConfiguration: RetryConfiguration? = nil
    ) {
       // builds internal provider and wraps in TokenCache
    }
}

package struct MDSAccessTokenProvider: TokenProvider, Sendable {
    package let endpoint: URL?
    package let quotaProjectID: String?
    package let scopes: [String]?
    package let client: AuthHTTPClient
    // ...
}
```

# Risks and Mitigation Strategies

-   **Risk**: Local development hangs trying to probe MDS.
    -   **Mitigation**: ADC resolution explicitly disables retries during MDS
        environment probing, bypassing exponential backoff delays.
-   **Risk**: Infinite loops during proactive token refresh if the MDS goes
    offline permanently.
    -   **Mitigation**: The `TokenCache` background refresh loop gracefully
        terminates on non-transient errors.

# Corpus of information

-   [AIP-4110: Application Default Credentials](https://google.aip.dev/auth/4110)
