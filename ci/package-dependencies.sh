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

edit_package_dependencies() {
    local dir="$1"
    _EDITED_PACKAGES+=("${dir}")
    local edited=false
    if [[ "${dir}" != "packages/swift-google-auth" && "${dir}" != "${REPO_ROOT}/packages/swift-google-auth" ]] && grep -q "swift-google-auth" "${dir}/Package.swift"; then
        swift package --package-path "${dir}" edit --path "${REPO_ROOT}/packages/swift-google-auth" swift-google-auth >/dev/null 2>&1 || true
        edited=true
    fi
    if [[ "${dir}" != "packages/swift-google-wkt" && "${dir}" != "${REPO_ROOT}/packages/swift-google-wkt" ]] && grep -q "swift-google-wkt" "${dir}/Package.swift"; then
        swift package --package-path "${dir}" edit --path "${REPO_ROOT}/packages/swift-google-wkt" swift-google-wkt >/dev/null 2>&1 || true
        edited=true
    fi
    # SwiftPM's --disable-automatic-resolution flag fails when a package dependency is in edit mode.
    # Temporarily remove --disable-automatic-resolution from flags if present.
    if [[ "${edited}" == true && -n "${flags+x}" ]]; then
        local filtered_flags=()
        for f in "${flags[@]}"; do
            [[ "${f}" != "--disable-automatic-resolution" ]] && filtered_flags+=("${f}")
        done
        flags=("${filtered_flags[@]}")
    fi
}

restore_package_dependencies() {
    local dir="$1"
    local edited=false
    if [[ "${dir}" != "packages/swift-google-auth" && "${dir}" != "${REPO_ROOT}/packages/swift-google-auth" ]] && grep -q "swift-google-auth" "${dir}/Package.swift"; then
        swift package --package-path "${dir}" unedit --force swift-google-auth >/dev/null 2>&1 || true
        edited=true
    fi
    if [[ "${dir}" != "packages/swift-google-wkt" && "${dir}" != "${REPO_ROOT}/packages/swift-google-wkt" ]] && grep -q "swift-google-wkt" "${dir}/Package.swift"; then
        swift package --package-path "${dir}" unedit --force swift-google-wkt >/dev/null 2>&1 || true
        edited=true
    fi
    if [[ "${edited}" == true && -n "${flags+x}" ]]; then
        local has_flag=false
        for f in "${flags[@]}"; do
            [[ "${f}" == "--disable-automatic-resolution" ]] && has_flag=true
        done
        if [[ "${has_flag}" == false ]]; then
            flags+=("--disable-automatic-resolution")
        fi
    fi
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
