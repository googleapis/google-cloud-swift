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
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "${SCRIPT_DIR}/../.." && pwd))"

source "${SCRIPT_DIR}/fetch.sh"
source "${SCRIPT_DIR}/build-flags.sh"

flags=("${build_flags[@]}")
source "${REPO_ROOT}/ci/package-dependencies.sh"
if [[ -z "${PROJECT_ID:-}" ]]; then
    echo "✗ missing PROJECT_ID environment variable"
    exit 1
fi
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export GOOGLE_CLOUD_SWIFT_TEST_SERVICE_ACCOUNT=swift-sdk-test@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com
export GOOGLE_CLOUD_SWIFT_TEST_BUCKET=${GOOGLE_CLOUD_PROJECT}-test-bucket

errors=0
count=1
echo "--- Running top-level integration tests ---"
edit_package_dependencies .
if swift test "${flags[@]}" --quiet; then
    echo; echo "✓ integration tests passed"
else
    echo; echo "✗ integration tests failed"
    errors=$((errors + 1))
fi
restore_package_dependencies .

for dir in packages/*; do
    [[ -f "${dir}/Package.swift" ]] || continue
    [[ -d "${dir}/Tests" ]] || continue
    count=$((count + 1))
    edit_package_dependencies "${dir}"
    echo "--- Running ${dir} integration tests ---"
    if swift test "${flags[@]}" --quiet --package-path "${dir}" --enable-all-traits; then
        echo; echo "✓ ${dir} passed"
    else
        echo; echo "✗ ${dir} failed"
        errors=$((errors + 1))
    fi
    restore_package_dependencies "${dir}"
done

count=$((count + 1))
echo "--- Smoke testing the StorageW1R3 benchmark ---"
edit_package_dependencies .
benchmark_args=(
    --bucket-name "${GOOGLE_CLOUD_SWIFT_TEST_BUCKET}"
    --min-object-size 0KiB
    --max-object-size 16KiB
    --task-count 1
    --iterations 4
)
if swift run "${flags[@]}" StorageW1R3 "${benchmark_args[@]}" >/dev/null; then
    echo; echo "✓ StorageW1R3 passed"
else
    echo; echo "✗ StorageW1R3 failed"
    errors=$((errors + 1))
fi
restore_package_dependencies .

echo; echo; echo "${count} local package(s) tested, ${errors} failure(s)."

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
