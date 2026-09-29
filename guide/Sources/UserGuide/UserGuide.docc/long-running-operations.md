# Long-running operations

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Installing Swift]: https://www.swift.org/getting-started/
[Getting Started with Swift]: <doc:quickstart>
[Workflows API]: https://cloud.google.com/workflows
[service quickstart]: https://cloud.google.com/workflows/docs/create-workflow-gcloud
[Long-running Operations AIP]: https://google.aip.dev/151

Some Google Cloud APIs perform operations that take longer to complete than
the duration of a typical HTTP request-response cycle. These operations are known
as Long-Running Operations (LROs). Instead of blocking until the operation is
finished, API methods return an operation object, and the client polls the
service periodically until the operation completes.

The Google Cloud client libraries for Swift simplify interacting with LROs by
providing helper methods that handle polling and exponential backoff
automatically. This guide will show you how to use these helpers.

## Prerequisites

This guide uses the [Workflows API]. To enable this API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

## Make an API request with a long-running operation

In this example, you use the `WorkflowsClient` to create a workflow. The
`createWorkflowPollingUntilDone` method initiates the operation and automatically
polls until the operation completes, returning the created `Workflow` object.

1. Add the imports needed to use the client library:
   @Snippet(path: "LongRunningOperations", slice: "imports")
2. Define a function that accepts the project ID, location, and workflow ID:
   @Snippet(path: "LongRunningOperations", slice: "function")
3. Initialize the client using the default options:
   @Snippet(path: "LongRunningOperations", slice: "client")
4. Create the workflow and automatically poll until completion:
   @Snippet(path: "LongRunningOperations", slice: "call")

## Next steps

* [Override the default authentication credentials](<doc:override-credentials>)
  describes how to configure custom credentials such as API keys.
* [Override the default endpoint](<doc:override-endpoint>) describes how to change
  the default endpoint used by the Swift client libraries.
* [Override the default retry policies](<doc:override-retry-policy>) describes how
  to change how the Swift client libraries retry failed requests.
* [Override the default polling policies](<doc:override-polling-policy>) describes
  how to change how the Swift client libraries poll long-running operations.
