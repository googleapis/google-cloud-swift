# Google Cloud Client Libraries for Swift - GAX (Google API Extensions)

Core runtime, transport, and resilience infrastructure for Google Cloud client
libraries in Swift.

## Overview

GAX (Google API Extensions) provides the runtime protocols, networking
abstractions, and resilience utilities that power Google Cloud client libraries
for Swift.

While developers typically consume high-level, service-specific clients (such as
Google Cloud Storage or Secret Manager), GAX exposes the configuration types
and policies used to customize client behavior: retry policies, backoff
intervals, endpoint overrides, request throttling, structured error handling,
and long-running operations.

## Libraries & Products

This package provides two products:

- **`GoogleCloudGax`**: Core HTTP transport (using `AsyncHTTPClient` and
  `SwiftNIO`), client and request configuration options (`ClientOptions`,
  `RequestOptions`), retry and backoff loops, circuit breakers, adaptive
  throttlers, LRO polling policies, and error models.
- **`GoogleCloudGaxGRPC`**: gRPC transport client built on `grpc-swift-2` and
  `SwiftProtobuf` for services supporting or requiring gRPC.

## Features

- **Client Configuration (`ClientOptions`)**: Override default endpoints (e.g.
  for VPC Service Controls, regional/locational endpoints, or local emulators),
  authentication credentials, structured logging (via Apple's `swift-log`), and
  default retry/polling policies.
- **Per-Request Overrides (`RequestOptions`)**: Fine-tune retry behavior,
  timeouts, or custom headers on individual API calls.
- **Resilience & Retry Policies**:
  - `RetryPolicy` protocol with standard implementations including
    `BaseRetryPolicy` (handles transient I/O and idempotent errors per
    [AIP-194](https://google.aip.dev/194)), `AlwaysRetry`, and `NeverRetry`.
  - Decorators to cap retry attempts (`.withAttemptLimit(_:)`) and total elapsed
    time (`.withTimeLimit(_:)`).
  - Exponential backoff with randomized jitter (`ExponentialBackoff`) and linear
    backoff (`LinearBackoffPolicy`).
  - Overload protection via `AdaptiveThrottler` (stochastic retry suppression
    based on success/failure ratio) and `CircuitBreaker`.
- **Long-Running Operations (LRO)**: Polling error policies
  (`BasePollingErrorPolicy`) and backoff policies for tracking asynchronous,
  long-running operations until completion ([AIP-151](https://google.aip.dev/151)).
- **Strongly Typed Error Handling**: Comprehensive error model via
  `RequestError`, including service errors (`ServiceError`) with Google RPC
  status codes and status details (`StatusDetail`), HTTP transport errors
  (`HTTPDetails`), I/O errors, and exhausted retry deadlines.
- **Pagination**: Asynchronous sequences and helpers for paginated APIs.

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-gax` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-gax.git --from 0.1.0
```

Then add `GoogleCloudGax` to your target's dependencies:

```bash
swift package add-target-dependency GoogleCloudGax <target-name> --package swift-google-gax
```

If your service uses the gRPC transport, also add `GoogleCloudGaxGRPC`:

```bash
swift package add-target-dependency GoogleCloudGaxGRPC <target-name> --package swift-google-gax
```

## Usage

### Configuring ClientOptions

You can configure client-level options such as endpoints, credentials, retry
policies, and backoff parameters:

```swift
import Foundation
import GoogleCloudAuth
import GoogleCloudGax

let options = try ClientOptions().with {
    // Custom endpoint (e.g. for VPC-SC, private access, or emulators)
    $0.endpoint = "https://private.googleapis.com"

    // Override credentials
    $0.credentials = try Credentials()

    // Configure retry policy (max 5 attempts and max 60 seconds)
    $0.retryPolicy = BaseRetryPolicy()
        .withAttemptLimit(5)
        .withTimeLimit(.seconds(60))

    // Configure exponential backoff
    $0.backoffPolicy = try ExponentialBackoff(
        config: ExponentialBackoffConfig().with {
            $0.initialDelay = .milliseconds(200)
            $0.maximumDelay = .seconds(15)
            $0.scaling = 1.5
        }
    )
}
```

### Per-Request Overrides (RequestOptions)

When a specific request needs distinct handling, pass a `RequestOptions` instance:

```swift
import GoogleCloudGax

// Disable retries for a specific call
let requestOptions = RequestOptions().with {
    $0.retryPolicy = NeverRetry()
}
```

### Error Handling

When an operation fails, the client libraries throw a `RequestError`:

```swift
import GoogleCloudGax

do {
    // Perform API call using a client
} catch let error as RequestError {
    switch error {
    case .service(let serviceError):
        print("Service error: \(serviceError.code) - \(serviceError.message)")
        for detail in serviceError.details {
            print("Status detail: \(detail)")
        }
    case .http(let httpDetails):
        print("HTTP error with status code: \(httpDetails.http_status_code)")
    case .io(let ioError):
        print("Transport I/O error: \(ioError)")
    case .exhausted(let exhausted):
        print("Retries exhausted after \(exhausted.maximumDuration): \(exhausted.source)")
    default:
        print("Request failed: \(error)")
    }
}
```

## See Also

- [AIP-194: Retries](https://google.aip.dev/194)
- [AIP-151: Long-running Operations](https://google.aip.dev/151)
- [Google Cloud Client Libraries Overview](https://cloud.google.com/docs/authentication/client-libraries)

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
