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

errors=0
count=0

shard_index="${1:-${SHARD_INDEX:-0}}"
shard_count="${2:-${SHARD_COUNT:-1}}"
trigger_name="${TRIGGER_NAME:-${GCB_TRIGGER_NAME:-}}"

if ! [[ "${shard_index}" =~ ^[0-9]+$ ]] || ! [[ "${shard_count}" =~ ^[0-9]+$ ]]; then
    echo "✗ Invalid shard parameters: shard_index='${shard_index}', shard_count='${shard_count}'"
    exit 1
fi

if (( shard_count <= 0 )); then
    echo "✗ shard_count must be greater than 0, got ${shard_count}"
    exit 1
fi

if (( shard_index >= shard_count )); then
    echo "✗ shard_index (${shard_index}) must be less than shard_count (${shard_count})"
    exit 1
fi

flags=("${build_flags[@]}")
source "${REPO_ROOT}/ci/package-dependencies.sh"
# By default, build all the packages. We search for `Package.swift` files
mapfile -t packages < <(find . \( -name Sources -o -name .build -o -name .build-cache \) -prune -o -type f -name Package.swift -exec dirname {} \; | sort -u)
# On PRs, detect any new libraries and compile their documentation. Without this
# step the post-merge build may break, and we prefer to avoid this problem.
if [[ "${trigger_name}" != gcb-pm-* && "${shard_count}" -le 1 ]]; then
    echo "--- Building a subset because this is a PR (trigger: ${trigger_name:-none})"
    # Add some standard packages.
    packages=('.')
    mapfile -t always < <(find pkgs -type f -name 'Package.swift' | xargs -I{} dirname {} | sort)
    packages+=("${always[@]}")
    if [[ -d .git ]]; then
        git fetch --unshallow || true
        mapfile -t new < <(git diff "origin/main...HEAD" --name-only --diff-filter=A 2>/dev/null | grep '/Package.swift' | grep -v /Sources/ | xargs -I{} dirname {})
        packages+=("${new[@]}")
        echo "--- Discovered new directories in this PR: ${new[*]}"
    fi
fi

if (( shard_count > 1 )); then
    echo "--- Total packages before sharding: ${#packages[@]}"
    shard_packages=()
    for i in "${!packages[@]}"; do
        if (( i % shard_count == shard_index )); then
            shard_packages+=("${packages[i]}")
        fi
    done
    packages=("${shard_packages[@]}")
fi

echo "--- Building shard ${shard_index} of ${shard_count} (${#packages[@]} packages)"
for p in "${packages[@]}"; do
    echo "  ${p}"
done
for dir in "${packages[@]}"; do
    [[ -f "${dir}/Package.swift" ]] || continue
    count=$((count + 1))
    name=${dir}
    if [[ ${dir} == . ]]; then
        name="top-level package"
    fi

    edit_package_dependencies "${dir}"

    echo; echo "--- Building ${name} ---"
    if swift build --build-tests "${flags[@]}" --package-path "${dir}" >"${dir}/.test.log" 2>&1; then
        echo "✓ ${name} built successfully"
    else
        cat "${dir}/.test.log"
        echo; echo "✗ ${name} failed to build"
        errors=$((errors + 1))
        restore_package_dependencies "${dir}"
        continue
    fi

    restore_package_dependencies "${dir}"
done

echo; echo; echo "${count} local package(s) built, ${errors} failure(s)."
echo "--- Remaining disk space"
df -h

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
