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

# Runs swift-format lint for every local package found under `packages/`.
# New local packages are picked up automatically — no changes to this script
# are required when adding one.
#
# Unfortunately, there are no standard or community tools to do this
# automatically in the Swift ecosystem.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# The PRs are too slow if we run them for all packages. We YOLO the PRs and just
# run this build for the hand-crafted files and some select GAPICs. The post-PR
# build will run for everything, we can afford those to be slower.
if [[ "${1:-missingevent}" == "push" ]]; then
    subset=(".")
else
    subset=(
        "packages"
        "guide"
        "generated/google-cloud-secretmanager-v1"
        "generated/google-cloud-workflows-v1"
        "generated/google-cloud-compute-v1"
    )
fi

echo "--- SWIFT VERSION ---"
swift --version
echo "--- SWIFT FORMAT VERSION ---"
swift-format --version
echo "--- SUBSET: " "${subset[@]}"
echo "--- START ---"

errors=0
count=0

# macOS ships with Bash 3.x, which does not support readfile. Use a plain
# assignment as a workaround, and set IFS to avoid breaking on spaces.
IFS=$'\n'
packages=($(git ls-files "${subset[@]}" | grep '/Package.swift' | xargs -I{} dirname {} | sort))
unset IFS
for dir in "${packages[@]}"; do
    [[ -f "${dir}/Package.swift" ]] || continue
    count=$((count + 1))

    if swift-format format -i -r "${dir}/Sources" "${dir}/Tests" "${dir}/Package.swift"; then
        echo "::notice:: ✓ ${dir} passed"
    else
        echo "::error:: ✗ ${dir} failed"
        errors=$((errors + 1))
    fi
done

if swift-format format -i -r "./Tests" "./Package.swift"; then
    echo "::notice:: ✓ top-level passed"
else
    echo "::error:: ✗ top-level failed"
    errors=$((errors + 1))
fi

echo ""
echo "::notice:: ${count} package(s) formatted, ${errors} failure(s)."

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
