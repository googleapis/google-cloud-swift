# Mocking and Testing

Test your Pub/Sub publishers and subscribers offline with plain `import GoogleCloudPubSub`.

## Overview

Every public client and handle in `GoogleCloudPubSub` is backed by a `Sendable`
protocol with default `GoogleGax.RequestError.unimplemented` stubs, so unit
tests only implement the methods they exercise and never break when new protocol
requirements gain defaults in minor releases:

- ``Clients/PublisherClientProtocol`` and ``Clients/PublisherProtocol``
- ``Clients/BlockingPublisherProtocol``
- ``Clients/SubscriberProtocol``
- ``MessageStreamProtocol`` (and concrete ``MessageStream`` initializers)
- ``AckHandlerProtocol`` (and ``ReceivedMessage/init(message:isExactlyOnce:ackHandler:)``)

Accept protocol types (`some Clients.PublisherProtocol` or
`any Clients.SubscriberProtocol`) at application boundaries rather than concrete
client classes.

## Example: Mocking Publishers and Streams

@Snippet(path: "MockingExample")

## Forwarding Decorators and Failure Injection

``MessageStream`` exposes both ``MessageStream/init(messages:)`` for simple
lists and ``MessageStream/init(next:onStop:)`` for simulating mid-stream RPC
errors, backpressure, and shutdown assertions without `@testable import`.

Because ``ReceivedMessage/init(message:isExactlyOnce:ackHandler:)`` accepts any
``AckHandlerProtocol``, you can inspect synchronous ``AckHandlerProtocol/ack(options:)``
/ ``AckHandlerProtocol/nack(options:)`` calls (including automatic nacks triggered
when an unsettled `ReceivedMessage` leaves scope) and control
``AckHandlerProtocol/ackWithResult(options:)`` outcomes for exactly-once delivery tests.
