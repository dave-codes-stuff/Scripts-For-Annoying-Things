#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/PDF2WEBP.log"

source "$SCRIPT_DIR/../lib/img-manip-lib.sh"

# ─── Defaults ────────────────────────────────────────────────────────────────
OUTPUT_OVERRIDE=""
QUALITY=90
QUALITY_SET=false
LOSSLESS=false
DPI=150
OUTPUT_TYPE="separate"
PDF_FILES=()

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] file1.pdf [file2.pdf ...]

Convert PDF files to high-quality WebP images.
Output is written to a timestamped subdirectory (configured in img-manip.config).

Options:
  -o, --output <dir>        Override the base output directory
  -q, --quality <1-100>     WebP lossy quality (default: 90)
                              Ignored if --lossless is set.
  -L, --lossless            Encode WebP losslessly (pixel-perfect, larger files)
  -r, --dpi <number>        Rasterization DPI (default: 150)
                              150 = good for web/screen display
                              300 = print-quality detail, ideal for zooming
  -t, --outputtype <mode>   How to handle multi-page PDFs (default: separate)
                              separate  One WebP file per page
                                        e.g. document_p001.webp, document_p002.webp
                              combined  All pages merged into a single tall WebP
                                        e.g. document.webp
                              first     First page only
                                        e.g. document.webp
  -h, --help                Show this help message

Examples:
  $(basename "$0") brochure.pdf
  $(basename "$0") --dpi 300 --lossless brochure.pdf
  $(basename "$0") --outputtype combined brochure.pdf
  $(basename "$0") -t first -q 95 doc1.pdf doc2.pdf
EOF
}

# ─── Error Trap ──────────────────────────────────────────────────────────────
trap 'log_error "Unexpected error at line $LINENO — script aborted."' ERR

# ─── Argument Parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a directory argument." >&2; exit 1; }
            OUTPUT_OVERRIDE="$2"; shift 2 ;;
        -q|--quality)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a number argument." >&2; exit 1; }
            QUALITY="$2"; QUALITY_SET=true; shift 2 ;;
        -L|--lossless)
            LOSSLESS=true; shift ;;
        -r|--dpi)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a number argument." >&2; exit 1; }
            DPI="$2"; shift 2 ;;
        -t|--outputtype)
            [[ $# -lt 2 ]] && { echo "Error: $1 requires a mode argument." >&2; exit 1; }
            OUTPUT_TYPE="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1 ;;
        *)
            PDF_FILES+=("$1"); shift ;;
    esac
done

# ─── Validation ──────────────────────────────────────────────────────────────
if [[ ${#PDF_FILES[@]} -eq 0 ]]; then
    echo "Error: No PDF files specified." >&2
    usage >&2
    exit 1
fi

if [[ "$LOSSLESS" == true && "$QUALITY_SET" == true ]]; then
    log_warn "--lossless is set; --quality value ($QUALITY) will be ignored"
fi

if ! [[ "$QUALITY" =~ ^[0-9]+$ ]] || (( QUALITY < 1 || QUALITY > 100 )); then
    log_error "--quality must be a number between 1 and 100 (got: $QUALITY)"
    exit 1
fi

if ! [[ "$DPI" =~ ^[0-9]+$ ]] || (( DPI < 1 )); then
    log_error "--dpi must be a positive integer (got: $DPI)"
    exit 1
fi

case "$OUTPUT_TYPE" in
    separate|combined|first) ;;
    *)
        log_error "--outputtype must be one of: separate, combined, first (got: $OUTPUT_TYPE)"
        exit 1 ;;
esac

for pdf in "${PDF_FILES[@]}"; do
    if [[ ! -f "$pdf" ]]; then
        log_error "File not found: $pdf"
        exit 1
    fi
    local_ext="${pdf##*.}"
    if [[ "${local_ext,,}" != "pdf" ]]; then
        log_error "File does not appear to be a PDF: $pdf"
        exit 1
    fi
done

# ─── Dependency Check ────────────────────────────────────────────────────────
DEPS_OK=true
check_dep pdftoppm poppler-utils
check_dep cwebp webp
check_dep convert imagemagick
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
    echo " PDF2WEBP run started : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Input files          : ${PDF_FILES[*]}"
    echo " Output directory     : $RUN_DIR"
    echo " Output type          : $OUTPUT_TYPE"
    echo " DPI                  : $DPI"
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

# ─── Processing ──────────────────────────────────────────────────────────────
TOTAL_PDFS=0
TOTAL_WEBPS=0

for pdf in "${PDF_FILES[@]}"; do
    pdf_abs="$(realpath "$pdf")"
    basename_orig="$(basename "$pdf")"
    basename_noext="${basename_orig%.*}"

    log_info "Processing: $basename_orig"
    log_detail "Full path: $pdf_abs | Type: $OUTPUT_TYPE | DPI: $DPI"

    # Rasterize all pages to PNG in temp directory
    pdftoppm -png -r "$DPI" "$pdf_abs" "$WORK_DIR/page"

    # Collect page PNGs — nullglob prevents literal expansion on no match
    shopt -s nullglob
    pages=("$WORK_DIR"/page-*.png)
    shopt -u nullglob

    if [[ ${#pages[@]} -eq 0 ]]; then
        log_error "No pages produced from: $pdf"
        exit 1
    fi

    # Natural sort so page-9 comes before page-10
    mapfile -t pages < <(printf '%s\n' "${pages[@]}" | sort -V)

    page_count=${#pages[@]}
    log_detail "Pages found: $page_count"

    # Zero-pad width: at least 3 digits (001, 002...), more if needed
    pad=$(( ${#page_count} > 3 ? ${#page_count} : 3 ))

    webp_count=0

    case "$OUTPUT_TYPE" in
        separate)
            i=0
            for page in "${pages[@]}"; do
                i=$(( i + 1 ))
                page_num="$(printf "%0${pad}d" "$i")"
                out="$RUN_DIR/${basename_noext}_p${page_num}.webp"
                cwebp "${CWEBP_OPTS[@]}" "$page" -o "$out" -quiet
                log_detail "  → $(basename "$out")"
                webp_count=$(( webp_count + 1 ))
            done
            ;;
        first)
            out="$RUN_DIR/${basename_noext}.webp"
            cwebp "${CWEBP_OPTS[@]}" "${pages[0]}" -o "$out" -quiet
            log_detail "  → $(basename "$out")"
            webp_count=1
            ;;
        combined)
            combined_png="$WORK_DIR/combined.png"
            convert "${pages[@]}" -append "$combined_png"
            out="$RUN_DIR/${basename_noext}.webp"
            cwebp "${CWEBP_OPTS[@]}" "$combined_png" -o "$out" -quiet
            log_detail "  → $(basename "$out")"
            webp_count=1
            ;;
    esac

    log_info "  Done: $webp_count WebP file(s) from '$basename_orig' ($page_count page(s))"
    log_detail "---"

    TOTAL_PDFS=$(( TOTAL_PDFS + 1 ))
    TOTAL_WEBPS=$(( TOTAL_WEBPS + webp_count ))

    # Clear temp files before processing the next PDF
    rm -f "$WORK_DIR"/page-*.png "$WORK_DIR/combined.png" 2>/dev/null || true
done

# ─── Summary ─────────────────────────────────────────────────────────────────
log_info "Complete: $TOTAL_PDFS PDF(s) → $TOTAL_WEBPS WebP file(s)"
echo "" >> "$LOG_FILE"
print_tree "$RUN_DIR"
