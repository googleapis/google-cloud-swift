---
name: write-devrel-sample
description: Use this skill when asked to write a DevRel sample.
---

# Task

You need to write a sample using a Swift client library.

You will be given a DevRel region tag, or a GitHub issue that requests adding
the region tag. A region tag is a way for Google Cloud to associate the sample
code with its documentation.

## Identify the sample

First, identify which service this is for. This is almost always the first word
in the snake case of the region. For example, if the region is
`storage_list_buckets`, the service will be `storage`.

Next, identify where the examples for this service live in the codebase. For
storage this will be the `Sources/StorageSamples` directory. We anticipate
that future clients will follow similar patterns, e.g. Pub/Sub samples will be
in `Sources/PubSubSamples`.

If this directory does not exist, stop and ask your human for help.

## Identify the sample package

Next identify the name of the target for the examples.  Look at the top-level
`Package.swift` file. By convention this is the same name as the directory
containing the samples.

Validate the code compiles using:

```shell
swift build --target <SamplesTarget>
```

Identify the name of the test for the examples. Look at the top-level
`Package.swift` and find tests that depend on this target. By convention the
test is called `<SamplesTarget>Driver`.

Run the test using:

```shell
swift test --filter <SamplesTargetDriver>
```

The tests may be disabled unless some environment variables are set. Read the
`integration-tests.sh` script to find good values for these environment
variables.

When the test are enabled and pass, you are done with this step. You can move on
to the next one.

## Research prior art

### Look for the same sample written in other languages.

Do a CodeSearch for the given sample region. e.g. search for
`"[START storage_list_buckets]"`. This will show how other client libraries (in
languages other than Swift) write the code. Read up to 5 of these examples to
understand what the sample is doing.

Alternatively, clone the `https://github.com/googleapis/google-cloud-rust`
repository and find the sample there. The Swift SDK uses some of the same
conventions as the Rust SDK, and the Rust SDK already has most samples.

Aside: If you are a human, you could do a Google search and try to find the
cloud.google.com docs associated with this region. For example
https://docs.cloud.google.com/storage/docs/listing-buckets is associated with
`storage_list_buckets`.

Note that other client libraries have different surfaces. We will need to adapt
the logic for the exact API exposed by Swift.

### Look for existing Swift samples for the same service.

Search the local codebase (e.g., `grep -r "key_term" Sources/<SamplesTarget>`) for key
terms from the region tag to identify the relevant Swift structs, methods, and
fields.

Look at the structure under `Sources/<SamplesTarget>`. Read every file to
discover common patterns for the samples.

Next read everything under `Tests/<SamplesTargetDriver>` to see how individual
samples are invoked.

### Identify where this sample should go.

Figure out where to create a new `<sample>.swift` file. Typically, we use the
region tag for the filename, but strip any prefixes that are encoded in the
directory structure. For example, the `storage_list_buckets` sample is located
under `Sources/StorageSamples/Buckets/ListBuckets.swift`

### Identify the most similar sample to the one you are writing

Identify which existing sample is most similar to the one you are about to
write. It is useful to identify:

- which client is used?
- which RPC is used?
- which fields in the RPC are important?

Examples:

- If the sample is to set a field in an RPC, find a sample that makes that same
  RPC.
- If the sample is to make an RPC we haven't seen, find a sample that makes a
  different RPC, with the same client.

### Look for Swift samples in the documentation.

Look at examples in the documentation (i.e. in `packages/<service>/Snippets/...`) for any
interfaces you will use in the sample. If we find examples in the documentation,
the sample you write should resemble it.

## Write the sample

### Initial set up

First create a file for this new sample. It is easiest to copy the sample that
is most similar to this one and make edits. Don't make edits just yet, though.

The sample should always include a copyright, and use a DevRel snippet region
tag (the things that looks like `// [START <snippet_region>]` and
`// [END <snippet_region>]`)

### Verify the new sample is compiled.

Add a `#error("TODO : making sure the test is built")`, and then build the
samples target as before.

```shell
swift build --target <SamplesTarget>
```

We should see this fail. If it does not fail, then we are not building our
sample. Make sure the new file is included somewhere.

If it does fail, you can remove the `#error` and move on.

### Verify the new sample is run.

Add a `fatalError("TODO : making sure the test is run")` inside the sample
function, and then execute the samples as before.

```shell
GOOGLE_CLOUD_PROJECT=${PROJECT_ID} swift test --filter <TargetSample>Driver
```

We should see this fail. If it does not fail, then we are not running our
sample. Make sure the new sample is executed by the test driver.

If it does fail, you can remove the `fatalError` and move on.

### Iterate

Next, edit the interior of the sample to fit the given DevRel snippet region.
This is where it is useful to remember what other languages did.

When you are done, test the code:

```shell
GOOGLE_CLOUD_PROJECT=${PROJECT_ID} swift test --filter <TargetSample>Driver
```

If this doesn't pass, keep making edits until it works. If you fail too many
times in a row, ask for help.

When this passes, clean up the code.

- Make it concise.
- Run `ci/format.sh`.
- Look over other things from `GEMINI.md`.

If you make any changes, test the code again.

## Report success!

Stop and report success to the human! What changes did you make to the repo?

Also, suggest any updates to this `SKILL.md` in an `EDITS.diff` that will
improve the process for next time. If the process went well, there is no need to
make any suggestions.
