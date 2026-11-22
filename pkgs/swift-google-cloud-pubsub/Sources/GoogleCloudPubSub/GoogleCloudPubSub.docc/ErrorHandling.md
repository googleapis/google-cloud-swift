# Error Handling

Distinguish between transport/service errors (`GoogleGax.RequestError`) and
client-detected Pub/Sub lifecycle or validation errors (`PubSubError`).

## Error Types

`GoogleCloudPubSub` operations throw two concrete public error types:

1. **`GoogleGax.RequestError`:** Thrown for gRPC service statuses
   (`.service(ServiceError)`), network I/O errors (`.io`), exhausted retry loops
   (`.exhausted`), invalid endpoints (`.badURL`), and default unimplemented mock
   stubs (`.unimplemented`).
2. **``PubSubError``:** Thrown for local invariant violations, shutdown state,
   paused ordering keys, exceeded flow-control limits with `.signalError`, invalid
   client configuration, and permanent exactly-once settlement rejections
   (``PubSubError/settlementFailed(_:)``).

## Matching Specific gRPC Error Codes

Import both `GoogleGax` and `GoogleRpc` to inspect `ServiceError.code` cleanly:

```swift
import GoogleCloudPubSub
import GoogleGax
import GoogleRpc

do {
  for try await received in try subscriber.subscribe(subscription: subscription) {
    received.ack()
  }
} catch RequestError.service(let serviceError) where serviceError.code == .notFound {
  // Handle missing subscription (for example, optimistic subscribe recovery)
} catch let error as PubSubError {
  switch error {
  case .orderingKeyPaused(let key):
    _ = key
  case .settlementFailed(let ackError):
    _ = ackError.status
  default:
    break
  }
}
```

Both ``PubSubError`` and ``SettlementStatus`` are non-exhaustive enums: always
include `@unknown default:` or `default:` clauses when switching on them.
