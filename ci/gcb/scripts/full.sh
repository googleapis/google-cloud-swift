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
echo "--- Initial disk space"
df -h
echo
echo

errors=0
count=0

flags=(
    -Xswiftc -warnings-as-errors
    -Xswiftc -Wwarning
    -Xswiftc DeprecatedDeclaration
    --scratch-path "/workspace/.build-cache"
    --build-path   "/workspace/.build"
)
# By default, build all the packages. We search for `Package.swift` files
mapfile -t packages < <(find . \( -name Sources -o -name .build -o -name .build-cache \) -prune -o -type f -name Package.swift -exec dirname {} \; | sort -u)
# On PRs, detect any new libraries and compile their documentation. Without this
# step the post-merge build may break, and we prefer to avoid this problem.
if [[ "${GCB_TRIGGER_NAME:-}" != gcb-pm-* ]]; then
    echo "--- Building a subset because this is a PR"
    # Add some standard packages.
    packages=('.')
    mapfile -t always < <(find packages -type f -name 'Package.swift' | xargs -I{} dirname {} | sort)
    packages+=("${always[@]}")
    if [[ -d .git ]]; then
        git fetch --unshallow
        mapfile -t new < <(git diff "origin/main...HEAD" --name-only --diff-filter=A | grep '/Package.swift' | grep -v /Sources/ | xargs -I{} dirname {})
        packages+=("${new[@]}")
        echo "--- Discovered new directories in this PR: ${new[@]}"
    fi
fi
echo DEBUG DEBUG
echo "--- Building ${#packages[@]} packages"
if env GOOGLE_CLOUD_SWIFT_FULL_BUILD=true swift build "${flags[@]}" --target AllModules ; then
    echo "✓ AllModules built successfully"
else
    echo; echo "✗ AllModules failed to build"
    errors=$((errors + 1))
    continue
fi

packages=()
echo DEBUG DEBUG
echo "--- Building ${#packages[@]} packages"
for dir in "${packages[@]}"; do
    [[ -f "${dir}/Package.swift" ]] || continue
    count=$((count + 1))
    name=${dir}
    if [[ ${dir} == . ]]; then
        name="top-level package"
    fi

    echo; echo "--- Building ${name} ---"
    if swift build --build-tests "${flags[@]}" --package-path "${dir}" >"${dir}/.test.log" 2>&1; then
        echo "✓ ${name} built successfully"
    else
        cat "${dir}/.test.log"
        echo; echo "✗ ${name} failed to build"
        errors=$((errors + 1))
        continue
    fi
done

echo; echo; echo "${count} local package(s) built, ${errors} failure(s)."
echo "--- Remaining disk space"
df -h

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
