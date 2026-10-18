#!/usr/bin/env bash
# Locks the LibreOffice conversion contract in tool/verify_visual_parity.sh.
#
# A missing, empty, or stale PDF must fail the script. A non-zero soffice
# exit that still wrote a new non-empty PDF (the javaldx warning seen in CI)
# must not be treated as a failed conversion, and must not skip the compare.
# Success of that path is not a fake visual pass: the mocks below make the
# rendered pages match, so RMSE is really zero. A conversion that produces
# nothing must not print the acceptance line.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tool/verify_visual_parity.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$TMP/bin" "$TMP/art"
cat >"$TMP/bin/pdftoppm" <<'EOF'
#!/bin/sh
if [ "$1" = "-v" ]; then echo "pdftoppm mock"; exit 0; fi
prefix=""
prev=""
for arg in "$@"; do
  prefix="$arg"
  prev="$arg"
done
printf 'png' >"${prefix}-1.png"
exit 0
EOF
cat >"$TMP/bin/pdftocairo" <<'EOF'
#!/bin/sh
prefix=""
for arg in "$@"; do prefix="$arg"; done
printf 'png' >"${prefix}-1.png"
exit 0
EOF
cat >"$TMP/bin/compare" <<'EOF'
#!/bin/sh
echo "0 (0)"
exit 0
EOF
# A real blank PNG. The vector content gate reads pixels; the text "png" is
# not a page, and a decode error must not look like a conversion failure.
BLANK_PNG="$(python3 - <<'PY'
import base64, struct, zlib
def chunk(tag, payload):
    return (struct.pack('>I', len(payload)) + tag + payload
            + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff))
raw = b''.join(b'\x00' + b'\xff' * 8 for _ in range(8))
ihdr = struct.pack('>IIBBBBB', 8, 8, 8, 0, 0, 0, 0)
png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
       + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
print(base64.b64encode(png).decode())
PY
)"
cat >"$TMP/bin/convert" <<EOF
#!/bin/sh
fmt=""
prev=""
out=""
for arg in "\$@"; do
  if [ "\$prev" = "-format" ]; then fmt=1; fi
  prev="\$arg"
  out="\$arg"
done
if [ "\$fmt" = 1 ]; then
  echo "794 1123"
  exit 0
fi
printf '%s' '$BLANK_PNG' | base64 -d >"\$out"
exit 0
EOF
cat >"$TMP/bin/unzip" <<'EOF'
#!/bin/sh
if [ "$1" = "-Z1" ]; then
  echo "word/media/image1.png"
  exit 0
fi
cat "$PREVIEW_PNG"
exit 0
EOF
cat >"$TMP/bin/soffice" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then echo "LibreOffice mock"; exit 0; fi
outdir=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--outdir" ]; then outdir="$arg"; fi
  prev="$arg"
done
mode="${SOFFICE_MODE:-fail}"
case "$mode" in
  fail)
    echo "Error: conversion failed"
    exit 1
    ;;
  empty)
    : >"$outdir/exact.pdf"
    echo "Error: empty output"
    exit 1
    ;;
  stale)
    # Refuse to write. A pre-seeded file, if the script failed to delete it,
    # must not be accepted.
    echo "Error: source could not be loaded"
    exit 1
    ;;
  javaldx)
    printf '%%PDF-1.4 mock\n' >"$outdir/exact.pdf"
    echo "Warning: failed to launch javaldx - java may not function correctly"
    exit 1
    ;;
  old)
    # Writes a file, then backdates it, so a converter that reuses an older
    # document cannot pass the mtime check.
    printf 'STALE' >"$outdir/exact.pdf"
    touch -d '2000-01-01 00:00:00' "$outdir/exact.pdf"
    echo "Error: reused an older document"
    exit 1
    ;;
  *)
    echo "unknown mode $mode" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$TMP/bin/"*

python3 - "$TMP/art/manifest.json" <<'PY'
import json, sys
json.dump({"pageCount": 1, "widthPx": 794, "heightPx": 1123}, open(sys.argv[1], "w"))
PY
printf 'preview-bytes' >"$TMP/art/preview_page_1.png"
printf '%%PDF' >"$TMP/art/vector.pdf"
printf '%%PDF' >"$TMP/art/exact.pdf"
printf 'docx' >"$TMP/art/exact.docx"

export PATH="$TMP/bin:$PATH"
export PREVIEW_PNG="$TMP/art/preview_page_1.png"

run() {
  local mode="$1"
  local art="$TMP/case-$mode"
  rm -rf "$art"
  mkdir -p "$art/rendered/exact_docx_pdf"
  cp "$TMP/art/manifest.json" "$TMP/art/preview_page_1.png" \
    "$TMP/art/vector.pdf" "$TMP/art/exact.pdf" "$TMP/art/exact.docx" "$art/"
  # A stale PDF from a previous run. The script must delete it before converting.
  printf 'STALE' >"$art/rendered/exact_docx_pdf/exact.pdf"
  touch -d '2000-01-01 00:00:00' "$art/rendered/exact_docx_pdf/exact.pdf"
  SOFFICE_MODE="$mode" bash "$SCRIPT" "$art" >"$TMP/out-$mode.txt" 2>&1
}

# 1. No output file: fail, and do not claim the visual gate passed.
set +e
run fail
status=$?
set -e
[ "$status" -ne 0 ] || fail "missing PDF exited 0"
grep -q 'تعذّر إنتاج ملف غير فارغ' "$TMP/case-fail/report.txt" \
  || fail "missing PDF did not record a conversion error"
if grep -q 'الطابقة البصرية مقبولة' "$TMP/case-fail/report.txt"; then
  fail "missing PDF printed an acceptance line"
fi
if grep -q 'STALE' "$TMP/case-fail/rendered/exact_docx_pdf/exact.pdf" 2>/dev/null; then
  fail "stale PDF survived a failed conversion"
fi

# 2. Empty file: fail. An empty file is not a converted document.
set +e
run empty
status=$?
set -e
[ "$status" -ne 0 ] || fail "empty PDF exited 0"
grep -q 'تعذّر إنتاج ملف غير فارغ' "$TMP/case-empty/report.txt" \
  || fail "empty PDF was accepted"
if grep -q 'الطابقة البصرية مقبولة' "$TMP/case-empty/report.txt"; then
  fail "empty PDF printed an acceptance line"
fi

# 3. A converter that writes and then backdates the file is still a stale file.
set +e
run old
status=$?
set -e
[ "$status" -ne 0 ] || fail "backdated PDF exited 0"
grep -q 'أقدم من بدء التحويل' "$TMP/case-old/report.txt" \
  || fail "backdated PDF was not rejected"
if grep -q 'الطابقة البصرية مقبولة' "$TMP/case-old/report.txt"; then
  fail "backdated PDF printed an acceptance line"
fi

# 4. javaldx: non-zero exit, new non-empty PDF, pages match. The conversion
# warning must not fail the script by itself, and the compare must have run.
set +e
run javaldx
status=$?
set -e
[ "$status" -eq 0 ] || fail "javaldx with a new PDF exited $status: $(cat "$TMP/out-javaldx.txt")"
grep -q 'exit=1' "$TMP/case-javaldx/report.txt" \
  || fail "javaldx exit code was not recorded"
grep -q 'الطابقة البصرية مقبولة' "$TMP/case-javaldx/report.txt" \
  || fail "matching pages were not accepted"
grep -q 'STALE' "$TMP/case-javaldx/rendered/exact_docx_pdf/exact.pdf" \
  && fail "javaldx path compared the stale PDF" || true
echo "verify_visual_parity conversion contract: ok"
