# Update IAM policies using optimistic concurrency control

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Getting started with Swift]: <doc:quickstart>
[Secret Manager API]: https://cloud.google.com/secret-manager
[service quickstart]: https://cloud.google.com/secret-manager/docs/quickstart
[IAM Conditions]: https://cloud.google.com/iam/docs/conditions-overview
[IAM etag]: https://cloud.google.com/iam/docs/policies#etag
[Override the default retry policies]: <doc:override-retry-policy>
[exponential backoff]: https://en.wikipedia.org/wiki/Exponential_backoff
[optimistic concurrency control]: https://en.wikipedia.org/wiki/Optimistic_concurrency_control
[swift-google-iam-v1]: https://github.com/googleapis/swift-google-iam-v1
[swift-google-gax]: https://github.com/googleapis/swift-google-gax

Modifying Identity and Access Management (IAM) policies across Google Cloud
services requires a read-modify-write cycle guarded by optimistic concurrency
control (OCC). This guide shows you how to safely update an IAM policy using an
OCC retry loop in Swift.

## Prerequisites

This guide uses the [Secret Manager API] as an example, though the same pattern
applies to any Google Cloud service that exposes `getIamPolicy` and
`setIamPolicy`. To enable the Secret Manager API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

### Add required dependencies

In addition to the service client library (`swift-google-cloud-secretmanager-v1`),
updating IAM policies and handling OCC conflicts requires types from
[`swift-google-iam-v1`][swift-google-iam-v1] (`GoogleIAMV1`) and
[`swift-google-gax`][swift-google-gax] (`GoogleGax`):

1. Add the packages to your `Package.swift` dependencies:
   ```bash
   swift package add-dependency \
     https://github.com/googleapis/swift-google-iam-v1.git --from 0.5.0
   swift package add-dependency \
     https://github.com/googleapis/swift-google-gax.git --from 0.5.0
   ```
2. Add the `GoogleIAMV1` and `GoogleGax` modules to your target dependencies:
   ```bash
   # Replace MyProgram with the name of your target
   swift package add-target-dependency \
     GoogleIAMV1 MyProgram --package swift-google-iam-v1
   swift package add-target-dependency \
     GoogleGax MyProgram --package swift-google-gax
   ```

## Why IAM policy updates require an OCC loop

Google Cloud IAM policies are updated as a whole document rather than by
patching individual role bindings on the server. To prevent concurrent writers
from overwriting each other's changes, IAM uses
[optimistic concurrency control] across three steps:

1. **Read**: Call `getIamPolicy` to fetch the current `Policy`, which includes an
   [`etag`][IAM etag] identifying the exact version of the policy stored on the
   server.
2. **Modify**: Update the `bindings` array on the returned `Policy` in memory
   while preserving its `etag`.
3. **Write**: Call `setIamPolicy` with the modified `Policy`. The server
   compares the `etag` in your request against the current policy's `etag`.

If another process modifies the policy between your `getIamPolicy` and
`setIamPolicy` calls, the `etag` no longer matches and the server rejects the
write with `RequestError.service(let serviceError)` where
`serviceError.code == .aborted` (HTTP `409 Conflict`).

The client library's [built-in retry policy][Override the default retry policies]
cannot resolve this conflict automatically: repeating the same `setIamPolicy`
request with the stale `etag` will always fail. Instead, your application must
catch the `.aborted` error, wait using [exponential backoff] with jitter, and
repeat the entire read-modify-write cycle so that your changes are applied to the
newly updated policy.

> Important: Always request policy version `3` (`requestedPolicyVersion = 3`) in
> `getIamPolicy` and preserve the `etag` in `setIamPolicy`. If a policy uses
> [IAM Conditions] and you omit the `etag`, IAM may overwrite a version `3`
> policy with a version `1` policy and drop existing conditions. If you add or
> modify conditional role bindings, also set `policy.version = 3` before calling
> `setIamPolicy`.

## Write an OCC read-modify-write loop

1. Add the imports needed for the service client, `GoogleGax`, and `GoogleIAMV1`:
   @Snippet(path: "OptimisticConcurrencyControlIAM", slice: "imports")
2. Define a function that receives the target resource identifiers, the IAM
   `role` (for example, `"roles/secretmanager.secretAccessor"`), and the
   `member` principal (for example, `"user:alice@example.com"`):
   @Snippet(path: "OptimisticConcurrencyControlIAM", slice: "function")
3. Initialize the client and configure an `ExponentialBackoff` policy to compute
   jittered delays between conflicted attempts:
   @Snippet(path: "OptimisticConcurrencyControlIAM", slice: "client")
4. Run a bounded loop that reads the current policy, applies the binding change,
   and writes the updated policy back. If `setIamPolicy` fails with `.aborted`,
   sleep for the backoff delay and retry the cycle from `getIamPolicy`:
   @Snippet(path: "OptimisticConcurrencyControlIAM", slice: "loop")

## Complete code

@Snippet(path: "OptimisticConcurrencyControlIAM")

## Next steps

* [Override the default retry policies](<doc:override-retry-policy>) describes
  how to change how the Swift client libraries retry failed RPC requests.
* [Update a resource using a field mask](<doc:update-resource>) describes how to
  perform partial resource updates using field masks and `etag` values.
* [Override the default authentication credentials](<doc:override-credentials>)
  describes how to configure custom credentials.
* [Enable logging](<doc:enable-logging>) describes how to enable debug logging
  to troubleshoot requests and responses.
