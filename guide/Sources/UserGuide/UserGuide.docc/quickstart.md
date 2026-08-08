# Getting started with Swift

<!-- 
    It seems that swift-docc does not support reference-style links at the bottom of the file:
    
    https://github.com/swiftlang/swift-docc/issues/685
-->
[Installing Swift]: https://www.swift.org/getting-started/
[Authenticate for using client libraries]: https://cloud.google.com/docs/authentication/client-libraries
[Application Default Credentials]: https://cloud.google.com/docs/authentication/application-default-credentials
[Get started with Google Cloud]: https://docs.cloud.google.com/docs/get-started
[secret manager api]: https://cloud.google.com/secret-manager
[service quickstart]: https://cloud.google.com/secret-manager/docs/quickstart

Follow this guide to create a small Swift project using the Google Cloud client
libraries for Swift.

## Install Swift

If you have not installed the Swift toolchain, follow the [Installing Swift]
instructions.

## Create a Google Cloud Project

If you do not have a Google Cloud project, follow the
[Get started with Google Cloud] guide.

## Enable the Secret Manager service

This guide uses the [Secret Manager API]. To enable this API, follow the
[service quickstart].

## Authenticate to Google Cloud

Follow the instructions in the [Authenticate for using client libraries] guide.
This guide will show you how to login to Google Cloud, and configure the
[Application Default Credentials] used in this guide.

## Create a Swift project

In this guide we will create a CLI to access Google Cloud. Initialize your
Swift project using:

```bash
mkdir Quickstart
cd Quickstart
swift package init --name Quickstart --type executable
```

## Configure the platforms

The Google Cloud client libraries only support macOS >= 15, while
`swift package init` defaults to much older versions. Edit the `Package.swift`
project to insert a `platforms: [ .macOS(.v15) ]` directive. The delta should
look like this:

```diff
diff --git a/Package.swift b/Package.swift
index 949f55e..3a15eda 100644
--- a/Package.swift
+++ b/Package.swift
@@ -5,6 +5,7 @@ import PackageDescription

 let package = Package(
     name: "Quickstart",
+    platforms: [ .macOS(.v15), ],
     dependencies: [
         .package(path: "google-cloud-swift/generated/google-cloud-secretmanager-v1"),
     ],
```

## Add the client library as a dependency

1. While the Google Cloud Client Libraries for Swift are under development you
   need to manually download the source to a local directory:
   ```bash
   git clone --depth 1 https://github.com/googleapis/google-cloud-swift
   ```
1. Then add the secret manager package within this download as a dependency:
   ```bash
   swift package add-dependency \
     google-cloud-swift/generated/google-cloud-secretmanager-v1 --type path
   ```
1. And add the specific module as a dependency of your executable:
   ```bash
   swift package add-target-dependency \
     GoogleCloudSecretManagerV1 Quickstart --package google-cloud-secretmanager-v1
   ```

## Edit the program to use Google Cloud

Modify your program as follows:

1. Import the dependencies
   @Snippet(path: "Quickstart", slice: "imports")
2. Create the entry point for your program
   @Snippet(path: "Quickstart", slice: "main")
3. Get your project id from the command-line:
   @Snippet(path: "Quickstart", slice: "args")
4. Initialize the client with the default settings
   @Snippet(path: "Quickstart", slice: "client")
5. Make a request to list all the secrets and iterate over the results
   @Snippet(path: "Quickstart", slice: "list")

## Run the program

To see the program in operation, run it with your project id as the first
argument:

```bash
# Replace the [PROJECT ID] placeholder with the id of your project
swift run Quickstart [PROJECT ID]
```

## Full code

The full code for your program should look like this:

@Snippet(path: "Quickstart")
