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

_EDITED_PACKAGES=()
_REMOVED_DISABLE_RESOLUTION=()
_MODIFIED_RESOLVED=()
_CREATED_RESOLVED=()

edit_package_dependencies() {
    local dir="$1"
    local clean_dir="${dir#./}"
    [[ -z "${clean_dir}" ]] && clean_dir="."
    _EDITED_PACKAGES+=("${dir}")

    export GOOGLE_CLOUD_SWIFT_LOCAL_DEPS="${REPO_ROOT}"

    for ws in "${dir}/.build/workspace-state.json" "${REPO_ROOT}/.build-cache/workspace-state.json" "${REPO_ROOT}/.build/workspace-state.json"; do
        if [[ -f "${ws}" ]] && grep -q '"edited"' "${ws}"; then
            rm -f "${ws}"
        fi
    done

    if [[ -f "${dir}/Package.resolved" ]]; then
        if [[ ! -f "${dir}/Package.resolved.ci-bak" ]]; then
            cp "${dir}/Package.resolved" "${dir}/Package.resolved.ci-bak"
            _MODIFIED_RESOLVED+=("${dir}/Package.resolved")
        fi
    else
        _CREATED_RESOLVED+=("${dir}/Package.resolved")
    fi

    # SwiftPM requires automatic resolution when dependencies are overridden.
    if [[ -n "${flags+x}" ]]; then
        local filtered_flags=()
        local had_flag=false
        for f in ${flags[@]+"${flags[@]}"}; do
            if [[ "${f}" == "--disable-automatic-resolution" ]]; then
                had_flag=true
            else
                filtered_flags+=("${f}")
            fi
        done
        if [[ "${had_flag}" == true ]]; then
            _REMOVED_DISABLE_RESOLUTION+=("${dir}")
            flags=(${filtered_flags[@]+"${filtered_flags[@]}"})
        fi
    fi
}

restore_package_dependencies() {
    local dir="$1"
    local clean_dir="${dir#./}"
    [[ -z "${clean_dir}" ]] && clean_dir="."

    if [[ -f "${dir}/Package.resolved.ci-bak" ]]; then
        mv "${dir}/Package.resolved.ci-bak" "${dir}/Package.resolved"
    else
        for res in ${_CREATED_RESOLVED[@]+"${_CREATED_RESOLVED[@]}"}; do
            if [[ "${res}" == "${dir}/Package.resolved" ]]; then
                rm -f "${dir}/Package.resolved"
                break
            fi
        done
    fi

    if [[ -n "${flags+x}" ]]; then
        for p in ${_REMOVED_DISABLE_RESOLUTION[@]+"${_REMOVED_DISABLE_RESOLUTION[@]}"}; do
            if [[ "${p}" == "${dir}" ]]; then
                flags+=("--disable-automatic-resolution")
                break
            fi
        done
    fi
    local new_removed=()
    for p in ${_REMOVED_DISABLE_RESOLUTION[@]+"${_REMOVED_DISABLE_RESOLUTION[@]}"}; do
        [[ "${p}" != "${dir}" ]] && new_removed+=("${p}")
    done
    _REMOVED_DISABLE_RESOLUTION=(${new_removed[@]+"${new_removed[@]}"})

    local new_list=()
    for p in ${_EDITED_PACKAGES[@]+"${_EDITED_PACKAGES[@]}"}; do
        [[ "${p}" != "${dir}" ]] && new_list+=("${p}")
    done
    _EDITED_PACKAGES=(${new_list[@]+"${new_list[@]}"})
}

restore_all_package_dependencies() {
    for p in ${_EDITED_PACKAGES[@]+"${_EDITED_PACKAGES[@]}"}; do
        restore_package_dependencies "${p}"
    done

    unset GOOGLE_CLOUD_SWIFT_LOCAL_DEPS

    for res in ${_MODIFIED_RESOLVED[@]+"${_MODIFIED_RESOLVED[@]}"}; do
        if [[ -f "${res}.ci-bak" ]]; then
            mv "${res}.ci-bak" "${res}"
        fi
    done
    _MODIFIED_RESOLVED=()

    for res in ${_CREATED_RESOLVED[@]+"${_CREATED_RESOLVED[@]}"}; do
        rm -f "${res}"
    done
    _CREATED_RESOLVED=()
}

trap restore_all_package_dependencies EXIT INT TERM
