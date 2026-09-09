# Generate text using the Vertex AI Gemini API

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Installing Swift]: https://www.swift.org/getting-started/
[Getting Started with Swift]: <doc:quickstart>
[Vertex AI setup guide]: https://cloud.google.com/vertex-ai/docs/start/cloud-environment

In this guide, you send a text prompt request, and then a multimodal prompt and
image request to the Vertex AI Gemini API and view the responses.

## Prerequisites

To complete this guide, you must have a Google Cloud project with the Vertex AI
API enabled. You can use the [Vertex AI setup guide] to complete these steps.

For complete setup instructions for the Swift client libraries, see
[Getting started with Swift].

## Add the Vertex AI client library as a dependency

Add the `GoogleCloudAIPlatformV1` library to your `Package.swift`:

```swift
dependencies: [
  .package(path: "google-cloud-swift/generated/swift-google-cloud-aiplatform-v1"),
],
targets: [
  .executableTarget(
    name: "MyProgram",
    dependencies: [
      .product(name: "GoogleCloudAIPlatformV1", package: "swift-google-cloud-aiplatform-v1"),
    ]
  )
]
```

## Send a prompt to the Vertex AI Gemini API

1. Add the imports needed to use the client library:
   @Snippet(path: "GenerateTextGemini", slice: "imports")
2. Define a function that accepts the project ID:
   @Snippet(path: "GenerateTextGemini", slice: "function")
3. Initialize the client using default settings:
   @Snippet(path: "GenerateTextGemini", slice: "client")
4. Build the model name:
   @Snippet(path: "GenerateTextGemini", slice: "model")
5. Send the request:
   @Snippet(path: "GenerateTextGemini", slice: "request")
6. Print the response:
   @Snippet(path: "GenerateTextGemini", slice: "response")

## Send a prompt and an image to the Vertex AI Gemini API

1. Initialize the client and model name as in the previous example:
   @Snippet(path: "PromptAndImageGemini", slice: "client")
   @Snippet(path: "PromptAndImageGemini", slice: "model")
2. Build the image part with Cloud Storage URI and MIME type:
   @Snippet(path: "PromptAndImageGemini", slice: "image_part")
3. Build the prompt text part:
   @Snippet(path: "PromptAndImageGemini", slice: "prompt_part")
4. Send the request:
   @Snippet(path: "PromptAndImageGemini", slice: "request")
5. Print the response:
   @Snippet(path: "PromptAndImageGemini", slice: "response")

## Text prompt: complete code

@Snippet(path: "GenerateTextGemini")

## Prompt and image: complete code

@Snippet(path: "PromptAndImageGemini")
