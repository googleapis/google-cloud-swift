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

if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd))"
fi

_EDITED_PACKAGES=()
_REMOVED_DISABLE_RESOLUTION=()

edit_package_dependencies() {
    local dir="$1"
    _EDITED_PACKAGES+=("${dir}")
    if [[ "${dir}" != "." && "${dir}" != "packages/swift-google-auth" && "${dir}" != "${REPO_ROOT}/packages/swift-google-auth" ]]; then
        swift package --package-path "${dir}" edit --path "${REPO_ROOT}/packages/swift-google-auth" swift-google-auth >/dev/null 2>&1 || true
    fi
    if [[ "${dir}" != "." && "${dir}" != "packages/swift-google-wkt" && "${dir}" != "${REPO_ROOT}/packages/swift-google-wkt" ]]; then
        swift package --package-path "${dir}" edit --path "${REPO_ROOT}/packages/swift-google-wkt" swift-google-wkt >/dev/null 2>&1 || true
    fi
    # SwiftPM's --disable-automatic-resolution flag is only valid for the root package
    # where Package.resolved is tracked in git. Subpackages do not track Package.resolved
    # and fail when automatic resolution is disabled.
    if [[ "${dir}" != "." && -n "${flags+x}" ]]; then
        local filtered_flags=()
        local had_flag=false
        for f in "${flags[@]}"; do
            if [[ "${f}" == "--disable-automatic-resolution" ]]; then
                had_flag=true
            else
                filtered_flags+=("${f}")
            fi
        done
        if [[ "${had_flag}" == true ]]; then
            _REMOVED_DISABLE_RESOLUTION+=("${dir}")
            flags=("${filtered_flags[@]}")
        fi
    fi
}

restore_package_dependencies() {
    local dir="$1"
    if [[ "${dir}" != "." && "${dir}" != "packages/swift-google-auth" && "${dir}" != "${REPO_ROOT}/packages/swift-google-auth" ]]; then
        swift package --package-path "${dir}" unedit --force swift-google-auth >/dev/null 2>&1 || true
    fi
    if [[ "${dir}" != "." && "${dir}" != "packages/swift-google-wkt" && "${dir}" != "${REPO_ROOT}/packages/swift-google-wkt" ]]; then
        swift package --package-path "${dir}" unedit --force swift-google-wkt >/dev/null 2>&1 || true
    fi
    if [[ -n "${flags+x}" ]]; then
        for p in "${_REMOVED_DISABLE_RESOLUTION[@]}"; do
            if [[ "${p}" == "${dir}" ]]; then
                flags+=("--disable-automatic-resolution")
                break
            fi
        done
    fi
    local new_removed=()
    for p in "${_REMOVED_DISABLE_RESOLUTION[@]}"; do
        [[ "${p}" != "${dir}" ]] && new_removed+=("${p}")
    done
    _REMOVED_DISABLE_RESOLUTION=("${new_removed[@]}")

    local new_list=()
    for p in "${_EDITED_PACKAGES[@]}"; do
        [[ "${p}" != "${dir}" ]] && new_list+=("${p}")
    done
    _EDITED_PACKAGES=("${new_list[@]}")
}

restore_all_package_dependencies() {
    for p in "${_EDITED_PACKAGES[@]}"; do
        restore_package_dependencies "${p}"
    done
}

trap restore_all_package_dependencies EXIT INT TERM
