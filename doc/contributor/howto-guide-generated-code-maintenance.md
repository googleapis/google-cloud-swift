# How-To Guide: Generated Code Maintenance

This guide is intended for contributors to the `google-cloud-swift` SDK. It will
walk you through the steps necessary to generate a new library, update libraries
with new changes in the proto specifications, and refresh the generated code
when the generator changes.

## Prerequisites

Make sure your workstation has up-to-date versions of Swift and Go. Follow the
instructions in [Set Up Development Environment].

To install the generator dependencies use `librarian install`:

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
# Relatively slow, use `librarian -v` to get progress reports.
go run github.com/googleapis/librarian/cmd/librarian@${V} -v install
```

If you are generating Swift protobufs (e.g. `swift-protobuf` modules), you must
also install the `protoc` plugins for Swift. Follow the instructions in
[Installing Protobuf Compiler & Plugins].

## Onboard new library

In this example we will use `google/cloud/kms/v1`. Change the pattern as needed.

Create a new branch in your fork:

```bash
git checkout -b feat-google-cloud-kms-v1-generate-library
```

This command will generate the library, and format the code:

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
# add library to librarian.yaml
go run github.com/googleapis/librarian/cmd/librarian@${V} add google/cloud/kms/v1
# generate library
go run github.com/googleapis/librarian/cmd/librarian@${V} generate google-cloud-kms-v1
```

Commit all these changes and send a PR to merge them:

```bash
git add .
git commit -m "feat(kms/v1): generate library"
```

### Troubleshooting

See the [playbook](librarian-playbook.md).

## Update the code generation sources

Run:

```bash
git checkout -b chore-update-shas-circa-$(date +%Y-%m-%d)
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
go run github.com/googleapis/librarian/cmd/librarian@${V} update sources.discovery
go run github.com/googleapis/librarian/cmd/librarian@${V} update sources.googleapis
go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
git add .
git commit -m"chore: update discovery and googleapis SHA circa $(date +%Y-%m-%d)" .
```

Then send a PR with whatever changed.

Alternatively you can run `librarian update --all` to update all sources at
once. Note that this includes `showcase` and `protojson-conformance`, though.

### Troubleshooting

See the [playbook](librarian-playbook.md).

## Update librarian

First get the latest version and update `librarian.yaml`:

```bash
git checkout -b chore-update-librarian-circa-$(date +%Y-%m-%d)
V=$(GOPROXY=direct go list -m -f '{{.Version}}' github.com/googleapis/librarian@main)
go run github.com/googleapis/librarian/cmd/librarian@${V} config set version ${V}
go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
git add .
git commit -m"chore: update librarian circa $(date +%Y-%m-%d)" .
```

Send the PR for review.

### Troubleshooting

See the [playbook](librarian-playbook.md).

## Formatting librarian.yaml

If you make manual changes to `librarian.yaml`, you should run `librarian tidy`
to automatically format and sort the file. This ensures consistency and
readability.

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
```

### Troubleshooting

Open a bug in the librarian repository.

## Making changes to `librarian`

Clone the `librarian` directory:

```bash
git -C .. clone git@github.com:googleapis/librarian
git -C ../librarian checkout -b fancy-swift-feature
```

Naturally you can choose to clone `librarian` into a different directory. Just
change the commands that follow.

You can make changes in the `librarian` directory as usual. To test them change
the normal commands to use the directory where your librarian changes live. For
example:

```bash
go -C ../librarian/cmd/librarian build && ../librarian/cmd/librarian/librarian generate --all
```

Once the changes work then send a PR in the librarian repo to make your changes.
Wait for the PR to be approved and merged.

The follow the instructions in the [Update librarian](#update-librarian) section.

### Testing library generation for an existing library

Sometimes it may be useful to re-generate an existing library, to test the
generation step, practice before generating a new library, or to test the
documentation.

We will use `google-cloud-secretmanager-v1` as an example. Start by removing the
existing library:

```shell
git rm -fr generated/swift-google-cloud-secretmanager-v1
# Remove the library from `librarian.yaml`
git commit -m"Remove for testing" generated/swift-google-cloud-secretmanager-v1
```

Now add the library back (get the library name from librarian yaml):

```shell
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
go run github.com/googleapis/librarian/cmd/librarian@${V} add google/cloud/secretmanager/v1
go run github.com/googleapis/librarian/cmd/librarian@${V} generate google-cloud-secretmanager-v1
```

[add new dependency]: #add-new-dependency
[generate new library]: #generate-new-library
[librarian.yaml]: https://github.com/googleapis/google-cloud-swift/blob/main/librarian.yaml
[sdk.yaml]: https://github.com/googleapis/librarian/blob/main/internal/serviceconfig/sdk.yaml
[set up development environment]: /doc/contributor/howto-guide-set-up-development-environment.md
[Installing Protobuf Compiler & Plugins]: /doc/contributor/howto-guide-set-up-development-environment.md#installing-protobuf-compiler-plugins
