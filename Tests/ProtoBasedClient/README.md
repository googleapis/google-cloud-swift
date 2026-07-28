# Integration tests for Protobuf-based client

This directory contains integration tests for a Protobuf-based client. The tests
uses two libraries:

- `GoogleCloudSecretManagerV1`, because it is easy to enable this API, the
  quota limits rarely affect integration tests, and because it covers a number
  of features including:
  - Multiple data types, including maps, bytes, timestamps, and field masks.
  - Nested messages, nested enums, and other complex types.
  - The location and IAM mixins.
  - Pagination.
  - Some regional endpoints.

- `GoogleCloudWorkflowsV1`, because it is also easy to enable, the quota limits
  rarely affect integration tests, and because it covers a different set of
  features including:
  - The LRO mixin.
  - Use of `Any` in the service.

We may want to expand these tests with something that covers other features such as:

- Recursive messages.
- Use more well-known types, such as `Struct` or `Value`.

However, basic unit tests cover these features fairly well: as long as
serialization works, we are fine.
