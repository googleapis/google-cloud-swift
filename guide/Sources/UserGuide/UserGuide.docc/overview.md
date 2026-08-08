# Swift for Google Cloud SDK overview

The Official Google Cloud Server-Side Swift SDK allows you to build and manage
backend services on Google Cloud using the Swift programming language. This SDK
is designed for developers building enterprise server infrastructure in Linux or
Windows environments.

## Full-stack Swift development

You can use a single language across your entire application stack. By pairing
the Google Cloud Server-Side Swift SDK with the Firebase SDK for Apple
platforms, you can manage both your mobile frontend and your cloud backend with
Swift.

## Performance and safety

Swift is a modern, strongly-typed language that offers high performance and
memory safety. These features make it suitable for performance-critical
server-side workloads and secure system programming.

## Developer efficiency

Building with a unified language ecosystem eliminates the need for
context-switching between different programming languages. This reduces
cognitive load for full-stack developers and allows frontend teams to leverage
their existing Swift expertise to build backend services.

## Product boundaries

Google provides two distinct Swift SDKs to serve different development needs.

| Feature | Firebase Apple SDKs | Google Cloud Server-Side Swift SDK |
| :---- | :---- | :---- |
| **Primary Use** | Client-side mobile and web development. | Backend server-side infrastructure. |
| **Environment** | Apple client ecosystem (iOS, watchOS, etc.). | Deploy on Server environments (Linux, Windows). Develop on Linux, macOS or Windows. |
| **Authentication** | User-based authentication and security rules. | Service Accounts, ADC, and Workload Identity Federation. |
| **Service Scope** | Mobile-centric tools (Analytics, Firestore, etc.). | 140+ GCP APIs (Storage, GKE, Compute, etc.). |

## Key features

The Swift SDK is designed to feel native to your existing development workflow.

* **Idiomatic Swift:** The SDK uses modern Swift features, including async/await for concurrency.  
* **Native Networking:** It uses Apple’s Swift NIO and AsyncHTTPClient for seamless integration with your Swift-native servers.
* **Secure Authentication:** You can securely authenticate using Application Default Credentials (ADC), Service Accounts, and Workload Identity Federation (WIF).  
* **Standard Integration:** The SDK integrates with standard Swift ecosystem tools like Swift Package Manager (SPM).
