# ```GoogleCloudGax```

The GAX library provides protocols, types and functions to configure the Coogle
Cloud Client libraries for Swift.

## Overview

A default-initialized client is expected to work in most environments. However,
specific deployments may need to tweak the retry loop parameters, the
authentication credentials source, the target endpoint, etc.

## Client initialization

The main type to configure clients is ``ClientOptions``. Use this type to
override the default endpoint, the default credentials, the default retry loop
policies, or to enable request and response logging.

## Request options

Sometimes a single client is used to make requests with different retry loop
parameters or different timeouts. For example, it may be known that the
operation takes longer for certain inputs. Use ``RequestOptions`` to change the
configuration of a single request.

## Request errors

The client libraries throw a ``RequestError`` when an operation fails. The error
type is an enum, each `case` providing information about exactly what failed.
When the error is returned by the service the `.serviceError` case contains a
``ServiceError`` which often includes more details about the cause of the
problem.

## Retry loop control

There are three orthogonal controls for the retry loop:

- Types conforming to the ``RetryPolicy`` protocol control what errors are
  retryable. ``BaseRetryPolicy`` works for most APIs. Remember to limit the
  number of attempts or the maximum time spent retrying using the
  ``RetryPolicy/withAttemptLimit(_:)`` and/or
  ``RetryPolicy/withTimeLimit(_:)``.
- Types conforming to the ``BackoffPolicy`` protocol determine how long the
  client waits before making a new attempt. The most common implementation is
  ``ExponentialBackoff``.
- Types conforming to the ``RetryThrottler`` protocol determine if a retry
  attempt should be suppressed. This is useful to prevent retry storms when even
  exponential backoff fails. The default throttler is ``AdaptiveThrottler``
  which rejects a percentage of the retry attempts based on the prior success
  rate, some applications may prefer ``CircuitBreaker`` which suppresses all
  requests if the failure rate is too high.

## Polling loop control

Likewise, there are two orthogonal controls for the polling loop:

- Types conforming to the ``PollingErrorPolicy`` protocol control what polling
  errors are retryable (as opposed to stopping the loop).
  ``BasePollingErrorPolicy`` is a good default that works for most APIs.
  Remember to limit the number of attempts or the maximum time spent in the
  polling loop using ``PollingErrorPolicy/withAttemptLimit(_:)`` and/or
  ``PollingErrorPolicy/withTimeLimit(_:)``.
- Types conforming to the ``BackoffPolicy`` protocol (the same protocol used for
  retry loops) determine how long the polling loop waits before polling again.
  The most common implementation is ``ExponentialBackoff``.
