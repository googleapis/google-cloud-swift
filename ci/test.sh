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
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "--- SWIFT VERSION ---"
swift --version
echo "--- VERSIONS ---"

errors=0
count=0

# macOS ships with Bash 3.x, which does not support readfile. Use a plain
# assignment as a workaround, and set IFS to avoid breaking on spaces.
IFS=$'\n'
packages=($(git ls-files -- 'Package.swift' 'packages/*Package.swift' 'guide/*Package.swift' | xargs -I{} dirname {} | sort))
unset IFS
flags=(
    -Xswiftc -warnings-as-errors
    -Xswiftc -Wwarning
    -Xswiftc DeprecatedDeclaration
    --scratch-path "$(git rev-parse --show-toplevel)/.build-cache"
    --build-path "$(git rev-parse --show-toplevel)/.build"
)
for dir in "${packages[@]}"; do
    [[ -f "${dir}/Package.swift" ]] || continue
    count=$((count + 1))

    echo "::group::--- Building ${dir} ---"
    if swift build --build-tests "${flags[@]}" --package-path "${dir}"; then
        echo "::info:: ✓ ${dir} built"
    else
        echo "::endgroup::"
        echo "::error:: ✗ ${dir} failed to build" >&2
        errors=$((errors + 1))
        continue
    fi

    [[ -d "${dir}/Tests" ]] || continue
    echo "::info:: --- Testing ${dir} ---"
    if swift test "${flags[@]}" --quiet --package-path "${dir}"; then
        echo "::notice:: ✓ ${dir} passed"
        echo "::endgroup::"
    else
        echo "::endgroup::"
        echo "::error:: ✗ ${dir} failed"
        errors=$((errors + 1))
    fi
done

echo ""
echo "::notice:: ${count} local package(s) tested, ${errors} failure(s)."

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
