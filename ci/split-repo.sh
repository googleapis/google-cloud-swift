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

# Performs a repository subtree split using `git subtree split` for specified
# package paths (e.g., packages/auth, generated/google-rpc) while preserving
# full commit history, placing the subtree contents at the root, and ensuring
# essential root files (LICENSE, CODE_OF_CONDUCT.md, CONTRIBUTING.md) are
# preserved on every commit across the split history.

set -euo pipefail

if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    REPO_ROOT="$(git rev-parse --show-toplevel)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

# Default root files to preserve on every commit in each split repository
DEFAULT_ROOT_FILES=("LICENSE" "CODE_OF_CONDUCT.md" "CONTRIBUTING.md")

# Colors for terminal output
if [[ -t 1 ]]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_GREEN="\033[32m"
    COLOR_YELLOW="\033[33m"
    COLOR_BLUE="\033[34m"
    COLOR_RED="\033[31m"
    COLOR_CYAN="\033[36m"
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_RED=""
    COLOR_CYAN=""
fi

log_info() {
    echo -e "${COLOR_BLUE}::info::${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}::notice::${COLOR_RESET} $*"
}

log_warning() {
    echo -e "${COLOR_YELLOW}::warning::${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}::error::${COLOR_RESET} $*" >&2
}

show_help() {
    cat << EOF
${COLOR_BOLD}USAGE${COLOR_RESET}
    ${0##*/} [OPTIONS] [PATH_OR_PACKAGE...]

${COLOR_BOLD}DESCRIPTION${COLOR_RESET}
    Splits one or more subdirectories (e.g., 'packages/auth', 'generated/google-rpc',
    'generated/google-cloud-secretmanager-v1') from the monorepo into standalone
    commit histories using 'git subtree split', placing the subtree contents at the root.
    Preserves commit history, author info, dates, and messages.

    By default, it preserves the monorepo root files on ${COLOR_BOLD}every commit${COLOR_RESET} in the split history:
      - LICENSE
      - CODE_OF_CONDUCT.md
      - CONTRIBUTING.md

${COLOR_BOLD}TARGET SELECTION${COLOR_RESET}
    [PATH_OR_PACKAGE...]        Positional paths or package names to split.
    -p, --prefix <path>         Subdirectory path in repository (e.g. 'packages/auth', 'generated/google-rpc').
                                Can be specified multiple times.
    --package <name>            Package name shorthand. Resolves 'packages/<name>', 'generated/<name>', or '<name>'.
                                Can be specified multiple times.
    --all                       Split all packages found in 'packages/'.
    --all-generated             Split all generated packages found in 'generated/'.

${COLOR_BOLD}ROOT FILES OPTIONS${COLOR_RESET}
    --include-root-file <file>  Additional monorepo root file to preserve on every commit in the split repository.
                                Can be specified multiple times.
    --no-root-files             Do not include root files (perform pure subtree split only).
    --root-files <file1,file2>  Override list of root files to preserve (comma-separated).

${COLOR_BOLD}GIT SPLIT OPTIONS${COLOR_RESET}
    -o, --origin <commit-ish>   Source commit or branch in the monorepo to split from (default: HEAD).
    -b, --branch <branch>       Local branch name to create or update with the split commit SHA.
                                (When splitting multiple packages, branch name is formatted as '<branch>/<pkg_name>').
    -t, --tag <tag_name>        Tag name to apply to the split commit.

${COLOR_BOLD}REMOTE PUBLISHING OPTIONS${COLOR_RESET}
    -r, --remote <url|name>     Remote repository URL or remote name to push the split commit to.
    --remote-base <base_url>    Base URL or org for multi-package pushing (e.g. 'git@github.com:googleapis').
                                Target URL becomes '<base_url>/google-cloud-swift-<pkg_name>.git'.
    --remote-branch <branch>    Branch name on the remote repository (default: same as --branch, or 'main').
    --push-tag                  Also push the tag specified with --tag to the remote repository.
    -f, --force                 Force branch updates and git pushes.
    -n, --dry-run               Simulate the split and show what would be updated/pushed without making changes.

${COLOR_BOLD}OUTPUT OPTIONS${COLOR_RESET}
    --sha-only                  Output only the final 40-character split commit SHA (ideal for single-target scripting).
    -v, --verbose               Enable verbose output (shows root contents of the split commit).
    -h, --help                  Show this help message.

${COLOR_BOLD}EXAMPLES${COLOR_RESET}
    # 1. Split 'packages/auth' with root LICENSE/CODE_OF_CONDUCT/CONTRIBUTING on every commit:
    ${0##*/} packages/auth

    # 2. Split a generated package 'generated/google-rpc':
    ${0##*/} generated/google-rpc

    # 3. Split by package shorthand and update branch:
    ${0##*/} --package google-rpc -b split/google-rpc

    # 4. Split multiple packages at once:
    ${0##*/} packages/auth generated/google-rpc

    # 5. Split and push to a remote repo:
    ${0##*/} generated/google-rpc --remote git@github.com:googleapis/google-cloud-swift-google-rpc.git --remote-branch main

    # 6. Split from a release tag and create a tag on the remote split repo:
    ${0##*/} packages/auth -o v1.0.0 --tag v1.0.0 -r git@github.com:googleapis/google-cloud-swift-auth.git --push-tag

    # 7. Split all hand-written packages:
    ${0##*/} --all

    # 8. Split all generated packages:
    ${0##*/} --all-generated
EOF
}

# Resolves a given package name or path to a relative directory within the repo
resolve_package_path() {
    local target="$1"
    # Strip leading/trailing slashes
    target="${target#/}"
    target="${target%/}"

    if [[ -d "${REPO_ROOT}/${target}" ]]; then
        echo "${target}"
        return 0
    elif [[ -d "${REPO_ROOT}/packages/${target}" ]]; then
        echo "packages/${target}"
        return 0
    elif [[ -d "${REPO_ROOT}/generated/${target}" ]]; then
        echo "generated/${target}"
        return 0
    fi
    return 1
}

# Rewrites every commit in the split history to include specified root files (e.g. LICENSE, CONTRIBUTING.md, CODE_OF_CONDUCT.md)
rewrite_history_with_root_files() {
    local raw_sha="$1"
    local origin_ref="$2"
    shift 2
    local files_to_include=("$@")

    if [[ ${#files_to_include[@]} -eq 0 ]]; then
        echo "${raw_sha}"
        return 0
    fi

    # Extract tree entries for the requested root files from origin_ref
    local root_entries=()
    for f in "${files_to_include[@]}"; do
        local entry
        entry="$(git ls-tree "${origin_ref}" -- "${f}" 2>/dev/null || true)"
        if [[ -n "${entry}" ]]; then
            root_entries+=("${entry}")
        fi
    done

    if [[ ${#root_entries[@]} -eq 0 ]]; then
        echo "${raw_sha}"
        return 0
    fi

    # Retrieve all commits in topological order (oldest to newest)
    local commits
    commits="$(git rev-list --reverse --topo-order "${raw_sha}")"

    # Temporary directory for commit mapping (portable across Bash 3.x / 4.x / 5.x)
    local map_dir
    map_dir="$(mktemp -d "${TMPDIR:-/tmp}/split-map-XXXXXX")"
    trap 'rm -rf "${map_dir}"' RETURN

    local last_new_c=""
    for c in ${commits}; do
        local current_entries
        current_entries="$(git ls-tree "${c}")"

        # Remove any pre-existing entry for the root files from current commit tree
        for f in "${files_to_include[@]}"; do
            current_entries="$(echo "${current_entries}" | grep -v "[[:space:]]${f}$" || true)"
        done

        local combined_input
        combined_input="$(printf "%s\n" "${current_entries}" "${root_entries[@]}" | sed '/^$/d')"

        local new_tree
        new_tree="$(echo "${combined_input}" | git mktree)"

        # Map parent commits to their newly rewritten commit SHAs
        local parent_args=()
        local p
        for p in $(git log --pretty=%P -n 1 "${c}"); do
            local mapped_p="${p}"
            if [[ -f "${map_dir}/${p}" ]]; then
                mapped_p="$(<"${map_dir}/${p}")"
            fi
            parent_args+=("-p" "${mapped_p}")
        done

        export GIT_AUTHOR_NAME="$(git log -n 1 --pretty=format:%an "${c}")"
        export GIT_AUTHOR_EMAIL="$(git log -n 1 --pretty=format:%ae "${c}")"
        export GIT_AUTHOR_DATE="$(git log -n 1 --pretty=format:%ad "${c}")"
        export GIT_COMMITTER_NAME="$(git log -n 1 --pretty=format:%cn "${c}")"
        export GIT_COMMITTER_EMAIL="$(git log -n 1 --pretty=format:%ce "${c}")"
        export GIT_COMMITTER_DATE="$(git log -n 1 --pretty=format:%cd "${c}")"
        local commit_msg
        commit_msg="$(git log -n 1 --pretty=format:%B "${c}")"

        local new_c
        new_c="$(echo "${commit_msg}" | git -c commit.gpgsign=false commit-tree "${new_tree}" "${parent_args[@]}")"
        echo "${new_c}" > "${map_dir}/${c}"
        last_new_c="${new_c}"
    done

    echo "${last_new_c}"
}

# Perform the subtree split for a single prefix path
split_single_prefix() {
    local prefix="$1"
    local origin="$2"
    local branch="$3"
    local tag="$4"
    local remote="$5"
    local remote_branch="$6"
    local push_tag="$7"
    local force="$8"
    local dry_run="$9"
    local sha_only="${10}"
    shift 10
    local root_files=("$@")

    # Normalize prefix (strip leading/trailing slashes)
    prefix="${prefix#/}"
    prefix="${prefix%/}"

    if [[ ! -d "${REPO_ROOT}/${prefix}" ]]; then
        log_error "Prefix path '${prefix}' does not exist in repository root (${REPO_ROOT})."
        return 1
    fi

    if [[ "${sha_only}" != "true" ]]; then
        log_info "Splitting '${COLOR_BOLD}${prefix}${COLOR_RESET}' from origin '${COLOR_BOLD}${origin}${COLOR_RESET}' using 'git subtree split'..."
    fi

    cd "${REPO_ROOT}"

    # Execute git subtree split.
    # Note: commit signing is disabled for the split operation to prevent interactive GPG prompts or sandbox signing errors.
    local split_sha
    split_sha="$(git -c commit.gpgsign=false subtree split --prefix="${prefix}" -q "${origin}")"
    split_sha="$(echo "${split_sha}" | tr -d '[:space:]')"

    if [[ -z "${split_sha}" || ${#split_sha} -ne 40 ]]; then
        log_error "Failed to retrieve a valid 40-character commit SHA for prefix '${prefix}'. Got: '${split_sha}'"
        return 1
    fi

    # Rewrite every commit in history to preserve monorepo root files if enabled
    if [[ ${#root_files[@]} -gt 0 ]]; then
        local raw_sha="${split_sha}"
        split_sha="$(rewrite_history_with_root_files "${raw_sha}" "${origin}" "${root_files[@]}")"
    fi

    if [[ "${sha_only}" == "true" ]]; then
        echo "${split_sha}"
        return 0
    fi

    log_success "Split commit created: ${COLOR_BOLD}${split_sha}${COLOR_RESET}"

    local commit_count
    commit_count="$(git rev-list --count "${split_sha}")"
    log_info "Split history contains ${COLOR_BOLD}${commit_count}${COLOR_RESET} commit(s) (with root files preserved on each commit)."

    # Update local branch if requested
    if [[ -n "${branch}" ]]; then
        if [[ "${dry_run}" == "true" ]]; then
            log_info "[DRY-RUN] Would update local branch '${branch}' -> ${split_sha}"
        else
            git branch -f "${branch}" "${split_sha}"
            log_success "Updated local branch '${COLOR_BOLD}${branch}${COLOR_RESET}' -> ${split_sha}"
        fi
    fi

    # Create tag if requested
    if [[ -n "${tag}" ]]; then
        if [[ "${dry_run}" == "true" ]]; then
            log_info "[DRY-RUN] Would create tag '${tag}' -> ${split_sha}"
        else
            local force_tag_flag=()
            if [[ "${force}" == "true" ]]; then
                force_tag_flag=("-f")
            fi
            git -c tag.gpgsign=false tag "${force_tag_flag[@]}" "${tag}" "${split_sha}"
            log_success "Created tag '${COLOR_BOLD}${tag}${COLOR_RESET}' -> ${split_sha}"
        fi
    fi

    # Push to remote repository if requested
    if [[ -n "${remote}" ]]; then
        local target_branch="${remote_branch:-${branch:-main}}"
        local force_push_flag=()
        if [[ "${force}" == "true" ]]; then
            force_push_flag=("--force")
        fi

        local push_ref="${split_sha}:refs/heads/${target_branch}"

        if [[ "${dry_run}" == "true" ]]; then
            log_info "[DRY-RUN] Would push to remote '${remote}': ${push_ref} ${force_push_flag[*]}"
            if [[ "${push_tag}" == "true" && -n "${tag}" ]]; then
                log_info "[DRY-RUN] Would push tag '${tag}' to remote '${remote}'"
            fi
        else
            log_info "Pushing split commit to '${remote}' (ref: ${target_branch})..."
            git push "${force_push_flag[@]}" "${remote}" "${push_ref}"
            log_success "Pushed split branch to '${COLOR_BOLD}${remote}${COLOR_RESET}' (${target_branch})"

            if [[ "${push_tag}" == "true" && -n "${tag}" ]]; then
                log_info "Pushing tag '${tag}' to '${remote}'..."
                git push "${force_push_flag[@]}" "${remote}" "refs/tags/${tag}"
                log_success "Pushed tag '${COLOR_BOLD}${tag}${COLOR_RESET}' to '${remote}'"
            fi
        fi
    fi

    # Show root contents if verbose
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo ""
        log_info "Root contents of split commit (${split_sha:0:8}):"
        git ls-tree --name-only "${split_sha}" | sed 's/^/  - /'
        echo ""
    fi

    return 0
}

# Main script entrypoint
main() {
    local target_paths=()
    local origin="HEAD"
    local branch=""
    local tag=""
    local remote=""
    local remote_base=""
    local remote_branch=""
    local push_tag="false"
    local force="false"
    local dry_run="false"
    local sha_only="false"
    local all_packages="false"
    local all_generated="false"
    local root_files=("${DEFAULT_ROOT_FILES[@]}")
    local custom_root_files="false"
    VERBOSE="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--prefix)
                target_paths+=("$2")
                shift 2
                ;;
            --package)
                target_paths+=("$2")
                shift 2
                ;;
            -o|--origin)
                origin="$2"
                shift 2
                ;;
            -b|--branch)
                branch="$2"
                shift 2
                ;;
            -t|--tag)
                tag="$2"
                shift 2
                ;;
            -r|--remote)
                remote="$2"
                shift 2
                ;;
            --remote-base)
                remote_base="$2"
                shift 2
                ;;
            --remote-branch)
                remote_branch="$2"
                shift 2
                ;;
            --push-tag)
                push_tag="true"
                shift
                ;;
            --include-root-file)
                root_files+=("$2")
                shift 2
                ;;
            --root-files)
                IFS=',' read -r -a root_files <<< "$2"
                custom_root_files="true"
                shift 2
                ;;
            --no-root-files)
                root_files=()
                custom_root_files="true"
                shift
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            -n|--dry-run)
                dry_run="true"
                shift
                ;;
            --sha-only)
                sha_only="true"
                shift
                ;;
            --all|--all-packages)
                all_packages="true"
                shift
                ;;
            --all-generated)
                all_generated="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Run '${0##*/} --help' for usage."
                exit 1
                ;;
            *)
                # Positional argument (path or package name)
                target_paths+=("$1")
                shift
                ;;
        esac
    done

    # Collect all packages if --all or --all-generated specified
    if [[ "${all_packages}" == "true" || "${all_generated}" == "true" ]]; then
        local scan_dirs=()
        if [[ "${all_packages}" == "true" ]]; then
            scan_dirs+=("packages")
        fi
        if [[ "${all_generated}" == "true" ]]; then
            scan_dirs+=("generated")
        fi

        log_info "Scanning for packages in: ${scan_dirs[*]}..."
        local found_packages=()
        IFS=$'\n'
        found_packages=($(git -C "${REPO_ROOT}" ls-files "${scan_dirs[@]}" | grep '/Package.swift$' | xargs -I{} dirname {} | sort -u))
        unset IFS

        for p in "${found_packages[@]}"; do
            target_paths+=("${p}")
        done
    fi

    if [[ ${#target_paths[@]} -eq 0 ]]; then
        log_error "No targets specified. Provide a path/package (e.g., 'packages/auth', 'generated/google-rpc') or use '--all' / '--all-generated'."
        echo "Run '${0##*/} --help' for usage."
        exit 1
    fi

    # Deduplicate targets while preserving order
    local resolved_targets=()
    local seen_targets=()
    for raw_target in "${target_paths[@]}"; do
        local resolved
        if resolved="$(resolve_package_path "${raw_target}")"; then
            if [[ ! " ${seen_targets[*]:-} " =~ " ${resolved} " ]]; then
                resolved_targets+=("${resolved}")
                seen_targets+=("${resolved}")
            fi
        else
            log_error "Target '${raw_target}' could not be found under 'packages/', 'generated/', or as a path in ${REPO_ROOT}."
            exit 1
        fi
    done

    # If single target and not batch mode, execute directly
    if [[ ${#resolved_targets[@]} -eq 1 ]]; then
        local single_target="${resolved_targets[0]}"
        local single_remote="${remote}"
        if [[ -z "${single_remote}" && -n "${remote_base}" ]]; then
            local pkg_base="${single_target##*/}"
            single_remote="${remote_base%/}/google-cloud-swift-${pkg_base}.git"
        fi

        split_single_prefix "${single_target}" "${origin}" "${branch}" "${tag}" "${single_remote}" "${remote_branch}" "${push_tag}" "${force}" "${dry_run}" "${sha_only}" "${root_files[@]}"
        exit $?
    fi

    # Multi-target batch mode
    log_info "Processing ${#resolved_targets[@]} target package(s)..."
    echo ""

    local success_count=0
    local fail_count=0
    local summary_results=()

    for pkg_path in "${resolved_targets[@]}"; do
        local pkg_base="${pkg_path##*/}"
        local pkg_branch=""
        if [[ -n "${branch}" ]]; then
            pkg_branch="${branch}/${pkg_base}"
        fi

        local pkg_remote="${remote}"
        if [[ -z "${pkg_remote}" && -n "${remote_base}" ]]; then
            pkg_remote="${remote_base%/}/google-cloud-swift-${pkg_base}.git"
        fi

        echo "::group:: --- Splitting ${pkg_path} ---"
        local split_sha
        if split_sha="$(split_single_prefix "${pkg_path}" "${origin}" "${pkg_branch}" "${tag}" "${pkg_remote}" "${remote_branch}" "${push_tag}" "${force}" "${dry_run}" "true" "${root_files[@]}")"; then
            echo "::endgroup::"
            log_success "✓ ${pkg_path} -> ${split_sha}"
            summary_results+=("${pkg_path}|${split_sha}")
            success_count=$((success_count + 1))
        else
            echo "::endgroup::"
            log_error "✗ ${pkg_path} failed to split"
            fail_count=$((fail_count + 1))
        fi
    done

    echo ""
    echo "================================ SPLIT SUMMARY ================================"
    printf "%-50s %s\n" "PACKAGE PATH" "SPLIT COMMIT SHA"
    echo "-------------------------------------------------------------------------------"
    for item in "${summary_results[@]}"; do
        local p_path="${item%%|*}"
        local p_sha="${item##*|}"
        printf "%-50s %s\n" "${p_path}" "${p_sha}"
    done
    echo "==============================================================================="
    echo "Total: ${success_count} succeeded, ${fail_count} failed."

    if [[ ${fail_count} -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
