# Streaming Subscriptions, Lease Renewal, and Exactly-Once Delivery

Understand `StreamingPull` connection lifecycle, flow control, adaptive lease
extension, exactly-once settlement, and managed unary pull.

## Optimistic Streaming & Keepalives

``SubscriberClient/subscribe(subscription:options:)`` opens `streamCount`
concurrent bidirectional `StreamingPull` streams immediately without issuing a
preflight `GetSubscription` RPC. If the subscription does not exist, the stream
throws `GoogleGax.RequestError.service` with code `.notFound`.

Each stream preserves its `clientID` across transient reconnects and exchanges
`protocol_version = 1` empty keepalive pings every `keepalivePingInterval` (`30s`
default), recycling the stream if no server response arrives within
`keepalivePongTimeout` (`15s` default). Server pong reads are decoupled from the
local flow-control admission gate so backpressure never triggers false keepalive
timeouts.

## Per-Stream Flow Control & Lease Management

Each stream advertises `maxOutstandingMessages` (`1,000` default) and
`maxOutstandingBytes` (`100 MiB` default) on Frame 0 and pauses local delivery
while unsettled deliveries saturate those limits.

A shared lease manager renews unsettled leases using an adaptive 99th-percentile
ack-latency histogram clamped to `[10s, 600s]` up to `maxExtension` (`3,600s`
default). On `maxExtension` expiry, renewal stops without sending `Nack(0)` and
releases local flow-control permits. Settling via ``ReceivedMessage`` marks the
message handled; dropping all copies of an unsettled ``ReceivedMessage`` before
expiry synchronously schedules a `nack`.

## Dynamic Exactly-Once Delivery & Graceful Shutdown

Streams inspect `subscription_properties.exactly_once_delivery_enabled` per
response batch dynamically (raising default `minAckExtension` to `60s` when
`nil`). ``ReceivedMessage/ackWithResult(options:)`` and
``ReceivedMessage/nackWithResult(options:)`` retry transient errors, split
innocent siblings away from permanent per-ID `ErrorInfo` failures, and resolve to
``AckResult`` or throw ``PubSubError/settlementFailed(_:)``.

@Snippet(path: "SubscriberExactlyOnce")

Call ``MessageStreamProtocol/stop(options:)`` with ``ShutdownBehavior/waitForProcessing``
(default) or ``ShutdownBehavior/nackImmediately`` for deterministic draining. For
batch/cron callers that prefer explicit RPC polling with automatic lease renewal,
use ``SubscriberClient/pull(subscription:options:)``.
