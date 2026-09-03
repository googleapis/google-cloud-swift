# Google Cloud Client Libraries for Swift - Auth

Google Cloud authentication and credentials management for Swift applications.

## Overview

`GoogleCloudAuth` provides authentication credentials and token management for
calling Google Cloud APIs in Swift. It handles resolving, obtaining, and
refreshing credentials across diverse environments—from local developer
machines to Google Cloud production workloads.

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

Add `swift-google-auth` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/googleapis/swift-google-auth.git", from: "0.1.0"),
]
```

Then add `GoogleCloudAuth` to your target dependencies:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "GoogleCloudAuth", package: "swift-google-auth"),
    ]
)
```

## Usage

### Application Default Credentials (ADC)

By default, initializing `Credentials` uses Application Default Credentials,
which automatically resolves the appropriate credential source for your runtime
environment:

```swift
import GoogleCloudAuth

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
import GoogleCloudAuth

let credentials = try Credentials(configuration: .apiKey("YOUR_API_KEY"))
```

### Service Account Key File

To authenticate explicitly using a Service Account JSON private key:

```swift
import Foundation
import GoogleCloudAuth

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
import GoogleCloudAuth

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
import GoogleCloudAuth
import GoogleCloudGax

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
