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

# Map host OS/arch to the gapic-showcase release asset and its pinned SHA-256 digest.
OS="$(uname -s)"
ARCH="$(uname -m)"
case "${OS}:${ARCH}" in
    Linux:x86_64|Linux:amd64)
        SHOWCASE_PLATFORM="linux-amd64"
        SHOWCASE_SHA256="873efedf090b055ee440ab6d4139d9539fbe26241830c0d0eaae65912e52026d"
        ;;
    Darwin:arm64|Darwin:aarch64)
        SHOWCASE_PLATFORM="darwin-arm64"
        SHOWCASE_SHA256="19a7d626f7676129e1a152ec31e2f02b6d0a1f5dc685a788ac0ce8612b394fdf"
        ;;
    Darwin:x86_64|Darwin:amd64)
        SHOWCASE_PLATFORM="darwin-amd64"
        SHOWCASE_SHA256="51f31975e5a1dd38ddee6778ba39b0189b12d0b1f923bb35545d040806f30b30"
        ;;
    *)
        echo "✗ unsupported platform for gapic-showcase: ${OS}/${ARCH}" >&2
        exit 1
        ;;
esac

SHOWCASE_DIR="${HOME}/.cache/gapic-showcase/${SHOWCASE_VERSION}"
SHOWCASE_BIN="${SHOWCASE_DIR}/gapic-showcase-${SHOWCASE_VERSION}-${SHOWCASE_PLATFORM}"

if [[ ! -x "${SHOWCASE_BIN}" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
        if [[ "${OS}" == "Linux" ]] && command -v apt-get >/dev/null 2>&1; then
            echo "--- Installing curl ---" >&2
            export DEBIAN_FRONTEND=noninteractive
            (apt-get update -o Acquire::Retries=3 || \
              (sleep 5 ; apt-get update -o Acquire::Retries=3) || \
              (sleep 10; apt-get update -o Acquire::Retries=3)) >&2
            (apt-get install -y -o Acquire::Retries=3 --no-install-recommends ca-certificates curl || \
              (sleep 5 ; apt-get install -y -o Acquire::Retries=3 --no-install-recommends ca-certificates curl) || \
              (sleep 10; apt-get install -y -o Acquire::Retries=3 --no-install-recommends ca-certificates curl)) >&2
        else
            echo "✗ curl is required to download gapic-showcase" >&2
            exit 1
        fi
    fi
    echo "--- Downloading gapic-showcase v${SHOWCASE_VERSION} (${SHOWCASE_PLATFORM}) ---" >&2
    mkdir -p "${SHOWCASE_DIR}"
    TMP_BASE="${TMPDIR:-/tmp}"
    WORK_DIR="$(mktemp -d "${TMP_BASE%/}/gapic-showcase.XXXXXX")"
    trap 'rm -rf "${WORK_DIR}"' EXIT
    SHOWCASE_ARCHIVE="${WORK_DIR}/gapic-showcase.tar.gz"
    curl -fsSL --retry 5 --retry-delay 15 \
        "https://github.com/googleapis/gapic-showcase/releases/download/v${SHOWCASE_VERSION}/gapic-showcase-${SHOWCASE_VERSION}-${SHOWCASE_PLATFORM}.tar.gz" \
        -o "${SHOWCASE_ARCHIVE}"
    # macOS ships shasum rather than GNU sha256sum.
    if command -v sha256sum >/dev/null 2>&1; then
        echo "${SHOWCASE_SHA256}  ${SHOWCASE_ARCHIVE}" | sha256sum -c - >&2
    elif command -v shasum >/dev/null 2>&1; then
        echo "${SHOWCASE_SHA256}  ${SHOWCASE_ARCHIVE}" | shasum -a 256 -c - >&2
    else
        echo "✗ neither sha256sum nor shasum found to verify archive" >&2
        exit 1
    fi
    tar -C "${WORK_DIR}" -xzf "${SHOWCASE_ARCHIVE}"
    mv "${WORK_DIR}/gapic-showcase" "${SHOWCASE_BIN}"
    chmod +x "${SHOWCASE_BIN}"
fi

echo "${SHOWCASE_BIN}"
