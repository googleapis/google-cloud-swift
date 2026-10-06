#!/usr/bin/env bash
#
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

# Redirect stdout and stderr to startup log (automatically forwarded to serial port by GCE)
mkdir -p /var/log
exec > >(tee -a /var/log/w1r3-startup.log) 2>&1

echo "=========================================================="
echo "Starting Storage W1R3 Benchmark Runner on GCE"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=========================================================="

get_attribute() {
  local key="$1"
  local default_val="${2:-}"
  local val
  val=$(curl -s -f --retry 3 --retry-connrefused --connect-timeout 2 -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${key}" 2>/dev/null || true)
  if [[ -n "${val}" ]]; then
    echo "${val}"
  else
    echo "${default_val}"
  fi
}

get_instance_metadata() {
  local path="$1"
  local val
  val=$(curl -s -f --retry 3 --retry-connrefused --connect-timeout 2 -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/${path}" 2>/dev/null || true)
  echo "${val}"
}

get_project_metadata() {
  local path="$1"
  local val
  val=$(curl -s -f --retry 3 --retry-connrefused --connect-timeout 2 -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/${path}" 2>/dev/null || true)
  echo "${val}"
}

# Read configuration from instance attributes
BUCKET_NAME=$(get_attribute "bucket-name" "")
RESULTS_BUCKET=$(get_attribute "results-bucket" "${BUCKET_NAME}")
RUN_ID=$(get_attribute "run-id" "$(date +%Y%m%d-%H%M%S)")
BQ_DATASET=$(get_attribute "bq-dataset" "w1r3")
BQ_TABLE=$(get_attribute "bq-table" "swift_${RUN_ID//-/_}")
BQ_LOCATION=$(get_attribute "bq-location" "")
GIT_REPO=$(get_attribute "git-repo" "https://github.com/googleapis/google-cloud-swift.git")
GIT_REF=$(get_attribute "git-ref" "main")
SOURCE_TAR_GCS=$(get_attribute "source-tar-gcs" "")
BENCHMARK_ARGS=$(get_attribute "benchmark-args" "")
AUTO_TEARDOWN=$(get_attribute "auto-teardown" "true")

# Read instance metadata
INSTANCE_NAME=$(get_instance_metadata "name")
[[ -z "${INSTANCE_NAME}" ]] && INSTANCE_NAME=$(hostname)
RAW_ZONE=$(get_instance_metadata "zone")
ZONE="${RAW_ZONE##*/}"
REGION="${ZONE%-*}"
[[ -z "${BQ_LOCATION}" ]] && BQ_LOCATION="${REGION}"
PROJECT_ID=$(get_project_metadata "project-id")
RAW_MACHINE_TYPE=$(get_instance_metadata "machine-type")
MACHINE_TYPE="${RAW_MACHINE_TYPE##*/}"

GCS_OUTPUT_DIR="gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}"
RUN_STATUS="INITIALIZING"
BENCHMARK_EXIT_CODE=-1
RUN_START_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Teardown trap handler
cleanup_and_teardown() {
  local exit_code=$?
  local end_time
  end_time="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  echo "=========================================================="
  echo "Benchmark run finished with exit code: ${exit_code}, status: ${RUN_STATUS}"
  echo "End time: ${end_time}"
  echo "=========================================================="

  # Upload logs and status to GCS if results bucket is configured
  if [[ -n "${RESULTS_BUCKET}" ]]; then
    # Flush asynchronously written log streams to disk
    sync
    sleep 1

    echo "Uploading final logs and status to ${GCS_OUTPUT_DIR}..."
    if [[ -f "/root/results.csv" ]]; then
      gcloud storage cp /root/results.csv "${GCS_OUTPUT_DIR}/results.csv" || true
    fi
    if [[ -f "/root/benchmark.log" ]]; then
      gcloud storage cp /root/benchmark.log "${GCS_OUTPUT_DIR}/benchmark.log" || true
    fi
    if [[ -f "/var/log/w1r3-startup.log" ]]; then
      gcloud storage cp /var/log/w1r3-startup.log "${GCS_OUTPUT_DIR}/startup.log" || true
    fi

    # Write metadata JSON safely with jq escaping if available
    if command -v jq &>/dev/null; then
      jq -n \
        --arg run_id "${RUN_ID}" \
        --arg project_id "${PROJECT_ID}" \
        --arg zone "${ZONE}" \
        --arg instance_name "${INSTANCE_NAME}" \
        --arg machine_type "${MACHINE_TYPE}" \
        --arg bucket_name "${BUCKET_NAME}" \
        --arg results_bucket "${RESULTS_BUCKET}" \
        --arg bq_dataset "${BQ_DATASET}" \
        --arg bq_table "${BQ_TABLE}" \
        --arg git_repo "${GIT_REPO}" \
        --arg git_ref "${GIT_REF}" \
        --arg benchmark_args "${BENCHMARK_ARGS}" \
        --arg start_time "${RUN_START_TIME}" \
        --arg end_time "${end_time}" \
        --arg status "${RUN_STATUS}" \
        --argjson exit_code "${exit_code}" \
        '{
          run_id: $run_id,
          project_id: $project_id,
          zone: $zone,
          instance_name: $instance_name,
          machine_type: $machine_type,
          bucket_name: $bucket_name,
          results_bucket: $results_bucket,
          bq_dataset: $bq_dataset,
          bq_table: $bq_table,
          git_repo: $git_repo,
          git_ref: $git_ref,
          benchmark_args: $benchmark_args,
          start_time: $start_time,
          end_time: $end_time,
          status: $status,
          exit_code: $exit_code
        }' > /root/metadata.json
    else
      cat <<EOF > /root/metadata.json
{
  "run_id": "${RUN_ID}",
  "project_id": "${PROJECT_ID}",
  "zone": "${ZONE}",
  "instance_name": "${INSTANCE_NAME}",
  "machine_type": "${MACHINE_TYPE}",
  "bucket_name": "${BUCKET_NAME}",
  "results_bucket": "${RESULTS_BUCKET}",
  "bq_dataset": "${BQ_DATASET}",
  "bq_table": "${BQ_TABLE}",
  "git_repo": "${GIT_REPO}",
  "git_ref": "${GIT_REF}",
  "benchmark_args": "${BENCHMARK_ARGS}",
  "start_time": "${RUN_START_TIME}",
  "end_time": "${end_time}",
  "status": "${RUN_STATUS}",
  "exit_code": ${exit_code}
}
EOF
    fi
    gcloud storage cp /root/metadata.json "${GCS_OUTPUT_DIR}/metadata.json" || true
    echo "${RUN_STATUS}" | gcloud storage cp - "${GCS_OUTPUT_DIR}/STATUS" || true
  fi

  if [[ "${AUTO_TEARDOWN}" == "true" ]]; then
    echo "Auto-teardown enabled. Initiating instance deletion..."
    # Attempt self-deletion via gcloud
    if gcloud compute instances delete "${INSTANCE_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" --quiet 2>/dev/null; then
      echo "Instance deletion requested successfully."
    else
      echo "Instance deletion failed or lacks permission; shutting down instance to halt compute billing..."
      poweroff || true
    fi
  else
    echo "Auto-teardown is disabled. Leaving instance running for inspection."
  fi
}
trap cleanup_and_teardown EXIT

if [[ -z "${BUCKET_NAME}" ]]; then
  echo "ERROR: 'bucket-name' instance attribute is required."
  RUN_STATUS="ERROR_MISSING_BUCKET"
  exit 1
fi

echo "Instance: ${INSTANCE_NAME} (${MACHINE_TYPE}) in ${ZONE}, Project: ${PROJECT_ID}"
echo "Bucket: ${BUCKET_NAME}, Results GCS: ${GCS_OUTPUT_DIR}"
echo "Run ID: ${RUN_ID}"

RUN_STATUS="INSTALLING_DEPENDENCIES"
echo "--- Installing build dependencies ---"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git curl binutils build-essential pkg-config \
  libicu-dev libcurl4-openssl-dev libssl-dev libxml2-dev zlib1g-dev jq \
  unzip zip gnupg2 libc6-dev libpython3-dev libncurses-dev libz3-dev

# Ensure CLI search paths include snap and system binaries
export PATH="/snap/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"

# Ensure Google Cloud CLI and bq are installed
if ! command -v gcloud &>/dev/null; then
  echo "--- Installing Google Cloud CLI ---"
  if command -v snap &>/dev/null; then
    snap install google-cloud-cli --classic || true
  fi
  if ! command -v gcloud &>/dev/null; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/cloud.google.gpg
    echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y google-cloud-cli
  fi
fi

if ! command -v bq &>/dev/null; then
  echo "--- Ensuring BigQuery CLI (bq) is installed ---"
  if command -v gcloud &>/dev/null; then
    gcloud components install bq --quiet 2>/dev/null || true
  fi
  if ! command -v bq &>/dev/null && [[ -f "/etc/apt/sources.list.d/google-cloud-sdk.list" ]]; then
    apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y google-cloud-cli-bq || true
  fi
fi

echo "--- Installing Swift toolchain ---"
if ! command -v swift &>/dev/null; then
  SWIFTLY_TMP=$(mktemp -d /tmp/swiftly-install-XXXXXX)
  (
    cd "${SWIFTLY_TMP}"
    ARCH=$(uname -m)
    curl -fsSL -O "https://download.swift.org/swiftly/linux/swiftly-${ARCH}.tar.gz"
    tar zxf "swiftly-${ARCH}.tar.gz"
    ./swiftly init --quiet-shell-followup
  )
  rm -rf "${SWIFTLY_TMP}"
  export SWIFTLY_HOME_DIR="/root/.local/share/swiftly"
  # shellcheck source=/dev/null
  source "${SWIFTLY_HOME_DIR}/env.sh"
  hash -r
  swiftly install 6.3 --use || swiftly install 6.2 --use || swiftly install latest --use
fi

echo "Swift version:"
swift --version

RUN_STATUS="FETCHING_SOURCE"
mkdir -p /root/workspace
cd /root/workspace

if [[ -n "${SOURCE_TAR_GCS}" ]]; then
  echo "--- Fetching source from GCS: ${SOURCE_TAR_GCS} ---"
  gcloud storage cp "${SOURCE_TAR_GCS}" source.tar.gz
  tar -zxf source.tar.gz
else
  echo "--- Cloning repository: ${GIT_REPO} (ref: ${GIT_REF}) ---"
  git clone "${GIT_REPO}" .
  git checkout "${GIT_REF}"
fi

RUN_STATUS="BUILDING_BENCHMARK"
echo "--- Building StorageW1R3Benchmark in release mode ---"
BUILD_FLAGS=(-c release --product StorageW1R3Benchmark -Xswiftc -warnings-as-errors)
if [[ -f "ci/swift-version.sh" ]]; then
  # shellcheck source=ci/swift-version.sh
  source "ci/swift-version.sh"
  if ! swift_supports_diagnose; then
    BUILD_FLAGS+=(-Xswiftc -Wwarning -Xswiftc DeprecatedDeclaration)
  fi
fi

export GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=1
swift build "${BUILD_FLAGS[@]}"

BIN_DIR=$(swift build "${BUILD_FLAGS[@]}" --show-bin-path 2>/dev/null || echo "/root/workspace/.build/$(uname -m)-unknown-linux-gnu/release")
BENCHMARK_BIN="${BIN_DIR}/StorageW1R3Benchmark"
if [[ ! -x "${BENCHMARK_BIN}" ]]; then
  echo "ERROR: Benchmark binary not found at ${BENCHMARK_BIN}"
  RUN_STATUS="BUILD_FAILED"
  exit 1
fi

RUN_STATUS="RUNNING_BENCHMARK"
echo "=========================================================="
echo "Executing StorageW1R3Benchmark"
echo "Command: ${BENCHMARK_BIN} --bucket-name ${BUCKET_NAME} ${BENCHMARK_ARGS}"
echo "=========================================================="

set +e
# Run benchmark, redirect stdout to results.csv and stderr to benchmark.log and console
# shellcheck disable=SC2086
"${BENCHMARK_BIN}" \
  --bucket-name "${BUCKET_NAME}" \
  ${BENCHMARK_ARGS} \
  > /root/results.csv 2> >(tee -a /root/benchmark.log)
BENCHMARK_EXIT_CODE=$?
set -e

if [[ ${BENCHMARK_EXIT_CODE} -ne 0 ]]; then
  echo "Benchmark failed with exit code: ${BENCHMARK_EXIT_CODE}"
  RUN_STATUS="BENCHMARK_FAILED"
  exit ${BENCHMARK_EXIT_CODE}
fi

echo "Benchmark finished successfully."

# Ingest results into BigQuery if dataset is specified and results file exists
if [[ -n "${BQ_DATASET}" && -s "/root/results.csv" ]]; then
  RUN_STATUS="UPLOADING_BIGQUERY"
  echo "--- Loading results into BigQuery: ${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE} ---"
  if command -v bq &>/dev/null; then
    bq show --project_id="${PROJECT_ID}" "${BQ_DATASET}" >/dev/null 2>&1 || \
      bq mk --project_id="${PROJECT_ID}" --location="${BQ_LOCATION}" --dataset "${PROJECT_ID}:${BQ_DATASET}" >/dev/null 2>&1 || true
    bq load \
      --project_id="${PROJECT_ID}" \
      --location="${BQ_LOCATION}" \
      --source_format=CSV \
      --skip_leading_rows=1 \
      --replace \
      "${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}" \
      /root/results.csv \
      Task:INT64,Iteration:INT64,IterationStart:INT64,Operation:STRING,Size:INT64,TransferSize:INT64,ElapsedMicroseconds:INT64,Object:STRING,Crc32cEnabled:BOOL,Result:STRING,Details:STRING || {
        echo "WARNING: Failed to load results into BigQuery from VM. Results CSV is preserved in GCS."
      }
  else
    echo "WARNING: 'bq' CLI not available on VM. Results will be loaded into BigQuery from the host deployment script."
  fi
fi

RUN_STATUS="SUCCESS"
echo "All benchmark tasks completed successfully!"
