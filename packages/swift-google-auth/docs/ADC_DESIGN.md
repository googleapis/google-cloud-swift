# Objective

Implement a pure, native Swift Application Default Credentials (ADC) resolution
engine in `google-cloud-swift` that resolves credentials automatically from the
environment.

**Out of scope:**

-   Impersonated Credentials (`impersonated_service_account`)
-   External Account Credentials (`external_account`)
-   GDCH Service Account Credentials (`gdch_service_account`)
-   Extracting or generating custom JWTs beyond standard Auth header needs.

# Background

Currently, the `google-cloud-swift` library resolves Application Default
Credentials and parses the environment using an architecture that relies on
non-native, external bindings. This integration introduces heavy compilation
overhead, limits portability (e.g. strict Linux ABI dependencies), and creates
an opaque debugging experience for Swift developers. We need a pure Swift
implementation of the ADC resolution strategy that is feature-complete, conforms
to the AIP-4110 standard, and maintains exact testing parity with the
established test suites.

# Requirements

-   **Strict Precedence:** Must parse `GOOGLE_APPLICATION_CREDENTIALS`
    environment variable first, then fallback to standard OS paths (AIP-4110),
    and finally fallback to Metadata Server (MDS).
-   **Environment Parity:** Must support `GOOGLE_CLOUD_QUOTA_PROJECT` overrides.
-   **Provider Routing:** Must dynamically route the JSON configuration to the
    appropriate credential provider based on the `"type"` field
    (`service_account` or `authorized_user`).
-   **Feature Parity:** Must implement `buildAccessTokenCredentials()`,
    `buildSigner()`, and `build()` endpoints natively.
-   **Test Parity:** Must execute all applicable unit tests matching Rust
    parity.

# Overview

The ADC resolution engine acts as the primary entry point for authentication in
`google-cloud-swift`. When initialized, the `Credentials` initializer will
attempt to load the ADC JSON file from the environment. It will parse the JSON
weakly to identify the credential type, and then delegate the strong decoding
and initialization to a registered `CredentialSourceParser`. If no file is found
or if well-known paths are absent, the resolver gracefully falls back to probing
the Google Compute Engine Metadata Server (MDS).

# Detailed Design

## 1. Application Default Credentials (ADC) Resolution (AIP-4110)

The system will resolve credentials following the exact standard precedence
(`ADCPath.swift`):

1.  **Environment Variable**: Check `GOOGLE_APPLICATION_CREDENTIALS`. If set,
    use strictly. If set but missing, throw an error.
1.  **Well-known File Locations**:
    -   Windows: `%APPDATA%\gcloud\application_default_credentials.json`
    -   POSIX (Linux/macOS):
        `$HOME/.config/gcloud/application_default_credentials.json`
1.  **Metadata Server**: If the environment variable is not set, and the
    well-known file is missing or paths cannot be determined, fall back to MDS.

## 2. Pluggable Parser Registry & Weak Decoding

To avoid coupling the core ADC resolver with all possible credential types (and
their heavy dependencies like Crypto), we will use a dynamic registry pattern.

See
[CredentialParserRegistry.swift](../Sources/GoogleCloudAuth/CredentialParserRegistry.swift)
for the protocol and the thread-safe dynamic registry pattern implementation.

The ADC resolver will read the file using `JSONSerialization` (weak typing) to
extract the `"type"` field. It will then pass the dictionary to the
corresponding registered parser, which can use `JSONDecoder` to decode the
specific configuration struct (e.g., `ServiceAccountCredentials` or
`UserCredentials`).

## 3. Quota and Scopes Configuration

The `CredentialsConfiguration` enum natively handles overrides using associated
values on the `.adc` case without breaking existing usage. See
[Credentials.swift](../Sources/GoogleCloudAuth/Credentials.swift) for the enum
implementation.

-   `quotaProjectID`: Manually sets the quota project ID. This is overridden by
    the `GOOGLE_CLOUD_QUOTA_PROJECT` environment variable if present.
-   `universeDomain`: Sets the expected universe domain.
-   `scopes`: Adds specific scopes to the credentials.

## 4. Token Caching

To prevent thundering herd problems and ensure optimal performance during token
refreshes, token caching will be the direct responsibility of the underlying
`CredentialsProvider` implementations (e.g., `ServiceAccountCredentials`,
`MDSCredentials`). Rather than relying on a generic, centralized wrapper, each
provider will encapsulate its own caching logic, allowing for provider-specific
optimization and behavior.

# Implementation details

-   `packages/swift-google-auth/Sources/GoogleCloudAuth/ADCPath.swift`: Handles AIP-4110 path
    precedence.
-   `packages/swift-google-auth/Sources/GoogleCloudAuth/ADCResolver.swift`: Reads raw JSON
    file data from the resolved path.
-   `packages/swift-google-auth/Sources/GoogleCloudAuth/ADC.swift`: Orchestrates JSON
    decoding, quota project injection, and registry delegation.
-   `packages/swift-google-auth/Sources/GoogleCloudAuth/CredentialParserRegistry.swift`:
    Contains the `CredentialParserRegistry` class and `CredentialSourceParser`
    protocol.
-   `packages/swift-google-auth/Sources/GoogleCloudAuth/Credentials.swift`: Maintains the
    public `CredentialsConfiguration` enum.

# Testing Parity

The native Swift implementation will map directly to the established test
suites:

### Unit Tests (`packages/swift-google-auth/Tests/ADCResolverTests.swift` & `ADCPathTests.swift`)

-   **Path Resolution**: `adc_well_known_path_windows`,
    `adc_well_known_path_posix`, `adc_path_from_env`
-   **Loading Behavior**:
    -   `load_adc_no_file_at_env_is_error`
    -   `load_adc_no_well_known_path_fallback_to_mds`
    -   `load_adc_success`
-   **Quota Project Override**:
    `create_access_token_credentials_fallback_to_mds_with_quota_project_override`

# Alternatives considered

**Alternative 1: Strong Codable Types for ADC (`JSONDecoder`)** We considered
using a single `Decodable` struct with optional fields for every possible
credential type. We went with weak JSON parsing (`JSONSerialization`) followed
by delegated decoding because it keeps the core resolver completely decoupled
from the specific config requirements of concrete credential providers.

**Alternative 2: Synchronous File I/O vs Asynchronous** We considered making the
ADC file loading fully asynchronous (`async`/`await` for reading from the
filesystem). We chose to use synchronous file loading (e.g. `Data(contentsOf:)`)
for the initial application bootstrap, as ADC resolution typically happens
exactly once during client initialization, and the complexity overhead of an
async boot sequence provides negligible performance benefits in this context.

# Risks and Mitigation Strategies

-   **Risk**: Breaking changes in generated client libraries that depend on the
    existing `Credentials` API. **Mitigation**: We will ensure the `Credentials`
    public API remains identical, preserving standard initializers and
    `AuthHeaders` returning formats.
-   **Risk**: Concurrency issues and data races when registering parsers.
    **Mitigation**: Using `Synchronization.Mutex` inside a `Sendable` `final
    class` guarantees thread-safe registration and resolution across
    asynchronous tasks.

# Corpus of information

-   [AIP-4110: Application Default Credentials](https://google.aip.dev/auth/4110)
-   `google-cloud-swift` mono-repo structure
