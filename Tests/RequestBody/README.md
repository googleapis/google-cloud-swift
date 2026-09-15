# Request body tests

These tests verify the HTTP request body produced by the generated code.

The generated clients build their own HTTP client, there is no way to mock the transport. The
tests start a small HTTP server on the loopback interface (`CaptureServer`, in
`Sources/GoogleCloudTestHelpers`), point the client at it using `ClientOptions.endpoint`, and then
inspect the captured request. They never contact a production service, and they do not require
credentials: the clients are configured with anonymous credentials.

The tests use the APIs already required by the other test targets, to avoid adding new
dependencies to the development build:

- `secretmanager-v1`: methods using `body: "*"` with a single path parameter
  (`addSecretVersion`, `setIamPolicy`) and a method using a named body (`createSecret`).
- `cloudbuild-v1`: `cancelBuild` interpolates two fields (`projectId` and `id`) into the path.
