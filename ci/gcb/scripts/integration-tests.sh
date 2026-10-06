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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/fetch.sh"
source "${SCRIPT_DIR}/build-flags.sh"

flags=("${build_flags[@]}")
if [[ -z "${PROJECT_ID:-}" ]]; then
    echo "✗ missing PROJECT_ID environment variable"
    exit 1
fi
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export GOOGLE_CLOUD_SWIFT_TEST_SERVICE_ACCOUNT=swift-sdk-test@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com
export GOOGLE_CLOUD_SWIFT_TEST_BUCKET=${GOOGLE_CLOUD_PROJECT}-test-bucket
export GOOGLE_CLOUD_SWIFT_TEST_STORAGE_KMS_KEY_RING=us-central1
export GOOGLE_CLOUD_SWIFT_TEST_STORAGE_KMS_RING=us-central1

# Workload Identity Federation (BYOID) integration test configuration
export EXTERNAL_ACCOUNT_PROJECT="rust-external-account-joonix"
export EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL="testsa@${EXTERNAL_ACCOUNT_PROJECT}.iam.gserviceaccount.com"
# The STS audience URI is constructed as:
#   //iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}
# where:
#   - PROJECT_NUMBER: 1092239828259 (numeric ID of rust-external-account-joonix, retrieved via:
#       gcloud projects describe rust-external-account-joonix --format='value(projectNumber)')
#   - LOCATION: global
#   - POOL_ID: google-idp
#   - PROVIDER_ID: google-idp
export GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE="//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/google-idp"

# Install Go if not present
if ! command -v go >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/install-go.sh"
fi

export GOPATH="${HOME}/go"
export PATH="${GOPATH}/bin:${PATH}"

SHOWCASE_VERSION="v0.43.1-0.20260817230810-0c88ce83d259"
SHOWCASE_BIN="${GOPATH}/bin/gapic-showcase"
if [[ ! -x "${SHOWCASE_BIN}" ]]; then
    echo "--- Installing gapic-showcase ---"
    installed=false
    for delay in 5 10 20; do
        if go install "github.com/googleapis/gapic-showcase/cmd/gapic-showcase@${SHOWCASE_VERSION}"; then
            installed=true
            break
        fi
        echo "go install failed, retrying in ${delay}s..."
        sleep "${delay}"
    done
    if [[ "${installed}" != true ]]; then
        go install "github.com/googleapis/gapic-showcase/cmd/gapic-showcase@${SHOWCASE_VERSION}"
    fi
fi

export GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH="${SHOWCASE_BIN}"

errors=0
count=1
echo "--- Running top-level integration tests ---"
if swift test "${flags[@]}" --disable-automatic-resolution --quiet; then
    echo; echo "✓ integration tests passed"
else
    echo; echo "✗ integration tests failed"
    errors=$((errors + 1))
fi

for dir in pkgs/*; do
    [[ -f "${dir}/Package.swift" ]] || continue
    [[ -d "${dir}/Tests/IntegrationTests" ]] || continue
    count=$((count + 1))
    echo "--- Running ${dir} integration tests ---"
    if swift test "${flags[@]}" --quiet --package-path "${dir}" --enable-all-traits; then
        echo; echo "✓ ${dir} passed"
    else
        echo; echo "✗ ${dir} failed"
        errors=$((errors + 1))
    fi
done

echo; echo; echo "${count} local package(s) tested, ${errors} failure(s)."

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
