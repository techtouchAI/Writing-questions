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
import xml.etree.ElementTree as ET

PACKAGE = 'com.techtouch.writing_questions_app'
IME_PACKAGE = 'org.writingquestions.acceptanceime'
IME_COMPONENT = IME_PACKAGE + '/.AcceptanceIme'
NAME = 'سَلَامٌ English 123٤٥٦'
MIXED_KEY_TEXT = {'Arabic': 'سَلَامٌ', 'English': ' English', 'digits': ' 123٤٥٦'}
MIXED_ORDERS = [('English', 'digits', 'Arabic'), ('digits', 'Arabic', 'English'),
                ('Arabic', 'English', 'digits')]
MULTILINE = 'سطر أول English ١٢٣\nسطر ثانٍ 456'
BODY = MULTILINE + '\n' + 'سطر عربي English ١٢٣ 456. ' * 320 + 'IMETAIL'


def require_exact_text(nodes, expected):
    matches = [n for n in nodes if n.get('class') == 'android.widget.EditText'
               and n.get('text') == expected and n.get('package') == PACKAGE]
    if len(matches) != 1:
        actual = [n.get('text', '') for n in nodes if n.get('class') == 'android.widget.EditText']
        def summary(value):
            mismatch = next((i for i, pair in enumerate(zip(expected, value))
                             if pair[0] != pair[1]), min(len(expected), len(value)))
            return dict(codePoints=len(value), sha256=hashlib.sha256(value.encode()).hexdigest(),
                        firstMismatchCodePoint=mismatch,
                        expectedContext=expected[max(0, mismatch-24):mismatch+48],
                        actualContext=value[max(0, mismatch-24):mismatch+48])
        # Full originals remain in native XML + InputConnection trace. Keep the
        # FIRST actual difference visible in bounded GitHub annotations too;
        # dumping an 8k expected value hid the actual value through truncation.
        raise AssertionError('Expected one exact native editable value: ' + json.dumps(dict(
            expectedCodePoints=len(expected), expectedSha256=hashlib.sha256(expected.encode()).hexdigest(),
            exactMatches=len(matches), nativeEditables=[summary(value) for value in actual]), ensure_ascii=False))
    return matches[0]


def require_key_events(events, previous_count, name):
    composed = {'Arabic': 'سَلَامٌ', 'English': ' English', 'digits': ' 123٤٥٦',
                'multiline': MULTILINE, 'long': BODY[len(MULTILINE)+1:]}
    direct = {'clear': ('commitText', ''), 'newline': ('commitText', '\n'),
              'select all': ('setSelection', 'all'), 'end': ('setSelection', 'end'),
              'copy': ('copy', ''), 'paste': ('paste', '')}
    new = events[previous_count:]
    if not new or any(not e.get('accepted') or e.get('package') != PACKAGE for e in new):
        raise AssertionError('Native IME key produced no accepted input events: ' + name)
    expected = ('finishComposingText', composed[name]) if name in composed else direct[name]
    if (new[-1].get('operation'), new[-1].get('input')) != expected:
        raise AssertionError('Native IME key did not finish its own expected operation: ' + name)
    return len(events)


def validate_trace(text):
    events = [json.loads(line) for line in text.splitlines() if line.strip()]
    if not events or any(not e.get('accepted') or e.get('package') != PACKAGE for e in events):
        raise AssertionError('IME event failed, missing, or targeted a different package')
    for operation in ['setSelection', 'setComposingText', 'commitText', 'finishComposingText', 'copy', 'paste']:
        if not any(e['operation'] == operation for e in events):
            raise AssertionError('Missing actual IME operation: ' + operation)
    for token in ['سَ', 'سَلَامٌ', ' English', ' 123٤٥٦', MULTILINE, BODY[len(MULTILINE)+1:]]:
        if not any(e['operation'] == 'setComposingText' and e['input'] == token for e in events):
            raise AssertionError('Missing actual composition for ' + repr(token))
    return events


def wait_for_ime_registration(adb, *, timeout=30, clock=time.monotonic, sleep=time.sleep):
    # Package installation returns BEFORE InputMethodManager's package-change
    # receiver necessarily rebuilds its registry. Observe registration, do not
    # retry composition failures or silently bypass a rejected enable request.
    deadline = clock() + timeout
    observed = ''
    while True:
        observed = adb('shell', 'ime', 'list', '-a', '-s')
        if IME_COMPONENT in [line.strip() for line in observed.splitlines()]:
            return observed
        if clock() >= deadline:
            raise AssertionError('Installed IME never registered with Android: ' + observed)
        sleep(.5)


def dump_interactive_windows(adb):
    output = adb('shell', 'am', 'instrument', '-w',
                 'org.writingquestions.acceptanceautomation/.WindowDump', timeout=60)
    match = re.search(r'^INSTRUMENTATION_RESULT: xml=(<.*>)\r?$', output, flags=re.MULTILINE)
    codes = re.findall(r'^INSTRUMENTATION_CODE: (-?\d+)\r?$', output, flags=re.MULTILINE)
    if (not match or codes != ['0'] or
            re.search(r'^INSTRUMENTATION_RESULT: error=', output, flags=re.MULTILINE)):
        raise AssertionError('Native interactive-window observer failed: ' + output)
    value = match.group(1)
    if ET.fromstring(value).tag != 'hierarchy':
        raise AssertionError('Native observer returned an unexpected XML root')
    return value


def display_size(output):
    # `wm size` reports Physical first and Override second. Pointer events use
    # Override; selecting the first match would swipe outside a 320/360dp screen.
    sizes = re.findall(r'(\d+)x(\d+)', output)
    if not sizes:
        raise AssertionError('Actual Android display size is unavailable')
    return tuple(map(int, sizes[-1]))


def visible_editable_point(xml, width, height):
    root = ET.fromstring(xml)
    found = []
    def visit(node, ancestors):
        if node.get('class') == 'android.widget.EditText' and node.get('package') == PACKAGE:
            found.append((node, ancestors))
        for child in node:
            visit(child, ancestors + [node])
    visit(root, [])
    if len(found) != 1:
        raise AssertionError('Active rich dialog must expose exactly one native editable')
    node, ancestors = found[0]
    left, top, right, bottom = _bounds(node)
    left, top, right, bottom = max(0, left), max(0, top), min(width, right), min(height, bottom)
    # A long multiline native node may span thousands of pixels. Tap ONLY its
    # visible intersection with the ACTUAL ancestor scroll viewport, not its
    # off-screen semantic centre. This changes no layout or hit-target size.
    for parent in ancestors:
        if parent.get('scrollable') == 'true':
            x0, y0, x1, y1 = _bounds(parent)
            left, top, right, bottom = max(left, x0), max(top, y0), min(right, x1), min(bottom, y1)
    if right <= left or bottom <= top:
        raise AssertionError('Native editable has no reachable visible intersection')
    return ((left + right) // 2, (top + bottom) // 2)


def run_acceptance(adb, out, snapshot, tap, check, nodes, label, keyboard_top, entirely_above, keyboard_apk, automation_apk):
    check('separate test IME APK installation', 'Success' in adb('install', '-r', str(keyboard_apk)),
          'Separate keyboard fixture; production APK is unchanged.')
    registration = wait_for_ime_registration(adb)
    check('separate read-only window observer installation', 'Success' in adb('install', '-r', str(automation_apk)),
          'Observer process is distinct from the IME and editor; no input injection.')
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
        value = dump_interactive_windows(adb)
        (out/'ime-windows.xml').write_text(value)
        return value

    def find(wanted, *, package=PACKAGE, clickable=False):
        candidates = [n for n in nodes(xml()) if wanted in label(n) and n.get('package') == package
                      and (not clickable or n.get('clickable') == 'true')]
        # Native hierarchy includes descendants and containers. Prefer a
        # clickable semantic leaf instead of a whole-screen wrapper.
        if not candidates:
            raise AssertionError('Native control not reachable: ' + wanted)
        return candidates[-1]

    event_count = 0
    def key(name):
        nonlocal event_count
        control = find('IME ' + name, package=IME_PACKAGE, clickable=True)
        tap(control)
        trace = adb('exec-out', 'run-as', IME_PACKAGE, 'cat', 'files/events.jsonl')
        (out/'ime-events.jsonl').write_text(trace)
        events = [json.loads(line) for line in trace.splitlines() if line.strip()]
        # A successful adb TAP is not proof that a native key received it.
        # System navigation consumed "long" in cf278d4. No retry or text API.
        try:
            event_count = require_key_events(events, event_count, name)
        except AssertionError as error:
            raise AssertionError(f'{error}; nativeBounds={control.get("bounds")}; '
                                 f'eventsBefore={event_count}; eventsAfter={len(events)}') from error
        check('actual native IME key completes: ' + name, True,
              json.dumps(dict(nativeBounds=control.get('bounds'), eventsThrough=event_count)))

    def edit_exact(expected):
        return require_exact_text(nodes(xml()), expected)

    def fill_name(field=None):
        # Same actual native field, different script-entry orders. Preserve
        # each exact state and its delivered event range in runtime.json;
        # do not replace UI input with a text/controller/data hook.
        for order in MIXED_ORDERS if field else [MIXED_ORDERS[-1]]:
            before = event_count
            key('clear')
            expected = ''
            for language in order:
                key(language)
                expected += MIXED_KEY_TEXT[language]
                edit_exact(expected)
            if field:
                observed = xml()
                require_exact_text(nodes(observed), expected)
                check('same native field / mixed input order / ' + field + ' / ' + '-'.join(order), True,
                      json.dumps(dict(expected=expected,
                          expectedSha256=hashlib.sha256(expected.encode()).hexdigest(),
                          eventsFrom=before, eventsThrough=event_count, nativeXml=observed), ensure_ascii=False))
        edit_exact(NAME)

    def save_content():
        control = find('حفظ المحتوى', clickable=True)
        top = keyboard_top(adb('shell', 'dumpsys', 'window', 'windows'))
        check('mixed editor Save entirely above the actual keyboard', entirely_above(control, top),
              json.dumps(dict(bounds=control.get('bounds'), keyboardTopPx=top)))
        tap(control)

    def open_rich(wanted):
        tap(find(wanted, clickable=True))
        current_xml = xml()
        editable = [n for n in nodes(current_xml) if n.get('class') == 'android.widget.EditText' and n.get('package') == PACKAGE]
        check('rich editor exposes its actual native input', len(editable) == 1,
              'The active dialog, not an unrelated question number, must expose one text editor.')
        point = visible_editable_point(current_xml, *display_size(adb('shell', 'wm', 'size')))
        adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
        time.sleep(2)
        focused = [n for n in nodes(xml()) if n.get('class') == 'android.widget.EditText'
                   and n.get('package') == PACKAGE and n.get('focused') == 'true']
        check('rich editor accepts actual native focus', len(focused) == 1,
              f'Pointer in the measured visible native viewport at {point}, not an off-screen text centre.')

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
    tap(fields[0]); fill_name('document-name')
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
    fill_name('question-statement'); snapshot('08-ime-mixed-statement'); save_content()
    # Dialog close can leave the IME hiding asynchronously; wait for the real
    # frame, not a synthetic viewInset supplied by a widget test.
    time.sleep(1)
    open_rich('نص السؤال (اختياري)')
    key('clear'); key('multiline'); key('newline'); key('long')
    edit_exact(BODY)
    check('multiline and long source exact through actual IME', True,
          json.dumps(dict(codePoints=len(BODY), sha256=hashlib.sha256(BODY.encode()).hexdigest(),
                          includes='newline, Arabic, Latin, digits and IMETAIL')))
    snapshot('09-ime-long-body'); save_content()
    tap(find('إنهاء وعرض النموذج', clickable=True))
    time.sleep(6)
    snapshot('10-ime-live-preview')
    # Actual horizontal toolbar scroll. The toolbar is below status/appbar and
    # question-actions bar, at 24+56+48+30 logical dp, independently of paper zoom.
    width, _ = display_size(adb('shell', 'wm', 'size'))
    density = re.findall(r'(\d+)', adb('shell', 'wm', 'density'))
    if not density: raise AssertionError('Cannot determine actual density')
    y = round((24 + 56 + 48 + 30) * int(density[-1]) / 160)
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
    (out/'ime-document.txt').write_text(text, encoding='utf-8')
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
                inputMethod=IME_COMPONENT, registeredMethods=registration, fullEditedContentVerified=True,
                observerApkSha256=hashlib.sha256(Path(automation_apk).read_bytes()).hexdigest(),
                actualPdfSha256=hashlib.sha256(raw).hexdigest(), pdfPages=len(pdf),
                limitation='UI-driven test InputMethodService; not Gboard prediction/swipe/handwriting or all focus/media/export races.')


def _bounds(node):
    values = [int(n) for n in re.findall(r'-?\d+',node.get('bounds',''))]
    if len(values)!=4: raise ValueError('Unmeasurable native control bounds')
    return values
