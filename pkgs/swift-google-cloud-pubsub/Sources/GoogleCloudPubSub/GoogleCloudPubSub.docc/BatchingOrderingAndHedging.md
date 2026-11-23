# Batching, Ordering, Flow Control, and Hedging

Tune publisher throughput, ordered delivery, payload compression, backpressure,
and tail-latency hedging.

## Batching and Single-Message Limits

``Publisher`` groups outbound messages per `orderingKey` (`""` for unordered)
and dispatches a `Publish` RPC as soon as any configured ``BatchingOptions``
threshold is met:

- ``BatchingOptions/countThreshold`` (default `100`, capped at `1,000` messages)
- ``BatchingOptions/byteThreshold`` (default `1_000_000` bytes, capped at `10_000_000` bytes)
- ``BatchingOptions/delayThreshold`` (default `10ms`, timed from the first message
  entering an empty batch)

Single messages larger than `10_000_000` encoded bytes fail immediately with
``PubSubError/messageTooLarge(sizeBytes:limitBytes:)`` without issuing a wire RPC.

## Automatic Ordering and Corking

Messages with a non-empty ``Message/orderingKey`` are automatically serialized
through per-key FIFO queues (at most one `Publish` batch in flight per key). If
publishing fails permanently for a key, all queued messages for that key fail
and the key enters a paused state until
``Publisher/resumePublishing(orderingKey:options:)`` is called.

## Flow Control and `gzip` Compression

Configure ``PublisherFlowControlOptions`` to limit memory pressure across
pending messages and bytes using `.ignore`, `.block` (with FIFO queueing and an
idle-publisher singleton exception for single messages `<= 10_000_000` bytes), or
`.signalError`. Enable ``CompressionOptions`` (`isEnabled = true`) to apply
gRPC `gzip` compression when serialized batches exceed `bytesThreshold`
(default `240` bytes).

## Request Hedging

When ``HedgingOptions/isEnabled`` is `true`, unkeyed batches that exceed
``HedgingOptions/delay`` draw from a fixed-point milli-token bucket
(starting at `0` and refilling by `refillRatio` per successful `Publish` RPC)
to send hedged duplicate attempts carrying `x-goog-pubsub-client-telemetry`.
Ordered keys automatically suppress concurrent hedging attempts.
