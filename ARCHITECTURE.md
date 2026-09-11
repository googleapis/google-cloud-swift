# Architecture Guide

This document describes the high-level architecture of the Google Cloud Swift
Client libraries. Its main audience is developers and contributors making
changes and additions to these libraries. If you want to familiarize yourself
with the code in the `google-cloud-swift` project, you are at the right place.

While we expect users of the libraries may find this document useful, this
document does not change or define the public API. You can use this document to
understand how things work, or to troubleshoot problems. You should not depend
on the implementation details described here to write your application. Only the
public API is stable; the rest is subject to change without notice.

## What these libraries do

The goal of the libraries is to provide idiomatic Swift libraries to access
services in [Google Cloud](https://cloud.google.com). All services are in scope.
As of 2026, we have over 200 client packages in `generated/`, covering most
Google Cloud services, alongside foundational handwritten packages in `pkgs/`
(such as authentication, GAX, well-known types, and Cloud Storage). The APIs are
not stable; they are **not** ready for use in production code.

What do we mean by idiomatic? We mean that Swift developers will find the APIs
familiar, or "natural", that these APIs will fit well with the rest of the Swift
ecosystem (particularly Swift 6 strict concurrency, async/await, and Swift
Package Manager), and that very few new "concepts" are needed to understand how
to use these libraries.

More specifically, the functionality offered by these libraries includes:

- Serialize and deserialize requests and responses: application developers
  spend more time writing application logic and less time dealing with message
  formatting.
- All RPCs are asynchronous and use Swift structured concurrency
  (`async`/`await`). The clients do not own threads or dispatch queues and rely
  on Swift's cooperative thread pool runtime for scheduling. All public types
  are `Sendable`.
- It is not possible to start an RPC without providing the parameters needed to
  format the request (with [some limitations](#what-these-libraries-do-not-do)).
- Optional parameters can be provided as needed; requests are constructed with
  sensible defaults and updated fluently using closure-based chaining
  (`.with { ... }`).
- The libraries convert pagination APIs into asynchronous streams conforming to
  `AsyncSequence`.
- The libraries convert long-running operations into pollable operations
  (`PollableOperation`) that allow callers to asynchronously `wait()` for the
  final outcome.
- Applications can define retry policies, exponential backoff, and retry
  throttling for all RPCs in a client and override them for specific requests.
- The libraries integrate with `swift-log` (`Logging.Logger`) to log requests,
  responses, and retries to help application developers troubleshoot their code.

## The structure of a client

A client is a Swift `final class` (such as `SecretManagerServiceClient`) that
conforms to a service protocol (such as `Clients.SecretManagerServiceProtocol`)
and `Sendable`.

Associated with each client, there is an internal `Stub` protocol (for example,
`Clients.SecretManagerServiceStub`). Each client wraps an `inner` object
conforming to this stub. Neither the `Stub` protocol nor its implementations are
public; they are internal implementation details and not part of the public
API.

During initialization, the client constructs a decorator pipeline around the
underlying transport:

- **Transport stub:** Serializes the request into HTTP/JSON or gRPC, attaches
  authorization headers and client metadata headers, executes the network call
  via the transport implementation, and deserializes the response or maps
  transport errors into `RequestError`.
- **Retry decorator:** Wraps the stub with a retry loop (`RetryLoop`),
  evaluating whether errors are transient using configured retry policies
  (`RetryPolicy`), computing exponential backoff delays, and consulting retry
  throttlers or circuit breakers.
- **Logging decorator:** If a `Logger` is configured in `ClientOptions`,
  intercepts requests and responses to emit structured log entries at
  appropriate log levels.

```swift
// Conceptual client initialization pipeline
var inner: any Clients.SecretManagerServiceStub =
    try Clients.SecretManagerServiceTransport(options)
inner = Clients.SecretManagerServiceRetry(inner, options: options)
if let logger = options.logger {
    inner = Clients.SecretManagerServiceLogging(inner, logger: logger)
}
self.inner = inner
```

### Mocking and testing

For unit testing, application code can depend on the service protocol
(`Clients.<Service>Protocol`) rather than the concrete client class.

In Swift, adding new methods to a protocol can cause source breaks for third-party
implementations. To prevent future Google Cloud service updates from breaking
user mocks, each service protocol provides default extension implementations
that throw `RequestError.unimplemented`. Applications can mock only the RPC
methods required for their test cases.

## Request configuration and the `.with` idiom

Unlike languages that use builder objects or sprawling parameter lists, Swift
client libraries use strongly-typed request structs conforming to `Codable`,
`Equatable`, and `Sendable`.

Each request struct provides a parameterless `init()` alongside a `.with`
mutation helper:

```swift
public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
}
```

This pattern enables clean, declarative initialization of nested request
structures:

```swift
let secret = try await client.createSecret(
    request: CreateSecretRequest().with {
        $0.parent = "projects/my-project"
        $0.secretId = "database-password"
        $0.secret = Secret().with { secret in
            secret.replication = Replication().with { replication in
                replication.automatic = Replication.Automatic()
            }
        }
    },
    options: RequestOptions().with {
        $0.attemptTimeout = .seconds(10)
    }
)
```

## Pagination

Google Cloud APIs that return lists of resources typically implement cursor-based
pagination (following [AIP-158](https://google.aip.dev/158)). Clients provide
two ways to call paginated APIs:

- **Single-page RPC:** Calling `listSecrets(request:options:) async throws -> ListSecretsResponse`
  fetches a single page of results and includes the `nextPageToken`.
- **Item stream:** Calling `listSecrets(byItem:options:) throws -> any AsyncSequence<Secret, Swift.Error>`
  returns an asynchronous sequence that yields individual items across pages.

```swift
// Iterate over items directly across all pages
let stream = try client.listSecrets(
    byItem: .init().with { $0.parent = "projects/my-project" }
)
for try await secret in stream {
    print("Found secret: \(secret.name)")
}
```

The underlying sequence (`GoogleCloudGax.PaginatedResponseSequence`) lazily
fetches new pages using the previous response's `nextPageToken`, buffers
retrieved elements, and handles intermediate empty pages as permitted by
AIP-158.

## Long-Running Operations (LRO)

Some operations in Google Cloud take minutes or hours to complete (such as
deploying a Cloud Function or provisioning a database). These APIs return an
`Operation` resource (per [AIP-151](https://google.aip.dev/151)).

Generated clients provide two interfaces for long-running operations:

- **Raw Operation RPC:** Calling `createFunction(request:options:) async throws -> GoogleLongRunning.Operation`
  issues the initial RPC and immediately returns the unpolled `Operation` token.
  Callers managing custom state machines or external scheduling can inspect the
  initial metadata and poll manually.
- **Pollable Operation:** Calling `createFunction(withPolling:options:) async throws -> any PollableOperation<Function>`
  initiates the operation and returns a `PollableOperation` handle.

```swift
// Initiate the operation and await completion
let operation = try await client.createFunction(withPolling: request)
let function = try await operation.wait()
```

When `wait()` is called, the poller queries the operation status periodically
using a backoff policy (`defaultPollingBackoffPolicy`), retries transient polling
failures according to a polling error policy (`defaultPollingErrorPolicy`), and
suspends execution non-blockingly via `Task.sleep(for:)` until the operation
reaches completion.

## Method overloads and convenience helpers

In addition to the primary RPC methods that accept a complete request struct and
`RequestOptions`, generated clients provide convenience overloads for common use
cases:

- **Omitting `RequestOptions`:** Most calls rely on client-level configuration
  defaults. Overloads allow omitting the `options:` argument, defaulting to
  `RequestOptions()`:

  ```swift
  let secret = try await client.getSecret(request: request)
  ```

- **Positional field arguments:** For common operations where only a few fields
  (such as a resource `name` or `parent`) are required, clients provide overloads
  that accept individual scalar arguments directly, constructing the underlying
  request struct internally:

  ```swift
  // Fetch a secret by name directly without instantiating GetSecretRequest
  let secret = try await client.getSecret(name: "projects/my-project/secrets/my-secret")

  // Stream items using just the parent resource name
  for try await secret in try client.listSecrets(parent: "projects/my-project") {
      print("Found secret: \(secret.name)")
  }

  // Create a secret using positional required arguments
  let newSecret = try await client.createSecret(
      parent: "projects/my-project",
      secretId: "database-password",
      secret: Secret().with { ... }
  )
  ```

These convenience overloads keep common operations concise while retaining the
full request struct methods for complex calls with multiple optional fields.

## Major design decisions

This section explains the rationale behind some of the major design choices in
the libraries.

### Swift 6 and strict concurrency

The entire codebase is written for Swift 6 with full structured concurrency:

- Every public type conforms to `Sendable`.
- All asynchronous calls use `async`/`await` and structured concurrency (`Task`,
  `AsyncSequence`).
- No public APIs expose legacy completion handlers, dispatch queues, or manual
  thread locks.
- We want to compile all packages under Swift 6 with `-warnings-as-errors`
  enforced in CI. We need to suppress some warnings about deprecated enum cases
  and fields first.

### REST/JSON over gRPC for most services

The generated client libraries communicate with Google Cloud services using
REST/JSON over HTTP by default. This choice offers several benefits:

- **Binary size:** REST/JSON avoids linking large transport stacks for simple
  request-response workloads.
- **Interoperability and debugging:** Standard HTTP/JSON payloads can be easily
  inspected, debugged, and routed through existing corporate proxies and
  observability tools.

For services that require gRPC (such as the Cloud Storage Control plane or
high-performance streaming APIs), `GoogleCloudGaxGRPC` provides a dedicated gRPC
transport layer.

### Hidden HTTP client

The HTTP transport in `GoogleCloudGax` uses `AsyncHTTPClient` (from the Swift on
Server ecosystem) internally via `_HTTPClientHolder`. However, this dependency
is entirely encapsulated and never exposed in public APIs:

- The client manages connection lifecycle and background shutdown automatically
  in `deinit`.
- Applications do not configure or interact directly with `AsyncHTTPClient` types.
- Encapsulating the transport allows the SDK to optimize, update, or replace the
  underlying HTTP engine in the future without breaking user code.

### Package granularity and SPM monorepo

Each Google Cloud service and version has its own Swift package (for example,
`swift-google-cloud-secretmanager-v1` and `swift-google-iam-v1`):

- **Fine-grained dependencies:** Applications only link and compile the services
  they use, keeping build times and executable sizes minimal.
- **Independent versioning:** Each package can be released, tagged, and versioned
  independently.
- **Remote dependencies by default:** In `Package.swift`, packages declare
  dependencies on remote GitHub repositories (`https://github.com/googleapis/...`).
  During local development, developer workflows (`swift package edit`,
  `ci/test.sh`, and `ci/package-dependencies.sh`) temporarily override remote
  references with local monorepo checkouts.

### Handwritten vs. generated clients

Most Google Cloud APIs are straightforward request-response or streaming
interfaces, which are fully served by auto-generated clients.

However, certain services involve complex client-side protocols that cannot be
expressed solely through code generation. For these services, we provide
hand-written packages:

- `swift-google-cloud-storage`: Provides high-level abstractions for Google Cloud
  Storage. The hand-written client manages chunked resumable uploads, transparent
  download resumption across network disconnections (`ResumeLoop`), and
  streaming checksum validation (CRC32C and MD5).
- Control plane operations for Storage (such as bucket, folder, and IAM
  management) delegate directly to the generated client
  (`Clients.StorageControlServiceClient` and `Clients.StorageServiceClient`) to
  minimize handwritten code maintenance.

### Custom ProtoJSON serialization

Instead of relying solely on `Foundation.JSONDecoder` and `Foundation.JSONEncoder`,
the libraries implement custom `ProtoJSONDecoder` and `ProtoJSONEncoder` in
`swift-google-wkt`.

This implementation is necessary to comply with the Google ProtoJSON
specification (AIP-160), including:

- **64-bit integers:** Encoded as decimal strings in JSON to avoid precision loss
  in IEEE 754 floating-point parsers.
- **Well-Known Types:** Custom representations for `Timestamp` (RFC 3339 string
  with trailing `Z`), `Duration` (string with trailing `s`), and `FieldMask`
  (comma-separated camelCase string).
- **Enum representations:** Supporting both integer and string variants.
- **Wrapper types:** Unwrapping `StringValue`, `Int64Value`, `BoolValue`, and
  related wrappers into native scalar JSON types.

Where interoperability with `swift-protobuf` is required, the
`GoogleCloudWKTConvert` target provides explicit conversions between WKT types
and protobuf messages.

### Separate namespace for fields vs. options

Request parameters belong to the request struct (e.g. `CreateSecretRequest`),
while execution settings belong to `ClientOptions` (client-wide) or
`RequestOptions` (per-call).

Keeping execution options (timeouts, retry policies, backoff parameters, quota
project IDs) distinct from request fields prevents naming collisions when
services introduce new fields with names like `timeout` or `options`.

### Authentication architecture (`swift-google-auth`)

The authentication library provides the `Credentials` struct, which acts as the
primary entry point for authenticating requests.

Features include:

- **Application Default Credentials (ADC):** Automatically resolves credentials
  from the environment via:
  1. The `GOOGLE_APPLICATION_CREDENTIALS` file.
  2. The Google Cloud CLI default credentials file.
  3. The Compute Engine, GKE, Cloud Run, or Cloud Functions Metadata Service (MDS).
- **Multiple credential flows:** Supports explicit service account keys (with
  local JWS signing), authorized user credentials, Workforce Identity
  Federation (external account STS token exchange), and API keys.
- **Multi-header support:** Authentication providers return `AuthHeaders`
  (`[(String, String)]`), allowing credentials that require multiple headers,
  duplicate header keys, or non-token schemes.
- **Token caching:** Credentials automatically cache tokens in memory (`TokenCache`)
  and refresh them proactively before expiration.

### Modern testing with Swift Testing

All tests in `google-cloud-swift` use Apple's modern Swift Testing framework
(`import Testing`, `@Suite`, `@Test`, `#expect`), rather than legacy `XCTest`.
Tests are organized into suites named after the struct or class under test.

## What these libraries do not do

### No client-side validation

The client libraries validate requests only to the extent necessary to format a
valid HTTP request (such as ensuring that required URL path parameters are
non-empty). No attempt is made to validate request contents, resource formats,
or parameter completeness before sending.

Client-side validation cannot replace server-side checks in distributed systems:

- **Authority:** The server remains the ultimate authority for authorization,
  quota, and business logic.
- **Complex dependencies:** Many Google Cloud parameters are conditionally
  required based on the values of other fields or server-side resource state.
  Replicating this logic on the client adds brittle complexity.
- **Forward compatibility:** When a required parameter becomes optional on the
  service, client-side validation would unnecessarily block valid requests until
  a new version of the client library is released.

### Localize error messages

Error messages from Google Cloud services are delivered without alteration. If
the remote service localizes its error messages, the client preserves those
localized messages in the returned `RequestError`.

### Global mutable state

The libraries do not maintain ambient global configuration, default client
singletons, or global thread pools. Every client instance is explicitly created
and configured with its own options and credentials.

## How is this code created?

Most client libraries are automatically generated from Protobuf service
specifications and Google Discovery documents using Google's `librarian` tool
(specifically the `sidekick` Swift generator).

The generation process is driven by `librarian.yaml`, which specifies source
commits for `googleapis/googleapis` and `protobuf`, tool versions, and package
metadata. Generated code lives in `generated/` and is never edited manually.

## Where is the code?

The repository is structured to clearly separate handwritten core libraries from
auto-generated client libraries:

- `pkgs/swift-google-auth`: Authentication library (ADC, service account keys,
  workforce pools, metadata server, token caching).
- `pkgs/swift-google-gax`: Google API Extensions (HTTP transport, gRPC transport,
  retry loops, backoff policies, throttlers, pagination, LRO pollers, and
  request options).
- `pkgs/swift-google-wkt`: Google Well-Known Types, ProtoJSON encoder/decoder,
  and conversions to `swift-protobuf`.
- `pkgs/swift-google-cloud-storage`: Hand-written client for Google Cloud
  Storage (uploads, downloads, resumption loops, and checksums).
- `generated/*`: Generated client libraries and shared schema packages (e.g.
  Secret Manager, Compute, KMS, IAM, Location).
- `Package.swift`: Root package manifest linking local packages for development
  and CI verification.
- `ci/*`: Continuous integration scripts for linting (`ci/lint.sh`), testing
  (`ci/test.sh`), and dependency management (`ci/package-dependencies.sh`).
- `doc/*`: Contributor documentation, how-to guides, and architectural designs.
- `guide/*`: Tutorials and code snippets.
