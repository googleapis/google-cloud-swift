# Enable logging

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Getting Started with Swift]: <doc:quickstart>
[Secret Manager API]: https://cloud.google.com/secret-manager
[service quickstart]: https://cloud.google.com/secret-manager/docs/quickstart
[swift-log]: https://github.com/apple/swift-log
[logging backends]: https://www.swift.org/ecosystem/server-libraries/#logging

This guide describes how to enable debug logging in the Google Cloud client
libraries for Swift. Logging requests, responses, and errors to the console can
make it easier to troubleshoot applications.

> Warning: The logs described in this document are meant to be used for
> debugging applications. The logs include full request and response messages,
> which may include sensitive information. If you decide to enable these logs in
> production, consider the security and privacy implications first.

## Prerequisites

This guide uses the [Secret Manager API]. To enable this API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting Started with Swift].

## Enable logging

The Swift client libraries use Apple's [swift-log] package (`Logging` module) to
emit structured, contextual diagnostic messages. The `swift-log` package
separates the logging API (`Logger`) from the components that collect and format
log messages (`LogHandler`). By default, `swift-log` uses `StreamLogHandler` to
write log messages to standard error, and many other [logging backends] are
available.

1. Add the `swift-log` package and its `Logging` product to your target
   dependencies:
   ```bash
   swift package add-dependency \
     https://github.com/apple/swift-log.git --from 1.12.0
   swift package add-target-dependency \
     Logging MyProgram --package swift-log
   ```
2. Add the imports needed to use the client library and `Logging`:
   @Snippet(path: "EnableLogging", slice: "imports")
3. Write a function that receives the project ID as a parameter:
   @Snippet(path: "EnableLogging", slice: "function")
4. Create a `Logger` and set its `logLevel` to `.debug`. Because the client
   libraries emit request, response, and error logs at the `.debug` level, a
   logger with the default `.info` level will not output these messages:
   @Snippet(path: "EnableLogging", slice: "logger")
5. Initialize a client with logging enabled by setting `logger` on
   `ClientOptions`. Because `Logger` has value semantics, configure `logLevel`
   (and any custom metadata) before passing `logger` to `ClientOptions`;
   modifying `logger` afterward does not affect the client:
   @Snippet(path: "EnableLogging", slice: "client")
6. Use the client to send a request:
   @Snippet(path: "EnableLogging", slice: "call")

### Expected output

When the client executes an RPC, it logs an `enter` message before sending the
request, followed by either a `success` message with the response or an `error`
message if the call fails.

The output (formatted for readability) includes lines such as:

```text
2026-09-30T18:00:00+0000 debug com.example.my-app :
  gcp.artifact.id=google-cloud-secretmanager-v1
  gcp.client.service=secretmanager
  gcp.experimental.swift.client=SecretManagerService
  gcp.experimental.swift.method=listSecrets
  gcp.experimental.swift.request.id=550E8400-E29B-41D4-A716-446655440000
  [GoogleCloudSecretManagerV1] enter  : ListSecretsRequest(parent: "projects/my-project", ...) RequestOptions(...)
```

Followed by the response on success:

```text
2026-09-30T18:00:01+0000 debug com.example.my-app :
  gcp.artifact.id=google-cloud-secretmanager-v1
  gcp.client.service=secretmanager
  gcp.experimental.swift.client=SecretManagerService
  gcp.experimental.swift.method=listSecrets
  gcp.experimental.swift.request.id=550E8400-E29B-41D4-A716-446655440000
  [GoogleCloudSecretManagerV1] success: ListSecretsRequest(...) RequestOptions(...) ListSecretsResponse(...)
```

Or the error details if the request fails:

```text
2026-09-30T18:00:01+0000 debug com.example.my-app :
  gcp.artifact.id=google-cloud-secretmanager-v1
  gcp.client.service=secretmanager
  gcp.experimental.swift.client=SecretManagerService
  gcp.experimental.swift.method=listSecrets
  gcp.experimental.swift.request.id=550E8400-E29B-41D4-A716-446655440000
  [GoogleCloudSecretManagerV1] error  : ListSecretsRequest(...) RequestOptions(...) RequestError(...)
```

In addition to any metadata already attached to the `Logger` by your
application, the client automatically attaches structured metadata to each log
entry:

* `gcp.artifact.id`: The client library package identifier (for example,
  `google-cloud-secretmanager-v1`).
* `gcp.client.service`: The target Google Cloud service name (for example,
  `secretmanager`).
* `gcp.experimental.swift.client`: The name of the service client (for example,
  `SecretManagerService`).
* `gcp.experimental.swift.method`: The RPC method name being invoked (for
  example, `listSecrets`).
* `gcp.experimental.swift.request.id`: A unique UUID generated for each RPC
  invocation to correlate its `enter` and `success` or `error` log entries.

## Complete code

@Snippet(path: "EnableLogging")

## Next steps

* [Override the default endpoint](<doc:override-endpoint>) describes how to
  change the default endpoint used by the Swift client libraries.
* [Override the default credentials](<doc:override-credentials>) describes how to
  change the default credentials used by the Swift client libraries.
* [Override the default retry policies](<doc:override-retry-policy>) describes
  how to change how the Swift client libraries retry failed requests.
* [Override the default polling policies](<doc:override-polling-policy>)
  describes how to change how the Swift client libraries poll long-running
  operations.
