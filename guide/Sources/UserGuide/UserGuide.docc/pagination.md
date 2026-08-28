# Paginated operations

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Installing Swift]: https://www.swift.org/getting-started/
[Getting Started with Swift]: <doc:quickstart>
[Secret Manager API]: https://cloud.google.com/secret-manager
[service quickstart]: https://cloud.google.com/secret-manager/docs/quickstart
[Pagination AIP]: https://google.aip.dev/158

Some Google Cloud APIs return lists of resources that are too large to fit in
a single response. These APIs implement pagination as described in
[Pagination AIP]. The service returns a single page of results along with a
token (`nextPageToken`) that the client can provide in subsequent requests to
fetch the next page.

The Google Cloud client libraries for Swift simplify interacting with paginated
RPCs by providing `AsyncSequence` helpers that automatically handle page tokens
and fetch subsequent pages as you iterate over the results. This guide shows you
how to use both automatic iteration and manual page-by-page fetching.

## Prerequisites

This guide uses the [Secret Manager API]. To enable this API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

## Automatically iterate over items

The simplest and most idiomatic way to handle paginated results in Swift is by
iterating over the items using Swift's `for try await` loop. The client library
automatically retrieves subsequent pages in the background as needed.

1. Add the imports needed to use the client library:
   @Snippet(path: "Pagination", slice: "imports")
2. Define a function that accepts the project ID:
   @Snippet(path: "Pagination", slice: "function")
3. Initialize the client using the default options:
   @Snippet(path: "Pagination", slice: "client")
4. Request an asynchronous sequence of items using `byItem:` and iterate over
   the results:
   @Snippet(path: "Pagination", slice: "auto")

## Iterate page-by-page manually

Some applications, such as web services implementing their own pagination, need
direct access to individual pages and page tokens. You can call the standard
request method to receive the raw page response and manage the page token
yourself.

1. Create a function that initializes the client:
   @Snippet(path: "Pagination", slice: "manual_function")
2. Make requests using `request:`, access the items on each page, and use the
   returned `nextPageToken` to fetch subsequent pages:
   @Snippet(path: "Pagination", slice: "manual")

## Next steps

* [Override the default authentication credentials](override-credentials.md)
  describes how to configure custom credentials such as API keys.
* [Override the default endpoint](override-endpoint.md) describes how to change
  the default endpoint used by the Swift client libraries.
* [Long-running operations](long-running-operations.md) describes how to make
  API requests that use long-running operations.
<!-- TODO(https://github.com/googleapis/google-cloud-swift/issues/144) - link the retry policy override guide -->
<!-- TODO(https://github.com/googleapis/google-cloud-swift/issues/145) - link the polling policy override guide -->
