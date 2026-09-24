# Override the default retry policies

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Getting Started with Swift]: <doc:quickstart>
[AIP-194]: https://google.aip.dev/194
[idempotent]: https://en.wikipedia.org/wiki/Idempotence
[secret manager api]: https://cloud.google.com/secret-manager
[service quickstart]: https://cloud.google.com/secret-manager/docs/quickstart
[exponential backoff]: https://en.wikipedia.org/wiki/Exponential_backoff

The Swift client libraries automatically retry requests that fail with
transient errors. Some applications need different behavior: they may need to
fail faster, keep trying for longer, or retry requests that the libraries
consider unsafe to retry. This guide shows you how to override the defaults.

## Prerequisites

This guide uses the [Secret Manager API]. To enable this API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

## The default behavior

Each client is configured with three policies that together control retries:

* The *retry policy* decides whether an error is worth retrying, and when to
  give up. By default it retries [AIP-194] transient errors and I/O errors for
  [idempotent] requests only, stopping after 60 seconds or 10 attempts,
  whichever comes first.
* The *backoff policy* decides how long to wait between attempts. By default
  it uses [exponential backoff], starting at one second and doubling up to a
  maximum of one minute.
* The *retry throttler* stops the client from adding load to a service that
  is already failing. By default it is an adaptive throttler.

A request is only retried when it is safe to do so: either the request failed
before any data was sent, or the error is transient and the request is
idempotent. The client libraries use a conservative heuristic for idempotency:
only `GET` and `PUT` requests qualify.

## Override the policies for a client

The policies set on the client apply to every request made through it.

1. Add the imports needed to use the client library
   @Snippet(path: "OverrideRetryPolicy", slice: "imports")
2. Write a function that receives the project ID as a parameter
   @Snippet(path: "OverrideRetryPolicy", slice: "function")
3. Initialize a client that gives up sooner than the default. Use
   `BaseRetryPolicy.unbounded()` to keep the default notion of which errors are
   transient, and decorate it with `withTimeLimit(_:)` and `withAttemptLimit(_:)`
   to set the limits. Either limit may be used on its own:
   @Snippet(path: "OverrideRetryPolicy", slice: "client")
4. Initialize a client that also waits differently between attempts:
   @Snippet(path: "OverrideRetryPolicy", slice: "backoff")

The library offers other policies to build on: `AlwaysRetry.unbounded()` retries every
error, which is only safe when the service guarantees idempotency, and
`NeverRetry` disables retries. Applications with requirements that none of
these express can implement the `RetryPolicy` protocol.

## Override the policy for a single request

Every client method accepts a `RequestOptions` value. The policies it sets
apply to that request only, and take precedence over the client configuration.

@Snippet(path: "OverrideRetryPolicy", slice: "request")

## Retry a request the library considers unsafe

Because the idempotency heuristic is conservative, some requests are never
retried even though the service documents them as safe to repeat. A delete
request guarded by an etag is one example: repeating it cannot delete a
different version of the resource. Use `idempotency` to tell the library the
request is safe to retry:

@Snippet(path: "OverrideRetryPolicy", slice: "idempotency")

> Warning: Overriding the idempotency of a request that is not idempotent may
> apply the request more than once.

## Next steps

* [Override the default endpoint](override-endpoint.md) describes how to change
  the default endpoint used by the Swift client libraries.
* [Override the default credentials](override-credentials.md) describes how to
  change the default credentials used by the Swift client libraries.
* [Long-running operations](long-running-operations.md) describes how to make
  API requests that use long-running operations.
<!-- TODO(https://github.com/googleapis/google-cloud-swift/issues/145) - link the polling policy override guide -->
