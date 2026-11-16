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

# Runs swift-format lint for local packages, guide snippets, and select GAPICs.
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
event="${1:-pr}"
if [[ "${event}" == "push" ]]; then
    subset=(".")
else
    subset=(
        "pkgs"
        "guide"
        "generated/swift-google-cloud-secretmanager-v1"
        "generated/swift-google-cloud-workflows-v1"
        "generated/swift-google-cloud-compute-v1"
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
packages+=(".")
unset IFS
for dir in "${packages[@]}"; do
    [[ -f "${dir}/Package.swift" ]] || continue
    count=$((count + 1))

    echo "::group:: --- Linting ${dir} ---"

    paths=()
    for subdir in Sources Tests Snippets; do
        [[ -d "${dir}/${subdir}" ]] && paths+=("${dir}/${subdir}")
    done
    paths+=("${dir}/Package.swift")

    # Run swift-format directly on existing source/test/snippet directories and Package.swift
    # to avoid the SPM plugin forcefully feeding the generated Rust bridge files.
    if swift-format lint --strict -r "${paths[@]}"; then
        echo "::notice:: ✓ ${dir} passed"
        echo "::endgroup::"
    else
        echo "::endgroup::"
        echo "::error:: ✗ ${dir} failed"
        errors=$((errors + 1))
    fi
done

echo ""
echo "::notice:: ${count} local package(s) linted, ${errors} failure(s)."

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
