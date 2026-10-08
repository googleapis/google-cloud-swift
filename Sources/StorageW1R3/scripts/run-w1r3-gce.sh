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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLEANUP_FILES=()
cleanup_host() {
  if [[ ${#CLEANUP_FILES[@]} -gt 0 ]]; then
    for f in "${CLEANUP_FILES[@]}"; do
      if [[ -e "${f}" ]]; then
        rm -f "${f}"
      fi
    done
  fi
}
trap cleanup_host EXIT INT TERM

usage() {
  cat <<'EOF'
Usage: run-w1r3-gce.sh [OPTIONS]

Deploys and runs benchmarks (default: Cloud Storage W1R3) on a Google Compute Engine (GCE) VM,
uploads performance metrics to Cloud Storage and BigQuery, and automatically tears down
the VM to prevent unnecessary compute costs.

Supports A/B testing two branches, commits, or runtime configurations on the same GCE instance
across interleaved execution rounds for statistically sound hardware-equivalent comparisons.

Options:
  --project PROJECT_ID         GCP project ID (default: current gcloud project)
  --zone ZONE                  GCE zone (default: us-central1-a)
  --region REGION              GCP region (default: derived from zone)
  --machine-type TYPE          GCE machine type (default: c4-standard-192)
  --bucket BUCKET_NAME         GCS test bucket name (has 1-day auto-delete lifecycle; default: w1r3-<PROJECT>-<REGION>)
  --results-bucket BUCKET_NAME GCS bucket for persistent results and logs (default: w1r3-results-<PROJECT>-<REGION>)
  --bq-dataset DATASET         BigQuery dataset for benchmark results (default: w1r3)
  --bq-table TABLE             BigQuery table name (default: swift_<RUN_ID>)
  --bq-schema SCHEMA           BigQuery CSV schema (default: W1R3 schema; use 'none' or --no-bq to skip BigQuery load)
  --no-bq                      Disable BigQuery ingestion
  --git-repo URL               Git repository URL to clone on the VM for baseline
                               (default: current git origin or https://github.com/googleapis/google-cloud-swift.git)
  --git-ref REF                Git commit, branch, or tag to checkout for baseline
                               (default: current git commit, or 'main' when --compare-stage-local is used)
  --stage-local                Stage current local repository directory to GCS for the baseline build,
                               enabling benchmarking of uncommitted or unpushed changes.
  --service-account EMAIL      Service account for the GCE VM (default: Compute Engine default SA)
  --task-count N               Number of concurrent benchmark tasks (default: 4)
  --iterations N               Number of iterations per task (default: 100)
  --min-object-size SIZE       Minimum object size, e.g. 0, 128KiB, 1MiB (default: 0)
  --max-object-size SIZE       Maximum object size, e.g. 128KiB, 1MiB, 16MiB (default: 128KiB)
  --read-count N               Number of reads per uploaded object (default: 3)
  --client-count N             Number of Storage clients (default: 1)
  --crc32c MODE                CRC32C mode: always, random, never (default: always)
  --extra-args "ARGS"          Extra arguments passed to the benchmark (or baseline in comparison mode)

A/B Comparison & Multi-Round Options:
  --compare-ref REF            Git commit, branch, or tag for the comparison ('experiment') variant
  --compare-repo URL           Git repository URL for the comparison variant (default: same as --git-repo)
  --compare-stage-local        Stage local working tree as the comparison ('experiment') variant
                               (while baseline builds from --git-ref, defaulting to 'main')
  --compare-extra-args "ARGS"  Extra arguments for the comparison variant (default: same as --extra-args).
                               Can be used alone to compare two flag configurations on the same build.
  --baseline-label LABEL       Label for Variant A in results (default: 'baseline')
  --compare-label LABEL        Label for Variant B in results (default: 'experiment')
  --rounds N                   Number of interleaved execution rounds per variant
                               (default: 1 for single run, 3 when comparison mode is enabled)

Generic Target / Custom Benchmark Options:
  --product NAME               Swift executable product to build and run (default: StorageW1R3Benchmark)
  --package-path PATH          Relative package path within the repository if building a subpackage
  --command "CMD"              Custom command template to run per execution. Supports placeholders:
                               {BIN} (path to built executable) and {BUCKET} (GCS test bucket name).
                               Extra arguments (--extra-args / --compare-extra-args) are appended.

Execution Lifecycle Options:
  --no-wait / --async          Launch the VM and return immediately without tailing logs
  --keep-vm / --no-teardown    Do not delete the VM after the benchmark completes
  -h, --help                   Show this help message and exit

Examples:
  # Quick smoke test with default settings:
  ./Sources/StorageW1R3/scripts/run-w1r3-gce.sh --task-count 2 --iterations 10

  # Compare a feature branch against main across 3 interleaved rounds on the same VM:
  ./Sources/StorageW1R3/scripts/run-w1r3-gce.sh \
    --git-ref main \
    --compare-ref my-feature-branch \
    --rounds 3

  # Compare uncommitted local changes against main across 3 rounds:
  ./Sources/StorageW1R3/scripts/run-w1r3-gce.sh \
    --compare-stage-local \
    --rounds 3

  # Compare two runtime configurations (streaming vs chunked resumable uploads) on the same binary:
  ./Sources/StorageW1R3/scripts/run-w1r3-gce.sh \
    --baseline-label streaming \
    --extra-args "--resumable-mode streaming" \
    --compare-label chunked \
    --compare-extra-args "--resumable-mode chunked" \
    --rounds 3
EOF
  exit 0
}

# Default configurations
PROJECT_ID=""
ZONE="us-central1-a"
REGION=""
MACHINE_TYPE="c4-standard-192"
BUCKET_NAME=""
RESULTS_BUCKET=""
BQ_DATASET="w1r3"
BQ_TABLE=""
DEFAULT_W1R3_SCHEMA="Task:INT64,Iteration:INT64,IterationStart:INT64,Operation:STRING,Size:INT64,TransferSize:INT64,ElapsedMicroseconds:INT64,Object:STRING,Crc32cEnabled:BOOL,Result:STRING,Details:STRING"
BQ_SCHEMA=""
NO_BQ=false
GIT_REPO=""
GIT_REF=""
STAGE_LOCAL=false
SERVICE_ACCOUNT=""
TASK_COUNT=4
ITERATIONS=100
MIN_OBJECT_SIZE="0"
MAX_OBJECT_SIZE="128KiB"
READ_COUNT=3
CLIENT_COUNT=1
CRC32C="always"
EXTRA_ARGS=""
COMPARE_REF=""
COMPARE_REPO=""
COMPARE_STAGE_LOCAL=false
COMPARE_EXTRA_ARGS=""
COMPARE_EXTRA_ARGS_SET=false
BASELINE_LABEL="baseline"
COMPARE_LABEL="experiment"
ROUNDS=""
BENCHMARK_PRODUCT="StorageW1R3Benchmark"
BENCHMARK_PACKAGE_PATH=""
BENCHMARK_COMMAND=""
WAIT_FOR_COMPLETION=true
AUTO_TEARDOWN=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_ID="$2"; shift 2 ;;
    --zone) ZONE="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --machine-type) MACHINE_TYPE="$2"; shift 2 ;;
    --bucket) BUCKET_NAME="$2"; shift 2 ;;
    --results-bucket) RESULTS_BUCKET="$2"; shift 2 ;;
    --bq-dataset) BQ_DATASET="$2"; shift 2 ;;
    --bq-table) BQ_TABLE="$2"; shift 2 ;;
    --bq-schema) BQ_SCHEMA="$2"; shift 2 ;;
    --no-bq) NO_BQ=true; shift 1 ;;
    --git-repo) GIT_REPO="$2"; shift 2 ;;
    --git-ref) GIT_REF="$2"; shift 2 ;;
    --stage-local) STAGE_LOCAL=true; shift 1 ;;
    --service-account) SERVICE_ACCOUNT="$2"; shift 2 ;;
    --task-count) TASK_COUNT="$2"; shift 2 ;;
    --iterations) ITERATIONS="$2"; shift 2 ;;
    --min-object-size) MIN_OBJECT_SIZE="$2"; shift 2 ;;
    --max-object-size) MAX_OBJECT_SIZE="$2"; shift 2 ;;
    --read-count) READ_COUNT="$2"; shift 2 ;;
    --client-count) CLIENT_COUNT="$2"; shift 2 ;;
    --crc32c) CRC32C="$2"; shift 2 ;;
    --extra-args) EXTRA_ARGS="$2"; shift 2 ;;
    --compare-ref) COMPARE_REF="$2"; shift 2 ;;
    --compare-repo) COMPARE_REPO="$2"; shift 2 ;;
    --compare-stage-local) COMPARE_STAGE_LOCAL=true; shift 1 ;;
    --compare-extra-args) COMPARE_EXTRA_ARGS="$2"; COMPARE_EXTRA_ARGS_SET=true; shift 2 ;;
    --baseline-label) BASELINE_LABEL="$2"; shift 2 ;;
    --compare-label) COMPARE_LABEL="$2"; shift 2 ;;
    --rounds) ROUNDS="$2"; shift 2 ;;
    --product) BENCHMARK_PRODUCT="$2"; shift 2 ;;
    --package-path) BENCHMARK_PACKAGE_PATH="$2"; shift 2 ;;
    --command) BENCHMARK_COMMAND="$2"; shift 2 ;;
    --no-wait|--async) WAIT_FOR_COMPLETION=false; shift 1 ;;
    --keep-vm|--no-teardown) AUTO_TEARDOWN=false; shift 1 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; echo "Run with --help for usage." >&2; exit 1 ;;
  esac
done

validate_label() {
  local label="$1"
  local flag_name="$2"
  if [[ ! "${label}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: ${flag_name} '${label}' may only contain alphanumeric characters, dots, underscores, and hyphens." >&2
    exit 1
  fi
}

validate_label "${BASELINE_LABEL}" "--baseline-label"
validate_label "${COMPARE_LABEL}" "--compare-label"

# Determine whether comparison mode is active
COMPARE_ENABLED=false
if [[ -n "${COMPARE_REF}" || "${COMPARE_STAGE_LOCAL}" == "true" || "${COMPARE_EXTRA_ARGS_SET}" == "true" || -n "${COMPARE_REPO}" ]]; then
  COMPARE_ENABLED=true
fi

if [[ "${COMPARE_ENABLED}" == "true" && "${BASELINE_LABEL}" == "${COMPARE_LABEL}" ]]; then
  echo "ERROR: --baseline-label and --compare-label must be distinct in comparison mode (both are '${BASELINE_LABEL}')." >&2
  exit 1
fi

if [[ -z "${ROUNDS}" ]]; then
  if [[ "${COMPARE_ENABLED}" == "true" ]]; then
    ROUNDS=3
  else
    ROUNDS=1
  fi
fi

if [[ ! "${ROUNDS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --rounds must be a positive integer (got '${ROUNDS}')." >&2
  exit 1
fi

if [[ "${NO_BQ}" == "true" || "${BQ_SCHEMA}" == "none" ]]; then
  BQ_DATASET=""
  BQ_SCHEMA=""
fi

# Determine whether CSV output includes Variant and Round columns
MULTI_RUN_SCHEMA=false
if [[ "${COMPARE_ENABLED}" == "true" || "${ROUNDS}" -gt 1 ]]; then
  MULTI_RUN_SCHEMA=true
fi

if [[ -n "${BQ_DATASET}" && -z "${BQ_SCHEMA}" ]]; then
  if [[ "${BENCHMARK_PRODUCT}" == "StorageW1R3Benchmark" && -z "${BENCHMARK_COMMAND}" ]]; then
    BQ_SCHEMA="${DEFAULT_W1R3_SCHEMA}"
  fi
fi

EFFECTIVE_BQ_SCHEMA="${BQ_SCHEMA}"
if [[ -n "${EFFECTIVE_BQ_SCHEMA}" && "${MULTI_RUN_SCHEMA}" == "true" ]]; then
  EFFECTIVE_BQ_SCHEMA="Variant:STRING,Round:INT64,${EFFECTIVE_BQ_SCHEMA}"
fi

# Prerequisite checks
if ! command -v gcloud &>/dev/null; then
  echo "ERROR: 'gcloud' CLI is required but not found in PATH." >&2
  exit 1
fi

if [[ -n "${BQ_DATASET}" ]] && ! command -v bq &>/dev/null; then
  echo "WARNING: 'bq' CLI not found. BigQuery loading might be skipped if not available on VM." >&2
fi

if [[ -n "${BQ_DATASET}" ]] && ! command -v jq &>/dev/null; then
  echo "Notice: 'jq' CLI not found. Falling back to pattern extraction for BigQuery dataset location." >&2
fi

# Detect project
if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
  if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
    echo "ERROR: GCP project is not configured in gcloud and was not specified via --project." >&2
    exit 1
  fi
fi

# Derive region from zone if unset (e.g. us-central1-a -> us-central1)
if [[ -z "${REGION}" ]]; then
  REGION="${ZONE%-*}"
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 2 2>/dev/null || date +%s)"
INSTANCE_NAME="w1r3-${RUN_ID}"

if [[ -z "${BUCKET_NAME}" ]]; then
  BUCKET_NAME="w1r3-${PROJECT_ID}-${REGION}"
fi

if [[ -z "${RESULTS_BUCKET}" ]]; then
  RESULTS_BUCKET="w1r3-results-${PROJECT_ID}-${REGION}"
fi

if [[ -z "${BQ_TABLE}" ]]; then
  BQ_TABLE="swift_${RUN_ID//-/_}"
else
  # BigQuery table names cannot contain hyphens
  BQ_TABLE="${BQ_TABLE//-/_}"
fi

# Detect Git repo and ref if not specified
if [[ -z "${GIT_REPO}" ]]; then
  GIT_REPO=$(git config --get remote.origin.url 2>/dev/null || echo "https://github.com/googleapis/google-cloud-swift.git")
fi
# Convert git@github.com:org/repo.git to https://github.com/org/repo.git for VM access
if [[ "${GIT_REPO}" =~ ^git@github\.com:(.*)$ ]]; then
  GIT_REPO="https://github.com/${BASH_REMATCH[1]}"
fi

if [[ -z "${GIT_REF}" ]]; then
  if [[ "${COMPARE_STAGE_LOCAL}" == "true" && "${STAGE_LOCAL}" != "true" ]]; then
    # When staging local tree as the experiment without an explicit baseline ref, default baseline to main
    GIT_REF="main"
  else
    GIT_REF=$(git rev-parse HEAD 2>/dev/null || echo "main")
  fi
fi

if [[ "${COMPARE_ENABLED}" == "true" ]]; then
  if [[ -z "${COMPARE_REPO}" ]]; then
    COMPARE_REPO="${GIT_REPO}"
  fi
  if [[ "${COMPARE_REPO}" =~ ^git@github\.com:(.*)$ ]]; then
    COMPARE_REPO="https://github.com/${BASH_REMATCH[1]}"
  fi
  if [[ -z "${COMPARE_REF}" ]]; then
    COMPARE_REF="${GIT_REF}"
  fi
  if [[ "${COMPARE_EXTRA_ARGS_SET}" != "true" ]]; then
    COMPARE_EXTRA_ARGS="${EXTRA_ARGS}"
  fi
fi

echo "=========================================================="
echo "Google Cloud Swift Benchmark - GCE Deployment"
echo "=========================================================="
echo "Project:         ${PROJECT_ID}"
echo "Zone:            ${ZONE} (Region: ${REGION})"
echo "Machine Type:    ${MACHINE_TYPE}"
echo "Instance:        ${INSTANCE_NAME}"
echo "Product:         ${BENCHMARK_PRODUCT}${BENCHMARK_PACKAGE_PATH:+ (package: ${BENCHMARK_PACKAGE_PATH})}"
if [[ -n "${BENCHMARK_COMMAND}" ]]; then
  echo "Custom Command:  ${BENCHMARK_COMMAND}"
fi
echo "Test Bucket:     gs://${BUCKET_NAME}"
echo "Results Bucket:  gs://${RESULTS_BUCKET}"
if [[ "${RESULTS_BUCKET}" == "${BUCKET_NAME}" ]]; then
  echo "WARNING: Results bucket is identical to test bucket. Output artifacts may be purged after 24h by bucket lifecycle rules." >&2
fi
if [[ -n "${BQ_DATASET}" && -n "${EFFECTIVE_BQ_SCHEMA}" ]]; then
  echo "BigQuery Target: ${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}"
else
  echo "BigQuery Target: (disabled)"
fi
if [[ "${COMPARE_ENABLED}" == "true" ]]; then
  echo "Mode:            A/B Comparison (${ROUNDS} interleaved round(s))"
  if [[ "${STAGE_LOCAL}" == "true" ]]; then
    echo "  Variant A [${BASELINE_LABEL}]: Local working tree ${EXTRA_ARGS:+(extra-args: ${EXTRA_ARGS})}"
  else
    echo "  Variant A [${BASELINE_LABEL}]: ${GIT_REPO} @ ${GIT_REF} ${EXTRA_ARGS:+(extra-args: ${EXTRA_ARGS})}"
  fi
  if [[ "${COMPARE_STAGE_LOCAL}" == "true" ]]; then
    echo "  Variant B [${COMPARE_LABEL}]: Local working tree ${COMPARE_EXTRA_ARGS:+(extra-args: ${COMPARE_EXTRA_ARGS})}"
  else
    echo "  Variant B [${COMPARE_LABEL}]: ${COMPARE_REPO} @ ${COMPARE_REF} ${COMPARE_EXTRA_ARGS:+(extra-args: ${COMPARE_EXTRA_ARGS})}"
  fi
else
  echo "Mode:            Single Configuration (${ROUNDS} round(s))"
  echo "Git Source:      ${GIT_REPO} @ ${GIT_REF}"
  if [[ "${STAGE_LOCAL}" == "true" ]]; then
    echo "Source Mode:     Staging local working tree"
  fi
fi
if [[ "${BENCHMARK_PRODUCT}" == "StorageW1R3Benchmark" && -z "${BENCHMARK_COMMAND}" ]]; then
  echo "Benchmark Config: tasks=${TASK_COUNT}, iterations=${ITERATIONS}, size=${MIN_OBJECT_SIZE}..${MAX_OBJECT_SIZE}, reads=${READ_COUNT}, crc32c=${CRC32C}"
fi
echo "Auto-teardown:   ${AUTO_TEARDOWN}"
echo "=========================================================="

# 1. Ensure test bucket exists
echo "Checking test bucket gs://${BUCKET_NAME}..."
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Bucket gs://${BUCKET_NAME} does not exist. Creating regional bucket with recommended performance settings..."
  LF_FILE="${SCRIPT_DIR}/lf.json"
  gcloud storage buckets create \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --enable-hierarchical-namespace \
    --uniform-bucket-level-access \
    --soft-delete-duration=0s \
    --lifecycle-file="${LF_FILE}" \
    "gs://${BUCKET_NAME}"
  echo "✓ Bucket gs://${BUCKET_NAME} created."
else
  echo "✓ Bucket gs://${BUCKET_NAME} exists."
fi

# Ensure results bucket exists if distinct
if [[ "${RESULTS_BUCKET}" != "${BUCKET_NAME}" ]]; then
  if ! gcloud storage buckets describe "gs://${RESULTS_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Creating results bucket gs://${RESULTS_BUCKET}..."
    gcloud storage buckets create \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --uniform-bucket-level-access \
      "gs://${RESULTS_BUCKET}"
    echo "✓ Results bucket gs://${RESULTS_BUCKET} created."
  fi
fi

# 2. Configure Service Account
if [[ -z "${SERVICE_ACCOUNT}" ]]; then
  PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')
  SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
fi
echo "Using VM Service Account: ${SERVICE_ACCOUNT}"

# Grant storage objectAdmin on the test and results bucket
echo "Ensuring IAM permissions on buckets..."
if ! gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/storage.objectAdmin" >/dev/null 2>&1; then
  echo "WARNING: Could not grant storage.objectAdmin on gs://${BUCKET_NAME}. Ensure ${SERVICE_ACCOUNT} has write access." >&2
fi

if [[ "${RESULTS_BUCKET}" != "${BUCKET_NAME}" ]]; then
  if ! gcloud storage buckets add-iam-policy-binding "gs://${RESULTS_BUCKET}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/storage.objectAdmin" >/dev/null 2>&1; then
    echo "WARNING: Could not grant storage.objectAdmin on gs://${RESULTS_BUCKET}. Ensure ${SERVICE_ACCOUNT} has write access." >&2
  fi
fi

# Ensure BigQuery permissions for the VM service account and ensure dataset exists
BQ_LOCATION=""
if [[ -n "${BQ_DATASET}" && -n "${EFFECTIVE_BQ_SCHEMA}" ]]; then
  echo "Ensuring BigQuery jobUser permission for VM service account..."
  if ! gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/bigquery.jobUser" \
    --condition=None >/dev/null 2>&1; then
    echo "WARNING: Could not grant roles/bigquery.jobUser on project ${PROJECT_ID}. Ensure ${SERVICE_ACCOUNT} can run BigQuery jobs." >&2
  fi

  if command -v bq &>/dev/null; then
    echo "Checking BigQuery dataset '${PROJECT_ID}:${BQ_DATASET}'..."
    if bq show --project_id="${PROJECT_ID}" "${BQ_DATASET}" >/dev/null 2>&1; then
      if command -v jq &>/dev/null; then
        BQ_LOCATION=$(bq show --project_id="${PROJECT_ID}" --format=prettyjson "${BQ_DATASET}" 2>/dev/null | jq -r '.location // empty')
      else
        BQ_LOCATION=$(bq show --project_id="${PROJECT_ID}" --format=prettyjson "${BQ_DATASET}" 2>/dev/null | sed -n 's/.*"location": "\([^"]*\)".*/\1/p' | head -n 1)
      fi
    fi
    if [[ -z "${BQ_LOCATION}" || "${BQ_LOCATION}" == "null" ]]; then
      BQ_LOCATION="${REGION}"
      echo "Creating BigQuery dataset '${PROJECT_ID}:${BQ_DATASET}' in location '${BQ_LOCATION}'..."
      bq mk --project_id="${PROJECT_ID}" --location="${BQ_LOCATION}" --dataset "${PROJECT_ID}:${BQ_DATASET}" >/dev/null 2>&1 || true
    else
      echo "BigQuery dataset '${PROJECT_ID}:${BQ_DATASET}' found in location '${BQ_LOCATION}'."
    fi

    echo "Granting dataset dataEditor permission on '${PROJECT_ID}:${BQ_DATASET}'..."
    if ! bq query \
      --project_id="${PROJECT_ID}" \
      --location="${BQ_LOCATION}" \
      --use_legacy_sql=false \
      "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`${PROJECT_ID}.${BQ_DATASET}\` TO 'serviceAccount:${SERVICE_ACCOUNT}'" >/dev/null 2>&1; then
      echo "WARNING: Could not grant dataEditor on dataset ${PROJECT_ID}:${BQ_DATASET}. Ensure ${SERVICE_ACCOUNT} can write to this dataset." >&2
    fi
  else
    BQ_LOCATION="${REGION}"
    echo "Notice: 'bq' CLI not found on host. Dataset verification and creation will be handled on the VM."
  fi
fi

# 3. Handle Local Staging if requested
SOURCE_TAR_GCS=""
COMPARE_SOURCE_TAR_GCS=""
if [[ "${STAGE_LOCAL}" == "true" || "${COMPARE_STAGE_LOCAL}" == "true" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
  echo "Creating archive of local repository from ${REPO_ROOT}..."
  TEMP_ARCHIVE=$(mktemp "${TMPDIR:-/tmp}/w1r3-src-XXXXXX")
  CLEANUP_FILES+=("${TEMP_ARCHIVE}")
  COPYFILE_DISABLE=1 tar --exclude='.git' --exclude='.build' --exclude='worktrees' -czf "${TEMP_ARCHIVE}" -C "${REPO_ROOT}" .
  STAGED_TAR_GCS="gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/source.tar.gz"
  echo "Uploading local source archive to ${STAGED_TAR_GCS}..."
  gcloud storage cp "${TEMP_ARCHIVE}" "${STAGED_TAR_GCS}"
  rm -f "${TEMP_ARCHIVE}"

  if [[ "${STAGE_LOCAL}" == "true" ]]; then
    SOURCE_TAR_GCS="${STAGED_TAR_GCS}"
  fi
  if [[ "${COMPARE_STAGE_LOCAL}" == "true" ]]; then
    COMPARE_SOURCE_TAR_GCS="${STAGED_TAR_GCS}"
  fi
fi

# 4. Prepare Metadata attributes
if [[ "${BENCHMARK_PRODUCT}" == "StorageW1R3Benchmark" && -z "${BENCHMARK_COMMAND}" ]]; then
  BASE_FLAGS="--task-count ${TASK_COUNT} --iterations ${ITERATIONS} --min-object-size ${MIN_OBJECT_SIZE} --max-object-size ${MAX_OBJECT_SIZE} --read-count ${READ_COUNT} --client-count ${CLIENT_COUNT} --crc32c ${CRC32C}"
else
  BASE_FLAGS=""
fi

BENCHMARK_ARGS="${BASE_FLAGS}"
if [[ -n "${EXTRA_ARGS}" ]]; then
  BENCHMARK_ARGS="${BENCHMARK_ARGS:+${BENCHMARK_ARGS} }${EXTRA_ARGS}"
fi

COMPARE_BENCHMARK_ARGS="${BASE_FLAGS}"
if [[ -n "${COMPARE_EXTRA_ARGS}" ]]; then
  COMPARE_BENCHMARK_ARGS="${COMPARE_BENCHMARK_ARGS:+${COMPARE_BENCHMARK_ARGS} }${COMPARE_EXTRA_ARGS}"
fi

# Use custom delimiter ^~^ for gcloud --metadata so values containing commas (like bq-schema) are preserved safely
METADATA_ENTRIES=(
  "bucket-name=${BUCKET_NAME}"
  "results-bucket=${RESULTS_BUCKET}"
  "run-id=${RUN_ID}"
  "bq-dataset=${BQ_DATASET}"
  "bq-table=${BQ_TABLE}"
  "bq-location=${BQ_LOCATION}"
  "bq-schema=${EFFECTIVE_BQ_SCHEMA}"
  "git-repo=${GIT_REPO}"
  "git-ref=${GIT_REF}"
  "benchmark-args=${BENCHMARK_ARGS}"
  "benchmark-product=${BENCHMARK_PRODUCT}"
  "benchmark-package-path=${BENCHMARK_PACKAGE_PATH}"
  "benchmark-command=${BENCHMARK_COMMAND}"
  "compare-enabled=${COMPARE_ENABLED}"
  "compare-repo=${COMPARE_REPO}"
  "compare-ref=${COMPARE_REF}"
  "compare-benchmark-args=${COMPARE_BENCHMARK_ARGS}"
  "baseline-label=${BASELINE_LABEL}"
  "compare-label=${COMPARE_LABEL}"
  "rounds=${ROUNDS}"
  "auto-teardown=${AUTO_TEARDOWN}"
)
if [[ -n "${SOURCE_TAR_GCS}" ]]; then
  METADATA_ENTRIES+=("source-tar-gcs=${SOURCE_TAR_GCS}")
fi
if [[ -n "${COMPARE_SOURCE_TAR_GCS}" ]]; then
  METADATA_ENTRIES+=("compare-source-tar-gcs=${COMPARE_SOURCE_TAR_GCS}")
fi

METADATA_STR="^~^$(printf "%s~" "${METADATA_ENTRIES[@]}")"
METADATA_STR="${METADATA_STR%~}"

# 5. Launch GCE Instance
STARTUP_SCRIPT="${SCRIPT_DIR}/vm-startup.sh"
if [[ ! -f "${STARTUP_SCRIPT}" ]]; then
  echo "ERROR: Startup script not found at ${STARTUP_SCRIPT}" >&2
  exit 1
fi

echo "Creating GCE VM instance '${INSTANCE_NAME}' in ${ZONE}..."
CREATE_FLAGS=(
  --project="${PROJECT_ID}"
  --zone="${ZONE}"
  --machine-type="${MACHINE_TYPE}"
  --network-tier=PREMIUM
  --scopes=cloud-platform
  --service-account="${SERVICE_ACCOUNT}"
  --image-family=ubuntu-2404-lts-amd64
  --image-project=ubuntu-os-cloud
  --boot-disk-size=50GB
  --boot-disk-type=pd-ssd
  --metadata="${METADATA_STR}"
  --metadata-from-file="startup-script=${STARTUP_SCRIPT}"
  --quiet
)
if [[ "${AUTO_TEARDOWN}" == "true" ]]; then
  CREATE_FLAGS+=(
    --max-run-duration=2h
    --instance-termination-action=DELETE
  )
fi

gcloud compute instances create "${INSTANCE_NAME}" "${CREATE_FLAGS[@]}"

echo "✓ VM '${INSTANCE_NAME}' created successfully."

if [[ "${WAIT_FOR_COMPLETION}" != "true" ]]; then
  echo ""
  echo "Benchmark launched asynchronously!"
  echo "To view execution logs in real-time, run:"
  echo "  gcloud compute instances tail-serial-port-output ${INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID}"
  echo ""
  echo "Results will be available at:"
  echo "  Cloud Storage: gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/"
  if [[ -n "${BQ_DATASET}" && -n "${EFFECTIVE_BQ_SCHEMA}" ]]; then
    echo "  BigQuery:      ${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}"
  fi
  if [[ "${AUTO_TEARDOWN}" == "true" ]]; then
    echo ""
    echo "Note: The VM will attempt to self-delete on completion (or power off if service account lacks compute.instances.delete)."
  fi
  exit 0
fi

# 6. Stream logs and wait for completion
echo ""
echo "Streaming VM console output (Ctrl+C will disconnect monitoring; the VM will continue running in GCE)..."
echo "----------------------------------------------------------"

handle_stream_interrupt() {
  echo ""
  echo "Disconnected from VM console streaming."
  echo "The benchmark is continuing to run on VM '${INSTANCE_NAME}' in GCE."
  echo "To view execution logs again, run:"
  echo "  gcloud compute instances tail-serial-port-output ${INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID}"
  exit 0
}
trap handle_stream_interrupt INT

# Tail serial port output until instance terminates/shuts down
gcloud compute instances tail-serial-port-output "${INSTANCE_NAME}" \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}" || true

# Restore default host cleanup trap on INT
trap cleanup_host INT

echo "----------------------------------------------------------"
echo "VM execution completed (serial console closed)."

# Check status in GCS
STATUS_FILE="gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/STATUS"
RUN_STATUS="UNKNOWN"
if gcloud storage objects describe "${STATUS_FILE}" >/dev/null 2>&1; then
  RUN_STATUS=$(gcloud storage cat "${STATUS_FILE}" 2>/dev/null || echo "UNKNOWN")
fi

echo "Run Status: ${RUN_STATUS}"
if [[ "${RUN_STATUS}" != "SUCCESS" ]]; then
  echo "WARNING: Benchmark run did not finish with SUCCESS (status: ${RUN_STATUS})." >&2
  echo "Check startup log: gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/startup.log" >&2
fi

# 7. Post-run Teardown check
if [[ "${AUTO_TEARDOWN}" == "true" ]]; then
  echo "Verifying VM deletion..."
  if gcloud compute instances describe "${INSTANCE_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Deleting VM '${INSTANCE_NAME}'..."
    gcloud compute instances delete "${INSTANCE_NAME}" \
      --zone="${ZONE}" \
      --project="${PROJECT_ID}" \
      --quiet || true
    echo "✓ VM deleted."
  else
    echo "✓ VM was automatically deleted by the startup script."
  fi
fi

# 8. Ensure results are published to BigQuery
if [[ -n "${BQ_DATASET}" && -n "${EFFECTIVE_BQ_SCHEMA}" ]]; then
  if ! command -v bq &>/dev/null; then
    echo "Notice: 'bq' CLI not installed on host. Results were uploaded to GCS (and loaded into BigQuery if bq was available on the VM)."
  else
    RESULTS_CSV_GCS="gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/results.csv"
    echo "Ensuring results are loaded into BigQuery: ${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}..."
    if ! bq show --project_id="${PROJECT_ID}" "${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}" >/dev/null 2>&1; then
      if gcloud storage objects describe "${RESULTS_CSV_GCS}" >/dev/null 2>&1; then
        echo "Publishing ${RESULTS_CSV_GCS} to ${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}..."
        TEMP_CSV=$(mktemp "${TMPDIR:-/tmp}/w1r3-results-XXXXXX")
        CLEANUP_FILES+=("${TEMP_CSV}")
        gcloud storage cp "${RESULTS_CSV_GCS}" "${TEMP_CSV}"
        bq load \
          --project_id="${PROJECT_ID}" \
          --location="${BQ_LOCATION:-${REGION}}" \
          --source_format=CSV \
          --skip_leading_rows=1 \
          --replace \
          "${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}" \
          "${TEMP_CSV}" \
          "${EFFECTIVE_BQ_SCHEMA}" || {
            echo "WARNING: Failed to load results into BigQuery."
          }
        rm -f "${TEMP_CSV}"
      else
        echo "WARNING: Results CSV not found at ${RESULTS_CSV_GCS}. Skipping BigQuery load."
      fi
    else
      echo "✓ BigQuery table ${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE} is ready."
    fi
  fi
fi

# 9. Summary and Query Instructions
echo ""
echo "=========================================================="
echo "Benchmark Summary"
echo "=========================================================="
echo "Run ID:          ${RUN_ID}"
echo "Status:          ${RUN_STATUS}"
echo "GCS Artifacts:   gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/"
echo "  - Combined CSV: gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/results.csv"
echo "  - Combined Log: gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/benchmark.log"
echo "  - Metadata:     gs://${RESULTS_BUCKET}/w1r3/${RUN_ID}/metadata.json"
if [[ -n "${BQ_DATASET}" && -n "${EFFECTIVE_BQ_SCHEMA}" ]]; then
  echo "BigQuery Table:  ${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}"
  if [[ "${BENCHMARK_PRODUCT}" == "StorageW1R3Benchmark" && -z "${BENCHMARK_COMMAND}" ]]; then
    echo ""
    if [[ "${COMPARE_ENABLED}" == "true" ]]; then
      echo "Sample BigQuery A/B Comparison Query:"
      cat <<EOF
WITH stats AS (
  SELECT
    Operation,
    Variant,
    COUNT(*) AS sample_count,
    AVG((TransferSize * 8.0) / ElapsedMicroseconds) AS avg_mbps,
    APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(50)] AS p50_ms,
    APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(90)] AS p90_ms,
    APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(99)] AS p99_ms
  FROM \`${PROJECT_ID}.${BQ_DATASET}.${BQ_TABLE}\`
  WHERE Result = 'OK'
  GROUP BY Operation, Variant
)
SELECT
  a.Operation,
  a.sample_count AS ${BASELINE_LABEL}_samples,
  b.sample_count AS ${COMPARE_LABEL}_samples,
  ROUND(a.avg_mbps, 2) AS ${BASELINE_LABEL}_mbps,
  ROUND(b.avg_mbps, 2) AS ${COMPARE_LABEL}_mbps,
  ROUND(((b.avg_mbps - a.avg_mbps) / NULLIF(a.avg_mbps, 0)) * 100, 2) AS mbps_diff_pct,
  ROUND(a.p50_ms, 2) AS ${BASELINE_LABEL}_p50_ms,
  ROUND(b.p50_ms, 2) AS ${COMPARE_LABEL}_p50_ms,
  ROUND(((b.p50_ms - a.p50_ms) / NULLIF(a.p50_ms, 0)) * 100, 2) AS p50_diff_pct,
  ROUND(a.p99_ms, 2) AS ${BASELINE_LABEL}_p99_ms,
  ROUND(b.p99_ms, 2) AS ${COMPARE_LABEL}_p99_ms,
  ROUND(((b.p99_ms - a.p99_ms) / NULLIF(a.p99_ms, 0)) * 100, 2) AS p99_diff_pct
FROM stats a
JOIN stats b
  ON a.Operation = b.Operation
WHERE a.Variant = '${BASELINE_LABEL}'
  AND b.Variant = '${COMPARE_LABEL}'
ORDER BY a.Operation;
EOF
    else
      echo "Sample BigQuery Analysis Query:"
      cat <<EOF
SELECT
  Operation,
  COUNT(*) as sample_count,
  ROUND(AVG(TransferSize / (1024 * 1024)), 2) as avg_size_mib,
  ROUND(AVG((TransferSize * 8.0) / (ElapsedMicroseconds)), 2) as avg_throughput_mbps,
  APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(50)] as p50_ms,
  APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(90)] as p90_ms,
  APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(99)] as p99_ms
FROM \`${PROJECT_ID}.${BQ_DATASET}.${BQ_TABLE}\`
WHERE Result = 'OK'
GROUP BY Operation
ORDER BY Operation;
EOF
    fi
  fi
fi
echo "=========================================================="
