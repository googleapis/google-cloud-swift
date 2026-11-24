# Universe Domain Support

## Intent

This design defines end-to-end support for Google Cloud universe domains across `GoogleAuth`, `GoogleGax`, `GoogleGaxGRPC`, and `GoogleCloudStorage`. It enables applications to authenticate and communicate with Trusted Partner Cloud and Sovereign Cloud environments while defaulting to `googleapis.com` for standard Google Cloud deployments.

### Goals

- Resolve universe domains consistently across all credential types, Application Default Credentials, and client configuration options in accordance with AIP-4110, AIP-4111, AIP-4115, AIP-4116, and AIP-4117.
- Construct default regional and global service endpoints dynamically from the configured universe domain when no custom endpoint override is supplied.
- Prevent cross-universe token exfiltration by verifying that the universe domain of the active credentials matches the universe domain configured on the transport client before attaching authentication headers.
- Ensure permanent credential and universe domain mismatch errors fail immediately without triggering transport retry or stream resume loops.

### Non-Goals

- Supporting user account (`authorized_user`) credentials in non-default universe domains.
- Modifying generated service client interfaces outside the shared `GoogleGax` and `GoogleGaxGRPC` transport layers.

## 1. Authentication and Credentials

`GoogleAuth` exposes `Credentials.defaultUniverseDomain` (`"googleapis.com"`), an asynchronous `universeDomain()` method on `Credentials`, and a shared `@_spi(GoogleCloudInternal)` value type `_UniverseDomain` that centralizes empty-string normalization, `GOOGLE_CLOUD_UNIVERSE_DOMAIN` precedence, universe-scoped HTTPS service URL construction, and exact case-sensitive `==` equality comparison. Universe domain strings are not pre-validated against hostname syntax rules at configuration time; malformed values fail when constructing and parsing endpoint URLs.

### Resolution Precedence

`GoogleAuth` resolves the effective universe domain in precedence order:
1. Explicit programmatic override on the credential configuration (`*Config.universeDomain`, when non-empty).
2. Embedded `"universe_domain"` field in the credential JSON payload (when present and non-empty), preserving credential-file vs. environment mismatch detection per AIP-4113.
3. `GOOGLE_CLOUD_UNIVERSE_DOMAIN` environment variable (when non-empty), except for `MDSCredentials`, which queries `/computeMetadata/v1/universe/universe-domain` unless an explicit programmatic override is configured.
4. `_UniverseDomain.default` (`"googleapis.com"`).

### Provider Behavior

- **Anonymous and API Key Credentials**: `AnonymousCredentials` defaults to `_UniverseDomain.default` and overrides `validateUniverseDomain(_:)` as a no-op so transport clients and impersonated credentials skip universe domain mismatch checks when anonymous credentials are used. `APIKeyCredentials` resolves `_UniverseDomain.resolve(configured: nil, environment: environment)`.
- **Service Account, External Account, and Access Token Credentials**: `ServiceAccountCredentials` parses the optional `"universe_domain"` field from its JSON key (`ServiceAccountData`) and resolves `_UniverseDomain.resolve(universeDomain, key.universeDomain, environment["GOOGLE_CLOUD_UNIVERSE_DOMAIN"])`. `ExternalAccountCredentials` resolves `_UniverseDomain.resolve(configured: config.universeDomain, environment: environment)` from `ExternalAccountConfig`, derives the default STS endpoint `https://sts.<universe_domain>/v1/token` via `_UniverseDomain.serviceURL(service:path:)` when `config.tokenURL` is `nil` (rejecting malformed universe domains with `CredentialsError.parseError`), returns the resolved universe domain from `universeDomain()`, and accepts `//iam.<universe_domain>/locations/{location}/workforcePools/{pool}/providers/{provider}` workforce pool audiences when `workforcePoolUserProject` is set. `AccessTokenCredentials` resolves `_UniverseDomain.resolve(configured: config.universeDomain, environment: environment)` from `AccessTokenConfig` and returns it from `universeDomain()`.
- **User Account Credentials**: `UserCredentials` parses `"universe_domain"` from JSON, accepts an optional `universeDomain` parameter, and falls back to `GOOGLE_CLOUD_UNIVERSE_DOMAIN`. In accordance with AIP-4116, `UserCredentials.validateUniverseDomain(_:)` fails initialization immediately with `CredentialsError.notSupported` if any resolved value differs from `"googleapis.com"`.
- **Impersonated Service Account Credentials**:
  - When initialized with a `targetPrincipal`, the target universe resolves `universeDomain` or `GOOGLE_CLOUD_UNIVERSE_DOMAIN` when set, deriving `https://iamcredentials.<universe>/v1/projects/-/serviceAccounts/<principal>:generateAccessToken` via `_UniverseDomain.serviceURL(service:path:)`. When neither an explicit `universeDomain` override nor `GOOGLE_CLOUD_UNIVERSE_DOMAIN` is set, `universeDomain()` delegates dynamically to `sourceCredentials.universeDomain()`, and `ImpersonatedTokenProvider` dynamically constructs the IAM Credentials endpoint from the source credential's resolved `_UniverseDomain`.
  - When initialized with an explicit `impersonationURLString` (such as from an `impersonated_service_account` JSON payload), any `iamcredentials.<universe>` hostname in the URL must match the effective `_UniverseDomain` (checked case-insensitively on the `iamcredentials.` prefix and case-sensitively on `<universe>`).
  - In `ImpersonatedServiceAccountParser`, conflicts between the `ADC` universe domain override, the outer JSON `"universe_domain"`, and any embedded `source_credentials["universe_domain"]` are rejected with `CredentialsError.parseError`.
  - Using `UserCredentials` as `sourceCredentials` for a non-default universe domain is rejected with `CredentialsError.notSupported`.
  - Before `ImpersonatedTokenProvider` calls `sourceCredentials.headers()`, it validates the source credentials against the target universe domain via `sourceCredentials.validateUniverseDomain(_:)`, throwing a non-retryable `CredentialsError.cannotFetchToken` wrapping `CredentialsError.parseError` on mismatch so source tokens are never sent to another universe's IAM endpoint.
- **Compute Engine Metadata Server (`MDSCredentials`)**:
  - When an explicit `universeDomain` override is supplied, `MDSCredentials.universeDomain()` returns that override without querying the metadata server.
  - Otherwise, `MDSAccessTokenProvider.fetchUniverseDomain()` sends a `GET /computeMetadata/v1/universe/universe-domain` request with `Metadata-Flavor: Google`, verifies that any 2xx response carries `Metadata-Flavor: Google` (ASCII case-insensitive across all present `Metadata-Flavor` headers) before reading the response body, and caches the resolved `_UniverseDomain` in `MDSUniverseDomainCache`.
  - If the metadata server returns HTTP 404 or a validated 2xx empty/whitespace-only body, `fetchUniverseDomain()` returns `_UniverseDomain.default`.
  - Non-retryable errors (such as 4xx status codes other than 404, 408, and 429, and missing/invalid `Metadata-Flavor` headers on 2xx responses) are cached as permanent errors in `MDSUniverseDomainCache`, while transient 5xx, 408, 429, and network errors propagate without poisoning the cache. Task cancellation (`CancellationError`) is never cached as a permanent error, and `MDSUniverseDomainCache` cancels any in-flight task on `deinit`.

## 2. HTTP Transport and Endpoint Resolution

`GoogleGax` provides `ClientOptions.universeDomain` and centralizes single-pass endpoint, HTTP `Host` header, and gRPC `:authority` derivation in `@_spi(GoogleCloudInternal) public struct _ResolvedEndpoint`.

### Endpoint, Host, and Authority Derivation (`_ResolvedEndpoint`)

- `_UniverseDomain.resolve(configured:environment:)` resolves the effective client universe domain in precedence order: `options.universeDomain` (when non-empty), `GOOGLE_CLOUD_UNIVERSE_DOMAIN` (when non-empty), and `_UniverseDomain.default` (`"googleapis.com"`).
- `_ResolvedEndpoint` validates `defaultEndpoint` and any `endpoint` override in a single pass, storing `baseURL`, `defaultEndpoint`, `service`, `universeDomain`, `hostHeader`, and `authority`:
  - When `endpoint` is `nil` and `universeDomain` differs from `"googleapis.com"`, it replaces the `.googleapis.com` suffix on `defaultEndpoint`'s host with `.<universeDomain>`, throwing `ClientError.invalidEndpoint` if a valid URL cannot be constructed.
  - HTTP transport requires explicit `http` or `https` schemes (`allowsBareHost: false`), while gRPC transport permits bare `host[:port]` endpoints (`allowsBareHost: true`, defaulting to `https`).
  - `hostHeader` and `authority` preserve regional (`<service>.<region>.rep.<universeDomain>`), locational (`<region>-<service>.<universeDomain>`), and non-universe custom hosts (and ports), while default endpoints and non-regional universe hosts (such as VPC-SC `private.<universeDomain>` or `restricted.<universeDomain>`) use `<service>.<effectiveUniverseDomain>`.

### HTTP Client Universe Validation and Retry Policies

- `_HTTPClient` stores the resolved `_ResolvedEndpoint` directly.
- Before `_HTTPClient` calls `credentials.headers()` on a request, it calls `credentials._validateUniverseDomain(self.endpoint.universeDomain)`. For non-anonymous credentials, `_validateUniverseDomain(_:)` checks exact case-sensitive `==` equality between the credentials' `_UniverseDomain` and the client's `universeDomain`, throwing `CredentialsError.parseError` on mismatch (which `_HTTPClient` wraps in `RequestError.io`).
- If `Task` cancellation (`CancellationError`) occurs while validating the universe domain or resolving authentication headers, `_HTTPClient` rethrows `CancellationError` directly rather than wrapping it in `RequestError.io`.
- `ContinueOnIO` (for both `RetryPolicy` and `PollingErrorPolicy`) inspects `RequestError.io(let underlying)` and returns `.permanent` when `underlying` is `CredentialsError` or `CancellationError`, ensuring credential and universe domain errors fail immediately on idempotent RPCs.

## 3. gRPC Transport

`GoogleGaxGRPC._GRPCClient` applies the same endpoint resolution and credential validation rules as `_HTTPClient`:

- `_GRPCClient.init` initializes `_ResolvedEndpoint` with `allowsBareHost: true`, configures `HTTP2ClientTransport.Posix` using `endpoint.host`, `endpoint.port`, `endpoint.isSecure`, and `endpoint.authority`, and stores `endpoint` directly.
- In `_GRPCClient.execute`, before calling `credentials.headers()`, it calls `credentials._validateUniverseDomain(self.endpoint.universeDomain)`. A mismatch throws `RequestError.io(CredentialsError.parseError(...))` before any RPC metadata is sent.

## 4. Cloud Storage Client

`GoogleCloudStorage` integrates universe domain support across both the handwritten REST data-plane veneer (`StorageClient`) and the generated gRPC control-plane client (`StorageControlClient`):

- `StorageClient.init` resolves `GoogleGax._ResolvedEndpoint` against `https://storage.googleapis.com` prior to connection pool creation and passes the resolved endpoint directly into `_HTTPClient`.
