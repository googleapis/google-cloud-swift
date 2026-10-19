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

_BUILD_FLAGS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_BUILD_FLAGS_SCRIPT_DIR}/.." && pwd)}"

build_flags=(
    --build-system native
    -Xswiftc -warnings-as-errors
    --scratch-path "${GOOGLE_CLOUD_SWIFT_SCRATCH_PATH:-${REPO_ROOT}/.build-cache}"
)

export GOOGLE_CLOUD_SWIFT_LOCAL_DEPS="${REPO_ROOT}"

# Swift < 6.4 cannot honor the `@diagnose` attributes in the generated code.
# The remaining builds stay strict.
source "${_BUILD_FLAGS_SCRIPT_DIR}/swift-version.sh"
if ! swift_supports_diagnose; then
    build_flags+=(-Xswiftc -Wwarning -Xswiftc DeprecatedDeclaration)
fi

source "${_BUILD_FLAGS_SCRIPT_DIR}/glinux-flags.sh"
add_glinux_flags

flags=("${build_flags[@]}")

resolve_flags=(
    --scratch-path "${GOOGLE_CLOUD_SWIFT_SCRATCH_PATH:-${REPO_ROOT}/.build-cache}"
)

# Resolves package dependencies for a given directory with retries to handle
# transient network or TLS flakes when fetching remote repositories.
#
# Sub-packages in `pkgs/*`, `guide`, and `generated/*` do not track a
# `Package.resolved` file in git, so SwiftPM fetches remote dependency updates
# each time a sub-package is built or tested. Running `swift package resolve`
# with the shared `--scratch-path` and any package-specific flags (such as
# `--enable-all-traits`) beforehand ensures that dependency resolution happens
# inside the retry loop and that the subsequent `swift build` / `swift test`
# reuses the resolved workspace state without hitting the network.
resolve_package() {
    local dir="${1:-.}"
    shift || true
    local pkg_resolve_flags=("${resolve_flags[@]}")
    if [[ "${dir}" == "." || "${dir}" == "${REPO_ROOT}" ]]; then
        pkg_resolve_flags+=(--disable-automatic-resolution)
    fi
    local delay
    for delay in 0 5 10; do
        if (( delay > 0 )); then
            sleep "${delay}"
        fi
        if swift package resolve "${pkg_resolve_flags[@]}" --package-path "${dir}" "$@"; then
            return 0
        fi
    done
    return 1
}
