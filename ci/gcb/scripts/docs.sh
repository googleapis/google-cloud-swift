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

source "${REPO_ROOT}/ci/package-dependencies.sh"

errors=0
count=0

shard_index="${1:-${SHARD_INDEX:-0}}"
shard_count="${2:-${SHARD_COUNT:-1}}"
trigger_name="${TRIGGER_NAME:-${GCB_TRIGGER_NAME:-}}"

if ! [[ "${shard_index}" =~ ^[0-9]+$ ]] || ! [[ "${shard_count}" =~ ^[0-9]+$ ]]; then
    echo "✗ Invalid shard parameters: shard_index='${shard_index}', shard_count='${shard_count}'"
    exit 1
fi

if (( shard_count <= 0 )); then
    echo "✗ shard_count must be greater than 0, got ${shard_count}"
    exit 1
fi

if (( shard_index >= shard_count )); then
    echo "✗ shard_index (${shard_index}) must be less than shard_count (${shard_count})"
    exit 1
fi


clean_flags=(
    --warnings-as-errors
)
clean_targets=(
    GoogleWKT
    GoogleAuth
    GoogleGax
    GoogleCloudStorage
    GoogleCloudSecretManagerV1
    GoogleCloudWorkflowsV1
    GoogleCloudSecurityPublicCAV1
)

declare -A built_targets
for target in "${clean_targets[@]}"; do
    built_targets["${target}"]=1
done
targets=()
run_clean_targets=false
discover_targets=false

# Select the packages *before* resolving the dependencies. Loading the manifests
# for all the packages in `generated/` is slow, PR builds only need a handful of
# them.
if [[ "${trigger_name}" != gcb-pm-* && "${shard_count}" -le 1 ]]; then
    echo "--- Building PR documentation subset (trigger: ${trigger_name:-none})"
    run_clean_targets=true
    # Setting this variable, even to an empty value, selects the small set of
    # packages used by the tests, plus any package added by this PR.
    extra_packages=""
    if [[ -d "${REPO_ROOT}/.git" ]] && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "${REPO_ROOT}" fetch --unshallow || true
        mapfile -t new_dirs < <(git -C "${REPO_ROOT}" diff "origin/main...HEAD" --name-only --diff-filter=A 2>/dev/null | grep '/Package.swift' | grep -v /Sources/ | xargs -I{} dirname {} 2>/dev/null || true)
        if [[ ${#new_dirs[@]} -gt 0 ]]; then
            echo "--- Discovered new directories in this PR: ${new_dirs[*]}"
            new_targets=()
            for d in "${new_dirs[@]}"; do
                t=$(sed -n 's/^  name: "\([^"]*\)",/\1/p' "${d}/Package.swift")
                [[ -n "${t}" ]] && new_targets+=("${t}")
            done
            if [[ ${#new_targets[@]} -gt 0 ]]; then
                targets+=("${new_targets[@]}")
                extra_packages="$(printf '%s ' "${new_dirs[@]##*/}")"
            fi
        fi
    fi
    export GOOGLE_CLOUD_SWIFT_EXTRA_PACKAGES="${extra_packages}"
else
    # Post-merge or multi-shard build. `SHARD_INDEX` and `SHARD_COUNT` select the
    # packages, and the targets are discovered once the dependencies resolve.
    # Shard 0 validates clean_targets with --warnings-as-errors.
    if (( shard_index == 0 )); then
        run_clean_targets=true
    fi
    discover_targets=true
    export GOOGLE_CLOUD_SWIFT_BUILD_SHARD_INDEX="${shard_index}"
    export GOOGLE_CLOUD_SWIFT_BUILD_SHARD_COUNT="${shard_count}"
fi

# Build the documentation against the packages in this repository, not against
# the last published version of each package. `restore_all_package_dependencies`
# runs on exit, via the trap installed by `package-dependencies.sh`.
edit_package_dependencies "."

echo "--- SWIFT VERSION ---"
swift --version
echo "--- FETCH DEPENDENCIES ---"
swift package resolve || \
  (sleep 5 ; swift package resolve) || \
  (sleep 10; swift package resolve)
echo "--- Initial disk space"
df -h
echo "--- DONE ---"

if [[ "${discover_targets}" == true ]]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "--- Installing jq ---"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -o Acquire::Retries=3 || \
          (sleep 5 ; apt-get update -o Acquire::Retries=3) || \
          (sleep 10; apt-get update -o Acquire::Retries=3)
        apt-get install -y -o Acquire::Retries=3 --no-install-recommends jq || \
          (sleep 5 ; apt-get install -y -o Acquire::Retries=3 --no-install-recommends jq) || \
          (sleep 10; apt-get install -y -o Acquire::Retries=3 --no-install-recommends jq)
    fi

    echo "--- Discovering targets for shard ${shard_index} of ${shard_count} via swift package dump-package"
    mapfile -t targets < <(swift package dump-package 2>/dev/null | jq -r '
      .targets[] |
      select(.name == "AllModules") |
      .dependencies[].product[0] |
      select(. != null and . != "UserGuide")
    ' || true)
fi

if [[ "${run_clean_targets}" == true ]]; then
    echo "--- Building ${#clean_targets[@]} targets with warnings as errors"
    for target in "${clean_targets[@]}"; do
        count=$((count + 1))
        built_targets["${target}"]=1

        echo; echo "================ Building ${target} ================"
        if swift package generate-documentation "${clean_flags[@]}" --target "${target}" >"${target}.docs.log" 2>&1; then
            echo "✓ ${target} built successfully"
        else
            echo; echo "✗ ${target} failed to build"
            cat "${target}.docs.log"
            errors=$((errors + 1))
        fi
    done
fi

echo; echo; echo "--- Building shard ${shard_index} of ${shard_count} (${#targets[@]} targets)"
for target in "${targets[@]}"; do
    if [[ -n "${built_targets[${target}]:-}" ]]; then
        echo "--- Skipping ${target} (already built in clean_targets) ---"
        continue
    fi
    count=$((count + 1))
    echo; echo "================ Building ${target} ================"
    if swift package generate-documentation --target "${target}" >"${target}.docs.log" 2>&1; then
        echo "✓ ${target} documentation built successfully"
    else
        echo; echo "✗ ${target} documentation failed to build"
        cat "${target}.docs.log"
        errors=$((errors + 1))
    fi
done

echo; echo; echo "${count} local target(s) built, ${errors} failure(s)."
echo "--- Remaining disk space"
df -h

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
