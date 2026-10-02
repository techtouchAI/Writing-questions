#!/usr/bin/env bash
# التحقق البصري الخارجي (Visual Regression): يصيّر مخرجات النمط الدقيق ببرامج
# مستقلة عن التطبيق — poppler لملف PDF، وLibreOffice ثم poppler لملف Word —
# ثم يقارن كل صفحة مصيَّرة بلقطة المعاينة المقابلة بمقياس RMSE.
#
# لماذا خارجياً؟ لأن الادّعاء «الملف مطابق للمعاينة» لا يُثبته إلا تصيير
# الملف بمحرّك آخر: `flutter test` يقارن البايتات، وهذا يقارن **الصورة**.
#
# المدخلات (تنتجها ركيزة الاختبار test/visual/visual_parity_fixture_test.dart):
#   build/visual_parity/manifest.json
#   build/visual_parity/preview_page_N.png
#   build/visual_parity/exact.pdf
#   build/visual_parity/exact.docx
#
# الاستعمال:  tool/verify_visual_parity.sh [مجلد القطع] [سقف PDF] [سقف Word]
set -euo pipefail

ARTIFACTS="${1:-build/visual_parity}"
PDF_THRESHOLD="${2:-0.02}"
DOCX_THRESHOLD="${3:-0.06}"

# أدوات التصيير والمقارنة (تثبّتها مهمة CI).
MISSING=()
for tool in pdftoppm python3; do
  command -v "$tool" >/dev/null 2>&1 || MISSING+=("$tool")
done
if command -v compare >/dev/null 2>&1; then
  COMPARE="compare"
elif command -v magick >/dev/null 2>&1; then
  COMPARE="magick compare"
else
  MISSING+=("imagemagick")
fi
if command -v convert >/dev/null 2>&1; then
  CONVERT="convert"
elif command -v magick >/dev/null 2>&1; then
  CONVERT="magick convert"
else
  MISSING+=("imagemagick-convert")
fi
SOFFICE="$(command -v soffice || command -v libreoffice || true)"
[ -n "$SOFFICE" ] || MISSING+=("libreoffice")

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "::error title=أدوات التحقق البصري::أدوات ناقصة: ${MISSING[*]} — لا يمكن التحقق البصري."
  exit 2
fi

if [ ! -f "$ARTIFACTS/manifest.json" ]; then
  echo "::error title=قطع التحقق البصري::$ARTIFACTS/manifest.json مفقود — شغّل ركيزة الاختبار أولاً."
  exit 2
fi

RENDERED="$ARTIFACTS/rendered"
REPORT="$ARTIFACTS/report.txt"
rm -rf "$RENDERED"
mkdir -p "$RENDERED/pdf" "$RENDERED/docx" "$RENDERED/docx_pdf" "$RENDERED/norm"

# التقرير يُفتح هنا (لا بعد التصيير): لو فشل أمر خارجي يبقى سببه مكتوباً
# وقابلاً للنشر بدل أن يضيع مع رقم الخروج.
{
  echo "التحقق البصري — مقارنة الملفات المصيَّرة بلقطات المعاينة"
  echo "السقوف: PDF ≤ $PDF_THRESHOLD، Word ≤ $DOCX_THRESHOLD"
  echo "الأدوات: $(pdftoppm -v 2>&1 | head -n 1)"
  echo "         $("$SOFFICE" --version 2>&1 | head -n 1)"
  echo
} >"$REPORT"

# ينفّذ أمراً ويسجّل مخرجه ورمزه في التقرير؛ وعند الفشل ينشر سببه كتعليق.
run_tool() { # <وصف> <أمر...>
  local label="$1"
  shift
  local output status=0
  output="$("$@" 2>&1)" || status=$?
  {
    echo "[$label] exit=$status"
    printf '%s\n' "$output"
  } >>"$REPORT"
  if [ "$status" -ne 0 ]; then
    echo "::error title=$label::فشل تنفيذ الأمر (exit $status): $(printf '%s' "$output" | head -c 600 | tr '\n' ' ')"
    return 1
  fi
  return 0
}

# تصيير صفحات PDF: pdftoppm أولاً، ثم pdftocairo (من poppler نفسه) بديلاً
# مكافئاً إن رفض البناء الحالي وسائط pdftoppm.
render_pdf() { # <ملف PDF> <بادئة المخرجات> <وسم>
  local pdf="$1" prefix="$2" label="$3"
  if run_tool "$label (pdftoppm)" pdftoppm -r 96 -png "$pdf" "$prefix"; then
    return 0
  fi
  run_tool "$label (pdftocairo)" pdftocairo -r 96 -png "$pdf" "$prefix"
}

# أبعاد الصفحة وعددها من الـmanifest نفسه (لا أرقام مكرّرة في السكربت).
read -r PAGES WIDTH HEIGHT < <(
  python3 - "$ARTIFACTS/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
print(data['pageCount'], int(data['widthPx']), int(data['heightPx']))
PY
)
# إطار اللوحة (بكسل واحد) يُستثنى من طرفي المقارنة: 2px من كل جهة.
CROP_WIDTH=$((WIDTH - 4))
CROP_HEIGHT=$((HEIGHT - 4))
echo "الصفحات: $PAGES، المقاس المرجعي: ${WIDTH}x${HEIGHT} (المقارنة بعد قصّ 2px)"

# ------------------------------ التصيير ------------------------------

# PDF: poppler يصيّر صفحات الملف بدقة 96dpi (بكسل لوحة المعاينة نفسه).
if ! render_pdf "$ARTIFACTS/exact.pdf" "$RENDERED/pdf/page" "تصيير PDF"; then
  echo "::error title=تصيير PDF::تعذّر تصيير exact.pdf بأدوات poppler — انظر $REPORT."
  exit 1
fi

# Word: LibreOffice يحوّل DOCX إلى PDF ثم poppler يصيّره. ملف تعريف
# LibreOffice في /tmp حتى لا يحتاج مجلد المستخدم في بيئة نظيفة.
# ضغط بلا فقد وإيقاف تصغير دقة الصور في تصدير LibreOffice: الفشل الافتراضي
# (JPEG) يُدخل ضجيج ضغط يُقرأ خطأً كفرق تخطيط، والمقارنة تقيس **ملفنا** لا
# إعدادات المُصدِّر الوسيط.
LO_EXPORT_OPTIONS='pdf:writer_pdf_Export:{"UseLosslessCompression":{"type":"boolean","value":"true"},"ReduceImageResolution":{"type":"boolean","value":"false"}}'
soffice_output="$("$SOFFICE" --headless --norestore --nolockcheck \
  -env:UserInstallation="file:///tmp/lo-visual-parity" \
  --convert-to "$LO_EXPORT_OPTIONS" --outdir "$RENDERED/docx_pdf" \
  "$ARTIFACTS/exact.docx" 2>&1)" || true
{
  echo '[تحويل Word (LibreOffice)]'
  printf '%s\n' "$soffice_output"
} >>"$REPORT"
if [ ! -f "$RENDERED/docx_pdf/exact.pdf" ]; then
  echo "::error title=تحويل Word::تعذّر على LibreOffice إنتاج PDF من exact.docx: $(printf '%s' "$soffice_output" | head -c 600 | tr '\n' ' ')"
  exit 1
fi
if ! render_pdf "$RENDERED/docx_pdf/exact.pdf" "$RENDERED/docx/page" "تصيير Word"; then
  echo "::error title=تصيير Word::تعذّر تصيير PDF الناتج من LibreOffice — انظر $REPORT."
  exit 1
fi

# ------------------------------ المقارنة ------------------------------

# RMSE المعياري (0..1) بين صفحتين بالحجم نفسه.
rmse_between() { # <أ> <ب>
  local raw value
  raw="$($COMPARE -metric RMSE "$1" "$2" null: 2>&1 || true)"
  value="$(printf '%s' "$raw" | sed -n 's/.*(\([0-9.]*\)).*/\1/p')"
  if [ -z "$value" ]; then
    value="$(printf '%s' "$raw" | awk '{print $1/65535}')"
  fi
  printf '%s' "$value"
}

failures=0
echo >>"$REPORT"

check_track() { # <وسم> <مجلد التصيير> <سقف>
  local label="$1" dir="$2" threshold="$3"
  local files count index=0 status=0
  files="$(find "$dir" -name '*.png' | sort -V)"
  count="$(printf '%s\n' "$files" | grep -c . || true)"
  if [ "$count" -ne "$PAGES" ]; then
    echo "::error title=عدد الصفحات ($label)::متوقّع $PAGES صفحة، والمصيَّر $count."
    return 1
  fi
  while IFS= read -r rendered; do
    [ -n "$rendered" ] || continue
    index=$((index + 1))
    local preview="$ARTIFACTS/preview_page_$index.png"
    if [ ! -f "$preview" ]; then
      echo "::error title=لقطة مفقودة::$preview غير موجودة."
      status=1
      continue
    fi
    # (1) مقاس الصفحة المصيَّرة: لا يخرج عن المرجع بأكثر من بكسلين، وإلا
    #     فمقاس الورقة/الهامش في الملف خطأ ولو تطابق المحتوى.
    local size rw rh size_status="OK"
    size="$($CONVERT "$rendered" -format '%w %h' info:)"
    rw="${size% *}"; rh="${size#* }"
    if [ "$((rw - WIDTH))" -gt 2 ] || [ "$((WIDTH - rw))" -gt 2 ] ||
       [ "$((rh - HEIGHT))" -gt 2 ] || [ "$((HEIGHT - rh))" -gt 2 ]; then
      size_status="SIZE-MISMATCH"
      status=1
    fi

    # (2) المقارنة على مقاس واحد (فرق بكسل واحد لا يجوز أن يُسقط الحكم)،
    #     وبعد قصّ إطار اللوحة: لقطة المعاينة تحمل حدوداً زخرفية بكسل واحداً
    #     لا مقابل لها في الورقة المطبوعة، فتُستثنى من **الصورتين** معاً
    #     بالتساوي ولا تُخفى فروق المحتوى (الهامش > 50px فلا يمسّها القصّ).
    local norm="$RENDERED/norm/${label}_$index.png"
    local reference="$RENDERED/norm/${label}_ref_$index.png"
    local crop="${CROP_WIDTH}x${CROP_HEIGHT}+2+2"
    $CONVERT "$rendered" -resize "${WIDTH}x${HEIGHT}!" -crop "$crop" +repage "$norm"
    $CONVERT "$preview" -crop "$crop" +repage "$reference"
    local value verdict="OK"
    value="$(rmse_between "$norm" "$reference")"
    if awk -v v="$value" -v t="$threshold" 'BEGIN { exit !(v > t) }'; then
      verdict="FAIL"
      status=1
    fi
    printf '%-4s صفحة %-2s  المقاس %sx%s (%s)  RMSE %s  (السقف %s)  %s\n' \
      "$label" "$index" "$rw" "$rh" "$size_status" "$value" "$threshold" "$verdict"
    # تشخيص (لا حكم): كم بكسل اختلف فعلاً بسماح 2%؟ وهل ينهار الفرق بتنعيم
    # نصف بكسل؟ فرق واسع ينهار بالتنعيم = ضجيج ضغط/إعادة تحجيم تحت البكسل،
    # وفرق محصور لا ينهار = انزياح أو اختلاف محتوى حقيقي.
    if [ "$verdict" = "FAIL" ]; then
      local differing blurred blurred_ref
      differing="$($COMPARE -metric AE -fuzz 2% "$norm" "$reference" null: 2>&1 || true)"
      blurred="$RENDERED/norm/${label}_${index}_blur.png"
      blurred_ref="$RENDERED/norm/${label}_${index}_blur_ref.png"
      $CONVERT "$norm" -blur 0x0.5 "$blurred"
      $CONVERT "$reference" -blur 0x0.5 "$blurred_ref"
      printf '     ↳ تشخيص: %s بكسل مختلف (سماح 2%%)، وRMSE بعد تنعيم نصف بكسل %s\n' \
        "$differing" "$(rmse_between "$blurred" "$blurred_ref")"
    fi
  done <<<"$files"
  return "$status"
}

check_track "PDF" "$RENDERED/pdf" "$PDF_THRESHOLD" 2>&1 | tee -a "$REPORT" || failures=$((failures + 1))
check_track "Word" "$RENDERED/docx" "$DOCX_THRESHOLD" 2>&1 | tee -a "$REPORT" || failures=$((failures + 1))

{
  echo
  if [ "$failures" -eq 0 ]; then
    echo "النتيجة: الطابقة البصرية مقبولة (RMSE داخل السقوف)."
  else
    echo "النتيجة: فشل في $failures مسار تصيير."
  fi
} >>"$REPORT"

if [ "$failures" -ne 0 ]; then
  excerpt="$(tail -n 20 "$REPORT")"
  excerpt="${excerpt//%/%25}"
  excerpt="${excerpt//$'\r'/%0D}"
  excerpt="${excerpt//$'\n'/%0A}"
  echo "::error title=الطابقة البصرية ($failures فشل)::$excerpt"
  exit 1
fi

tail -n 6 "$REPORT"
