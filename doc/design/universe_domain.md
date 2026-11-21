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

`GoogleAuth` exposes `Credentials.defaultUniverseDomain` (`"googleapis.com"`) and an asynchronous `universeDomain()` method on `Credentials` and `CredentialsProvider`. Universe domain strings are not pre-validated against hostname syntax rules at configuration time; malformed values fail when constructing and parsing endpoint URLs.

### Resolution Precedence

For Application Default Credentials (`ADC`), `CredentialsConfiguration.adc(_:)` via `ADCConfig` (and `ADC.resolve`) accepts an optional `universeDomain` override. When `universeDomain` is non-empty, `ADC` passes it as an override to the resolved credential provider.

### Provider Behavior

- **Anonymous and API Key Credentials**: `AnonymousCredentials` defaults to `Credentials.defaultUniverseDomain` and overrides `validateUniverseDomain(_:)` as a no-op so transport clients and impersonated credentials skip universe domain mismatch checks when anonymous credentials are used. `APIKeyCredentials` always returns `Credentials.defaultUniverseDomain` via the default `CredentialsProvider` extension.
- **Service Account, External Account, and Access Token Credentials**: `ServiceAccountCredentials` parses the optional `"universe_domain"` field from its JSON key (`ServiceAccountData`) and resolves `universeDomain ?? nonEmpty(key.universeDomain) ?? defaultUniverseDomain`. `ExternalAccountCredentials` resolves `nonEmpty(config.universeDomain) ?? defaultUniverseDomain` from `ExternalAccountConfig`, derives the default STS endpoint `https://sts.<universe_domain>/v1/token` when `config.tokenURL` is `nil` (rejecting malformed universe domains with `CredentialsError.parseError`), returns the resolved universe domain from `universeDomain()`, and accepts `//iam.<universe_domain>/locations/{location}/workforcePools/{pool}/providers/{provider}` workforce pool audiences when `workforcePoolUserProject` is set. `AccessTokenCredentials` resolves `nonEmpty(config.universeDomain) ?? defaultUniverseDomain` from `AccessTokenConfig` and returns it from `universeDomain()`.
- **User Account Credentials**: `UserCredentials` parses `"universe_domain"` from JSON and accepts an optional `universeDomain` parameter. In accordance with AIP-4116, if the resolved universe domain is anything other than `"googleapis.com"`, initialization fails immediately with `CredentialsError.notSupported`.
- **Impersonated Service Account Credentials**:
  - When initialized with a `targetPrincipal`, the IAM Credentials endpoint defaults to `https://iamcredentials.<universe>/v1/projects/-/serviceAccounts/<principal>:generateAccessToken`. When no explicit `universeDomain` override is set on `ImpersonatedCredentials`, `universeDomain()` delegates dynamically to `sourceCredentials.universeDomain()`, and `ImpersonatedTokenProvider` dynamically constructs the IAM Credentials endpoint from the source credential's resolved universe domain.
  - When initialized with an explicit `impersonationURLString` (such as from an `impersonated_service_account` JSON payload), any `iamcredentials.<universe>` hostname in the URL must match the effective universe domain (checked case-insensitively on the `iamcredentials.` prefix).
  - In `ImpersonatedServiceAccountParser`, conflicts between the `ADC` universe domain override, the outer JSON `"universe_domain"`, and any embedded `source_credentials["universe_domain"]` are rejected with `CredentialsError.parseError`.
  - Using `UserCredentials` as `sourceCredentials` for a non-default universe domain is rejected with `CredentialsError.notSupported`.
  - Before `ImpersonatedTokenProvider` calls `sourceCredentials.headers()`, it validates the source credentials against the target universe domain via `sourceCredentials.validateUniverseDomain(_:)`, throwing a non-retryable `CredentialsError.cannotFetchToken` wrapping `CredentialsError.parseError` on mismatch so source tokens are never sent to another universe's IAM endpoint.
- **Compute Engine Metadata Server (`MDSCredentials`)**:
  - When an explicit `universeDomain` override is supplied, `MDSCredentials.universeDomain()` returns that override without querying the metadata server.
  - Otherwise, `MDSAccessTokenProvider.fetchUniverseDomain()` sends a `GET /computeMetadata/v1/universe/universe-domain` request with `Metadata-Flavor: Google` and caches the resolved value in `MDSUniverseDomainCache`.
  - If the metadata server returns HTTP 404 or an empty/whitespace-only body, `fetchUniverseDomain()` returns `Credentials.defaultUniverseDomain`.
  - Non-retryable HTTP errors (such as 4xx status codes other than 404, 408, and 429) are cached as permanent errors in `MDSUniverseDomainCache`, while transient 5xx, 408, 429, and network errors propagate without poisoning the cache. Task cancellation (`CancellationError`) is never cached as a permanent error, and `MDSUniverseDomainCache` cancels any in-flight task on `deinit`.

## 2. HTTP Transport and Host Resolution

`GoogleGax` provides `ClientOptions.universeDomain` and centralizes endpoint and authority derivation in `_Host`.

### Host and Endpoint Derivation (`_Host`)

- `_Host.defaultUniverseDomain` is `"googleapis.com"`.
- `_Host.resolveUniverseDomain(options:environment:)` resolves the effective universe domain in precedence order: `options.universeDomain` (when non-empty), `GOOGLE_CLOUD_UNIVERSE_DOMAIN` (when non-empty), and `_Host.defaultUniverseDomain`.
- `_Host.endpoint(endpoint:defaultEndpoint:universeDomain:)` returns `endpoint` as-is when `endpoint` is non-nil. When `endpoint` is `nil` and `universeDomain` differs from `"googleapis.com"`, it replaces the `.googleapis.com` suffix on `defaultEndpoint`'s host with `.<universeDomain>` while preserving whether `defaultEndpoint` includes a scheme, throwing `ClientError.invalidEndpoint` if a valid URL cannot be constructed.
- `_Host.header(endpoint:defaultEndpoint:universeDomain:)` and `_Host.authority(endpoint:defaultEndpoint:universeDomain:)` derive the HTTP `Host` header and gRPC authority from the resolved endpoint: regional/locational endpoints and non-universe custom hosts preserve their custom host (and port), while default endpoints and non-regional universe hosts (such as VPC-SC `private.<universeDomain>` or `restricted.<universeDomain>`) use `<service>.<universeDomain>`.

### HTTP Client Universe Validation and Retry Policies

- `_HTTPClient` stores the client's resolved `universeDomain` (defaulting to `_Host.defaultUniverseDomain`).
- Before `_HTTPClient` calls `credentials.headers()` on a request, it calls `credentials.validateUniverseDomain(self.universeDomain)`. For non-anonymous credentials, `validateUniverseDomain(_:)` awaits `universeDomain()` and verifies that it equals the client's `universeDomain`, throwing `CredentialsError.parseError` on mismatch (which `_HTTPClient` wraps in `RequestError.io`).
- If `Task` cancellation (`CancellationError`) occurs while validating the universe domain or resolving authentication headers, `_HTTPClient` rethrows `CancellationError` directly rather than wrapping it in `RequestError.io`.
- `ContinueOnIO` (for both `RetryPolicy` and `PollingErrorPolicy`) inspects `RequestError.io(let underlying)` and returns `.permanent` when `underlying` is `CredentialsError` or `CancellationError`, ensuring credential and universe domain errors fail immediately on idempotent RPCs.

### Endpoint and Request URI Validation (`_HTTPClient`)

- `_HTTPClient.validateEndpoint(_:)` parses configured endpoints with `URLComponents(string:encodingInvalidCharacters: false)`, clears query items and resets the path, rejects userinfo and fragments, requires an `http` or `https` scheme, and requires a non-empty host without `/`, `\`, or percent-encoding outside bracketed IPv6 literals, throwing `ClientError.invalidEndpoint` on failure.
- `_HTTPClient.newRequest(uri:options:)` validates continuation and session URIs before calling `configureHeaders` (so `credentials.validateUniverseDomain(_:)` and `credentials.headers()` are never invoked for invalid URIs, throwing permanent `RequestError.badURL(uri)` instead). It rejects empty URIs, ports outside `1...65535`, userinfo, fragments, and paths that are empty, lack a leading `/`, contain `\`, or contain `.` or `..` segments; after validation, it encodes `;` as `%3B` in `percentEncodedQuery` and requires `components.url != nil`.
- Path-relative URIs (leading `/` without `//`, and with `scheme`, `host`, `encodedHost`, and `port` all `nil`) resolve `(scheme, encodedHost, port)` onto `self.baseURL`.
- Full URIs must use `http` or `https` with a non-empty host without `/`, `\`, or percent-encoding outside bracketed IPv6 literals, and must satisfy one of:
  - Matching `(baseScheme, baseEncodedHost, basePort)` or `(baseScheme, hostHeader, basePort | nil)` (supporting VPC-SC/PSC endpoints such as `https://private.<universeDomain>` with `Host: <service>.<universeDomain>`, as well as custom-port endpoints where the server reflects a portless `Host` header).
  - When `self.baseURL` uses `http` on a loopback host (`localhost`, `127.0.0.1`, `[::1]`), targeting either a local emulator host (`localhost`, `127.0.0.1`, `[::1]`, or `0.0.0.0` on any valid port) or `defaultServiceHosts` (`<service>.<universeDomain>` and `<service>.googleapis.com`).
  Accepted URIs normalize `(scheme, encodedHost, port)` onto `self.baseURL`.

## 3. gRPC Transport

`GoogleGaxGRPC._GRPCClient` applies the same universe domain resolution and credential validation rules as `_HTTPClient`:

- `_GRPCClient.init` resolves `universeDomain` via `_Host.resolveUniverseDomain`, derives the target endpoint and TLS/channel authority via `_Host.endpoint` and `_Host.authority`, and stores the effective `universeDomain`.
- In `_GRPCClient.execute`, before calling `credentials.headers()`, it calls `credentials.validateUniverseDomain(self.universeDomain)`. A mismatch throws `RequestError.io(CredentialsError.parseError(...))` before any RPC metadata is sent.

## 4. Cloud Storage Client

`GoogleCloudStorage` integrates universe domain support across both the handwritten REST data-plane veneer (`StorageClient`) and the generated gRPC control-plane client (`StorageControlClient`):

- `StorageClient.init(_:mock:)` resolves `universeDomain` and `endpoint` from `options.client` using `_Host.resolveUniverseDomain` and `_Host.endpoint` against `https://storage.googleapis.com` and forwards `universeDomain` and `defaultEndpoint` to `_HTTPClient` (which derives the `Host` header via `_Host.header`).
- `StorageClient` resumable upload status and chunk requests (`Location` headers from session initiation and `uploadId` values) pass through `_HTTPClient.newRequest(uri:options:)`, keeping VPC-SC and local HTTP loopback emulator sessions routed through the configured endpoint while surfacing invalid or mismatched session URIs as `WriteObjectError.requestError(.badURL(uri))`.
