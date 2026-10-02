# Override the default polling policies

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Getting Started with Swift]: <doc:quickstart>
[Long-running operations]: <doc:long-running-operations>
[Override the default retry policies]: <doc:override-retry-policy>
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
[Getting Started with Swift].

## What is a Long-Running Operation (LRO)?

Some Google Cloud APIs perform operations that take too long to finish within a
single request-response cycle. Instead of blocking until the work finishes, these
APIs make an initial request that starts a background task on the server and
immediately returns an operation resource representing the in-progress work.

To get the final result, the client must periodically poll the service for the
operation's status. When you call a `*PollingUntilDone` helper method (see
[Long-running operations]), the client library runs this polling loop for you:

1. It sends the initial request to start the background task on the server.
2. While the operation is still in progress, it waits for a delay determined by
   the *polling backoff policy* and requests the latest status of the operation.
3. If a status check fails (for example, due to a transient network or service
   error), the *polling error policy* decides whether to continue polling or
   abort the loop. The policy also enforces overall time or attempt limits so
   polling does not run indefinitely.
4. Once the server reports that the operation has finished, the helper returns
   the completed resource—or throws the operation's error if the background task
   itself failed on the server.

## The default behavior

Each client is configured with default policies for this polling loop:

* The *polling error policy* continues polling on [AIP-194] transient errors,
  `TOO_MANY_REQUESTS` errors, and I/O errors, and stops polling after 30
  minutes.
* The *polling backoff policy* uses truncated [exponential backoff] without
  jitter, starting at one second and doubling between attempts up to a maximum
  of five minutes.

In addition, each status request made during the polling loop is an idempotent
RPC and uses the client's [retry policy][Override the default retry policies]
before reporting an error to the polling loop.

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
* [Enable logging](<doc:enable-logging>) describes how to enable debug logging
  to troubleshoot requests and responses.
