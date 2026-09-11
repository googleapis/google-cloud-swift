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

flags=("${build_flags[@]}")
source "${REPO_ROOT}/ci/package-dependencies.sh"

# DEBUG DEBUG temporary: force full build on PR to measure build time
echo "DEBUG DEBUG temporary: forcing full build on PR to measure build time"
mapfile -t packages < <(git ls-files 'Package.swift' 'pkgs/*/Package.swift' 'generated/*/Package.swift' 'guide/Package.swift' | xargs -I{} dirname {} | sort -u)

if false; then
# On PRs, detect any new libraries and compile their documentation. Without this
# step the post-merge build may break, and we prefer to avoid this problem.
if [[ "${GCB_TRIGGER_NAME:-}" != gcb-pm-* ]]; then
    echo "--- Building a subset because this is a PR"
    # Add some standard packages.
    packages=('.')
    mapfile -t always < <(git ls-files 'pkgs/*/Package.swift' | xargs -I{} dirname {} | sort)
    packages+=("${always[@]}")
    if [[ -d .git ]]; then
        git fetch --unshallow || true
        mapfile -t new < <(git diff "origin/main...HEAD" --name-only --diff-filter=A | grep '/Package.swift' | grep -v /Sources/ | xargs -I{} dirname {})
        packages+=("${new[@]}")
        echo "--- Discovered new directories in this PR: ${new[*]}"
    fi
fi
fi

echo "--- Building ${#packages[@]} packages"

# Determine worker pool parallelism based on available cores (up to 8 on e2-standard-32)
NPROC=$(nproc 2>/dev/null || echo 4)
PARALLEL_JOBS=$(( NPROC >= 16 ? 8 : (NPROC > 4 ? 4 : 2) ))
if [[ ${#packages[@]} -lt ${PARALLEL_JOBS} ]]; then
    PARALLEL_JOBS=${#packages[@]}
fi

echo "--- Running build with ${PARALLEL_JOBS} parallel workers"

# Use /workspace/.build-cache for Cloud Build, or fallback to repo .build-cache
SCRATCH_BASE="/workspace/.build-cache"
if [[ ! -d "/workspace" || ! -w "/workspace" ]]; then
    SCRATCH_BASE="${REPO_ROOT}/.build-cache"
fi
mkdir -p "${SCRATCH_BASE}"

build_single_package() {
    local dir="$1"
    local worker_id="$2"
    local name="${dir}"
    [[ "${dir}" == "." ]] && name="top-level package"

    local worker_scratch="${SCRATCH_BASE}/w${worker_id}"
    mkdir -p "${worker_scratch}"

    # Construct flags with worker-isolated scratch path
    local worker_flags=()
    local skip_next=false
    for f in "${flags[@]}"; do
        if [[ "${skip_next}" == true ]]; then
            skip_next=false
            continue
        fi
        if [[ "${f}" == "--scratch-path" ]]; then
            skip_next=true
            continue
        fi
        worker_flags+=("${f}")
    done
    worker_flags=(--scratch-path "${worker_scratch}" "${worker_flags[@]}")

    local flags=("${worker_flags[@]}")
    edit_package_dependencies "${dir}"

    local log_file="${dir}/.test.log"
    echo "--- Building ${name} [worker ${worker_id}] ---"
    if swift build --build-tests "${worker_flags[@]}" --package-path "${dir}" >"${log_file}" 2>&1; then
        echo "✓ ${name} built successfully"
        if [[ -z "${GOOGLE_CLOUD_SWIFT_TEST_RUNNING_ON_GCB:-}" && -z "${CI:-}" ]]; then
            restore_package_dependencies "${dir}"
        fi
        return 0
    else
        cat "${log_file}"
        echo; echo "✗ ${name} failed to build"
        if [[ -z "${GOOGLE_CLOUD_SWIFT_TEST_RUNNING_ON_GCB:-}" && -z "${CI:-}" ]]; then
            restore_package_dependencies "${dir}"
        fi
        return 1
    fi
}

declare -A job_to_worker
declare -A job_to_pkg
available_slots=()
for ((i=1; i<=PARALLEL_JOBS; i++)); do
    available_slots+=("$i")
done

for dir in "${packages[@]}"; do
    [[ -f "${dir}/Package.swift" ]] || continue
    count=$((count + 1))

    if [[ ${#available_slots[@]} -eq 0 ]]; then
        wait -n -p finished_pid
        status=$?
        worker_id="${job_to_worker[$finished_pid]}"
        unset "job_to_worker[$finished_pid]"
        unset "job_to_pkg[$finished_pid]"
        available_slots+=("${worker_id}")
        if [[ ${status} -ne 0 ]]; then
            errors=$((errors + 1))
        fi
    fi

    worker_id="${available_slots[0]}"
    available_slots=("${available_slots[@]:1}")

    build_single_package "${dir}" "${worker_id}" &
    pid=$!
    job_to_worker["$pid"]="${worker_id}"
    job_to_pkg["$pid"]="${dir}"
done

for pid in "${!job_to_worker[@]}"; do
    wait "${pid}" || errors=$((errors + 1))
done

rm -rf "${SCRATCH_BASE}" 2>/dev/null || true

echo; echo; echo "${count} local package(s) built, ${errors} failure(s)."
echo "--- Remaining disk space"
df -h

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
