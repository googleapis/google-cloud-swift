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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

_EDITED_PACKAGES=()
_REMOVED_DISABLE_RESOLUTION=()

edit_package_dependencies() {
    local dir="$1"
    local clean_dir="${dir#./}"
    [[ -z "${clean_dir}" ]] && clean_dir="."
    _EDITED_PACKAGES+=("${dir}")
    local scratch_args=()
    if [[ -n "${flags+x}" ]]; then
        for ((i=0; i<${#flags[@]}; i++)); do
            if [[ "${flags[i]}" == "--scratch-path" && $((i+1)) -lt ${#flags[@]} ]]; then
                scratch_args=("--scratch-path" "${flags[i+1]}")
                break
            fi
        done
    fi
    if [[ "${clean_dir}" != "." && "${clean_dir}" != "packages/swift-google-auth" && "${clean_dir}" != "${REPO_ROOT}/packages/swift-google-auth" ]]; then
        swift package "${scratch_args[@]}" --package-path "${dir}" edit --path "${REPO_ROOT}/packages/swift-google-auth" swift-google-auth >/dev/null 2>&1 || true
    fi
    if [[ "${clean_dir}" != "." && "${clean_dir}" != "packages/swift-google-wkt" && "${clean_dir}" != "${REPO_ROOT}/packages/swift-google-wkt" ]]; then
        swift package "${scratch_args[@]}" --package-path "${dir}" edit --path "${REPO_ROOT}/packages/swift-google-wkt" swift-google-wkt >/dev/null 2>&1 || true
    fi
    # SwiftPM's --disable-automatic-resolution flag is only valid for the root package
    # where Package.resolved is tracked in git. Subpackages do not track Package.resolved
    # and fail when automatic resolution is disabled.
    if [[ "${clean_dir}" != "." && -n "${flags+x}" ]]; then
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
    local clean_dir="${dir#./}"
    [[ -z "${clean_dir}" ]] && clean_dir="."
    local scratch_args=()
    if [[ -n "${flags+x}" ]]; then
        for ((i=0; i<${#flags[@]}; i++)); do
            if [[ "${flags[i]}" == "--scratch-path" && $((i+1)) -lt ${#flags[@]} ]]; then
                scratch_args=("--scratch-path" "${flags[i+1]}")
                break
            fi
        done
    fi
    if [[ "${clean_dir}" != "." && "${clean_dir}" != "packages/swift-google-auth" && "${clean_dir}" != "${REPO_ROOT}/packages/swift-google-auth" ]]; then
        swift package "${scratch_args[@]}" --package-path "${dir}" unedit --force swift-google-auth >/dev/null 2>&1 || true
    fi
    if [[ "${clean_dir}" != "." && "${clean_dir}" != "packages/swift-google-wkt" && "${clean_dir}" != "${REPO_ROOT}/packages/swift-google-wkt" ]]; then
        swift package "${scratch_args[@]}" --package-path "${dir}" unedit --force swift-google-wkt >/dev/null 2>&1 || true
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
