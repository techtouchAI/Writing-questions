"""Unit tests of reporting/error paths only; NEVER Android runtime evidence."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import android_runtime_probe as probe


class RuntimeReporting(unittest.TestCase):
    def test_native_bounds_and_unicode_labels_are_retained(self):
        node = probe.nodes('<hierarchy><node text="اسم" content-desc="Name" bounds="[12,24][60,72]"/></hierarchy>')[0]
        self.assertEqual(probe.centre(node), (36, 48))
        self.assertEqual(probe.label(node), 'اسم\nName')

    def test_keyboard_geometry_rejects_the_observed_050ea_hidden_button(self):
        dump = ('  Window #7 Window{abc u0 InputMethod}:\n'
                '    touchable region=SkRegion((0,852,900,1600))\n'
                '    isVisible=true\n')
        top = probe.keyboard_top(dump)
        self.assertEqual(top, 852)
        hidden = probe.nodes('<hierarchy><node bounds="[30,1385][870,1510]"/></hierarchy>')[0]
        visible = probe.nodes('<hierarchy><node bounds="[30,690][870,815]"/></hierarchy>')[0]
        self.assertFalse(probe.entirely_above(hidden, top))
        self.assertTrue(probe.entirely_above(visible, top))
        with self.assertRaises(ValueError):
            probe.keyboard_top('unmeasurable')
        with self.assertRaises(ValueError):
            probe.keyboard_top(dump.replace('isVisible=true', 'isVisible=false'))

    def test_environment_failure_still_writes_honest_report_and_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / 'release.apk'
            apk.write_bytes(b'unit fixture, not a real APK')
            out = root / 'evidence'
            argv = ['probe', '--apk', str(apk), '--output', str(out)]
            with patch.object(sys, 'argv', argv), patch.object(probe, 'adb', side_effect=RuntimeError('No device')):
                with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, 'No device'):
                    probe.main()
            report = json.loads((out / 'runtime.json').read_text())
            self.assertFalse(report['completeAcceptance'])
            self.assertFalse(report['smokePassed'])
            self.assertIn('No device', report['closureBlockers'][0])
            self.assertEqual(set(json.loads((out / 'manifest.json').read_text())['files']),
                             {'runtime.json', 'logcat.txt'})

    def test_successful_mock_smoke_is_never_full_ime_acceptance(self):
        state = dict(screen='home', taps=0, launches=0)

        def fake_adb(*args, **kwargs):
            if args[0] == 'install':
                return 'Success'
            if args[:2] == ('shell', 'monkey'):
                state['launches'] += 1
                state['screen'] = 'home' if state['launches'] == 1 else 'reopened'
            elif args[:3] == ('shell', 'input', 'tap'):
                state['taps'] += 1
                state['screen'] = {1: 'header', 2: 'editing', 3: 'question'}[state['taps']]
            elif args[:3] == ('shell', 'input', 'keyevent'):
                state['screen'] = 'dismissed'
            if args[:2] == ('exec-out', 'cat'):
                text = {'home': 'إنشاء ورقة أسئلة جديدة', 'header': 'اسم',
                        'editing': 'Runtime2026_123', 'dismissed': 'التالي: إعداد السؤال الأول',
                        'question': 'السؤال', 'reopened': 'Runtime2026_123'}[state['screen']]
                extra = '<node content-desc="التالي: إعداد السؤال الأول" bounds="[0,600][100,700]"/>' if state['screen']=='editing' else ''
                return f'<hierarchy><node text="{text}" bounds="[0,0][100,100]" class="android.widget.EditText"/>{extra}</hierarchy>'
            if args[:2] == ('exec-out', 'screencap'):
                return b'unit screenshot placeholder'
            if args[:3] == ('shell', 'dumpsys', 'input_method'):
                return f'mInputShown={str(state["screen"] == "editing").lower()}'
            if args[:4] == ('shell', 'dumpsys', 'window', 'windows'):
                return '  Window #7 Window{abc u0 InputMethod}:\n    touchable region=SkRegion((0,800,900,1600))\n    isVisible=true\n'
            return 'unit fixture'

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / 'release.apk'
            apk.write_bytes(b'unit APK placeholder')
            out = root / 'evidence'
            argv = ['probe', '--apk', str(apk), '--output', str(out)]
            with patch.object(sys, 'argv', argv), patch.object(probe, 'adb', side_effect=fake_adb), patch.object(probe.time, 'sleep'):
                with contextlib.redirect_stdout(io.StringIO()):
                    probe.main()
            report = json.loads((out / 'runtime.json').read_text())
            self.assertTrue(report['smokePassed'])
            self.assertFalse(report['completeAcceptance'])
            self.assertEqual(report['deviceKind'], 'emulator')
            self.assertIn('NOT real keyboard composition', report['inputMethod'])
            self.assertGreater(len(report['closureBlockers']), 0)
            self.assertTrue(all(check['passed'] for check in report['checks']))
            self.assertTrue((out / '06-reopened.xml').exists())


if __name__ == '__main__':
    unittest.main()
