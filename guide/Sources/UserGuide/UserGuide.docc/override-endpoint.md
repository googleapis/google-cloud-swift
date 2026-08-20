# Override the default endpoint

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Installing Swift]: https://www.swift.org/getting-started/
[Getting Started with Swift]: <doc:quickstart>
[locational endpoints]: /storage/docs/locational-endpoints
[private access options]: /vpc/docs/private-access-options
[regional endpoints]: https://cloud.google.com/sovereign-controls-by-partners/docs/regional-endpoints
[secret manager api]: https://cloud.google.com/secret-manager
[service quickstart]: https://cloud.google.com/secret-manager/docs/quickstart

The Swift client libraries automatically configure the endpoint for each
service. Some applications may need to override the default endpoint either
because their network has specific requirements, or because they need to use
regional versions of the service. This guide shows you how to override the
default.

## Prerequisites

This guide uses the [Secret Manager API]. To enable this API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

## Override the default endpoint

In this example you configure the client library to use secret manager's
[regional endpoints]. The same override can be used to configure the endpoint
with one of the [private access options], or for [locational endpoints] in the
services that support them.

1. Add the imports needed to use the client library
   @Snippet(path: "OverrideEndpoint", slice: "imports")
2. Write a function that receives the project ID and region as parameters
   @Snippet(path: "OverrideEndpoint", slice: "function")
3. Initialize a client and override the endpoint to use a regional endpoint:
   @Snippet(path: "OverrideEndpoint", slice: "client")
4. Use the client to retrieve the list of secrets in a region, and iterate over
   the results:
   @Snippet(path: "OverrideEndpoint", slice: "list")

## Next steps

* [Override the default credentials](override-credentials.md) describes how to
  change the default credentials used by the Swift client libraries.
* [Long-running operations](long-running-operations.md) describes how to make
  API requests that use long-running operations.
<!-- TODO(https://github.com/googleapis/google-cloud-swift/issues/144) - lint the retry policy override guide -->
<!-- TODO(https://github.com/googleapis/google-cloud-swift/issues/145) - lint the polling policy override guide -->
