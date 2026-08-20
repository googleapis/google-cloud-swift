# Override the default authentication credentials

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Installing Swift]: https://www.swift.org/getting-started/
[Getting Started with Swift]: <doc:quickstart>
[cloud natural language api]: https://cloud.google.com/natural-language
[service quickstart]: https://cloud.google.com/natural-language/docs/setup
[API keys]: https://cloud.google.com/docs/authentication/api-keys
[authentication methods]: https://cloud.google.com/docs/authentication
[best practices for managing api keys]: https://cloud.google.com/docs/authentication/api-keys-best-practices

The Swift client libraries automatically configure the authentication
credentials used to access Google Cloud. Some applications may need to override
the default credentials. This guide shows you how to override the default.

## Prerequisites

This guide uses the [Cloud Natural Language API]. To enable this API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

## Override the default credentials: API keys

[API keys] are text strings that grant access to some Google Cloud services.
Using API keys may simplify development as they require less configuration than
other [authentication methods]. There are some risks associated with API keys,
we recommended you read [Best practices for managing API keys] if you plan to
use them.

In this example you configure the client library to use a service account key
file for authentication. In general, service account keys should be The same override can be used to configure the endpoint
with one of the [private access options], or for [locational endpoints] in the
services that support them.

1. Add the imports needed to use the client library
   @Snippet(path: "OverrideCredentials", slice: "imports")
2. Write a function that receives the project ID and region as parameters
   @Snippet(path: "OverrideCredentials", slice: "function")
3. Initialize a client and override the endpoint to use a regional endpoint:
   @Snippet(path: "OverrideCredentials", slice: "client")
4. Use the client to retrieve the list of secrets in a region, and iterate over
   the results:
   @Snippet(path: "OverrideCredentials", slice: "call")

## Next steps

* [Override the default endpoint](override-endpoint.md) describes how to change
  the default endpoint used by the Swift client libraries.
* [Long-running operations](long-running-operations.md) describes how to make
  API requests that use long-running operations.
<!-- TODO(https://github.com/googleapis/google-cloud-swift/issues/144) - lint the retry policy override guide -->
<!-- TODO(https://github.com/googleapis/google-cloud-swift/issues/145) - lint the polling policy override guide -->
