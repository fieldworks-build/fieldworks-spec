#!/usr/bin/env bash
# Render spec/*.md to a PDF: pandoc -> Typst -> PDF.
#
#   scripts/build-pdf.sh [VERSION]      e.g. scripts/build-pdf.sh 0.3
#
# Needs only uv. pandoc and the Typst compiler come from pinned Python
# packages (pypandoc_binary bundles pandoc; typst bundles the compiler), and
# the fonts live in scripts/fonts, so local builds and CI render identically.
# The look lives in scripts/fieldworks.typ.
# Output: build/FieldWorks_Framework_Specification_v<VERSION>.pdf
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-dev}"
DATE="$(date -u +'%B %Y')"
OUT="build/FieldWorks_Framework_Specification_v${VERSION}.pdf"
mkdir -p build

uv run --quiet --no-project \
  --with pypandoc_binary==1.17 --with typst==0.15.2 \
  python -I - "$VERSION" "$DATE" "$OUT" <<'PY'
import glob, subprocess, sys
from pathlib import Path

import pypandoc
import typst

version, date, out = sys.argv[1:]
typ = Path("spec/.build.typ")  # next to the Markdown so images/… resolve
subprocess.run(
    [
        pypandoc.get_pandoc_path(),
        *sorted(glob.glob("spec/[0-9][0-9]-*.md")),
        "--metadata-file", "spec/metadata.yaml",
        "--metadata", f"subtitle=Version {version}",
        "--metadata", f"date={date}",
        "--resource-path", "spec",
        "--lua-filter", "scripts/table-widths.lua",
        "--variable", "template=/scripts/fieldworks.typ",
        "--standalone", "--to", "typst",
        "--output", str(typ),
    ],
    check=True,
)
try:
    typst.compile(
        str(typ),
        output=out,
        root=".",
        font_paths=["scripts/fonts"],
        ignore_system_fonts=True,
    )
finally:
    typ.unlink(missing_ok=True)
print(out)
PY
