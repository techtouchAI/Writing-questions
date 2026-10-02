#!/usr/bin/env python3
"""يولّد ملف DOCX للعرض المسبق عن مخرج مُصدِّر OMML (المرحلة 1).

السبب: بيئة العمل هذه لا تحمل Flutter/Dart، فملفات Word الحقيقية يولّدها
`flutter test` (يكتبها في `build/math_samples/`) أو `tool/make_math_samples.dart`.
هذا السكربت يعيد إنتاج **الشكل نفسه** الذي يولّده المُصدِّر — لكل عيّنة من
عيّنات المدرّس — من شجرة العقد نفسها يدوياً، ليُفتح الملف في Word الآن ويُرى:
هل المعادلة أصلية قابلة للتحرير؟ هل تنزل في وسط الجملة العربية؟ هل الشكل مطابق؟

لا يُستعمل في البناء ولا في الاختبارات؛ ومخرجه في `build/` (غير متتبَّع).

    python3 tool/make_omml_preview_docx.py [مجلد الخروج]
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path
from xml.dom import minidom

M_NS = 'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"'
W_NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
R_NS = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
FONT = 'Cambria Math'

SAMPLES: list[tuple[str, str]] = [
    ('5^2', 'أسّ'),
    ('x_1', 'دليل'),
    ('{x_1}^2', 'دليل وأسّ معاً'),
    ('sqrt(66)', 'جذر تربيعي'),
    ('cbrt(x,3)', 'جذر بتعيين درجة'),
    ('frac(5,8)', 'كسر'),
    ('frac(frac(1,2),3)', 'كسر متداخل'),
    ('sum(i=1..n) i', 'مجموع بحدّين'),
    ('int(0..1) x dx', 'تكامل بحدّين'),
    ('vec(F)', 'سهم فوق'),
    ('hat(x)', 'قبعة'),
    ('overline(AB)', 'خط فوق'),
    ('text+math', 'نص عربي ومعادلة'),
    ('rtl-inline', 'معادلة داخل سؤال RTL'),
]


def esc(text: str) -> str:
    return (
        text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    )


def run(text: str, size_half: int, *, upright: bool = False) -> str:
    """جريان رياضيات `m:r` — بنفس ترتيب العناصر الذي يفرضه المخطط."""
    style = '<m:rPr><m:sty m:val="p"/></m:rPr>' if upright else ''
    return (
        f'<m:r>{style}'
        f'<w:rPr>'
        f'<w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}" w:cs="{FONT}"/>'
        f'<w:sz w:val="{size_half}"/><w:szCs w:val="{size_half}"/>'
        f'</w:rPr>'
        f'<m:t xml:space="preserve">{esc(text)}</m:t></m:r>'
    )


def frac(num: str, den: str) -> str:
    return f'<m:f><m:num>{num}</m:num><m:den>{den}</m:den></m:f>'


def rad(body: str, deg: str | None = None) -> str:
    if deg is None:
        return (
            f'<m:rad><m:radPr><m:degHide m:val="1"/></m:radPr><m:deg/>'
            f'<m:e>{body}</m:e></m:rad>'
        )
    return (
        f'<m:rad><m:radPr></m:radPr><m:deg>{deg}</m:deg>'
        f'<m:e>{body}</m:e></m:rad>'
    )


def sub(base: str, sub_expr: str) -> str:
    return f'<m:sSub><m:e>{base}</m:e><m:sub>{sub_expr}</m:sub></m:sSub>'


def sup(base: str, sup_expr: str) -> str:
    return f'<m:sSup><m:e>{base}</m:e><m:sup>{sup_expr}</m:sup></m:sSup>'


def subsup(base: str, sub_expr: str, sup_expr: str) -> str:
    return (
        f'<m:sSubSup><m:e>{base}</m:e><m:sub>{sub_expr}</m:sub>'
        f'<m:sup>{sup_expr}</m:sup></m:sSubSup>'
    )


def nary(glyph: str, low: str, high: str, operand: str, *, display: bool) -> str:
    limits = 'undOvr' if display else 'subSup'
    return (
        f'<m:nary><m:naryPr><m:chr m:val="{glyph}"/><m:limLoc m:val="{limits}"/>'
        f'<m:subHide m:val="0"/><m:supHide m:val="0"/></m:naryPr>'
        f'<m:sub>{low}</m:sub><m:sup>{high}</m:sup><m:e/></m:nary>{operand}'
    )


def acc(char: str, body: str) -> str:
    return f'<m:acc><m:accPr><m:chr m:val="{char}"/></m:accPr><m:e>{body}</m:e></m:acc>'


def bar(body: str) -> str:
    return f'<m:bar><m:barPr><m:pos m:val="top"/></m:barPr><m:e>{body}</m:e></m:bar>'


def fence(inner: str, *, left: str = '(', right: str = ')') -> str:
    props = ''
    if left != '(':
        props += f'<m:begChr m:val="{left}"/>'
    if right != ')':
        props += f'<m:endChr m:val="{right}"/>'
    return f'<m:d><m:dPr>{props}</m:dPr><m:e>{inner}</m:e></m:d>'


def zone(content: str) -> str:
    return f'<m:oMath>{content}</m:oMath>'


def paragraph(content: str, *, bidi: bool = True, size_half: int = 22,
              math_para: bool = False, text: str = '') -> str:
    """فقرة واحدة: نص + منطقة رياضيات (وابن مباشر لـ w:p كما يُخرج المُصدِّر)."""
    bidi_xml = '<w:bidi/>' if bidi else ''
    head = (
        f'<w:p><w:pPr>{bidi_xml}<w:jc w:val="right"/>'
        f'<w:spacing w:before="60" w:after="60" w:line="276" w:lineRule="auto"/>'
        f'<w:rPr><w:sz w:val="{size_half}"/></w:rPr></w:pPr>'
    )
    body = text_run(text, size_half, bidi=bidi) if text else ''
    if math_para:
        body += (
            '<m:oMathPara><m:oMathParaPr><m:jc m:val="center"/></m:oMathParaPr>'
            + content + '</m:oMathPara>'
        )
    else:
        body += content
    return head + body + '</w:p>'


def text_run(text: str, size_half: int, *, bidi: bool = True) -> str:
    rtl = '<w:rtl/>' if bidi else ''
    return (
        f'<w:r><w:rPr>{rtl}<w:sz w:val="{size_half}"/></w:rPr>'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r>'
    )


def equation_for(key: str, size_half: int, *, display: bool) -> str:
    """منطقة الرياضيات لكل عيّنة — كأصح مما يولّده المُصدِّر مباشرة."""
    if key == '5^2':
        return sup(run('5', size_half), run('2', size_half))
    if key == 'x_1':
        return sub(run('x', size_half), run('1', size_half))
    if key == '{x_1}^2':
        return subsup(run('x', size_half), run('1', size_half), run('2', size_half))
    if key == 'sqrt(66)':
        return rad(run('66', size_half))
    if key == 'cbrt(x,3)':
        return rad(run('x', size_half), deg=run('3', size_half))
    if key == 'frac(5,8)':
        return frac(run('5', size_half), run('8', size_half))
    if key == 'frac(frac(1,2),3)':
        return frac(frac(run('1', size_half), run('2', size_half)), run('3', size_half))
    if key == 'sum(i=1..n) i':
        return nary(
            '\u2211',
            run('i=1', size_half),
            run('n', size_half),
            run(' i', size_half),
            display=display,
        )
    if key == 'int(0..1) x dx':
        return nary(
            '\u222b',
            run('0', size_half),
            run('1', size_half),
            run(' x', size_half) + run(' ', size_half, upright=True) + run('dx', size_half),
            display=display,
        )
    if key == 'vec(F)':
        return acc('\u20D7', run('F', size_half))
    if key == 'hat(x)':
        return acc('\u0302', run('x', size_half))
    if key == 'overline(AB)':
        return bar(run('AB', size_half))
    if key == 'text+math':
        return (
            run('طول', size_half, upright=True)
            + '/'
            + run('عرض', size_half, upright=True)
        )
    # rtl-inline: أقواس ممتدة حول كسر — `\\left(\\frac{1}{2}\\right)`
    return fence(frac(run('1', size_half), run('2', size_half)))


def document_xml() -> str:
    parts: list[str] = [
        '<w:document ' + W_NS + ' ' + M_NS + ' ' + R_NS + '><w:body>'
        + '<w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr>'
        + text_run('عيّنة مخرج مُصدِّر OMML — معادلات Word أصلية', 32, bidi=True)
        + '</w:p>'
    ]
    for index, (key, label) in enumerate(SAMPLES, start=1):
        parts.append(
            paragraph(
                zone(equation_for(key, 22, display=False)),
                text=f'({index}) {label}: ',
            )
        )
        parts.append(
            paragraph(
                zone(equation_for(key, 28, display=True)),
                text='',
                math_para=True,
            )
        )
    # صندوق نصي (جدول عائم) وفيه معادلة: كما يُخرج _buildTextBox بـ mathOverride.
    parts.append(
        '<w:tbl><w:tblPr><w:tblpPr w:horzAnchor="margin" w:vertAnchor="text" '
        'w:tblpX="1200" w:tblpY="600"/><w:bidiVisual/>'
        '<w:tblW w:w="5000" w:type="pct"/>'
        '<w:tblBorders><w:top w:val="single" w:sz="6" w:space="0" w:color="111827"/>'
        '<w:left w:val="single" w:sz="6" w:space="0" w:color="111827"/>'
        '<w:bottom w:val="single" w:sz="6" w:space="0" w:color="111827"/>'
        '<w:right w:val="single" w:sz="6" w:space="0" w:color="111827"/></w:tblBorders>'
        '<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid><w:gridCol w:w="9000"/></w:tblGrid>'
        '<w:tr><w:tc><w:tcPr><w:tcW w:w="9000" w:type="dxa"/></w:tcPr>'
        + paragraph(zone(equation_for('frac(5,8)', 24, display=True)), text='')
        + '</w:tc></w:tr></w:tbl>'
    )
    parts.append(
        '<w:p><w:pPr><w:bidi/></w:pPr>'
        + text_run('افتح المعادلة في Word: إدراج ← معادلة — يجب أن تكون '
                   'محرَّرة لا صورة.', 20, bidi=True) + '</w:p>'
    )
    parts.append(
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
        'w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>'
    )
    parts.append('</w:body></w:document>')
    xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + ''.join(parts)
    )
    # فحص الصرامة XML: يفشل هنا فوراً لو أُخلّ بوسم.
    minidom.parseString(xml)
    return xml


CONTENT_TYPES = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>'
)

ROOT_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/></Relationships>'
)

DOC_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdStyles" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
    'Target="styles.xml"/></Relationships>'
)

STYLES = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    f'<w:styles {W_NS}><w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Tajawal" w:hAnsi="Tajawal" w:cs="Tajawal"/>'
    '<w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
    '<w:name w:val="Normal"/><w:pPr><w:bidi/></w:pPr></w:style></w:styles>'
)


def main() -> int:
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/math_samples')
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / 'handwritten-preview-omml.docx'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as package:
        package.writestr('[Content_Types].xml', CONTENT_TYPES)
        package.writestr('_rels/.rels', ROOT_RELS)
        package.writestr('word/_rels/document.xml.rels', DOC_RELS)
        package.writestr('word/document.xml', document_xml())
        package.writestr('word/styles.xml', STYLES)
    print(f'عاينة Word: {target} ({target.stat().st_size} بايت)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
