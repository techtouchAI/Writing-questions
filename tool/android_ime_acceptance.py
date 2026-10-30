"""Real, UI-driven test-IME acceptance. Never injects text using adb input.

The separately installed keyboard is an actual InputMethodService, not a mock
Flutter channel or a broadcast text inserter. This verifies the platform input
connection, not every commercial keyboard's prediction/swipe/handwriting UI.
"""
import hashlib
import json
from pathlib import Path
import re
import shlex
import time

PACKAGE = 'com.techtouch.writing_questions_app'
IME_PACKAGE = 'org.writingquestions.acceptanceime'
IME_COMPONENT = IME_PACKAGE + '/.AcceptanceIme'
NAME = 'سَلَامٌ English 123٤٥٦'
MULTILINE = 'سطر أول English ١٢٣\nسطر ثانٍ 456'
BODY = MULTILINE + '\n' + 'سطر عربي English ١٢٣ 456. ' * 320 + 'IMETAIL'


def require_exact_text(nodes, expected):
    matches = [n for n in nodes if n.get('class') == 'android.widget.EditText'
               and n.get('text') == expected and n.get('package') == PACKAGE]
    if len(matches) != 1:
        actual = [n.get('text') for n in nodes if n.get('class') == 'android.widget.EditText']
        raise AssertionError(f'Expected one exact native editable value {expected!r}; got {actual!r}')
    return matches[0]


def validate_trace(text):
    events = [json.loads(line) for line in text.splitlines() if line.strip()]
    if not events or any(not e.get('accepted') or e.get('package') != PACKAGE for e in events):
        raise AssertionError('IME event failed, missing, or targeted a different package')
    for operation in ['setSelection', 'setComposingText', 'commitText', 'finishComposingText', 'copy', 'paste']:
        if not any(e['operation'] == operation for e in events):
            raise AssertionError('Missing actual IME operation: ' + operation)
    for token in ['سَ', 'سَلَامٌ', ' English', ' 123٤٥٦', MULTILINE]:
        if not any(e['operation'] == 'setComposingText' and e['input'] == token for e in events):
            raise AssertionError('Missing actual composition for ' + repr(token))
    return events


def run_acceptance(adb, out, snapshot, tap, check, nodes, label, keyboard_top, entirely_above, keyboard_apk):
    check('separate test IME APK installation', 'Success' in adb('install', '-r', str(keyboard_apk)),
          'Separate keyboard fixture; production APK is unchanged.')
    adb('shell', 'ime', 'enable', IME_COMPONENT)
    adb('shell', 'ime', 'set', IME_COMPONENT)
    check('actual test IME selected', IME_PACKAGE in adb('shell', 'settings', 'get', 'secure', 'default_input_method'),
          'InputMethodService must be selected by Android, not a fake app input API.')
    # Read-only extraction of generated PDF from this emulator requires root.
    # Never silently replace this with a seeded PDF or declare a device PASS.
    adb('root'); adb('wait-for-device')
    check('emulator permits read-only PDF evidence extraction', adb('shell', 'id', '-u').strip() == '0',
          'Only the test document cache is read; no application data is written.')

    def xml():
        adb('shell', 'uiautomator', 'dump', '/sdcard/ime-window.xml', timeout=60)
        return adb('exec-out', 'cat', '/sdcard/ime-window.xml')

    def find(wanted, *, package=PACKAGE, clickable=False):
        candidates = [n for n in nodes(xml()) if wanted in label(n) and n.get('package') == package
                      and (not clickable or n.get('clickable') == 'true')]
        # Native hierarchy includes descendants and containers. Prefer a
        # clickable semantic leaf instead of a whole-screen wrapper.
        if not candidates:
            raise AssertionError('Native control not reachable: ' + wanted)
        return candidates[-1]

    def key(name):
        tap(find('IME ' + name, package=IME_PACKAGE, clickable=True))

    def edit_exact(expected):
        return require_exact_text(nodes(xml()), expected)

    def fill_name():
        key('clear'); key('Arabic'); key('English'); key('digits')
        edit_exact(NAME)

    def save_content():
        control = find('حفظ المحتوى', clickable=True)
        top = keyboard_top(adb('shell', 'dumpsys', 'window', 'windows'))
        check('mixed editor Save entirely above the actual keyboard', entirely_above(control, top),
              json.dumps(dict(bounds=control.get('bounds'), keyboardTopPx=top)))
        tap(control)

    def open_rich(wanted):
        tap(find(wanted, clickable=True))
        editable = [n for n in nodes(xml()) if n.get('class') == 'android.widget.EditText' and n.get('package') == PACKAGE]
        check('rich editor exposes its actual native input', len(editable) == 1,
              'The active dialog, not an unrelated question number, must expose one text editor.')
        tap(editable[0])

    def preview_back():
        # The real app bar's leading button is top-right in this RTL screen.
        # Native accessibility bounds, followed by an asserted destination;
        # never invoke a Flutter callback or inject controller state.
        buttons = [n for n in nodes(xml()) if n.get('package') == PACKAGE and n.get('class') == 'android.widget.Button'
                   and n.get('clickable') == 'true' and _bounds(n)[1] < 200]
        if not buttons: raise AssertionError('Native app-bar back target absent')
        tap(max(buttons, key=lambda n: _bounds(n)[2]))

    tap(find('ورقة أسئلة جديدة (معالج متسلسل)', clickable=True))
    fields = [n for n in nodes(xml()) if n.get('class') == 'android.widget.EditText' and n.get('package') == PACKAGE]
    if not fields: raise AssertionError('New document name editor absent')
    tap(fields[0]); fill_name()
    key('select all'); key('copy'); key('end'); key('paste')
    edit_exact(NAME + NAME)
    check('actual Android copy/paste preserves mixed diacritics and digits', True, 'Exact native editable value after paste, no normalization.')
    fill_name()
    snapshot('07-ime-name-copy-paste')
    next_button = find('التالي: إعداد السؤال الأول', clickable=True)
    top = keyboard_top(adb('shell', 'dumpsys', 'window', 'windows'))
    check('header navigation above test IME', entirely_above(next_button, top), next_button.get('bounds'))
    tap(next_button)  # Navigate while IME is OPEN, not only after dismissal.
    open_rich('منطوق السؤال')
    fill_name(); snapshot('08-ime-mixed-statement'); save_content()
    # Dialog close can leave the IME hiding asynchronously; wait for the real
    # frame, not a synthetic viewInset supplied by a widget test.
    time.sleep(1)
    open_rich('نص السؤال (اختياري)')
    key('clear'); key('multiline'); key('newline'); key('long')
    edit_exact(BODY)
    check('multiline and long source exact through actual IME', True,
          f'{len(BODY)} code points including newline, Arabic, Latin, digits and IMETAIL.')
    snapshot('09-ime-long-body'); save_content()
    tap(find('إنهاء وعرض النموذج', clickable=True))
    time.sleep(6)
    snapshot('10-ime-live-preview')
    # Actual horizontal toolbar scroll. The toolbar is below status/appbar and
    # question-actions bar, at 24+56+48+30 logical dp, independently of paper zoom.
    size = re.search(r'(\d+)x(\d+)', adb('shell', 'wm', 'size'))
    density = re.findall(r'(\d+)', adb('shell', 'wm', 'density'))
    if not size or not density: raise AssertionError('Cannot determine actual screen/density')
    width = int(size.group(1)); y = round((24 + 56 + 48 + 30) * int(density[-1]) / 160)
    export = None
    for direction in [1] * 10 + [-1] * 10:
        candidates = [n for n in nodes(xml()) if n.get('package') == PACKAGE and n.get('clickable') == 'true'
                      and ('PDF' in label(n)) and 0 <= _bounds(n)[0] < _bounds(n)[2] <= width]
        if candidates:
            export = candidates[-1]; break
        start, end = (int(width*.15), int(width*.85)) if direction == 1 else (int(width*.85), int(width*.15))
        adb('shell', 'input', 'swipe', str(start), str(y), str(end), str(y), '400');time.sleep(.5)
    if export is None: raise AssertionError('PDF toolbar target never became reachable by real scrolling')
    tap(export); tap(find('تصدير PDF', clickable=True));time.sleep(6)
    snapshot('11-ime-export-preview')
    share = [n for n in nodes(xml()) if n.get('clickable') == 'true' and re.search(r'share|مشاركة',label(n),re.I)]
    if not share: raise AssertionError('Actual PDF share control not available')
    tap(share[-1]);time.sleep(2)
    paths = adb('shell', 'find', f'/data/user/0/{PACKAGE}', '-type', 'f', '-name', '*.pdf').splitlines()
    if not paths: raise AssertionError('Real export did not write a shareable PDF')
    raw = adb('exec-out', 'cat ' + shlex.quote(paths[-1]), binary=True)
    if not raw.startswith(b'%PDF'): raise AssertionError('Export evidence is not PDF')
    (out/'ime-document.pdf').write_bytes(raw)
    import pymupdf
    pdf = pymupdf.open(stream=raw,filetype='pdf')
    text='\n'.join(page.get_text() for page in pdf)
    check('actual device PDF preserves the long tail once', text.count('IMETAIL') == 1 and len(pdf) >= 2,
          f'{len(pdf)} actual PDF pages, IMETAIL count={text.count("IMETAIL")}')
    check('actual device PDF preserves every English token', text.count('English') == 322,
          f'Expected322 from actual statement+body; found{text.count("English")}.')
    check('actual device PDF retains diacritized Arabic statement', 'سَلَامٌ' in text,
          'No normalization/extractor exemption; actual PDF text plus retained PNG/PDF for visual review.')
    time.sleep(5)
    adb('shell', 'am', 'force-stop', PACKAGE)
    adb('shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1');time.sleep(5)
    tap(find('متابعة العمل', clickable=True));time.sleep(5)
    preview_back()
    open_rich('منطوق السؤال'); edit_exact(NAME); tap(find('إلغاء',clickable=True))
    open_rich('نص السؤال (اختياري)'); edit_exact(BODY)
    snapshot('12-ime-reopened-exact-body');tap(find('إلغاء',clickable=True))
    preview_back()
    edit_exact(NAME);snapshot('13-ime-reopened-exact-name')
    check('actually reopened document preserves all edited content', True,
          'Exact name, statement and multiline long body checked in native editable fields after process restart.')
    trace = adb('exec-out','run-as',IME_PACKAGE,'cat','files/events.jsonl')
    (out/'ime-events.jsonl').write_text(trace)
    events = validate_trace(trace)
    check('real composing operations target this application', True,
          f'{len(events)} accepted native InputConnection events; trace retained verbatim.')
    return dict(passed=True, keyboardApkSha256=hashlib.sha256(Path(keyboard_apk).read_bytes()).hexdigest(),
                inputMethod=IME_COMPONENT, fullEditedContentVerified=True,
                actualPdfSha256=hashlib.sha256(raw).hexdigest(), pdfPages=len(pdf),
                limitation='UI-driven test InputMethodService; not Gboard prediction/swipe/handwriting or all focus/media/export races.')


def _bounds(node):
    values = [int(n) for n in re.findall(r'-?\d+',node.get('bounds',''))]
    if len(values)!=4: raise ValueError('Unmeasurable native control bounds')
    return values
