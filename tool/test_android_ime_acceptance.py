"""Offline protocol regressions, explicitly NOT Android execution evidence."""
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
import android_ime_acceptance as ime


class ActualInputContract(unittest.TestCase):
    def trace(self):
        events = [dict(operation=op, input='', accepted=True, package=ime.PACKAGE)
                  for op in ['setSelection','copy','paste','commitText','finishComposingText']]
        events.extend(dict(operation='setComposingText',input=text,accepted=True,package=ime.PACKAGE)
                      for text in ['سَ','سَلَامٌ',' English',' 123٤٥٦',ime.MULTILINE,ime.BODY[len(ime.MULTILINE)+1:]])
        return events

    def test_installed_keyboard_must_reach_actual_android_registry_before_enable(self):
        now=[0.0];calls=[]
        def adb(*args):
            calls.append(args)
            return 'another/.Ime' if now[0] < 1 else ime.IME_COMPONENT+'\n'
        ime.wait_for_ime_registration(adb,clock=lambda:now[0],sleep=lambda s:now.__setitem__(0,now[0]+s))
        self.assertEqual(len(calls),3)
        self.assertEqual(calls[0],('shell','ime','list','-a','-s'))
        with self.assertRaisesRegex(AssertionError,'never registered'):
            ime.wait_for_ime_registration(lambda *args:'another/.Ime',timeout=1,
                clock=lambda:now[0],sleep=lambda s:now.__setitem__(0,now[0]+s))

    def test_observer_reads_native_windows_in_a_third_process(self):
        xml='<hierarchy><node package="'+ime.IME_PACKAGE+'" text="IME clear"/></hierarchy>'
        calls=[]
        def adb(*args,**kwargs):
            calls.append(args)
            return 'INSTRUMENTATION_RESULT: xml='+xml+'\r\nINSTRUMENTATION_CODE: 0\n'
        self.assertEqual(ime.dump_interactive_windows(adb),xml)
        self.assertEqual(calls[0],('shell','am','instrument','-w',
            'org.writingquestions.acceptanceautomation/.WindowDump'))
        with self.assertRaisesRegex(AssertionError,'observer failed'):
            ime.dump_interactive_windows(lambda *args,**kwargs:'INSTRUMENTATION_RESULT: error=no roots')
        for result in ['INSTRUMENTATION_CODE: 1', 'INSTRUMENTATION_CODE: -1',
                       'INSTRUMENTATION_RESULT: error=failed\nINSTRUMENTATION_CODE: 0', '']:
            with self.subTest(result=result), self.assertRaisesRegex(AssertionError,'observer failed'):
                ime.dump_interactive_windows(lambda *args,**kwargs:'INSTRUMENTATION_RESULT: xml='+xml+'\n'+result)
        source=(Path(__file__).parent/'android_automation_fixture/src/org/writingquestions/acceptanceautomation/WindowDump.java').read_text()
        self.assertIn('FLAG_RETRIEVE_INTERACTIVE_WINDOWS',source)
        self.assertIn('automation.getWindows()',source)
        self.assertNotIn('InputConnection',source)
        self.assertNotIn('setText',source)
        manifest=ET.parse(Path(__file__).parent/'android_automation_fixture/AndroidManifest.xml').getroot()
        self.assertEqual(manifest.find('instrumentation').get('{http://schemas.android.com/apk/res/android}targetPackage'),
            'org.writingquestions.acceptanceautomation')

    def test_actual_override_and_visible_scroll_intersection_drive_pointer(self):
        self.assertEqual(ime.display_size('Physical size: 1080x1920\nOverride size: 800x1600'),(800,1600))
        self.assertEqual(ime.display_size('Physical size: 900x1600'),(900,1600))
        with self.assertRaises(AssertionError):ime.display_size('unavailable')
        xml='<hierarchy><node scrollable="true" bounds="[16,100][304,300]"><node package="'+ime.PACKAGE+'" class="android.widget.EditText" bounds="[16,-2000][304,4000]"/></node></hierarchy>'
        self.assertEqual(ime.visible_editable_point(xml,320,640),(160,200))
        with self.assertRaisesRegex(AssertionError,'no reachable'):
            ime.visible_editable_point(xml.replace('[16,100][304,300]','[16,700][304,900]'),320,640)
        with self.assertRaisesRegex(AssertionError,'exactly one'):
            ime.visible_editable_point('<hierarchy/>',320,640)

    def test_long_native_mismatch_diagnostic_keeps_actual_difference_and_hashes(self):
        actual=ime.BODY.replace('أول','اول',1)
        node=ET.Element('node',{'class':'android.widget.EditText','package':ime.PACKAGE,'text':actual})
        with self.assertRaises(AssertionError) as error:ime.require_exact_text([node],ime.BODY)
        detail=json.loads(str(error.exception).split(': ',1)[1])
        self.assertEqual(detail['expectedCodePoints'],len(ime.BODY))
        self.assertEqual(detail['expectedSha256'],ime.hashlib.sha256(ime.BODY.encode()).hexdigest())
        self.assertEqual(detail['nativeEditables'][0]['firstMismatchCodePoint'],ime.BODY.index('أ'))
        self.assertIn('اول',detail['nativeEditables'][0]['actualContext'])
        self.assertLess(len(str(error.exception)),1500)

    def test_native_tap_is_not_accepted_without_that_keys_own_input_event(self):
        prefix=self.trace()
        with self.assertRaisesRegex(AssertionError,'no accepted input events'):
            ime.require_key_events(prefix,len(prefix),'long')
        event=dict(operation='finishComposingText', input=ime.BODY[len(ime.MULTILINE)+1:],
                   accepted=True,package=ime.PACKAGE)
        self.assertEqual(ime.require_key_events(prefix+[event],len(prefix),'long'),len(prefix)+1)
        for change in [dict(accepted=False),dict(package='other'),dict(input='wrong'),dict(operation='paste')]:
            bad=dict(event,**change)
            with self.assertRaises(AssertionError):ime.require_key_events(prefix+[bad],len(prefix),'long')
        source=(Path(__file__).parent/'android_ime_fixture/src/org/writingquestions/acceptanceime/AcceptanceIme.java').read_text()
        self.assertIn('WindowInsets.Type.navigationBars()',source)
        self.assertIn('view.setPadding(',source)

    def test_actual_operations_and_each_language_are_required(self):
        events=self.trace()
        self.assertEqual(ime.validate_trace('\n'.join(map(json.dumps,events))),events)
        for i in range(len(events)):
            with self.subTest(omitted=events[i]):
                with self.assertRaises(AssertionError):
                    ime.validate_trace('\n'.join(map(json.dumps,events[:i]+events[i+1:])))

    def test_rejected_or_wrong_editor_is_never_a_pass(self):
        for changes in [dict(accepted=False),dict(package='some.other.app')]:
            events=self.trace();events[0].update(changes)
            with self.assertRaises(AssertionError):ime.validate_trace('\n'.join(map(json.dumps,events)))
        with self.assertRaises(AssertionError):ime.validate_trace('')

    def test_mixed_orders_preserve_exact_script_chunks_and_restore_final_source(self):
        self.assertEqual(len(ime.MIXED_ORDERS), 3)
        self.assertEqual({order[0] for order in ime.MIXED_ORDERS}, {'Arabic', 'English', 'digits'})
        for order in ime.MIXED_ORDERS:
            self.assertEqual(set(order), set(ime.MIXED_KEY_TEXT))
            expected = ''.join(ime.MIXED_KEY_TEXT[key] for key in order)
            node = ET.Element('node', {'class': 'android.widget.EditText', 'package': ime.PACKAGE, 'text': expected})
            self.assertIs(ime.require_exact_text([node], expected), node)
            with self.assertRaises(AssertionError):
                ime.require_exact_text([node], expected.strip() if expected.startswith(' ') else expected + ' ')
        self.assertEqual(''.join(ime.MIXED_KEY_TEXT[key] for key in ime.MIXED_ORDERS[-1]), ime.NAME)

    def test_native_value_is_exact_not_normalized_or_substring_matched(self):
        def node(value):
            return ET.Element('node',{'class':'android.widget.EditText','package':ime.PACKAGE,'text':value})
        n=node(ime.NAME)
        self.assertIs(ime.require_exact_text([n],ime.NAME),n)
        for bad in ['سلام English 123٤٥٦',ime.NAME+' ',ime.NAME*2,'']:
            with self.assertRaises(AssertionError):ime.require_exact_text([node(bad)],ime.NAME)
        with self.assertRaises(AssertionError):ime.require_exact_text([n,n],ime.NAME)

    def test_long_multiline_fixture_is_explicit_and_bound_to_native_ime_source(self):
        source=(Path(__file__).parent/'android_ime_fixture/src/org/writingquestions/acceptanceime/AcceptanceIme.java').read_text()
        self.assertIn('i < 320',source)
        self.assertIn('سطر عربي English ١٢٣ 456. ',source)
        self.assertEqual(ime.BODY.count('English'),321)
        self.assertEqual(ime.BODY.count('IMETAIL'),1)
        self.assertIn('\n',ime.BODY)
        self.assertIn('original.setComposingText',source)
        self.assertIn('original.finishComposingText()',source)
        self.assertNotIn('sendBroadcast',source)

    def test_real_ime_has_sufficient_reference_groups_without_relaxing_reader(self):
        workflow=(Path(__file__).parents[1]/'.github/workflows/build_apk.yml').read_text()
        android=workflow.split('  android-runtime-evidence:',1)[1].split('  validation-log-review:',1)[0]
        for group in range(6):self.assertIn(f'android-index.json" --group {group}',android)
        self.assertIn('width: [320, 360]',android)
        self.assertIn('--ime-apk',android)
        manifest=ET.parse(Path(__file__).parent/'android_ime_fixture/AndroidManifest.xml').getroot()
        ns='{http://schemas.android.com/apk/res/android}'
        service=manifest.find('application/service')
        self.assertEqual(service.get(ns+'permission'),'android.permission.BIND_INPUT_METHOD')
        self.assertTrue((Path(__file__).parents[1]/'android/app/src/main/AndroidManifest.xml').exists())
        # Test keyboard must never be merged into the release app manifest.
        self.assertNotIn('AcceptanceIme',(Path(__file__).parents[1]/'android/app/src/main/AndroidManifest.xml').read_text())

if __name__=='__main__':unittest.main()
