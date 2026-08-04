# Howto-Guide: Update CI builds on Google Cloud Build

This guide is intended for contributors to the `google-cloud-swift` SDK. It
describes how to test and configure new CI builds on GCB (Google Cloud Build).

## Create new builds

Suppose you want a new build, maybe run the unit tests with the
`--sanitize=address` flag. You need to follow these steps:

### Create a new build script in `ci/gcb/scripts`

Copy one of the existing scripts and add the new options, the delta may
look like this:

```diff
diff -u ci/gcb/scripts/{unit-tests,asan}.sh
--- ci/gcb/scripts/unit-tests.sh	2026-07-31 11:59:48
+++ ci/gcb/scripts/asan.sh	2026-07-31 11:49:31
@@ -33,7 +33,6 @@
     -Xswiftc DeprecatedDeclaration
     --scratch-path "/workspace/.build-cache"
     --build-path   "/workspace/.build"
-    --sanitize=address
 )
 for dir in "${packages[@]}"; do
     [[ -f "${dir}/Package.swift" ]] || continue
```

Make sure the new script is executable

```shell
chmod 755 ci/gcb/scripts/asan.sh
```

### Test the new script on GCB

Now run the build on GCB, you may need to iterate on the build script until this
works reliably:

```sh
gcloud builds submit --project=swift-sdk-testing --region=us-central1 \
  --config=ci/gcb/scripted.yaml --substitutions=_SCRIPT=asan
```

### Edit the trigger files

Edit `ci/gcb/builds/triggers/main.tf` to create a new trigger. The diff may look like this:

```diff
diff --git a/ci/gcb/builds/triggers/main.tf b/ci/gcb/builds/triggers/main.tf
index 153e615ca..0ab906ec2 100644
--- a/ci/gcb/builds/triggers/main.tf
+++ b/ci/gcb/builds/triggers/main.tf
@@ -37,6 +37,10 @@ locals {
   # These builds appear in both the PR (Pull Request) triggers and the
   # PM (Post Merge) triggers. See below for builds that only appear in one.
   common_builds = {
+    asan = {
+      config = "scripted.yaml"
+      script = "asan"
+    }
     unit-tests = {
       config = "scripted.yaml"
       script = "unit-tests"
```

### Send a PR to add the new files

You know what to do.

### Enable the new trigger

One the PR is merged, but not before, enable the trigger:

```shell
cd ci/gcb/builds
terraform init
terraform plan -out /tmp/build.tfplan
terraform apply /tmp/build.tfplan
```

## Update resources for new integration tests

If the integration test needs to create and delete project-level resources, you
need to modify the project configuration in overground.

To create persistent resources used in the tests, first edit
`ci/gcb/builds/test-resources/main.tf`, send a PR with these changes and then:

```shell
cd ci/gcb
terraform init
terraform plan -out /tmp/build.tfplan
terraform apply /tmp/build.tfplan
```
