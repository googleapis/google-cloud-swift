# Playbook: most common `librarian` errors and resolution

This guide describes how to handle the most common errors during
`librarian add` and the corresponding `librarian generate`.

The main audience are members of the Swift SDK team and the SDK platform team.

## PascalCase style deviate from the default name for this library

**Symptom:** during `librarian generate` you get an error like this:

```
librarian: generate library "google-cloud-devicestreaming-v1" (swift): default library name for google.cloud.devicestreaming.v1 needs override.
Other languages with PascalCase style deviate from the default name for this library,
most likely, that indicates the default library name is not a good choice. Consider
these alternatives and use library_name_override to silence this error:
C# suggests using GoogleCloudDeviceStreamingV1
PHP suggests using GoogleCloudDeviceStreamingV1
Ruby suggests using GoogleCloudDeviceStreamingV1
```

**Context:** By convention, Swift uses `PascalCase` for modules. For this
discussion, think of modules as the thing that developers `import`. The module
name is unrelated to the package name in swift. Our packages are named
`swift-google-cloud-secretmanager-v1` but the one module within that package is
`GoogleCloudSecretManagerV1`.

Librarian has noticed that other languages with similar naming conventions override the
top-level name (package or namespace for those languages). Most likely, using the
default name will produce a bad developer experience: in the example 
`import Devicestreaming` is harder to read than `import DeviceStreaming`.

**Resolution:** you need to override the library (not package) name. A directive
in the `librarian.yaml` file like this will do:

```yaml
  - name: google-cloud-devicestreaming-v1
    version: 0.0.0-preview
    copyright_year: "2026"
    swift:
      library_name_override: GoogleCloudDeviceStreamingV1
```

Then call `librarian generate` again.

**Caveats:** Swift uses different conventions for acronyms vs. other languages.
It is conventional to name the library `GoogleIAMV1` instead of `GoogleIamV1`.
Keep this in mind because the suggestion based on .NET, PHP, and Ruby may not
take this into account.

## Package not found in ApiPackages

**Symptom:** calling `librarian generate` fails with an error similar to:

```
librarian: generate library "google-cloud-policytroubleshooter-iam-v3" (swift): package "google.iam.v2" not found in ApiPackages
```

**Context:** As you are well aware, APIs often depend on types defined in other
APIs. Sidekick for Swift (and Rust and Dart) lacks automatic resolution of
missing APIs, instead, a single stanza in the `default -> swift -> dependencies`
section defines what **Swift** packages provide what **Protobuf** packages. When
an API uses an "external" message or enum, sidekick tries to find the Protobuf
package in that stanza. If it cannot, sidekick emits an error.

You may run into this error when onboarding new APIs, as this may have unique
dependencies, or when updating the APIs to a new SHA, as the new protos may
introduce new dependencies.

It is safe to add any package to the dependencies, sidekick prunes unused
dependencies and only adds the minimum set of dependencies needed to build the
package.

**Resolution:** you need to edit `librarian.yaml` and add the missing
package to the list of potential dependencies. Using the example from above:

```yaml
default:
  swift:
    dependencies:
      - name: GoogleIAMV2
        path: generated/swift-google-iam-v2
        api_package: google.iam.v2
```

Remember to use `librarian tidy` after your manual edits, and then regenerate.

## The CI build fails after onboarding an API

**Symptom:** the CI build compiles new APIs as part of the PR. The CI has failed.

**Resolution:** most likely this is a bug in the code generator. Please contact
the Swift SDK team.

## Missing Idempotency Hook in Storage Client

**Symptom:** building `pkgs/swift-google-cloud-storage` fails with an error similar to:

```text
error: value of type '<RequestType>' has no member 'resolveIdempotency'
```

in `pkgs/swift-google-cloud-storage/Sources/GoogleCloudStorage/generated/Storage/Storage+Retry.swift`.

**Context:** The `google-cloud-storage` entry in `librarian.yaml` configures:

```yaml
idempotency_hook: resolveIdempotency
```

When new RPCs are added to the Google Cloud Storage API definitions in `googleapis`, the generated retry client calls `request.resolveIdempotency(options: options)`. Because these hooks are handwritten, the new request type must be extended with `resolveIdempotency(options:)`.

**Resolution:** You have two options:

1. **Implement the missing hook in the same PR**:
   Add the `resolveIdempotency(options:)` extension in `pkgs/swift-google-cloud-storage/Sources/GoogleCloudStorage/StorageIdempotency.swift` and corresponding unit tests in `pkgs/swift-google-cloud-storage/Tests/StorageIdempotencyTests.swift`. Consult [`pkgs/swift-google-cloud-storage/GEMINI.md`](../../pkgs/swift-google-cloud-storage/GEMINI.md) for the rules on read-only vs mutating, precondition handling, and `etag` exclusion.
2. **Defer to a separate PR**:
   Add `skip_release: true` to the `google-cloud-storage` entry in `librarian.yaml` (under `- name: google-cloud-storage`), run `librarian tidy`, and open a GitHub issue to fix the hooks in a follow-up PR.

## Other

Please contact the Swift SDK team.
