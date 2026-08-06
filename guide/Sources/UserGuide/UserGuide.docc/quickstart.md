# Quickstart

<!-- 
    It seems that swift-docc does not support reference-style links at the bottom of the file:
    
    https://github.com/swiftlang/swift-docc/issues/685
-->
[Installing Swift]: https://www.swift.org/getting-started/
[Authenticate for using client libraries]: https://cloud.google.com/docs/authentication/client-libraries
[Application Default Credentials]: https://cloud.google.com/docs/authentication/application-default-credentials
[Get started with Google Cloud]: https://docs.cloud.google.com/docs/get-started

## Install Swift

If you have not installed the Swift toolchain, follow the [Installing Swift]
instructions.

## Create a Google Cloud Project

If you do not have a Google Cloud project, follow the
[Get started with Google Cloud] guide.

## Authenticate to Google Cloud

Follow the instructions in the [Authenticate for using client libraries] guide.
This guide will show you how to login to configure [Application Default Credentials]
used in this guide.

## Create a Swift project

In this guide we will create a CLI to access Google Cloud. Initialize your
Swift project using:

```bash
mkdir GoogleCloudCLI
cd GoogleCloudCLI
swift package init --name GoogleCloudCLI --type executable
```

## Install the Google Cloud Client Libraries

At the moment, you need to extract the client libraries as source code. In your
project directory run:

```bash
# Replace the [REPO SOURCE] placeholder with the actual location of the code.
git clone [REPO SOURCE] google-cloud-swift
```

## Add the client library as a dependency

Edit your `Package.swift` to add `GoogleCloudSecretManagerV1` as a dependency.
It should read:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "GoogleCloudCLI",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "google-cloud-swift/generated/google-cloud-secretmanager-v1")
  ],
  targets: [
    .executableTarget(
      name: "GoogleCloudCLI",
      dependencies: [
        .product(name: "GoogleCloudSecretManagerV1", package: "google-cloud-secretmanager-v1")
      ],
    )
  ],
)
```

## Import the dependencies

@Snippet(path: "GoogleCloudCLI", slice: "imports")

## Create the entry point for your program

@Snippet(path: "GoogleCloudCLI", slice: "main")

## Get a project id

Get your project id from the command-line:

@Snippet(path: "GoogleCloudCLI", slice: "args")

## Initialize the client

Initialize the client with the defaults:

@Snippet(path: "GoogleCloudCLI", slice: "client")

## List the secrets

And then list the secrets:

@Snippet(path: "GoogleCloudCLI", slice: "list")

## Running the program

Run the program:

```bash
# Replace the [PROJECT ID] placeholder with the id of your project
swift run GoogleCloudCLI [PROJECT ID]
```

## Full code

The full code for your program should look like this:

@Snippet(path: "GoogleCloudCLI")
