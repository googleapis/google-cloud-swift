# Update a resource using a field mask

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Getting started with Swift]: <doc:quickstart>
[Secret Manager API]: https://cloud.google.com/secret-manager
[service quickstart]: https://cloud.google.com/secret-manager/docs/quickstart
[FieldMask AIP]: https://google.aip.dev/161
[Update AIP]: https://google.aip.dev/134
[swift-google-wkt]: https://github.com/googleapis/swift-google-wkt

This guide shows you how to update a resource using a field mask, so that you
can control which fields on the resource are modified. The guide uses a secret
from the [Secret Manager API] as an example resource, but the same concepts
apply across Google Cloud services that follow [Update AIP] and [FieldMask AIP].

## Prerequisites

This guide uses the [Secret Manager API]. To enable this API, follow the
[service quickstart].

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

## Install well-known types

The [`swift-google-wkt`][swift-google-wkt] package (`GoogleWKT` module) contains
Protocol Buffer well-known types for Google Cloud APIs, including the field mask
type, `WKTFieldMask`.

When specifying field masks using array literals (such as
`updateMask: ["annotations", "labels"]`), you do not need to import `GoogleWKT`
or add it as a direct dependency. However, if your application constructs
dynamic field masks from runtime `[String]` collections using
`WKTFieldMask(paths:)`, you can add `swift-google-wkt` as a dependency:

1. Add the `swift-google-wkt` package as a dependency:
   ```bash
   swift package add-dependency \
     https://github.com/googleapis/swift-google-wkt.git --from 0.4.0
   ```
1. Add the `GoogleWKT` module as a dependency of your target:
   ```bash
   swift package add-target-dependency \
     GoogleWKT MyProgram --package swift-google-wkt
   ```

## `WKTFieldMask`

A `WKTFieldMask` represents a set of symbolic field paths (for example,
`paths: ["annotations", "labels"]` or `paths: ["user.display_name", "photo"]`).
Field masks are used to specify a subset of fields that should be returned by a
read operation or modified by an update operation.

In an update operation, a field mask specifies which fields of the targeted
resource should be updated. The API changes only the values of the fields
specified in the mask and leaves all other fields untouched. If a resource is
passed in to describe the updated values, the API ignores the values of any
fields not covered by the mask. If a service supports a full replacement of a
resource, it typically accepts a wildcard mask `["*"]` to update all fields.

`WKTFieldMask` conforms to `ExpressibleByArrayLiteral`, allowing you to specify
field masks using array literals:

* **Prefer array literals** (such as `updateMask: ["annotations", "labels"]`)
  when the fields to update are known at compile time. This style is concise,
  idiomatic, and does not require importing `GoogleWKT`.
* **Use `WKTFieldMask(paths: myPaths)`** when the list of fields to update is
  determined dynamically at runtime from an array of strings (`[String]`). This
  requires importing `GoogleWKT` and adding `swift-google-wkt` as a dependency.

Field paths use the Protocol Buffer `snake_case` field names relative to the
resource being updated. When encoding requests to JSON, `WKTFieldMask`
automatically converts each path to `camelCase`.

To reset a field to its default value, include the field path in the mask and
leave the field set to its default value on the provided resource.

## Update fields on a resource

1. Add the imports needed to use the Secret Manager client library:
   @Snippet(path: "UpdateResource", slice: "imports")
2. Define a function that accepts the project ID and secret ID:
   @Snippet(path: "UpdateResource", slice: "function")
3. Initialize a Secret Manager client and create a secret (when created, both
   the `labels` and `annotations` dictionaries on the secret are empty):
   @Snippet(path: "UpdateResource", slice: "create")
4. Construct a `Secret` containing the updated `labels` and `annotations`, along
   with the resource's `name` and
   [etag](https://cloud.google.com/secret-manager/docs/etags) (setting `etag`
   prevents overwriting concurrent updates):
   @Snippet(path: "UpdateResource", slice: "update")
5. Call `updateSecret(secret:updateMask:)`, passing an array literal with the
   `annotations` and `labels` field paths to update only those fields:
   @Snippet(path: "UpdateResource", slice: "update_mask")

## Complete code

@Snippet(path: "UpdateResource")

## Next steps

* [Override the default authentication credentials](<doc:override-credentials>)
  describes how to configure custom credentials such as API keys.
* [Override the default endpoint](<doc:override-endpoint>) describes how to change
  the default endpoint used by the Swift client libraries.
* [Long-running operations](<doc:long-running-operations>) describes how to make
  API requests that use long-running operations.
* [Paginated operations](<doc:pagination>) describes how to iterate over
  paginated API responses.
* [Override the default retry policies](<doc:override-retry-policy>) describes how
  to change how the Swift client libraries retry failed requests.
* [Override the default polling policies](<doc:override-polling-policy>) describes
  how to change how the Swift client libraries poll long-running operations.
