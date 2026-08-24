# Google Cloud client libraries for Swift: endurance test

This directory contains a test to verify the client libraries work well in
long-running applications. Our unit and integration tests are (and should be)
short-lived. These tests may miss bugs that only manifest themselves when the
application runs for a long time. Examples of such bugs include:

- Failure to refresh access tokens in the authentication library.
- Transient errors that appear rarely and are not handled correctly.
- Race conditions that only appear rarely.
- Resource leaks, including memory, file descriptors, or any other resource.

While Swift's memory safety and structured concurrency make it hard to
introduce some of the problems described above, it is not impossible to do so.
While running a test for a long time does not guarantee that such bugs will be
found, it makes it less likely that such bugs do exist. In the worst case, such
a test provides scaffolding to reproduce any bugs reported by our customers.

## Basic Deployment

For a one-time run, we can use GCE to run the program and manually configure the
resources and permissions to run the program. If we wanted to run this program
continuously, then we should consider a more advanced deployment, such as GKE.

## Pre-requisites

You will need a project with billing enabled. The Secret Manager and Compute
Engine APIs should be enabled too. You will need a GCE VM instance, and the
default GCE service account will need to have the secret manager admin role.

Capture the project id:

```shell
export PROJECT_ID=$(gcloud config get project)
```

Make sure the service account has the necessary privileges:

```shell
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')
ACCOUNT=${PROJECT_NUMBER}-compute@developer.gserviceaccount.com
gcloud projects add-iam-policy-binding ${PROJECT_ID} --role=roles/secretmanager.viewer --member=serviceAccount:${ACCOUNT}
gcloud projects add-iam-policy-binding ${PROJECT_ID} --role=roles/secretmanager.secretAccessor --member=serviceAccount:${ACCOUNT}
gcloud projects add-iam-policy-binding ${PROJECT_ID} --role=roles/secretmanager.secretVersionManager --member=serviceAccount:${ACCOUNT}
```

Create the testing resources:

```shell
for i in $(seq 0 19); do
    id=$(printf "secret-%03d" $i)
    gcloud secrets create --labels=endurance-test=true ${id}
done
```

If the resources already exist these commands will fail, you can ignore those errors.

## Deployment

On a single GCE instance, install the Swift development tools (e.g. via swiftly
or official Swift packages), git, and build tools:

```shell
sudo apt update && sudo apt install -y git curl binutils libcurl4-openssl-dev libssl-dev gpg build-essential
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz && \
tar zxf swiftly-$(uname -m).tar.gz && \
./swiftly init --quiet-shell-followup && \
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" && \
hash -r
swiftly install latest
sudo apt-get -y install libicu-dev libedit-dev libsqlite3-dev libncurses-dev libpython3-dev libxml2-dev pkg-config uuid-dev libstdc++-12-dev
```

Clone the code and build/run the test:

```shell
git clone https://github.com/googleapis/google-cloud-swift.git
cd google-cloud-swift
swift run -c release Endurance
```

That should print some progress metrics every 10 seconds or so. If it fails to
start or cannot successfully update and access the secrets, check the
permissions and project configuration.

Once it is working, run it in the background with the logs going to Cloud Logging.
First, copy the binary to `/usr/local/bin`:

```shell
sudo cp .build/release/Endurance /usr/local/bin/endurance-test
```

Create the systemd user service unit:

```shell
mkdir -p ~/.config/systemd/user
sudo sed "s/@PROJECT@/$PROJECT_ID/" Tests/Endurance/endurance-test.service >/etc/systemd/system/swift-endurance.service
```

Start the program as a background service:

```shell
sudo systemctl daemon-reload
sudo systemctl enable --now endurance-test.service
sudo systemctl status endurance-test.service
```

The benchmark is tuned to use all the API quota in a single project. If you run
more than one copy of the test you will see a much higher failure rate than
expected.

## Future Work

It would be nice to report metrics, such as successful request counts and
request latency to Cloud Monitoring.

If we wanted to deploy and run this continuously, it would be nice to use GKE
and Cloud Build to automatically deploy new versions.

It may be easier to deploy this by building a docker image (there is a Swift
plugin to do this locally), and then deploy the image to an instance
configured with the Container-Optimized OS image.

Alternatively, we could configure configure the VM using Terraform and use a
`metadata_startup_script` to do all the work.

However, this benchmark is executed rarely, once every few of years, if that.
Before investing on a lot of automation consider whether there is a return on
it.
