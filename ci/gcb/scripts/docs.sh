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

errors=0
count=0

clean_flags=(
    --warnings-as-errors
)
clean_targets=(
    GoogleCloudWKT
    GoogleCloudAuth
    GoogleCloudGax
    GoogleCloudSecretManagerV1
    GoogleCloudStorage
)
echo "--- Building ${#clean_targets[@]} targets with warnings as errors"
for target in "${clean_targets[@]}"; do
    count=$((count + 1))

    echo; echo "================ Building ${target} ================"
    if swift package generate-documentation "${clean_flags[@]}" --target "${target}" >"${target}.docs.log" 2>&1; then
        echo "✓ ${target} built successfully"
    else
        echo; echo "✗ ${target} failed to build"
        cat "${target}.docs.log"
        errors=$((errors + 1))
        continue
    fi
done

targets=()
# On post-merge builds build all the things.
if [[ "${GCB_TRIGGER_NAME:-}" == gcb-pm-* ]]; then
    export GOOGLE_CLOUD_SWIFT_FULL_BUILD=true
    mapfile -t generated < <(sed -n 's/^  name: "\([^"]*\)",/\1/p' generated/*/Package.swift)
    targets+=("${generated[@]}")
fi

if [[ ${#targets[@]} -gt 0 ]]; then
    echo; echo; echo "--- Building ${#targets[@]} targets"
    count=$((count + 1))
    args=()
    for target in "${targets[@]}"; do
        args+=(--target "${target}")
    done
    if swift package generate-documentation --enable-experimental-combined-documentation "${args[@]}"; then
        echo "✓ combined documentation built successfully"
    else
        echo; echo "✗ combined documentation failed to build"
        errors=$((errors + 1))
    fi
fi

echo; echo; echo "${count} local targets(s) built, ${errors} failure(s)."
echo "--- Remaining disk space"
df -h

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
