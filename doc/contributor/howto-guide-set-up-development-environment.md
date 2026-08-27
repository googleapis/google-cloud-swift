# Howto-Guide: Set Up Development Environment

This guide is intended for contributors to the `google-cloud-swift` SDK. It will
walk you through the steps necessary to set up your development workstation to
compile the code, run the unit tests, and formatting miscellaneous files.

## Installing Swift

We recommend that you follow the [Getting Started][getting-started-swift] guide.
Once you have `swiftly` and `swift` installed the rest is relatively easy.

You will need Swift >= 6.2. Check the version you have installed with:

```shell
swift --version
```

If you need to upgrade, consider:

```shell
swiftly update
```

## Installing Go

The code generator is implemented in [Go](https://go.dev). Follow the
[Download and install][golang-install] guide to install Golang.

## Installing tools

To install the generator dependencies use `librarian install`:

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
# Relatively slow, use `librarian -v` to get progress reports.
go run github.com/googleapis/librarian/cmd/librarian@${V} -v install
```

## IDE Recommendations

Whatever works for you. Several team members use Visual Studio Code, but Swift
can be used with many IDEs.

## Compile the Code

```bash
swift build
```

> [!NOTE] If you encounter an error like `fatal: cannot use bare repository
'...' (safe.bareRepository is 'explicit')` when SwiftPM tries to fetch or
> update dependencies, you may need to update your global git configuration:
>
> ```bash
> git config --global safe.bareRepository all
> ```
>
> **Why this happens:** SwiftPM creates and uses bare repositories in its local
> cache to save space. However, when it runs Git commands against them, it
> doesn't explicitly declare them as bare. If your environment enforces
> `safe.bareRepository = explicit` (a common security policy), Git will refuse
> to use them.
>
> **Why the fix works:** Setting it to `all` tells Git to trust all bare
> repositories again, allowing SwiftPM to operate normally.

## Run the unit tests

```bash
swift test
```

## Run the unit tests for a specific package

```bash
swift test --quiet --package-path packages/gax
```

## Sharing a build cache

By default, when using `--package-path` does not reuse the build results for
common libraries like `swift-crypto` or `gax`. You can add a build cache using
`--scratch-path` to a common directory.

For example, if using `bash`, you set this in your startup scripts:

```bash
alias sbuild='swift build --scratch-path $(git rev-parse --show-toplevel)/.build-cache'
alias stest='swift test --scratch-path $(git rev-parse --show-toplevel)/.build-cache'
```

Then use these aliases to speed up testing:

```bash
stest --package-path packages/wkt
```

or to verify the generated code compiles:

```bash
stest --package-path generated/swift-google-cloud-secretmanager-v1
```

You can customize these aliases even further. Consider

- Add `-Xswiftc -warnings-as-errors` to catch build problems earlier
  - You may need to suppress some warnings too, with
    `-Xswiftc -Wwarning -Xswiftc DeprecatedDeclaration`
- Add `--quiet` to `stest` to reduce the noise and only see test failures

## Exhaustive builds and tests

Our repository will become too large to build all the packages. The previous
commands only build the default set of packages.

If you make a large change, for example, use a new version of the generator,
consider testing all the packages.

```bash
ci/test.sh
```

## Running lints and unit tests

```bash
ci/lint.sh
git status # Shows any diffs created by `swift-format`
```

If you are seeing errors when running locally that are not present in the CI,
you may need to update your local Swift version.

## Getting code coverage locally

### Install coverage tools (once)

```bash
# TODO
```

### Getting coverage in cobertura format

```bash
# TODO
```

## Integration tests

This guide assumes you are familiar with the [Google Cloud CLI], you have access
to an existing Google Cloud Project, and have enough permissions on that
project.

### One time set up

We use [Secret Manager], [Workflows], and [KMS] to run integration tests. Follow
the [Enable the Secret Manager API] guide to, as it says, enable the API and
make sure that billing is enabled in your projects. To enable the APIs you can
run this command:

```bash
gcloud services enable workflows.googleapis.com firestore.googleapis.com speech.googleapis.com cloudkms.googleapis.com
gcloud services enable publicca.googleapis.com
```

Verify this is working with something like:

```bash
gcloud firestore databases list
gcloud secrets list
gcloud workflows list
```

It is fine if the list is empty, you just don't want an error.

### Create a service account

The integration tests need a service account (SA) in your project. This service
account is used to:

- Run tests that perform IAM operations, temporarily granting this service
  account some permissions.
- Configure the service account used for test workflows.

For a test project, just create the SA using the CLI:

```bash
gcloud iam service-accounts create swift-sdk-test \
    --display-name="Used in SA testing" \
    --description="This SA gets assigned to roles on short-lived resources during integration tests"
```

For extra safety, disable the service account:

```bash
GOOGLE_CLOUD_PROJECT="$(gcloud config get project)"
gcloud iam service-accounts disable swift-sdk-test@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com
```

### Create a test bucket

We suggest a name related to the project id, but you can use any bucket name you
like, just remember to change the name below:

```bash
gcloud storage mb gs://${GOOGLE_CLOUD_PROJECT}-bucket
```

### Running the integration tests

```bash
P_ID="$(gcloud config get project)"
env GOOGLE_CLOUD_PROJECT=${P_ID} \
  GOOGLE_CLOUD_SWIFT_TEST_BUCKET="${P_ID}-bucket" \
  GOOGLE_CLOUD_SWIFT_TEST_SERVICE_ACCOUNT=swift-sdk-test@${P_ID}.iam.gserviceaccount.com \
  swift test

env GOOGLE_CLOUD_PROJECT=${P_ID} \
  GOOGLE_CLOUD_SWIFT_TEST_BUCKET="${P_ID}-bucket" \
  GOOGLE_CLOUD_SWIFT_TEST_SERVICE_ACCOUNT=swift-sdk-test@${P_ID}.iam.gserviceaccount.com \
  swift test --package-path packages/storage
```

## Preview Documentation

To preview the user guide use:

```bash
swift package --disable-sandbox preview-documentation --target UserGuide
```

To preview one of the hand-crated packages use:

```bash
swift package --disable-sandbox preview-documentation --target GoogleCloudAuth
swift package --disable-sandbox preview-documentation --target GoogleCloudWKT
swift package --disable-sandbox preview-documentation --target GoogleCloudGax
```

You can also preview the GAPICs used by the top-level tests, for example:

```bash
swift package --disable-sandbox preview-documentation --target GoogleCloudSecretManagerV1
swift package --disable-sandbox preview-documentation --target GoogleCloudComputeV1
```

## Miscellaneous Tools

We use a number of tools to format non-Swift code. The CI builds enforce
formatting, you can fix any formatting problems manually (using the CI logs), or
may prefer to install these tools locally to fix formatting problems.

Typically we do not format these files for generated code, so local runs
requires skipping the generated files.

### Detect typos in comments and code

We use `typos` to detect typos. Install with:

```bash
cargo install typos-cli
```

### Format Markdown files

We use `mdformat` to format hand-crafted markdown files. Install with:

```bash
python -m venv .venv
source .venv/bin/activate # Or whatever is the right command for your shell
pip install -r ci/requirements.txt
```

use with:

```bash
git ls-files -z -- \
    '*.md' ':!:**/testdata/**' ':!:**/generated/**' | \
    xargs -0 mdformat
```

### Format YAML files

We use `yamlfmt` to format hand-crafted YAML files (mostly GitHub Actions).
Install and use with:

```bash
go install github.com/google/yamlfmt/cmd/yamlfmt@v0.13.0
```

use with:

```bash
git ls-files -z -- \
    '*.yaml' '*.yml' ':!:**/testdata/**' ':!:**/generated/**' | \
    xargs -0 yamlfmt
```

### Format Terraform files

We use `terraform` to format `.tf` files. You will rarely have any need to edit
these files. If you do, you probably know how to [install terraform].

Format the files using:

```bash
git ls-files -z --
    '*.tf' ':!:**/testdata/**' ':!:**/generated/**' | \
    xargs -0 terraform fmt
```

## Troubleshooting

### Issue: `swift build` fails with "Invalid manifest... error: extra argument 'traits' in call"

This may happen if your swift install somehow gets interrupted. Your machine may
be pointing to the system's default Apple-provided toolchain talking, not
Swiftly's.

**How to Diagnose**

Run `swift --version` in your terminal and check the output format.

If you see `swift-driver` and swiftlang in parentheses, you are using the Apple
system toolchain. e.g:

```
$ swift --version
swift-driver version: 1.127.14.1 Apple Swift version 6.2.1 (swiftlang-6.2.1.4.8 clang-1700.4.4.1)
Target: arm64-apple-macosx15.0
```

A correct installation should look something like this:

```
Apple Swift version 6.3.1 (swift-6.3.1-RELEASE)
Target: arm64-apple-macosx15.0
```

**How to Fix**

To fix, run the following:

```
swiftly install latest
swiftly link
```

[enable the secret manager api]: https://cloud.google.com/secret-manager/docs/configuring-secret-manager
[getting-started-rust]: https://www.rust-lang.org/learn/get-started
[getting-started-swift]: https://www.swift.org/install/
[golang-install]: https://go.dev/doc/install
[google cloud cli]: https://cloud.google.com/cli
[install terraform]: https://developer.hashicorp.com/terraform/install
[kms]: https://cloud.google.com/kms/
[secret manager]: https://cloud.google.com/secret-manager/
[workflows]: https://cloud.google.com/workflows/
