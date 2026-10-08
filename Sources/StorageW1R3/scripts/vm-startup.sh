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
echo "Starting Google Cloud Swift Benchmark Runner on GCE"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=========================================================="

get_attribute() {
  local key="$1"
  local default_val="${2:-}"
  local val
  if val=$(curl -s -f --retry 3 --retry-connrefused --connect-timeout 2 -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${key}" 2>/dev/null); then
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
DEFAULT_W1R3_SCHEMA="Task:INT64,Iteration:INT64,IterationStart:INT64,Operation:STRING,Size:INT64,TransferSize:INT64,ElapsedMicroseconds:INT64,Object:STRING,Crc32cEnabled:BOOL,Result:STRING,Details:STRING"
BQ_SCHEMA=$(get_attribute "bq-schema" "")
GIT_REPO=$(get_attribute "git-repo" "https://github.com/googleapis/google-cloud-swift.git")
GIT_REF=$(get_attribute "git-ref" "main")
SOURCE_TAR_GCS=$(get_attribute "source-tar-gcs" "")
BENCHMARK_ARGS=$(get_attribute "benchmark-args" "")
BENCHMARK_PRODUCT=$(get_attribute "benchmark-product" "StorageW1R3Benchmark")
BENCHMARK_PACKAGE_PATH=$(get_attribute "benchmark-package-path" "")
BENCHMARK_COMMAND=$(get_attribute "benchmark-command" "")
COMPARE_ENABLED=$(get_attribute "compare-enabled" "false")
COMPARE_REPO=$(get_attribute "compare-repo" "${GIT_REPO}")
COMPARE_REF=$(get_attribute "compare-ref" "${GIT_REF}")
COMPARE_SOURCE_TAR_GCS=$(get_attribute "compare-source-tar-gcs" "")
COMPARE_BENCHMARK_ARGS=$(get_attribute "compare-benchmark-args" "${BENCHMARK_ARGS}")
BASELINE_LABEL=$(get_attribute "baseline-label" "baseline")
COMPARE_LABEL=$(get_attribute "compare-label" "experiment")
ROUNDS=$(get_attribute "rounds" "1")
[[ "${ROUNDS}" =~ ^[1-9][0-9]*$ ]] || ROUNDS=1
AUTO_TEARDOWN=$(get_attribute "auto-teardown" "true")

MULTI_RUN_SCHEMA=false
if [[ "${COMPARE_ENABLED}" == "true" || "${ROUNDS}" -gt 1 ]]; then
  MULTI_RUN_SCHEMA=true
fi

if [[ "${BQ_SCHEMA}" == "none" ]]; then
  BQ_DATASET=""
  BQ_SCHEMA=""
elif [[ -n "${BQ_DATASET}" && -z "${BQ_SCHEMA}" && "${BENCHMARK_PRODUCT}" == "StorageW1R3Benchmark" && -z "${BENCHMARK_COMMAND}" ]]; then
  if [[ "${MULTI_RUN_SCHEMA}" == "true" ]]; then
    BQ_SCHEMA="Variant:STRING,Round:INT64,${DEFAULT_W1R3_SCHEMA}"
  else
    BQ_SCHEMA="${DEFAULT_W1R3_SCHEMA}"
  fi
fi

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
mkdir -p /root/runs

# Teardown trap handler
cleanup_and_teardown() {
  local exit_code=$?
  set +e
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
    if [[ -d "/root/runs" ]]; then
      shopt -s nullglob
      local run_artifacts=(/root/runs/*)
      shopt -u nullglob
      if [[ ${#run_artifacts[@]} -gt 0 ]]; then
        gcloud storage cp "${run_artifacts[@]}" "${GCS_OUTPUT_DIR}/" || true
      fi
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
        --arg bq_schema "${BQ_SCHEMA}" \
        --arg git_repo "${GIT_REPO}" \
        --arg git_ref "${GIT_REF}" \
        --arg benchmark_args "${BENCHMARK_ARGS}" \
        --arg benchmark_product "${BENCHMARK_PRODUCT}" \
        --arg benchmark_package_path "${BENCHMARK_PACKAGE_PATH}" \
        --arg benchmark_command "${BENCHMARK_COMMAND}" \
        --arg compare_enabled "${COMPARE_ENABLED}" \
        --arg compare_repo "${COMPARE_REPO}" \
        --arg compare_ref "${COMPARE_REF}" \
        --arg compare_benchmark_args "${COMPARE_BENCHMARK_ARGS}" \
        --arg baseline_label "${BASELINE_LABEL}" \
        --arg compare_label "${COMPARE_LABEL}" \
        --argjson rounds "${ROUNDS}" \
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
          bq_schema: $bq_schema,
          git_repo: $git_repo,
          git_ref: $git_ref,
          benchmark_args: $benchmark_args,
          benchmark_product: $benchmark_product,
          benchmark_package_path: $benchmark_package_path,
          benchmark_command: $benchmark_command,
          compare_enabled: ($compare_enabled == "true"),
          compare_repo: $compare_repo,
          compare_ref: $compare_ref,
          compare_benchmark_args: $compare_benchmark_args,
          baseline_label: $baseline_label,
          compare_label: $compare_label,
          rounds: $rounds,
          start_time: $start_time,
          end_time: $end_time,
          status: $status,
          exit_code: $exit_code
        }' > /root/metadata.json || true
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
  "bq_schema": "${BQ_SCHEMA}",
  "git_repo": "${GIT_REPO}",
  "git_ref": "${GIT_REF}",
  "benchmark_args": "${BENCHMARK_ARGS}",
  "benchmark_product": "${BENCHMARK_PRODUCT}",
  "benchmark_package_path": "${BENCHMARK_PACKAGE_PATH}",
  "benchmark_command": "${BENCHMARK_COMMAND}",
  "compare_enabled": ${COMPARE_ENABLED},
  "compare_repo": "${COMPARE_REPO}",
  "compare_ref": "${COMPARE_REF}",
  "compare_benchmark_args": "${COMPARE_BENCHMARK_ARGS}",
  "baseline_label": "${BASELINE_LABEL}",
  "compare_label": "${COMPARE_LABEL}",
  "rounds": ${ROUNDS},
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

if [[ "${BENCHMARK_PRODUCT}" == "StorageW1R3Benchmark" && -z "${BENCHMARK_COMMAND}" && -z "${BUCKET_NAME}" ]]; then
  echo "ERROR: 'bucket-name' instance attribute is required for StorageW1R3Benchmark."
  RUN_STATUS="ERROR_MISSING_BUCKET"
  exit 1
fi

echo "Instance: ${INSTANCE_NAME} (${MACHINE_TYPE}) in ${ZONE}, Project: ${PROJECT_ID}"
echo "Bucket: ${BUCKET_NAME}, Results GCS: ${GCS_OUTPUT_DIR}"
echo "Run ID: ${RUN_ID}, Product: ${BENCHMARK_PRODUCT}, Compare: ${COMPARE_ENABLED}, Rounds: ${ROUNDS}"

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

if [[ -n "${BQ_DATASET}" && -n "${BQ_SCHEMA}" ]] && ! command -v bq &>/dev/null; then
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

export GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true

prepare_workspace() {
  local workspace_dir="$1"
  local repo_url="$2"
  local git_ref="$3"
  local source_tar="$4"
  local label="$5"

  rm -rf "${workspace_dir}"
  mkdir -p "${workspace_dir}"
  if [[ -n "${source_tar}" ]]; then
    echo "--- [${label}] Fetching staged source from GCS: ${source_tar} ---"
    gcloud storage cp "${source_tar}" "${workspace_dir}/source.tar.gz"
    tar -zxf "${workspace_dir}/source.tar.gz" -C "${workspace_dir}"
    rm -f "${workspace_dir}/source.tar.gz"
  else
    echo "--- [${label}] Cloning repository: ${repo_url} (ref: ${git_ref}) ---"
    git clone "${repo_url}" "${workspace_dir}"
    git -C "${workspace_dir}" checkout "${git_ref}"
  fi
}

build_benchmark() {
  local workspace_dir="$1"
  local pkg_path="$2"
  local product="$3"
  local label="$4"
  local out_bin_var="$5"

  echo "--- [${label}] Building ${product} in release mode ---"
  local build_flags=(-c release --product "${product}" -Xswiftc -warnings-as-errors)
  if [[ -n "${pkg_path}" ]]; then
    build_flags+=(--package-path "${workspace_dir}/${pkg_path}")
  else
    build_flags+=(--package-path "${workspace_dir}")
  fi

  if [[ -f "${workspace_dir}/ci/swift-version.sh" ]]; then
    # shellcheck source=/dev/null
    source "${workspace_dir}/ci/swift-version.sh"
    if ! swift_supports_diagnose; then
      build_flags+=(-Xswiftc -Wwarning -Xswiftc DeprecatedDeclaration)
    fi
  fi

  swift build "${build_flags[@]}"

  local bin_dir
  bin_dir=$(swift build "${build_flags[@]}" --show-bin-path 2>/dev/null || echo "${workspace_dir}/.build/$(uname -m)-unknown-linux-gnu/release")
  local bin_path="${bin_dir}/${product}"
  if [[ ! -x "${bin_path}" ]]; then
    echo "ERROR: [${label}] Benchmark binary not found at ${bin_path}"
    RUN_STATUS="BUILD_FAILED"
    exit 1
  fi

  printf -v "${out_bin_var}" "%s" "${bin_path}"
}

RUN_STATUS="FETCHING_SOURCE"
WORKSPACE_A="/root/workspace-a"
prepare_workspace "${WORKSPACE_A}" "${GIT_REPO}" "${GIT_REF}" "${SOURCE_TAR_GCS}" "${BASELINE_LABEL}"

RUN_STATUS="BUILDING_BENCHMARK"
BIN_A=""
build_benchmark "${WORKSPACE_A}" "${BENCHMARK_PACKAGE_PATH}" "${BENCHMARK_PRODUCT}" "${BASELINE_LABEL}" BIN_A

BIN_B="${BIN_A}"
WORKSPACE_B="${WORKSPACE_A}"
if [[ "${COMPARE_ENABLED}" == "true" ]]; then
  # Only clone and compile a second workspace if the source repository, git ref, or staged archive differs
  if [[ "${COMPARE_SOURCE_TAR_GCS}" != "${SOURCE_TAR_GCS}" || "${COMPARE_REPO}" != "${GIT_REPO}" || "${COMPARE_REF}" != "${GIT_REF}" ]]; then
    RUN_STATUS="FETCHING_COMPARE_SOURCE"
    WORKSPACE_B="/root/workspace-b"
    prepare_workspace "${WORKSPACE_B}" "${COMPARE_REPO}" "${COMPARE_REF}" "${COMPARE_SOURCE_TAR_GCS}" "${COMPARE_LABEL}"

    RUN_STATUS="BUILDING_COMPARE_BENCHMARK"
    build_benchmark "${WORKSPACE_B}" "${BENCHMARK_PACKAGE_PATH}" "${BENCHMARK_PRODUCT}" "${COMPARE_LABEL}" BIN_B
  else
    echo "--- [${COMPARE_LABEL}] Source matches [${BASELINE_LABEL}]; reusing compiled binary ${BIN_A} ---"
  fi
fi

CSV_HEADER_WRITTEN=false

append_to_combined_csv() {
  local raw_csv="$1"
  local variant_label="$2"
  local round_num="$3"

  [[ -s "${raw_csv}" ]] || return 0

  if [[ "${MULTI_RUN_SCHEMA}" != "true" ]]; then
    cp "${raw_csv}" /root/results.csv
    CSV_HEADER_WRITTEN=true
    return 0
  fi

  if [[ "${CSV_HEADER_WRITTEN}" != "true" ]]; then
    local first_line
    first_line=$(head -n 1 "${raw_csv}" | tr -d '\r')
    echo "Variant,Round,${first_line}" > /root/results.csv
    CSV_HEADER_WRITTEN=true
  fi

  tail -n +2 "${raw_csv}" | tr -d '\r' | awk -v v="${variant_label}" -v r="${round_num}" 'NF > 0 { print v "," r "," $0 }' >> /root/results.csv
}

run_single_execution() {
  local variant_label="$1"
  local round_num="$2"
  local workspace_dir="$3"
  local bin_path="$4"
  local args="$5"

  local run_tag="${variant_label}-round-${round_num}"
  local raw_csv="/root/runs/results-${run_tag}.csv"
  local run_log="/root/runs/benchmark-${run_tag}.log"

  echo "=========================================================="
  echo "Executing [${variant_label}] (Round ${round_num}/${ROUNDS})"
  echo "Binary: ${bin_path}"
  if [[ -n "${BENCHMARK_COMMAND}" ]]; then
    local rendered_cmd="${BENCHMARK_COMMAND//\{BIN\}/${bin_path}}"
    rendered_cmd="${rendered_cmd//\{BUCKET\}/${BUCKET_NAME}}"
    if [[ -n "${args}" ]]; then
      rendered_cmd="${rendered_cmd} ${args}"
    fi
    echo "Command: ${rendered_cmd}"
    echo "=========================================================="
    echo "=== [${variant_label}] Round ${round_num}/${ROUNDS} ($(date -u +"%Y-%m-%dT%H:%M:%SZ")) ===" >> /root/benchmark.log

    set +e
    (
      cd "${workspace_dir}"
      bash -c "${rendered_cmd}"
    ) 2> >(tee -a "${run_log}" /root/benchmark.log) > "${raw_csv}"
    BENCHMARK_EXIT_CODE=$?
    set -e
  else
    local cmd=("${bin_path}")
    if [[ "${BENCHMARK_PRODUCT}" == "StorageW1R3Benchmark" && -n "${BUCKET_NAME}" ]]; then
      cmd+=(--bucket-name "${BUCKET_NAME}")
    fi
    if [[ -n "${args}" ]]; then
      local extra_arr=()
      mapfile -t extra_arr < <(xargs -n 1 <<< "${args}")
      cmd+=("${extra_arr[@]}")
    fi
    echo "Command: ${cmd[*]}"
    echo "=========================================================="
    echo "=== [${variant_label}] Round ${round_num}/${ROUNDS} ($(date -u +"%Y-%m-%dT%H:%M:%SZ")) ===" >> /root/benchmark.log

    set +e
    # Run benchmark, redirect stdout to raw_csv and stderr to run_log, benchmark.log, and console.
    # In Bash, redirections are evaluated left to right; placing 2> before > ensures tee inherits
    # the console/startup log stdout rather than raw_csv.
    (
      cd "${workspace_dir}"
      "${cmd[@]}"
    ) 2> >(tee -a "${run_log}" /root/benchmark.log) > "${raw_csv}"
    BENCHMARK_EXIT_CODE=$?
    set -e
  fi

  if [[ ${BENCHMARK_EXIT_CODE} -ne 0 ]]; then
    echo "Benchmark [${variant_label}] (Round ${round_num}) failed with exit code: ${BENCHMARK_EXIT_CODE}"
    RUN_STATUS="BENCHMARK_FAILED"
    exit "${BENCHMARK_EXIT_CODE}"
  fi

  append_to_combined_csv "${raw_csv}" "${variant_label}" "${round_num}"
  echo "✓ Completed [${variant_label}] (Round ${round_num}/${ROUNDS})"
}

RUN_STATUS="RUNNING_BENCHMARK"
for (( round=1; round<=ROUNDS; round++ )); do
  run_single_execution "${BASELINE_LABEL}" "${round}" "${WORKSPACE_A}" "${BIN_A}" "${BENCHMARK_ARGS}"
  if [[ "${COMPARE_ENABLED}" == "true" ]]; then
    run_single_execution "${COMPARE_LABEL}" "${round}" "${WORKSPACE_B}" "${BIN_B}" "${COMPARE_BENCHMARK_ARGS}"
  fi
done

echo "All benchmark rounds finished successfully."

# Ingest results into BigQuery if dataset and schema are specified and results file exists
if [[ -n "${BQ_DATASET}" && -n "${BQ_SCHEMA}" && -s "/root/results.csv" ]]; then
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
      "${BQ_SCHEMA}" || {
        echo "WARNING: Failed to load results into BigQuery from VM. Results CSV is preserved in GCS."
      }
  else
    echo "WARNING: 'bq' CLI not available on VM. Results will be loaded into BigQuery from the host deployment script."
  fi
fi

RUN_STATUS="SUCCESS"
echo "All benchmark tasks completed successfully!"
