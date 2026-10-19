# Deploy a Swift service to Google Kubernetes Engine

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Application Default Credentials]: https://cloud.google.com/docs/authentication/application-default-credentials
[Getting started with Swift]: <doc:quickstart>
[Google Cloud CLI]: https://cloud.google.com/sdk/docs/install
[Google Kubernetes Engine]: https://cloud.google.com/kubernetes-engine/docs
[Hummingbird]: https://github.com/hummingbird-project/hummingbird
[Vertex AI Gemini API]: <doc:generate-text-using-the-vertex-ai-gemini-api>
[Workload Identity Federation for GKE]: https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
[install kubectl]: https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_kubectl

In this guide, you build a containerized HTTP service in Swift using
[Hummingbird] and the [Vertex AI Gemini API], package it with a multi-stage
`Dockerfile`, configure IAM permissions with
[Workload Identity Federation for GKE], and deploy it to a
[Google Kubernetes Engine] (GKE) Autopilot cluster.

## Prerequisites

To complete this guide, you need:

1. A Google Cloud project with billing enabled.
1. The [Google Cloud CLI] (`gcloud`) installed and initialized.
1. `kubectl` and the `gke-gcloud-auth-plugin` installed (see [install kubectl]).
1. The following APIs enabled in your project:
   ```bash
   gcloud services enable \
     aiplatform.googleapis.com \
     artifactregistry.googleapis.com \
     cloudbuild.googleapis.com \
     container.googleapis.com \
     iam.googleapis.com
   ```

For local Swift setup instructions, see [Getting started with Swift].

## Create a Swift project

1. Initialize a new executable Swift package:
   ```bash
   mkdir GKEGemini
   cd GKEGemini
   swift package init --name GKEGemini --type executable
   ```

1. If you are developing and building locally on macOS, edit `Package.swift` to
   specify `platforms: [.macOS(.v15)]`. Linux container builds do not require any
   platform configuration in `Package.swift`.

1. Add the Vertex AI client library and [Hummingbird] as package dependencies:
   ```bash
   swift package add-dependency \
     https://github.com/googleapis/swift-google-cloud-aiplatform-v1.git --from 0.5.0
   swift package add-dependency \
     https://github.com/hummingbird-project/hummingbird.git --from 2.0.0
   ```

1. Add the product dependencies to your executable target:
   ```bash
   swift package add-target-dependency \
     GoogleCloudAIPlatformV1 GKEGemini --package swift-google-cloud-aiplatform-v1
   swift package add-target-dependency \
     Hummingbird GKEGemini --package hummingbird
   ```

## Write the HTTP service

On [Google Kubernetes Engine], the client library automatically authenticates
using [Application Default Credentials] via the GKE metadata server provided by
[Workload Identity Federation for GKE]. Replace the contents of
`Sources/GKEGemini/GKEGemini.swift`:

1. Import the required modules:
   @Snippet(path: "DeployToGKE", slice: "imports")
2. Define the application entry point:
   @Snippet(path: "DeployToGKE", slice: "main")
3. Read the `GOOGLE_CLOUD_PROJECT`, `HOST`, and `PORT` environment variables:
   @Snippet(path: "DeployToGKE", slice: "config")
4. Initialize the `PredictionServiceClient` once at startup so it is shared
   across incoming requests:
   @Snippet(path: "DeployToGKE", slice: "client")
5. Configure a route that sends a prompt to Gemini and returns the generated
   text:
   @Snippet(path: "DeployToGKE", slice: "router")
6. Start the HTTP server listening on the configured host and port:
   @Snippet(path: "DeployToGKE", slice: "run")

[Google Kubernetes Engine console]: https://console.cloud.google.com/kubernetes
[Workload Identity Federation for GKE]: https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity

## Containerize the application

Create a `Dockerfile` in the root of your `GKEGemini` directory. This
multi-stage build compiles the application in release mode with a statically
linked Swift standard library and copies the binary into a minimal Debian
runtime image:

1. The initial layer contains the Swift toolchain:
   ```dockerfile
   FROM swift:6.3-bookworm AS builder
   ```

2. Copy just the package file(s) and populate the Swift package cache:
   ```dockerfile
   WORKDIR /app
   COPY Package.* ./
   RUN swift package resolve
   ```

3. Copy the full source code. This allows code-only modifications to
   preserve the dependency layer in the cache:
   ```dockerfile
   COPY . .
   ```

4. Compile the code for production:
   ```dockerfile
   RUN swift build -c release --static-swift-stdlib
   ```

5. Use a smaller runtime image that includes the minimum runtime requirements
   (excluding the Swift build toolchain) to reduce the size of the container
   image:
   ```dockerfile
   FROM debian:bookworm-slim

   RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      libcurl4 \
   && rm -rf /var/lib/apt/lists/*

   RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app swift
   WORKDIR /app
   ```

6. Copy the production binary and prepare the entrypoint:
   ```dockerfile
   COPY --from=builder /app/.build/release/GKEGemini /app/GKEGemini
   USER swift:swift
   EXPOSE 8080

   ENTRYPOINT ["/app/GKEGemini"]
   ```

Create a `.dockerignore` file to exclude local build artifacts from the build
context:

```text
.build
.git
```

## Build and push the container image

1. Set your project ID, project number, and region variables:
   ```bash
   export PROJECT_ID=$(gcloud config get project)
   export PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
   export REGION=us-central1
   ```

1. Create an Artifact Registry repository to store the container image:
   ```bash
   gcloud artifacts repositories create gke-apps \
     --repository-format=docker \
     --location="${REGION}" \
     --description="Docker repository for GKE apps"
   ```

1. Build and push the container image using Cloud Build with a high-CPU machine
   type (`e2-highcpu-32`) to speed up Swift compilation:
   ```bash
   gcloud builds submit \
     --machine-type=e2-highcpu-32 \
     --tag "${REGION}-docker.pkg.dev/${PROJECT_ID}/gke-apps/gke-gemini:latest"
   ```

## Create a GKE cluster and configure IAM permissions

1. Create a GKE Autopilot cluster (which enables
   [Workload Identity Federation for GKE] by default):
   ```bash
   gcloud container clusters create-auto gke-gemini-cluster \
     --region="${REGION}"
   ```

1. Configure `kubectl` to communicate with your cluster:
   ```bash
   gcloud container clusters get-credentials gke-gemini-cluster \
     --region="${REGION}"
   ```

1. Create a dedicated Kubernetes ServiceAccount for your application:
   ```bash
   kubectl create serviceaccount gke-gemini-ksa --namespace default
   ```

1. Grant the Kubernetes ServiceAccount the Vertex AI User role
   (`roles/aiplatform.user`) so pods running as `gke-gemini-ksa` can invoke
   Gemini models.

   With [Workload Identity Federation for GKE], you can grant IAM roles directly
   to the Kubernetes ServiceAccount principal:
   ```bash
   gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
     --role="roles/aiplatform.user" \
     --member="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/default/sa/gke-gemini-ksa" \
     --condition=None
   ```

   > Note: If you are using a Google Cloud API that does not support direct
   > `principal://` IAM bindings, or if your organization requires IAM service
   > accounts, you can instead bind the Kubernetes ServiceAccount to an IAM
   > service account:
   > ```bash
   > gcloud iam service-accounts create gke-gemini-gsa \
   >   --display-name="GKE Gemini Service Account"
   >
   > gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
   >   --member="serviceAccount:gke-gemini-gsa@${PROJECT_ID}.iam.gserviceaccount.com" \
   >   --role="roles/aiplatform.user" \
   >   --condition=None
   >
   > gcloud iam service-accounts add-iam-policy-binding \
   >   "gke-gemini-gsa@${PROJECT_ID}.iam.gserviceaccount.com" \
   >   --role="roles/iam.workloadIdentityUser" \
   >   --member="serviceAccount:${PROJECT_ID}.svc.id.goog[default/gke-gemini-ksa]"
   >
   > kubectl annotate serviceaccount gke-gemini-ksa \
   >   --namespace default \
   >   "iam.gke.io/gcp-service-account=gke-gemini-gsa@${PROJECT_ID}.iam.gserviceaccount.com"
   > ```

## Deploy to GKE

1. Create a Kubernetes manifest file named `deployment.yaml` that configures a
   `Deployment` using the `gke-gemini-ksa` service account and a `Service` to
   expose it:
   ```bash
   cat <<EOF > deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: gke-gemini
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: gke-gemini
     template:
       metadata:
         labels:
           app: gke-gemini
       spec:
         serviceAccountName: gke-gemini-ksa
         containers:
         - name: gke-gemini
           image: ${REGION}-docker.pkg.dev/${PROJECT_ID}/gke-apps/gke-gemini:latest
           ports:
           - containerPort: 8080
           env:
           - name: GOOGLE_CLOUD_PROJECT
             value: "${PROJECT_ID}"
           resources:
             requests:
               cpu: "500m"
               memory: "512Mi"
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: gke-gemini-service
   spec:
     type: ClusterIP
     selector:
       app: gke-gemini
     ports:
     - protocol: TCP
       port: 80
       targetPort: 8080
   EOF
   ```

1. Apply the manifest to your cluster and wait for the deployment to become
   available (GKE Autopilot may take a few minutes to provision compute capacity
   for the first pod):
   ```bash
   kubectl apply -f deployment.yaml
   kubectl rollout status deployment/gke-gemini --timeout=5m
   ```

## Test the deployed service

1. Forward a local port to the service running in your GKE cluster:
   ```bash
   kubectl port-forward service/gke-gemini-service 8080:80
   ```

1. In a separate terminal, send a request to the service:
   ```bash
   curl http://localhost:8080/
   ```

The service sends the prompt to Gemini and returns a response with suggested
names for a dried-flower shop, similar to the following:

```text
Here are a few name ideas for a dried flower shop, broken down by vibe:

**Earthy & Bohemian**
* Everlasting Bloom
* Sun & Stem
* Wild & Preserved
...
```

You can also view your deployed workloads, inspect pod logs, and monitor cluster
metrics in the [Google Kubernetes Engine console].

## Clean up

To avoid incurring ongoing charges, delete the GKE cluster, Artifact Registry
repository, and IAM policy bindings when you are finished:

```bash
gcloud container clusters delete gke-gemini-cluster \
  --region="${REGION}"

gcloud artifacts repositories delete gke-apps \
  --location="${REGION}"

gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --role="roles/aiplatform.user" \
  --member="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/default/sa/gke-gemini-ksa" \
  --condition=None
```

If you created an IAM service account (`gke-gemini-gsa`) instead of using a
direct `principal://` binding, remove its policy binding and delete the service
account:

```bash
gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:gke-gemini-gsa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user" \
  --condition=None

gcloud iam service-accounts delete \
  "gke-gemini-gsa@${PROJECT_ID}.iam.gserviceaccount.com"
```

## Complete Swift code

The full code for `Sources/GKEGemini/GKEGemini.swift` should look like this:

@Snippet(path: "DeployToGKE")
