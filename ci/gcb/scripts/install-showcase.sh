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
#
# Downloads and verifies the pinned `gapic-showcase` binary into the local
# cache if not already present, and prints the binary path to stdout.

set -euo pipefail

SHOWCASE_VERSION="0.44.2"
SHOWCASE_SHA256="873efedf090b055ee440ab6d4139d9539fbe26241830c0d0eaae65912e52026d"
SHOWCASE_DIR="${HOME}/.cache/gapic-showcase/${SHOWCASE_VERSION}"
SHOWCASE_BIN="${SHOWCASE_DIR}/gapic-showcase-${SHOWCASE_VERSION}"

if [[ ! -x "${SHOWCASE_BIN}" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "--- Installing curl ---" >&2
        export DEBIAN_FRONTEND=noninteractive
        (apt-get update -o Acquire::Retries=3 || \
          (sleep 5 ; apt-get update -o Acquire::Retries=3) || \
          (sleep 10; apt-get update -o Acquire::Retries=3)) >&2
        (apt-get install -y -o Acquire::Retries=3 --no-install-recommends ca-certificates curl || \
          (sleep 5 ; apt-get install -y -o Acquire::Retries=3 --no-install-recommends ca-certificates curl) || \
          (sleep 10; apt-get install -y -o Acquire::Retries=3 --no-install-recommends ca-certificates curl)) >&2
    fi
    echo "--- Downloading gapic-showcase v${SHOWCASE_VERSION} ---" >&2
    mkdir -p "${SHOWCASE_DIR}"
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gapic-showcase.XXXXXX")"
    trap 'rm -rf "${WORK_DIR}"' EXIT
    SHOWCASE_ARCHIVE="${WORK_DIR}/gapic-showcase.tar.gz"
    curl -fsSL --retry 5 --retry-delay 15 \
        "https://github.com/googleapis/gapic-showcase/releases/download/v${SHOWCASE_VERSION}/gapic-showcase-${SHOWCASE_VERSION}-linux-amd64.tar.gz" \
        -o "${SHOWCASE_ARCHIVE}"
    echo "${SHOWCASE_SHA256}  ${SHOWCASE_ARCHIVE}" | sha256sum -c - >&2
    tar -C "${WORK_DIR}" -xzf "${SHOWCASE_ARCHIVE}"
    mv "${WORK_DIR}/gapic-showcase" "${SHOWCASE_BIN}"
    chmod +x "${SHOWCASE_BIN}"
fi

echo "${SHOWCASE_BIN}"
