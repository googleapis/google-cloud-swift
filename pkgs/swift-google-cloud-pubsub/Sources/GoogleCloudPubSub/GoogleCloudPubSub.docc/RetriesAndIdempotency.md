# Retries and Idempotency Defaults

Understand how `GoogleCloudPubSub` retries transient RPC errors, honors custom
policies, and preserves ordering guarantees.

## Default Publish and Subscribe Retry Policy

``PubSubRetryPolicy`` implements `GoogleGax.RetryPolicy` and defaults to:

- **Retryable codes:** `DEADLINE_EXCEEDED`, `RESOURCE_EXHAUSTED`, `ABORTED`,
  `INTERNAL`, and `UNAVAILABLE`, plus transport `.io` failures (except local
  pre-transmission validation errors such as ``PubSubError/messageTooLarge(sizeBytes:limitBytes:)``
  or ``PubSubError/invalidUTF8Attribute(description:)``).
- **Permanent fast-fail:** Non-retryable codes such as `INVALID_ARGUMENT`,
  `PERMISSION_DENIED`, `NOT_FOUND`, and `UNAUTHENTICATED` fail after 1 attempt.
- **Time budget:** 600 seconds (`Duration.seconds(600)`) by default, paired with
  `GoogleGax.ExponentialBackoff` (`100ms` initial delay, `60s` max delay, `1.3`
  multiplier).

Pub/Sub `Publish`, `StreamingPull` reconnects, and `Pull` are treated as retryable
according to the active `GoogleGax.RetryPolicy`. Override per client or per
operation through `GoogleGax.RequestOptions.retryPolicy` and `backoffPolicy`.

## Ordered Publishing and Settlement Retries

- **Ordered batches (`orderingKey != ""`):** At most one batch is in flight per
  ordering key. Transient failures retry in FIFO order within `timeLimit`;
  permanent failures fail all queued messages for that key and pause the key
  until ``Publisher/resumePublishing(orderingKey:options:)`` is called.
- **Exactly-once settlements (`ackWithResult` / `nackWithResult`):** Transient
  RPC failures and transient per-ID `ErrorInfo` reasons (`TRANSIENT_FAILURE_*`)
  retry automatically. Innocent sibling ack IDs in mixed batches are split out
  and retried independently of permanently failed IDs.
- **Standard at-least-once leases:** Background `Acknowledge` and
  `ModifyAckDeadline` errors are isolated and logged without tearing down active
  `StreamingPull` sessions.
