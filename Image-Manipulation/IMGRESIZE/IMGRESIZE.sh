#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/IMGRESIZE.log"

source "$SCRIPT_DIR/../lib/img-manip-lib.sh"

# ─── Defaults ────────────────────────────────────────────────────────────────
RESIZE_MODE=""
RESIZE_VALUE=""
OUTPUT_OVERRIDE=""
IMG_FILES=()

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] file1.jpg [file2.jpg ...]

Resize images by width, height, or percentage.
Output is written to a timestamped subdirectory (configured in img-manip.config).
Aspect ratio is always preserved.

Options:
  -W, --width <px>          Resize to this width; height scales proportionally
  -H, --height <px>         Resize to this height; width scales proportionally
  -p, --percent <n>         Scale by percentage (e.g. 50 = half size)
  -o, --output <dir>        Override the base output directory
  -h, --help                Show this help message

Exactly one of --width, --height, or --percent must be provided.

Supported formats: jpg, jpeg, png, webp, tiff, gif, bmp

Examples:
  $(basename "$0") --width 1200 photo.jpg
  $(basename "$0") --height 800 photo.jpg banner.png
  $(basename "$0") --percent 50 large-image.png
  $(basename "$0") -W 800 -o /tmp/out *.jpg
EOF
}

# ─── Error Trap ──────────────────────────────────────────────────────────────
trap 'log_error "Unexpected error at line $LINENO — script aborted."' ERR

# ─── Argument Parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -W|--width)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a pixel value." >&2; exit 1; }
            RESIZE_MODE="width"; RESIZE_VALUE="$2"; shift 2 ;;
        -H|--height)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a pixel value." >&2; exit 1; }
            RESIZE_MODE="height"; RESIZE_VALUE="$2"; shift 2 ;;
        -p|--percent)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a percentage value." >&2; exit 1; }
            RESIZE_MODE="percent"; RESIZE_VALUE="$2"; shift 2 ;;
        -o|--output)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a directory argument." >&2; exit 1; }
            OUTPUT_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1 ;;
        *)
            IMG_FILES+=("$1"); shift ;;
    esac
done

# ─── Validation ──────────────────────────────────────────────────────────────
if [[ ${#IMG_FILES[@]} -eq 0 ]]; then
    echo "Error: No image files specified." >&2
    usage >&2
    exit 1
fi

if [[ -z "$RESIZE_MODE" ]]; then
    echo "Error: Specify one of --width, --height, or --percent." >&2
    usage >&2
    exit 1
fi

if ! [[ "$RESIZE_VALUE" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$RESIZE_VALUE <= 0" | bc -l) )); then
    log_error "--${RESIZE_MODE} must be a positive number (got: $RESIZE_VALUE)"
    exit 1
fi

SUPPORTED_EXTS="jpg jpeg png webp tiff gif bmp"
for img in "${IMG_FILES[@]}"; do
    if [[ ! -f "$img" ]]; then
        log_error "File not found: $img"
        exit 1
    fi
    ext="${img##*.}"
    if ! echo "$SUPPORTED_EXTS" | grep -qiw "$ext"; then
        log_error "Unsupported file type '.${ext}': $img"
        log_error "Supported formats: $SUPPORTED_EXTS"
        exit 1
    fi
done

# ─── Dependency Check ────────────────────────────────────────────────────────
DEPS_OK=true
check_dep convert imagemagick
check_dep identify imagemagick
[[ "$DEPS_OK" == true ]] || exit 1

# ─── Run Directory Setup ─────────────────────────────────────────────────────
if [[ -n "$OUTPUT_OVERRIDE" ]]; then
    RUN_DIR="${OUTPUT_OVERRIDE}/$(date '+%Y-%m-%d_%H-%M-%S')_$$"
    mkdir -p "$RUN_DIR"
else
    RUN_DIR="$(make_run_dir "$SCRIPT_DIR")"
fi

# ─── Log Run Header ──────────────────────────────────────────────────────────
{
    echo ""
    echo "════════════════════════════════════════════════════"
    echo " IMGRESIZE run started : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Input files           : ${IMG_FILES[*]}"
    echo " Output directory      : $RUN_DIR"
    echo " Resize mode           : $RESIZE_MODE = $RESIZE_VALUE"
    echo "════════════════════════════════════════════════════"
} >> "$LOG_FILE"

# ─── Build ImageMagick Resize Spec ───────────────────────────────────────────
case "$RESIZE_MODE" in
    width)   RESIZE_SPEC="${RESIZE_VALUE}x" ;;
    height)  RESIZE_SPEC="x${RESIZE_VALUE}" ;;
    percent) RESIZE_SPEC="${RESIZE_VALUE}%" ;;
esac

# ─── Processing ──────────────────────────────────────────────────────────────
TOTAL_FILES=0

for img in "${IMG_FILES[@]}"; do
    img_abs="$(realpath "$img")"
    basename_orig="$(basename "$img")"
    basename_noext="${basename_orig%.*}"
    ext="${basename_orig##*.}"

    log_info "Processing: $basename_orig"
    log_detail "Full path: $img_abs | Resize: $RESIZE_MODE=$RESIZE_VALUE"

    # Temporary output path — rename once we know the actual dimensions
    tmp_out="$RUN_DIR/${basename_noext}_resized_tmp.${ext}"

    convert "$img_abs" -resize "$RESIZE_SPEC" "$tmp_out"

    # Get actual output dimensions and rename with them
    dims="$(identify -format "%wx%h" "$tmp_out")"
    final_out="$RUN_DIR/${basename_noext}_resized_${dims}.${ext}"
    mv "$tmp_out" "$final_out"

    log_info "  Done: $(basename "$final_out")"
    log_detail "  → $(basename "$final_out")"

    TOTAL_FILES=$(( TOTAL_FILES + 1 ))
done

# ─── Summary ─────────────────────────────────────────────────────────────────
log_info "Complete: $TOTAL_FILES image(s) resized"
echo "" >> "$LOG_FILE"
print_tree "$RUN_DIR"
