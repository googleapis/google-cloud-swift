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

## Operation return types: gRPC vs. Discovery-based APIs

Depending on the underlying API design, the return value of a `*PollingUntilDone`
helper method varies:

* **gRPC and AIP-151 APIs** (such as Workflows, Cloud Storage, or Secret Manager):
  The operation service metadata includes the response type of the target
  resource. In these libraries, polling helpers unwrap the operation and return
  the target resource directly (such as `Workflow` or `Secret`).

* **Discovery-based APIs** (such as Compute Engine):
  The Discovery document schema defines operation methods as returning a service
  `Operation` status resource (for example, `GoogleCloudComputeV1.Operation`).
  The polling helper returns this completed `Operation` object once the task
  finishes, rather than fetching the created or modified resource.

To obtain the created or modified resource after a Discovery-based operation
completes:

1. Await the polling helper. If the operation fails, the helper will throw an error.
2. Call the corresponding `get` method for the target resource using the
   identifiers from the request or properties on the returned `Operation`
   (such as `operation.targetLink`).

## Next steps

* [Override the default authentication credentials](<doc:override-credentials>)
  describes how to configure custom credentials such as API keys.
* [Override the default endpoint](<doc:override-endpoint>) describes how to change
  the default endpoint used by the Swift client libraries.
* [Override the default retry policies](<doc:override-retry-policy>) describes how
  to change how the Swift client libraries retry failed requests.
* [Override the default polling policies](<doc:override-polling-policy>) describes
  how to change how the Swift client libraries poll long-running operations.
