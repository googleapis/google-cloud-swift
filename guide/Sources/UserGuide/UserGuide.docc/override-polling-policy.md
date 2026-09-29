# Override the default polling policies

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Getting Started with Swift]: <doc:quickstart>
[long-running operation]: <doc:long-running-operations>
[AIP-151]: https://google.aip.dev/151
[AIP-194]: https://google.aip.dev/194
[Workflows API]: https://cloud.google.com/workflows
[service quickstart]: https://cloud.google.com/workflows/docs/create-workflow-gcloud
[exponential backoff]: https://en.wikipedia.org/wiki/Exponential_backoff

The Swift client libraries provide `*PollingUntilDone` methods to poll
long-running operations until they complete. Some applications may need to
change the default polling limits, the backoff intervals, and/or the type of
polling errors that abort the polling loop. This guide shows you how to
override the default settings in the client libraries.

## Prerequisites

This guide uses the [Workflows API]. To enable this API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

## The default behavior

Some Google Cloud APIs perform operations that take too long to finish in a
single request-response cycle ([AIP-151]). Instead of blocking, the service
starts a background task on the server and returns an operation object
immediately. When you call a `*PollingUntilDone` helper method, the client
starts the [long-running operation] and periodically polls the service to check
the operation's state until it finishes.

Each client is configured with two policies that together control how
long-running operations are polled:

* The *polling error policy* decides how long to keep polling an in-progress
  operation, and whether an error encountered while polling is transient or
  should stop the loop. By default it continues polling on [AIP-194] transient
  errors, `TOO_MANY_REQUESTS` errors, and I/O errors, stopping after 30
  minutes.
* The *polling backoff policy* decides how long to wait between polling
  attempts. By default it uses truncated [exponential backoff] without jitter,
  starting at one second and doubling up to a maximum of five minutes.

Polling errors are distinct from errors in the long-running operation itself. If
the operation fails on the server, polling completes and throws the operation's
error. In addition, each status request made during the polling loop is an
idempotent RPC and uses the client's retry policy before reporting an error to
the polling loop.

## Override the policies for a client

The policies set on the client apply to every long-running operation polled
through it.

1. Add the imports needed to use the client library:
   @Snippet(path: "OverridePollingPolicy", slice: "imports")
2. Write a function that receives the project ID, location, and workflow ID as
   parameters:
   @Snippet(path: "OverridePollingPolicy", slice: "function")
3. Initialize a client that stops polling sooner than the default. Use
   `BasePollingErrorPolicy.unbounded()` to keep the default notion of which
   polling errors are transient, and decorate it with `withTimeLimit(_:)` and
   `withAttemptLimit(_:)` to set the limits. Either limit may be used on its
   own:
   @Snippet(path: "OverridePollingPolicy", slice: "client")
4. Initialize a client that also waits differently between polling attempts:
   @Snippet(path: "OverridePollingPolicy", slice: "backoff")

The library offers other policies to build on: `AIP194.unbounded()` continues
polling only on `UNAVAILABLE` errors and can be decorated with
`continueOnIO()` and `continueOnTooManyRequests()`, while
`AlwaysPoll.unbounded()` continues polling on all errors. Applications with
requirements that none of these express can implement the `PollingErrorPolicy`
and `PollingBackoffPolicy` protocols.

## Override the policy for a single request

Every `*PollingUntilDone` method accepts a `RequestOptions` value. The polling
policies it sets apply to that operation only, and take precedence over the
client configuration.

@Snippet(path: "OverridePollingPolicy", slice: "request")

## Next steps

* [Override the default endpoint](<doc:override-endpoint>) describes how to change
  the default endpoint used by the Swift client libraries.
* [Override the default credentials](<doc:override-credentials>) describes how to
  change the default credentials used by the Swift client libraries.
* [Long-running operations](<doc:long-running-operations>) describes how to make
  API requests that use long-running operations.
* [Override the default retry policies](<doc:override-retry-policy>) describes how
  to change how the Swift client libraries retry failed requests.
