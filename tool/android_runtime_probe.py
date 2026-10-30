"""Install the real release APK and retain an honestly scoped emulator probe.

This is NOT the Arabic/English composition, long-option, navigation/export IME
acceptance matrix. A successful process means the listed smoke checks passed;
runtime.json always states the remaining closure blockers. ASCII text uses adb
injection, not an assertion that a human keyboard composition sequence passed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = 'com.techtouch.writing_questions_app'


def adb(*args, binary=False, timeout=45):
    data = subprocess.check_output(['adb', *args], timeout=timeout)
    return data if binary else data.decode('utf-8', errors='replace')


def nodes(xml):
    return list(ET.fromstring(xml).iter('node'))


def centre(node):
    coords = [int(v) for v in re.findall(r'\d+', node.attrib['bounds'])]
    if len(coords) != 4:
        raise ValueError('Invalid native accessibility bounds')
    return (coords[0] + coords[2]) // 2, (coords[1] + coords[3]) // 2


def keyboard_top(window_dump):
    """Actual InputMethod touchable region, not the full transparent window.

    Android 15's IME window covers almost the entire screen, but the keyboard
    starts at its touchable region (852 px in the preserved failing evidence).
    Missing/unparseable evidence is an error, never guessed from a focused node.
    """
    sections = re.findall(r'^\s*Window #[^\n]*InputMethod[^\n]*:\n(.*?)(?=^\s*Window #|\Z)',
                          window_dump, flags=re.MULTILINE | re.DOTALL)
    tops = []
    for section in sections:
        if 'isVisible=true' not in section:
            continue
        region = re.search(r'touchable region=SkRegion\(([^\n]+)\)', section)
        if region:
            tops.extend(int(y0) for _, y0, _, _ in re.findall(
                r'\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\)', region.group(1)))
    if not tops:
        raise ValueError('Cannot measure visible InputMethod touchable top')
    return min(tops)


def entirely_above(node, top):
    left, y0, right, bottom = [int(v) for v in re.findall(r'-?\d+', node.attrib['bounds'])]
    return left >= 0 and right > left and y0 >= 0 and bottom > y0 and bottom <= top


def label(node):
    return node.get('text', '') + '\n' + node.get('content-desc', '')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ime-apk', type=Path, help='Separate real test InputMethodService, not adb text injection')
    args = parser.parse_args()
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    report = dict(sourceSha=os.environ.get('GITHUB_SHA'), sourceRun=os.environ.get('GITHUB_RUN_ID'),
        apkSha256=hashlib.sha256(args.apk.read_bytes()).hexdigest(), deviceKind='emulator',
        completeAcceptance=False, inputMethod='adb ASCII injection; NOT real keyboard composition',
        checks=[], closureBlockers=[
            'Actual Arabic and English keyboard composition (including composing region) is not covered.',
            'Multiline statements, long options and continuations are not covered by this smoke probe.',
            'All keyboard insets, focus/navigation, save visibility and export-state scenarios remain unverified.',
            'This emulator evidence is not physical-device evidence.'])

    if args.ime_apk is not None:
        report['testImeApkSha256'] = hashlib.sha256(args.ime_apk.read_bytes()).hexdigest()

    def check(name, condition, detail):
        report['checks'].append(dict(name=name, passed=bool(condition), detail=detail))
        if not condition:
            raise AssertionError(f'{name}: {detail}')

    def snapshot(name):
        adb('shell', 'uiautomator', 'dump', '/sdcard/runtime-window.xml', timeout=60)
        xml = adb('exec-out', 'cat', '/sdcard/runtime-window.xml')
        (out / f'{name}.xml').write_text(xml)
        (out / f'{name}.png').write_bytes(adb('exec-out', 'screencap', '-p', binary=True))
        (out / f'{name}-ime.txt').write_text(adb('shell', 'dumpsys', 'input_method'))
        (out / f'{name}-window.txt').write_text(adb('shell', 'dumpsys', 'window', 'windows'))
        return xml

    def tap(node):
        x, y = centre(node)
        adb('shell', 'input', 'tap', str(x), str(y))
        time.sleep(2)

    try:
        report['device'] = {key: adb('shell', 'getprop', key).strip() for key in
            ['ro.product.model', 'ro.build.version.release', 'ro.build.version.sdk', 'ro.product.cpu.abi', 'ro.build.fingerprint']}
        report['keyboard'] = adb('shell', 'settings', 'get', 'secure', 'default_input_method').strip()
        adb('logcat', '-c')
        install = adb('install', '-r', str(args.apk), timeout=120)
        check('release APK installation', 'Success' in install, install.strip())
        adb('shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1')
        time.sleep(6)
        xml = snapshot('01-home')
        candidates = [n for n in nodes(xml) if 'إنشاء ورقة أسئلة جديدة' in label(n)]
        if not candidates:
            candidates = [n for n in nodes(xml) if 'ورقة أسئلة جديدة (معالج متسلسل)' in label(n)]
        check('home launch / native accessibility', bool(candidates), 'New-document control must actually be exposed.')
        tap(candidates[0])
        xml = snapshot('02-header')
        fields = [n for n in nodes(xml) if n.get('class') == 'android.widget.EditText']
        check('open editable document', bool(fields), 'Header must expose at least one native editable semantic field.')
        tap(fields[0])
        adb('shell', 'input', 'text', 'Runtime2026_123')
        time.sleep(2)
        xml = snapshot('03-keyboard-visible')
        check('ASCII/numeric document edit', 'Runtime2026_123' in xml, 'adb-injected ASCII must appear in the live editable field.')
        ime = (out / '03-keyboard-visible-ime.txt').read_text()
        check('real emulator keyboard visible', bool(re.search(r'(?:mInputShown|isInputViewShown)=true', ime)),
              'Visibility must be observed in dumpsys, not inferred from focus.')
        next_open = [n for n in nodes(xml) if 'التالي: إعداد السؤال الأول' in label(n)]
        top = keyboard_top((out / '03-keyboard-visible-window.txt').read_text())
        report['keyboardOcclusion'] = dict(keyboardTopPx=top,
            nextBounds=[n.attrib['bounds'] for n in next_open],
            assertion='entire button bounds above actual IME touchable top, not node presence')
        check('header Next entirely above the OPEN keyboard',
              bool(next_open) and all(entirely_above(n, top) for n in next_open),
              json.dumps(report['keyboardOcclusion']))
        adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
        time.sleep(2)
        xml = snapshot('04-keyboard-dismissed')
        next_buttons = [n for n in nodes(xml) if 'التالي: إعداد السؤال الأول' in label(n)]
        check('next control accessible after keyboard dismissal', bool(next_buttons), 'Actual native accessibility node must remain present.')
        tap(next_buttons[0])
        snapshot('05-question-step')
        time.sleep(5)  # Existing production auto-save debounce, not a test-only save API.
        adb('shell', 'am', 'force-stop', PACKAGE)
        adb('shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1')
        time.sleep(6)
        xml = snapshot('06-reopened')
        check('saved document survives process restart', 'Runtime2026_123' in xml,
              'The actual library UI must contain the edited name after a force-stop/relaunch.')
        if args.ime_apk is not None:
            from android_ime_acceptance import run_acceptance
            report['imeAcceptance'] = run_acceptance(adb, out, snapshot, tap, check,
                nodes, label, keyboard_top, entirely_above, args.ime_apk)
            report['inputMethod'] = report['imeAcceptance']['inputMethod']
            report['closureBlockers'] = [
                'Commercial keyboard prediction/swipe/handwriting and all platform focus/media/export races are not covered.',
                'This emulator evidence is not physical-device evidence; full editor acceptance has separate gates.']
        report['smokePassed'] = True
    except Exception as error:
        report['smokePassed'] = False
        report['error'] = f'{type(error).__name__}: {error}'
        report['closureBlockers'].insert(0, report['error'])
        raise
    finally:
        if args.ime_apk is not None:
            # Retain actual composition/focus evidence even if a UI assertion
            # fails before the happy-path trace retrieval. Never replace the
            # original failure with a collection error or synthetic document.
            try:
                trace = adb('exec-out', 'run-as', 'org.writingquestions.acceptanceime',
                            'cat', 'files/events.jsonl')
                (out / 'ime-events.jsonl').write_text(trace)
            except Exception as error:
                report['imeTraceCollectionError'] = str(error)
            if not report.get('imeAcceptance', {}).get('passed'):
                try:
                    adb('shell', 'uiautomator', 'dump', '/sdcard/ime-final.xml', timeout=60)
                    (out / 'ime-failure.xml').write_text(adb('exec-out', 'cat', '/sdcard/ime-final.xml'))
                    (out / 'ime-failure.png').write_bytes(adb('exec-out', 'screencap', '-p', binary=True))
                    report['imeFailureInputMethod'] = adb('shell', 'dumpsys', 'input_method')
                    report['imeRegistryAtFailure'] = adb('shell', 'ime', 'list', '-a', '-s')
                except Exception as error:
                    report['imeFailureCollectionError'] = str(error)
        try:
            (out / 'logcat.txt').write_text(adb('logcat', '-d', '-t', '3000', timeout=30))
        except Exception as error:
            (out / 'logcat.txt').write_text(f'Log collection failed: {error}')
        (out / 'runtime.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        names = sorted(p.name for p in out.iterdir() if p.is_file() and p.name != 'manifest.json')
        (out / 'manifest.json').write_text(json.dumps(dict(files=names), indent=2))
        print('::warning title=Android runtime scope::' + json.dumps(dict(
            smokePassed=report['smokePassed'], completeAcceptance=False,
            remaining=report['closureBlockers']), ensure_ascii=False))


if __name__ == '__main__':
    main()
