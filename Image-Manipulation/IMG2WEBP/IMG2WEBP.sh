#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/IMG2WEBP.log"

source "$SCRIPT_DIR/../lib/img-manip-lib.sh"

# ─── Format Lists ────────────────────────────────────────────────────────────
# cwebp accepts these natively — no intermediate file needed
DIRECT_EXTS=(jpg jpeg png tiff tif)

# ImageMagick converts these to lossless PNG, then cwebp encodes
INDIRECT_EXTS=(bmp svg avif ico psd pnm ppm pgm pbm)

# ─── Defaults ────────────────────────────────────────────────────────────────
QUALITY=90
QUALITY_SET=false
LOSSLESS=false
DPI=150
OUTPUT_OVERRIDE=""
RAW_ARGS=()

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] file1.jpg [file2.png ...] [directory/]

Convert images to high-quality WebP format.
Output is written to a timestamped subdirectory (configured in img-manip.config).

Supported formats:
  Direct   : jpg, jpeg, png, tiff, tif
  Indirect : bmp, svg, avif, ico, psd, pnm, ppm, pgm, pbm
  Skipped  : gif (use GIF2WEBP script), webp (already WebP)

Wildcards are supported: IMG2WEBP.sh *.jpg
Directories are supported: IMG2WEBP.sh ./photos/ (scans top level only)

Options:
  -q, --quality <1-100>     WebP lossy quality (default: 90)
                              Ignored if --lossless is set.
  -L, --lossless            Encode WebP losslessly (pixel-perfect, larger files)
  -r, --dpi <number>        DPI for SVG rasterization only (default: 150)
  -o, --output <dir>        Override the base output directory
  -h, --help                Show this help message

Examples:
  $(basename "$0") photo.jpg
  $(basename "$0") --lossless graphic.png logo.svg
  $(basename "$0") --quality 95 ./photos/
  $(basename "$0") *.jpg *.png
EOF
}

# ─── Error Trap ──────────────────────────────────────────────────────────────
trap 'log_error "Unexpected error at line $LINENO — script aborted."' ERR

# ─── Argument Parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quality)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a number." >&2; exit 1; }
            QUALITY="$2"; QUALITY_SET=true; shift 2 ;;
        -L|--lossless)
            LOSSLESS=true; shift ;;
        -r|--dpi)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a number." >&2; exit 1; }
            DPI="$2"; shift 2 ;;
        -o|--output)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a directory." >&2; exit 1; }
            OUTPUT_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1 ;;
        *)
            RAW_ARGS+=("$1"); shift ;;
    esac
done

# ─── Validation ──────────────────────────────────────────────────────────────
if [[ ${#RAW_ARGS[@]} -eq 0 ]]; then
    echo "Error: No input files or directories specified." >&2
    usage >&2
    exit 1
fi

if [[ "$LOSSLESS" == true && "$QUALITY_SET" == true ]]; then
    log_warn "--lossless is set; --quality value ($QUALITY) will be ignored"
fi

if ! [[ "$QUALITY" =~ ^[0-9]+$ ]] || (( QUALITY < 1 || QUALITY > 100 )); then
    log_error "--quality must be between 1 and 100 (got: $QUALITY)"
    exit 1
fi

if ! [[ "$DPI" =~ ^[0-9]+$ ]] || (( DPI < 1 )); then
    log_error "--dpi must be a positive integer (got: $DPI)"
    exit 1
fi

# ─── Dependency Check ────────────────────────────────────────────────────────
DEPS_OK=true
check_dep cwebp webp
check_dep convert imagemagick
[[ "$DEPS_OK" == true ]] || exit 1

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Returns 0 if the first argument matches any subsequent argument
ext_in_list() {
    local target="$1"; shift
    local e
    for e in "$@"; do
        [[ "$target" == "$e" ]] && return 0
    done
    return 1
}


# ─── Collect Files ───────────────────────────────────────────────────────────
ALL_KNOWN_EXTS=("${DIRECT_EXTS[@]}" "${INDIRECT_EXTS[@]}" gif webp)

IMG_FILES=()
for arg in "${RAW_ARGS[@]}"; do
    if [[ -d "$arg" ]]; then
        while IFS= read -r -d '' f; do
            ext="${f##*.}"
            ext="${ext,,}"
            if ext_in_list "$ext" "${ALL_KNOWN_EXTS[@]}"; then
                IMG_FILES+=("$f")
            fi
        done < <(find "$arg" -maxdepth 1 -type f -print0 | sort -z)
    elif [[ -f "$arg" ]]; then
        IMG_FILES+=("$arg")
    else
        log_error "Not found: $arg"
        exit 1
    fi
done

if [[ ${#IMG_FILES[@]} -eq 0 ]]; then
    log_error "No supported image files found in the specified input(s)."
    exit 1
fi

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
    echo " IMG2WEBP run started : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Input args           : ${RAW_ARGS[*]}"
    echo " Files found          : ${#IMG_FILES[@]}"
    echo " Output directory     : $RUN_DIR"
    echo " DPI (SVG)            : $DPI"
    if [[ "$LOSSLESS" == true ]]; then
        echo " Encoding             : lossless"
    else
        echo " Encoding             : lossy (quality $QUALITY)"
    fi
    echo "════════════════════════════════════════════════════"
} >> "$LOG_FILE"

# ─── Temp Directory ──────────────────────────────────────────────────────────
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# ─── Build cwebp Options ─────────────────────────────────────────────────────
if [[ "$LOSSLESS" == true ]]; then
    CWEBP_OPTS=(-lossless)
else
    CWEBP_OPTS=(-q "$QUALITY")
fi

# ─── Processing Loop ─────────────────────────────────────────────────────────
TOTAL_CONVERTED=0
TOTAL_SKIPPED=0

for img in "${IMG_FILES[@]}"; do
    img_abs="$(realpath "$img")"
    basename_orig="$(basename "$img")"
    basename_noext="${basename_orig%.*}"
    ext="${basename_orig##*.}"
    ext="${ext,,}"

    if [[ "$ext" == "gif" ]]; then
        log_info "Skipping $basename_orig — GIF files are handled by the GIF2WEBP script"
        TOTAL_SKIPPED=$(( TOTAL_SKIPPED + 1 ))
        continue
    fi

    if [[ "$ext" == "webp" ]]; then
        log_info "Skipping $basename_orig — already WebP"
        TOTAL_SKIPPED=$(( TOTAL_SKIPPED + 1 ))
        continue
    fi

    log_info "Converting: $basename_orig"

    # Resolve output path, handling collisions when two inputs share a base name
    out_file="$RUN_DIR/${basename_noext}.webp"
    if [[ -f "$out_file" ]]; then
        local_n=2
        while [[ -f "$RUN_DIR/${basename_noext}_${local_n}.webp" ]]; do
            local_n=$(( local_n + 1 ))
        done
        out_file="$RUN_DIR/${basename_noext}_${local_n}.webp"
        log_warn "Name collision — writing as $(basename "$out_file")"
    fi

    if ext_in_list "$ext" "${DIRECT_EXTS[@]}"; then
        log_detail "Full path: $img_abs | Conversion: direct"
        cwebp "${CWEBP_OPTS[@]}" "$img_abs" -o "$out_file" -quiet
    else
        log_detail "Full path: $img_abs | Conversion: indirect (via PNG)"
        tmp_png="$WORK_DIR/intermediate.png"
        if [[ "$ext" == "svg" ]]; then
            convert -density "$DPI" "$img_abs" PNG:"$tmp_png"
        else
            convert "$img_abs" PNG:"$tmp_png"
        fi
        cwebp "${CWEBP_OPTS[@]}" "$tmp_png" -o "$out_file" -quiet
        rm -f "$tmp_png"
    fi

    log_info "  → $(basename "$out_file")"
    log_detail "  Output: $out_file"
    TOTAL_CONVERTED=$(( TOTAL_CONVERTED + 1 ))
done

# ─── Summary ─────────────────────────────────────────────────────────────────
log_info "Complete: $TOTAL_CONVERTED converted, $TOTAL_SKIPPED skipped"
echo "" >> "$LOG_FILE"
print_tree "$RUN_DIR"
