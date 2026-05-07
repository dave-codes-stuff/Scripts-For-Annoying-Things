#!/usr/bin/env bash
# Shared library for Image Manipulation scripts.
# Source this file at the top of each script:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/img-manip-lib.sh"

# ─── Config ──────────────────────────────────────────────────────────────────

# find_config_value <key> <script_dir>
# Walks up from script_dir looking for img-manip.config, returns the value for key.
# Resolves ./relative paths against the config file's own directory.
find_config_value() {
    local key="$1" start_dir="$2"
    local dir="$start_dir"
    while [[ "$dir" != "/" ]]; do
        local cfg="$dir/img-manip.config"
        if [[ -f "$cfg" ]]; then
            local raw
            raw="$(grep -m1 "^${key}=" "$cfg" 2>/dev/null | cut -d'=' -f2-)"
            [[ -z "$raw" ]] && return
            if [[ "$raw" == ./* || "$raw" == ../* ]]; then
                local resolved
                resolved="$(cd "$dir/${raw}" 2>/dev/null && pwd)" || resolved="$dir/${raw#./}"
                echo "$resolved"
            else
                echo "$raw"
            fi
            return
        fi
        dir="$(dirname "$dir")"
    done
}

# ─── Run Directory ────────────────────────────────────────────────────────────

# make_run_dir <script_dir>
# Creates and returns a timestamped output directory for this script run.
# Uses OUTPUT_DIR from img-manip.config; falls back to ./Output with a warning.
make_run_dir() {
    local script_dir="$1"
    local output_base
    output_base="$(find_config_value OUTPUT_DIR "$script_dir")"

    if [[ -z "$output_base" ]]; then
        echo "[WARN ] img-manip.config not found — falling back to ${script_dir}/Output" >&2
        output_base="${script_dir}/Output"
    fi

    local run_dir="${output_base}/$(date '+%Y-%m-%d_%H-%M-%S')_$$"
    mkdir -p "$run_dir"
    echo "$run_dir"
}

# ─── Tree View ────────────────────────────────────────────────────────────────

# print_tree <dir>
# Prints a human-friendly summary of the output directory.
print_tree() {
    local dir="$1"
    echo ""
    echo "Output Directory: $dir"
    echo ""
    local name
    name="$(basename "$dir")"
    echo "$name/"
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$(basename "$f")")
    done < <(find "$dir" -maxdepth 1 -type f -print0 | sort -z)
    local count=${#files[@]}
    for i in "${!files[@]}"; do
        if (( i < count - 1 )); then
            echo "├── ${files[$i]}"
        else
            echo "└── ${files[$i]}"
        fi
    done
    if [[ $count -eq 0 ]]; then
        echo "(no files)"
    fi
    echo ""
}

# ─── Logging ─────────────────────────────────────────────────────────────────
# Scripts set LOG_FILE before sourcing or call these with LOG_FILE in scope.

_log() {
    local level="$1"; shift
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local msg="[${ts}] [${level}] $*"
    echo "$msg"
    [[ -n "${LOG_FILE:-}" ]] && echo "$msg" >> "$LOG_FILE"
}

_log_err() {
    local level="$1"; shift
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local msg="[${ts}] [${level}] $*"
    echo "$msg" >&2
    [[ -n "${LOG_FILE:-}" ]] && echo "$msg" >> "$LOG_FILE"
}

_log_file() {
    local level="$1"; shift
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    [[ -n "${LOG_FILE:-}" ]] && echo "[${ts}] [${level}] $*" >> "$LOG_FILE"
}

log_info()   { _log    "INFO " "$@"; }
log_warn()   { _log    "WARN " "$@"; }
log_error()  { _log_err "ERROR" "$@"; }
log_detail() { _log_file "DETAIL" "$@"; }

# ─── Dependency Check ─────────────────────────────────────────────────────────

# check_dep <tool> <apt-package>
# Prints an error and sets DEPS_OK=false if tool is not found.
check_dep() {
    local tool="$1" pkg="$2"
    if ! command -v "$tool" &>/dev/null; then
        log_error "Required tool '$tool' not found. Install with: sudo apt install $pkg"
        DEPS_OK=false
    fi
}
