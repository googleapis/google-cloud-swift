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

if [[ -n "${_PACKAGE_DEPENDENCIES_LOADED:-}" ]]; then
    return 0
fi
_PACKAGE_DEPENDENCIES_LOADED=1

_PKG_DEPS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_PKG_DEPS_SCRIPT_DIR}/.." && pwd)"

export GOOGLE_CLOUD_SWIFT_LOCAL_DEPS="${REPO_ROOT}"

_REMOVED_DISABLE_RESOLUTION=false

edit_package_dependencies() {
    local dir="$1"
    local clean_dir="${dir#./}"
    [[ -z "${clean_dir}" ]] && clean_dir="."

    export GOOGLE_CLOUD_SWIFT_LOCAL_DEPS="${REPO_ROOT}"

    for ws in "${dir}/.build/workspace-state.json" "${REPO_ROOT}/.build-cache/workspace-state.json" "${REPO_ROOT}/.build/workspace-state.json"; do
        if [[ -f "${ws}" ]] && grep -q '"edited"' "${ws}"; then
            rm -f "${ws}"
        fi
    done

    # SwiftPM's --disable-automatic-resolution flag is only valid for the root package
    # where Package.resolved is tracked in git. Subpackages do not track Package.resolved
    # and fail when automatic resolution is disabled.
    if [[ "${clean_dir}" != "." && "${clean_dir}" != "${REPO_ROOT}" && -n "${flags+x}" ]]; then
        local filtered_flags=()
        for f in "${flags[@]}"; do
            if [[ "${f}" == "--disable-automatic-resolution" ]]; then
                _REMOVED_DISABLE_RESOLUTION=true
            else
                filtered_flags+=("${f}")
            fi
        done
        if [[ "${_REMOVED_DISABLE_RESOLUTION}" == true ]]; then
            flags=("${filtered_flags[@]}")
        fi
    fi
}

restore_package_dependencies() {
    if [[ "${_REMOVED_DISABLE_RESOLUTION}" == true && -n "${flags+x}" ]]; then
        flags+=("--disable-automatic-resolution")
        _REMOVED_DISABLE_RESOLUTION=false
    fi
}

restore_all_package_dependencies() {
    restore_package_dependencies
    unset GOOGLE_CLOUD_SWIFT_LOCAL_DEPS
}

trap restore_all_package_dependencies EXIT INT TERM
