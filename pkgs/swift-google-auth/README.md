# Google Cloud Client Libraries for Swift - Auth

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-auth%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/googleapis/swift-google-auth)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-auth%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/googleapis/swift-google-auth)

Google Cloud authentication and credentials management for Swift applications.

## Overview

`GoogleAuth` provides authentication credentials and token management for
calling Google Cloud APIs in Swift. It handles resolving, obtaining, and
refreshing credentials across diverse environments—from local developer
machines to Google Cloud production workloads.

Almost all calls into Google Cloud require [authentication]: verifying that the
caller is who they claim to be. Once received, the destination service verifies that the
caller is authorized to perform the specific requested operation.

### Principals, Credentials, and Tokens

Google Cloud manages access through several key concepts:

- **[Principals]**: An identity that can be granted access to Google Cloud resources.
  Principals can be human users (managed via Google Accounts or Cloud Identity),
  [Service Accounts] (identities for workloads, microservices, or compute resources),
  or external federated identities from third-party identity providers.
- **[Credentials]**: A digital object providing proof of identity, such as a
  service account's RSA private key, an authorized user's OAuth 2.0 refresh token,
  or an external identity provider assertion.
- **[Tokens]**: Short-lived, digitally signed access tokens asserting that the caller
  possesses valid credentials.

The authentication library exchanges credentials for time-limited access
tokens (or generates local self-signed JSON Web Signatures under [AIP-4111]). Tokens
are automatically refreshed before they expire and may be cached in memory.

### Application Default Credentials (ADC)

The primary entry point is the `Credentials` struct. A default-initialized
`Credentials` instance automatically resolves authentication using
[Application Default Credentials] (ADC), following the standard precedence order:

1. **Environment Variable**: The path pointed to by `GOOGLE_APPLICATION_CREDENTIALS`.
   This file can contain a service account key or authorized user credentials.
2. **Well-Known User Credentials**: The user credentials file created by running
   `gcloud auth application-default login` on a developer workstation.
3. **Google Cloud Runtime**: Attached service accounts discovered from the environment
   (such as Compute Engine, Google Kubernetes Engine, Cloud Run, or Cloud Functions
   metadata server).

## Features

- **Application Default Credentials (ADC)**: Automatically discovers credentials
  in Google Cloud environments (Compute Engine, Google Kubernetes Engine, Cloud
  Run, Cloud Functions) or from local development environments configured via
  `gcloud auth application-default login` or the `GOOGLE_APPLICATION_CREDENTIALS`
  environment variable.
- **Service Account Credentials**: Authenticate with service account private key
  JSON files, supporting both OAuth 2.0 scopes and self-signed JWT assertions
  with custom audiences ([AIP-4111](https://google.aip.dev/auth/4111)).
- **API Keys**: Lightweight credential support for Google Cloud APIs that accept
  API keys.
- **Authorized User Credentials**: Supports user credential files created by the
  `gcloud` CLI.
- **Workload / Workforce Identity Federation (WIF)**: Programmatic Security Token
  Service (STS) token exchange for federated identity providers.
- **Automatic Token Refresh & Caching**: Proactively and concurrently refreshes
  expiring OAuth access tokens and safely caches them in memory.
- **Universe Domain Support**: Supports custom and multi-tenant Google Cloud
  universe domains (defaults to `googleapis.com`).
- **Modern Swift Concurrency**: Built from the ground up for Swift 6 with strict
  concurrency (`Sendable`), using `NIOCore` and `AsyncHTTPClient`.

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-auth` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-auth.git --from 0.1.0
```

Then add `GoogleAuth` to your target's dependencies:

```bash
swift package add-target-dependency GoogleAuth <target-name> --package swift-google-auth
```

## Usage

### Application Default Credentials (ADC)

By default, initializing `Credentials` uses Application Default Credentials,
which automatically resolves the appropriate credential source for your runtime
environment:

```swift
import GoogleAuth

// Automatically resolves credentials from the environment (ADC)
let credentials = try Credentials()
let clientOptions = ClientOptions().with {
    $0.credentials = credentials
}
// Pass clientOptions when initializing a client:
// let client = try SecretManagerServiceClient(clientOptions)
```

### API Keys

For APIs that support API key authentication:

```swift
import GoogleAuth

let credentials = try Credentials(configuration: .apiKey("YOUR_API_KEY"))
```

### Service Account Key File

To authenticate explicitly using a Service Account JSON private key:

```swift
import Foundation
import GoogleAuth

let keyData = try Data(contentsOf: URL(fileURLWithPath: "/path/to/service-account.json"))
let credentials = try Credentials(
    configuration: .serviceAccount(
        keyJSON: keyData,
        accessSpecifier: .scopes(["https://www.googleapis.com/auth/cloud-platform"])
    )
)
```

### Customizing Application Default Credentials

You can customize ADC settings such as billing/quota project ID or scopes:

```swift
import GoogleAuth

let credentials = try Credentials(
    configuration: .adc(
        quotaProjectID: "my-quota-project-id",
        scopes: ["https://www.googleapis.com/auth/cloud-platform"]
    )
)
```

### Using with Google Cloud Client Libraries

Google Cloud Swift client libraries accept credentials via `ClientOptions`:

```swift
import GoogleAuth
import GoogleGax

let credentials = try Credentials(configuration: .apiKey("YOUR_API_KEY"))
let clientOptions = ClientOptions().with {
    $0.credentials = credentials
}
// Pass clientOptions when initializing a client:
// let client = try SecretManagerServiceClient(clientOptions)
```

## See Also

- [Google Cloud Authentication Overview](https://cloud.google.com/docs/authentication)
- [Application Default Credentials Guide](https://cloud.google.com/docs/authentication/application-default-credentials)
- [AIP-4111: Self-Signed JWTs](https://google.aip.dev/auth/4111)

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.

[authentication]: https://cloud.google.com/docs/authentication
[credentials]: https://cloud.google.com/docs/authentication#credentials
[principals]: https://cloud.google.com/iam/docs/overview#principals
[tokens]: https://cloud.google.com/docs/authentication#token
[Application Default Credentials]: https://cloud.google.com/docs/authentication/application-default-credentials
[Service Accounts]: https://cloud.google.com/iam/docs/service-account-overview
[AIP-4111]: https://google.aip.dev/auth/4111
