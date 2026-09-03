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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/fetch.sh"
source "${SCRIPT_DIR}/build-flags.sh"

errors=0
count=0

flags=("${build_flags[@]}")
source "${REPO_ROOT}/ci/package-dependencies.sh"

mapfile -t packages < <(find . \( -name Sources -o -name .build -o -name .build-cache -o -name generated \) -prune -o -type f -name Package.swift -exec dirname {} \; | sort -u)
for dir in "${packages[@]}"; do
    [[ -f "${dir}/Package.swift" ]] || continue
    count=$((count + 1))
    name=${dir}
    if [[ ${dir} == . ]]; then
        name="top-level package"
    fi

    edit_package_dependencies "${dir}"

    echo; echo; echo "--- Building ${name} ---"
    if swift build --build-tests "${flags[@]}" --package-path "${dir}" >${dir}/.build.log 2>&1; then
        echo "✓ ${name} built successfully"
    else
        cat ${dir}/.build.log
        echo "✗ ${name} failed to build"
        errors=$((errors + 1))
        restore_package_dependencies "${dir}"
        continue
    fi

    if [[ -d "${dir}/Tests" ]]; then
        echo "--- Testing ${name} ---"
        if swift test "${flags[@]}" --quiet --package-path "${dir}" >${dir}/.test.log 2>&1; then
            echo "✓ ${name} passed"
        else
            cat ${dir}/.test.log
            echo "✗ ${name} failed"
            errors=$((errors + 1))
        fi
    fi

    restore_package_dependencies "${dir}"
done

echo; echo; echo "${count} local package(s) tested, ${errors} failure(s)."

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
