#!/usr/bin/env bash
# يعقد فحص أداة التحقق البصري (tool/verify_visual_parity.sh) بعد إزالة مسار Exact/Word:
# يبقى فقط المسار المتجهي (vector PDF)؛ لا تحويل DOCX عبر LibreOffice بعد الآن.
# سيناريوهات:
# 1. ملفات صالحة (manifest + vector.pdf + لقطة معاينة) → خروج 0 وسطر القبول في التقرير.
# 2. manifest مفقود → خروج 2 مع خطأ صريح ولا يُدعى التحويل على الإطلاق.
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
# صورة PNG فارغة صالحة (بكسل 8×8 متبادل الأبيض والأسود) ताकत المقارنة لا تفكّ تشفيرها.
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
echo "LibreOffice mock: no conversion performed (vector track only)" >&2
exit 0
EOF
chmod +x "$TMP/bin/"*

python3 - "$TMP/art/manifest.json" <<'PY'
import json, sys
json.dump({"pageCount": 1, "widthPx": 794, "heightPx": 1123}, open(sys.argv[1], "w"))
PY
printf 'preview-bytes' >"$TMP/art/preview_page_1.png"
printf '%%PDF' >"$TMP/art/vector.pdf"

export PATH="$TMP/bin:$PATH"

# 1. ملفات صالحة: المسار المتجهي ينجح ويُnisب قبول الطابقة.
set +e
bash "$SCRIPT" "$TMP/art" >"$TMP/out-valid.txt" 2>&1
status=$?
set -e
[ "$status" -eq 0 ] || fail "valid vector artifacts exited $status: $(cat "$TMP/out-valid.txt")"
grep -q 'الطابقة البصرية مقبولة' "$TMP/art/report.txt" \
  || fail "valid run did not print the acceptance line"
grep -q 'تحويل' "$TMP/art/report.txt" && fail "valid run mentioned conversion though Word track was removed"

# 2. manifest مفقود: رفض فوري دون touching التحويل.
rm -f "$TMP/art/manifest.json"
set +e
bash "$SCRIPT" "$TMP/art" >"$TMP/out-missing.txt" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "missing manifest exited 0"
grep -q 'manifest.json مفقود' "$TMP/out-missing.txt" \
  || fail "missing manifest did not report the missing manifest"

echo "verify_visual_parity vector contract: ok"
