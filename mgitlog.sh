#!/bin/bash
set -euo pipefail

#===============================================================================
# Configuration
#===============================================================================
TOOL_NAME="mgitlog"
VERSION="1.1.0"

# Initialize arrays and flags
declare -a root_dirs
declare -a git_args=()
declare -a exclude_patterns=()
show_header=false
export git_args
git_args_string=""
parallel_processes=0  # 0 means no parallelization

# HOOK: Added - Document new environment variables for hooks
# MGITLOG_BEFORE_CMD: If set, run this command before 'git log'.
# MGITLOG_AFTER_CMD:  If set, run this command after 'git log' has been printed.

#===============================================================================
# Helper Functions
#===============================================================================

# Display help information
show_help() {
    cat << EOF
Usage: $TOOL_NAME [options] [git log arguments] # Run 'git log' across multiple repositories

Options:
  --mroot DIR               Specify root directory. Defaults to current directory (can be used multiple times)
  --mheader                 Show repository headers
  --mexclude PATTERN        Exclude repository path(s) from scanning (can be used multiple times)
                                Supports partial matches (e.g., 'test' excludes 'test-repo')
  --mparallelize [NUMBER]   Enable parallel processing with optional number of processes (default: 4)
  --help                    Show this help message
  --version                 Show version information. Current is $VERSION

Environment Variables:
  MGITLOG_BEFORE_CMD        A command (or series of commands) to run *before* 'git log' in each repository.
                            For example:
                              MGITLOG_BEFORE_CMD="git pull --rebase"

  MGITLOG_AFTER_CMD         A command (or series of commands) to run *after* 'git log' output is printed for each repository.
                            For example:
                              MGITLOG_AFTER_CMD="echo 'Done with repo!'"

If these variables are unset or empty, no pre- or post-processing is done.
EOF
}

#===============================================================================
# Repository Processing Functions
#===============================================================================

# Get repository name from path
get_repo_name() {
    local repo_path="$1"
    basename "$repo_path" | tr '[:lower:]' '[:upper:]'
}

# Print repository header
print_repo_header() {
    local repo_path="$1"
    local repo_name
    
    repo_name=$(get_repo_name "$repo_path")
    echo "$repo_name [$repo_path]"
    echo "----------------------------------------"
    echo
}

# Process a single repository
process_repository() {
    local repo_path="$1"
    local show_header="$2"
    local git_args_str="$4"
    
    [[ -z "$repo_path" ]] && return
    
    # HOOK: Run before-hook if MGITLOG_BEFORE_CMD is set
    if [[ -n "${MGITLOG_BEFORE_CMD:-}" ]]; then
        (cd "$repo_path" && eval "$MGITLOG_BEFORE_CMD") || {
            echo "Warning: Pre-processing command failed in $repo_path. Skipping."
            return
        }
    fi
    
    local git_output
    if [[ -n "$git_args_str" ]]; then
        git_output=$(cd "$repo_path" && eval "git -c color.ui=always --no-pager log $git_args_str") || return
    else
        git_output=$(cd "$repo_path" && git -c color.ui=always --no-pager log) || return
    fi

    if [[ -n "$git_output" ]]; then
        {
            if [[ "$show_header" == "true" ]]; then
                echo
                print_repo_header "$repo_path"
            fi
            echo "$git_output"
            echo
        }
    fi

    # HOOK: Run after-hook if MGITLOG_AFTER_CMD is set
    if [[ -n "${MGITLOG_AFTER_CMD:-}" ]]; then
        (cd "$repo_path" && eval "$MGITLOG_AFTER_CMD") || {
            echo "Warning: Post-processing command failed in $repo_path."
        }
    fi
}

# Find git repositories in a directory
find_git_repos() {
    local dir="$1"
    [[ ! -d "$dir" ]] && { echo "Error: Directory does not exist: $dir" >&2; return 1; }

    if [[ -d "$dir/.git" ]]; then
        if (( ${#exclude_patterns[@]} > 0 )); then
            for pattern in "${exclude_patterns[@]}"; do
                [[ "$dir" == *"$pattern"* ]] && return
            done
        fi
        echo "$dir"
        return
    fi

    find "$dir" -mindepth 1 -maxdepth 2 -type d -name .git 2>/dev/null | while read -r gitdir; do
        local repo_path
        repo_path=$(dirname "$gitdir")
        local excluded=false
        if (( ${#exclude_patterns[@]} > 0 )); then
            for pattern in "${exclude_patterns[@]}"; do
                if [[ "$repo_path" == *"$pattern"* ]]; then
                    excluded=true
                    break
                fi
            done
        fi
        [[ "$excluded" == false ]] && echo "$repo_path"
    done
}

# Export functions for parallel processing
export -f process_repository
export -f print_repo_header
export -f get_repo_name

#===============================================================================
# Argument Parsing
#===============================================================================

# Flag to indicate if we have started processing git log arguments
git_args_started=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            echo "$VERSION"
            exit 0
            ;;
        --help)
            show_help
            exit 0
            ;;
        --m*)
            if $git_args_started; then
                echo "Error: All mgitlog options (--m*) must appear before git log arguments" >&2
                show_help >&2
                exit 1
            fi
            case $1 in
                --mroot)
                    if [[ -n "${2:-}" ]]; then
                        root_dirs+=("$(eval echo "$2")")
                        shift 2
                    else
                        echo "Error: --mroot requires a directory argument" >&2
                        show_help >&2
                        exit 1
                    fi
                    ;;
                --mheader)
                    show_header=true
                    shift
                    ;;
                --mexclude)
                    if [[ -n "${2:-}" ]]; then
                        exclude_patterns+=("$2")
                        shift 2
                    else
                        echo "Error: --mexclude requires a pattern argument" >&2
                        show_help >&2
                        exit 1
                    fi
                    ;;
                --mparallelize)
                    parallel_processes="${2:-4}"
                    if ! [[ "$parallel_processes" =~ ^[0-9]+$ ]]; then
                        parallel_processes=4
                        shift
                    else
                        shift 2
                    fi
                    ;;
                *)
                    echo "Error: Unknown mgitlog option: $1" >&2
                    show_help >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            git_args_started=true
            git_args+=("$1")
            shift
            ;;
    esac
done

#===============================================================================
# Main Execution
#===============================================================================

# Use current directory if no roots specified
[[ ${#root_dirs[@]} -eq 0 ]] && root_dirs+=("$(pwd)")

# Convert all paths to absolute paths
for i in "${!root_dirs[@]}"; do
    if cd "${root_dirs[$i]}" 2>/dev/null; then
        root_dirs[$i]="$(pwd)"
        cd - >/dev/null
    else
        echo "Error: Cannot access directory: ${root_dirs[$i]}" >&2
        exit 1
    fi
done

# Convert git_args array to string
[[ ${#git_args[@]} -gt 0 ]] && printf -v git_args_string '%q ' "${git_args[@]}"

# Process repositories in parallel or sequentially
for root_dir in "${root_dirs[@]}"; do
    if [ "$parallel_processes" -gt 0 ]; then
        find_git_repos "$root_dir" | xargs -P "$parallel_processes" -I {} bash -c "process_repository {} '$show_header' false '$git_args_string'" || true
    else
        while IFS= read -r repo; do
            process_repository "$repo" "$show_header" false "$git_args_string"
        done < <(find_git_repos "$root_dir")
    fi
done