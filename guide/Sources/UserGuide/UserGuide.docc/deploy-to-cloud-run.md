# Deploy a Swift service to Cloud Run

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Application Default Credentials]: https://cloud.google.com/docs/authentication/application-default-credentials
[Cloud Run]: https://cloud.google.com/run/docs
[Getting started with Swift]: <doc:quickstart>
[Google Cloud CLI]: https://cloud.google.com/sdk/docs/install
[Hummingbird]: https://github.com/hummingbird-project/hummingbird
[Installing Swift]: https://www.swift.org/getting-started/
[Vertex AI Gemini API]: <doc:generate-text-using-the-vertex-ai-gemini-api>
[Vertex AI setup guide]: https://cloud.google.com/vertex-ai/docs/start/cloud-environment

In this guide, you build a containerized HTTP service in Swift using
[Hummingbird] and the [Vertex AI Gemini API], package it with a multi-stage
`Dockerfile`, and deploy it to [Cloud Run].

## Prerequisites

To complete this guide, you need:

1. A Google Cloud project with billing enabled.
1. The [Google Cloud CLI] (`gcloud`) installed and initialized.
1. The following APIs enabled in your project:
   ```bash
   gcloud services enable \
     aiplatform.googleapis.com \
     artifactregistry.googleapis.com \
     cloudbuild.googleapis.com \
     run.googleapis.com
   ```

For local Swift setup instructions, see [Getting started with Swift].

## Create a Swift project

1. Initialize a new executable Swift package:
   ```bash
   mkdir CloudRunGemini
   cd CloudRunGemini
   swift package init --name CloudRunGemini --type executable
   ```

1. If you are developing and building locally on macOS, edit `Package.swift` to
   specify `platforms: [.macOS(.v15)]`. Linux container builds do not require any
   platform configuration in `Package.swift`.

1. Add the Vertex AI client library and Hummingbird as package dependencies:
   ```bash
   swift package add-dependency \
     https://github.com/googleapis/swift-google-cloud-aiplatform-v1.git --from 0.4.0
   swift package add-dependency \
     https://github.com/hummingbird-project/hummingbird.git --from 2.0.0
   ```

1. Add the product dependencies to your executable target:
   ```bash
   swift package add-target-dependency \
     GoogleCloudAIPlatformV1 CloudRunGemini --package swift-google-cloud-aiplatform-v1
   swift package add-target-dependency \
     Hummingbird CloudRunGemini --package hummingbird
   ```

## Write the HTTP service

Replace the contents of `Sources/CloudRunGemini/CloudRunGemini.swift` (or
`Sources/main.swift` depending on your Swift version; if using `main.swift`,
rename it to `CloudRunGemini.swift` so `@main` can be used):

1. Import the required modules:
   @Snippet(path: "DeployToCloudRun", slice: "imports")
1. Define the application entry point:
   @Snippet(path: "DeployToCloudRun", slice: "main")
1. Read the `GOOGLE_CLOUD_PROJECT` and `PORT` environment variables provided by
   Cloud Run:
   @Snippet(path: "DeployToCloudRun", slice: "config")
1. Initialize the `PredictionServiceClient` once at startup so it is shared
   across incoming requests. On Cloud Run, the client automatically uses
   [Application Default Credentials] from the service's attached service
   account:
   @Snippet(path: "DeployToCloudRun", slice: "client")
1. Configure a route that sends a prompt to Gemini and returns the generated
   text:
   @Snippet(path: "DeployToCloudRun", slice: "router")
1. Start the HTTP server listening on the configured host and port:
   @Snippet(path: "DeployToCloudRun", slice: "run")

### Complete Swift code

@Snippet(path: "DeployToCloudRun")

## Containerize the application

Create a `Dockerfile` in the root of your `CloudRunGemini` directory. This
multi-stage build compiles the application in release mode with a statically
linked Swift standard library and copies the binary into a minimal Debian
runtime image:

```dockerfile
FROM swift:6.4-bookworm AS builder

WORKDIR /app
COPY Package.* ./
RUN swift package resolve

COPY Sources ./Sources
RUN swift build -c release --static-swift-stdlib

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4 \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app swift
WORKDIR /app

COPY --from=builder /app/.build/release/CloudRunGemini /app/CloudRunGemini

USER swift:swift
EXPOSE 8080

ENTRYPOINT ["/app/CloudRunGemini"]
```

Create a `.dockerignore` file to exclude local build artifacts from the build
context:

```text
.build
.git
```

## Grant permissions and deploy to Cloud Run

1. Set your project ID and region variables:
   ```bash
   export PROJECT_ID=$(gcloud config get project)
   export REGION=us-central1
   ```

1. Create a dedicated service account for the Cloud Run service and grant it the
   Vertex AI User role (`roles/aiplatform.user`) so it can invoke Gemini models:
   ```bash
   gcloud iam service-accounts create cloud-run-gemini \
     --display-name="Cloud Run Gemini Service Account"

   gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
     --member="serviceAccount:cloud-run-gemini@${PROJECT_ID}.iam.gserviceaccount.com" \
     --role="roles/aiplatform.user"
   ```

1. Deploy the service to Cloud Run from source. Cloud Build builds the
   `Dockerfile` and deploys the resulting container image:
   ```bash
   gcloud run deploy cloud-run-gemini \
     --source . \
     --region "${REGION}" \
     --service-account "cloud-run-gemini@${PROJECT_ID}.iam.gserviceaccount.com" \
     --no-allow-unauthenticated \
     --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}"
   ```

## Test the deployed service

Because the service was deployed with `--no-allow-unauthenticated`, include an
identity token when sending a request:

```bash
SERVICE_URL=$(gcloud run services describe cloud-run-gemini \
  --region "${REGION}" \
  --format="value(status.url)")

curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  "${SERVICE_URL}/"
```

## Clean up

To avoid incurring ongoing charges, delete the Cloud Run service when you are
finished:

```bash
gcloud run services delete cloud-run-gemini --region "${REGION}"
```
