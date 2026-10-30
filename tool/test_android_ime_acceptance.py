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
                      for text in ['سَ','سَلَامٌ',' English',' 123٤٥٦',ime.MULTILINE])
        return events

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
