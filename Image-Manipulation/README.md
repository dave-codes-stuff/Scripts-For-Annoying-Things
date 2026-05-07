# Image Manipulation Toolkit

A collection of bash scripts for converting and processing images on Linux. Each script is self-contained, reads from a shared config file, and writes output to organized timestamped directories.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Output Organization](#output-organization)
- [Scripts](#scripts)
  - [PDF2WEBP — Convert PDFs to WebP](#pdf2webp--convert-pdfs-to-webp)
  - [IMG2WEBP — Convert Images to WebP](#img2webp--convert-images-to-webp)
  - [IMGRESIZE — Resize Images](#imgresize--resize-images)
- [Shared Library](#shared-library)
- [Logging](#logging)
- [Planned Scripts](#planned-scripts)

---

## Directory Structure

```
Image-Manipulation/
├── img-manip.config          # Shared configuration
├── lib/
│   └── img-manip-lib.sh      # Shared functions sourced by all scripts
├── PDF2WEBP/
│   ├── PDF2WEBP.sh
│   └── PDF2WEBP.log          # Created on first run
├── IMG2WEBP/
│   ├── IMG2WEBP.sh
│   └── IMG2WEBP.log          # Created on first run
├── IMGRESIZE/
│   ├── IMGRESIZE.sh
│   └── IMGRESIZE.log         # Created on first run
├── TestFiles/                # Test inputs (not committed to git)
└── Output/                   # All script output (not committed to git)
    ├── 2026-05-07_13-15-29_1234/
    └── 2026-05-07_14-20-00_5678/
```

---

## Prerequisites

Install the required system tools before using these scripts.

```bash
# PDF to WebP conversion
sudo apt install poppler-utils webp

# Image conversion and resizing
sudo apt install imagemagick webp
```

| Tool | Package | Used By |
|------|---------|---------|
| `pdftoppm` | `poppler-utils` | PDF2WEBP |
| `cwebp` | `webp` | PDF2WEBP, IMG2WEBP |
| `convert` | `imagemagick` | PDF2WEBP, IMG2WEBP, IMGRESIZE |
| `identify` | `imagemagick` | IMGRESIZE |

Each script checks for its required tools at startup and prints a clear install instruction if anything is missing.

---

## Configuration

All scripts read from `img-manip.config`, a plain text file at the root of this directory.

```ini
# img-manip.config
OUTPUT_DIR=./Output
```

**`OUTPUT_DIR`** — The base directory where all script output is written. The path is resolved relative to the config file's own location, so it works correctly regardless of where you call a script from.

To change the output location, edit this value. Absolute paths are also supported:

```ini
OUTPUT_DIR=/home/dave/Pictures/Converted
```

Scripts automatically find the config by walking up the directory tree from their own location. If the config is not found, they fall back to `./Output` and print a warning.

---

## Output Organization

Every script run creates a uniquely named subdirectory inside `OUTPUT_DIR`:

```
Output/
├── 2026-05-07_13-15-29_12345/    ← date, time, process ID
│   ├── brochure_p001.webp
│   └── brochure_p002.webp
└── 2026-05-07_14-20-00_12346/
    └── photo_resized_800x533.jpg
```

The process ID at the end of the folder name ensures two scripts running at the same second never collide. At the end of every run, the terminal displays:

```
Output Directory: /path/to/Output/2026-05-07_13-15-29_12345

2026-05-07_13-15-29_12345/
├── brochure_p001.webp
└── brochure_p002.webp
```

---

## Scripts

---

### PDF2WEBP — Convert PDFs to WebP

Converts PDF files to high-quality WebP images. Each page can be saved as a separate file, all pages merged into a single image, or just the first page extracted.

**Rasterization pipeline:** `pdftoppm` renders each PDF page to PNG at the specified DPI, then `cwebp` encodes each PNG to WebP.

#### Usage

```bash
./PDF2WEBP/PDF2WEBP.sh [OPTIONS] file1.pdf [file2.pdf ...]
```

#### Options

| Short | Long | Default | Description |
|-------|------|---------|-------------|
| `-o` | `--output <dir>` | from config | Override the base output directory |
| `-q` | `--quality <1-100>` | `90` | WebP lossy quality |
| `-L` | `--lossless` | off | Pixel-perfect lossless encoding |
| `-r` | `--dpi <number>` | `150` | Rasterization resolution |
| `-t` | `--outputtype <mode>` | `separate` | Page output mode (see below) |
| `-h` | `--help` | — | Show help |

#### DPI Guide

| DPI | Best For |
|-----|----------|
| `150` | Web display, standard screen viewing (default) |
| `300` | Print-quality detail, zooming in on fine text |

#### Output Type Modes

| Mode | Output | Description |
|------|--------|-------------|
| `separate` | `doc_p001.webp`, `doc_p002.webp`, … | One WebP file per page |
| `combined` | `doc.webp` | All pages stacked vertically into one image |
| `first` | `doc.webp` | First page only |

#### Quality Note

When both `--lossless` and `--quality` are specified, `--lossless` takes priority and a warning is printed.

#### Examples

```bash
# Basic conversion — 2-page PDF becomes 2 WebP files
./PDF2WEBP/PDF2WEBP.sh brochure.pdf

# High-resolution lossless conversion
./PDF2WEBP/PDF2WEBP.sh --dpi 300 --lossless brochure.pdf

# Single combined image of all pages
./PDF2WEBP/PDF2WEBP.sh --outputtype combined brochure.pdf

# First page only, higher quality
./PDF2WEBP/PDF2WEBP.sh --outputtype first --quality 95 brochure.pdf

# Multiple PDFs in one run
./PDF2WEBP/PDF2WEBP.sh doc1.pdf doc2.pdf doc3.pdf
```

#### Log File

`PDF2WEBP/PDF2WEBP.log` — records every run with timestamp, settings, pages converted, and output file names.

---

### IMG2WEBP — Convert Images to WebP

Converts a wide range of image formats to WebP. Accepts individual files, wildcards, and directories.

**Conversion pipeline:** Formats that `cwebp` accepts natively are encoded directly. All other formats are first converted to a lossless PNG intermediate by ImageMagick, then encoded by `cwebp`. This two-step approach produces better WebP quality than letting ImageMagick encode WebP directly.

#### Usage

```bash
./IMG2WEBP/IMG2WEBP.sh [OPTIONS] file1.jpg [file2.png ...] [directory/]
```

#### Supported Formats

| Type | Formats |
|------|---------|
| **Direct** (cwebp native) | `jpg`, `jpeg`, `png`, `tiff`, `tif` |
| **Indirect** (via PNG) | `bmp`, `svg`, `avif`, `ico`, `psd`, `pnm`, `ppm`, `pgm`, `pbm` |
| **Skipped** | `gif` — use the GIF2WEBP script (planned) |
| **Skipped** | `webp` — already WebP, nothing to do |

Skipped files do not abort the run — the script processes all other files and reports what was skipped in the summary.

#### Options

| Short | Long | Default | Description |
|-------|------|---------|-------------|
| `-q` | `--quality <1-100>` | `90` | WebP lossy quality |
| `-L` | `--lossless` | off | Pixel-perfect lossless encoding |
| `-r` | `--dpi <number>` | `150` | DPI for SVG rasterization only |
| `-o` | `--output <dir>` | from config | Override the base output directory |
| `-h` | `--help` | — | Show help |

#### Output Naming

The output file takes the same base name with a `.webp` extension:
`photo.jpg` → `photo.webp`

If two input files from different directories share the same name, the second is automatically renamed to avoid overwriting the first:
`photo.webp`, `photo_2.webp`, `photo_3.webp`, …

#### Examples

```bash
# Single file
./IMG2WEBP/IMG2WEBP.sh photo.jpg

# Multiple files
./IMG2WEBP/IMG2WEBP.sh photo.jpg graphic.png logo.svg

# Wildcard
./IMG2WEBP/IMG2WEBP.sh *.jpg

# Entire directory (top level only)
./IMG2WEBP/IMG2WEBP.sh ./photos/

# Lossless PNG conversion
./IMG2WEBP/IMG2WEBP.sh --lossless graphic.png

# Higher quality
./IMG2WEBP/IMG2WEBP.sh --quality 95 photo.jpg
```

#### Log File

`IMG2WEBP/IMG2WEBP.log` — records every run with timestamp, files processed, conversion path (direct or indirect), and output file names.

---

### IMGRESIZE — Resize Images

Resizes images by width, height, or percentage. Aspect ratio is always preserved automatically.

#### Usage

```bash
./IMGRESIZE/IMGRESIZE.sh [OPTIONS] file1.jpg [file2.jpg ...]
```

Exactly one of `--width`, `--height`, or `--percent` must be provided.

#### Options

| Short | Long | Default | Description |
|-------|------|---------|-------------|
| `-W` | `--width <px>` | — | Target width in pixels; height scales proportionally |
| `-H` | `--height <px>` | — | Target height in pixels; width scales proportionally |
| `-p` | `--percent <n>` | — | Scale by percentage (e.g. `50` = half size) |
| `-o` | `--output <dir>` | from config | Override the base output directory |
| `-h` | `--help` | — | Show help |

#### Supported Formats

Any format ImageMagick handles: `jpg`, `jpeg`, `png`, `webp`, `tiff`, `gif`, `bmp`, and more.

#### Output Naming

The actual output dimensions are embedded in the filename:
`photo.jpg` → `photo_resized_800x533.jpg`

This makes it easy to identify resized files and confirm the correct dimensions were applied.

#### Examples

```bash
# Resize to 1200px wide (height auto-calculated)
./IMGRESIZE/IMGRESIZE.sh --width 1200 photo.jpg

# Resize to 800px tall
./IMGRESIZE/IMGRESIZE.sh --height 800 banner.png

# Scale down to 50%
./IMGRESIZE/IMGRESIZE.sh --percent 50 large-image.png

# Resize multiple files at once
./IMGRESIZE/IMGRESIZE.sh --width 800 photo1.jpg photo2.jpg photo3.jpg

# Wildcard
./IMGRESIZE/IMGRESIZE.sh --width 1200 *.jpg
```

#### Log File

`IMGRESIZE/IMGRESIZE.log` — records every run with timestamp, resize mode and value, and output file names with dimensions.

---

## Shared Library

`lib/img-manip-lib.sh` is sourced by every script and provides the shared functions that keep the toolkit consistent.

| Function | Description |
|----------|-------------|
| `find_config_value <key> <dir>` | Locates `img-manip.config` by walking up the directory tree and returns the value for the given key |
| `make_run_dir <script_dir>` | Reads `OUTPUT_DIR` from config and creates a timestamped run directory inside it |
| `print_tree <dir>` | Prints a formatted tree view of the output directory to the terminal |
| `log_info <message>` | Prints an `[INFO]` message to terminal and log file |
| `log_warn <message>` | Prints a `[WARN]` message to terminal and log file |
| `log_error <message>` | Prints an `[ERROR]` message to stderr and log file |
| `log_detail <message>` | Writes a `[DETAIL]` message to the log file only (not terminal) |
| `check_dep <tool> <package>` | Checks a tool is installed; sets `DEPS_OK=false` with an install hint if not |

This library is not executable and should not be run directly.

---

## Logging

Each script maintains its own log file in its own directory (e.g. `PDF2WEBP/PDF2WEBP.log`). Logs are appended — they accumulate across runs and are never overwritten.

Each run writes a header block followed by per-file detail entries:

```
════════════════════════════════════════════════════
 PDF2WEBP run started : 2026-05-07 13:15:29
 Input files          : TestFiles/brochure.pdf
 Output directory     : /path/to/Output/2026-05-07_13-15-29_12345
 Output type          : separate
 DPI                  : 150
 Encoding             : lossy (quality 90)
════════════════════════════════════════════════════
[2026-05-07 13:15:29] [INFO ] Processing: brochure.pdf
[2026-05-07 13:15:36] [DETAIL] Pages found: 2
[2026-05-07 13:15:37] [DETAIL]   → brochure_p001.webp
[2026-05-07 13:15:38] [DETAIL]   → brochure_p002.webp
[2026-05-07 13:15:38] [INFO ] Done: 2 WebP file(s) from 'brochure.pdf' (2 page(s))
[2026-05-07 13:15:38] [INFO ] Complete: 1 PDF(s) → 2 WebP file(s)
```

Log files are excluded from git via `.gitignore`.

---

## Planned Scripts

| Script | Description |
|--------|-------------|
| `GIF2WEBP` | Convert animated and static GIF files to WebP, preserving animation |
