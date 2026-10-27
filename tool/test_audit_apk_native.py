"""Synthetic packaging tests; only the workflow's real APK is production proof."""
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

from audit_apk_native import ABIS, EXPORTS, FONT_ASSET, audit, library_info


def elf(abi, *, symbols=EXPORTS, defined=1, visibility=0):
    cls, machine = ABIS[abi]
    header_size, section_size, symbol_size = (64, 64, 24) if cls == 2 else (52, 40, 16)
    strings = b'\0'
    table = bytes(symbol_size)
    for name in sorted(symbols):
        offset = len(strings)
        strings += name.encode() + b'\0'
        table += (struct.pack('<IBBHQQ', offset, 0x12, visibility, defined, 0, 0) if cls == 2
            else struct.pack('<IIIBBH', offset, 0, 0, 0x12, visibility, defined))
    header = bytearray(header_size)
    header[:6] = b'\x7fELF' + bytes([cls, 1])
    struct.pack_into('<H', header, 18, machine)
    section_offset = header_size + len(strings) + len(table)
    if cls == 2:
        struct.pack_into('<Q', header, 40, section_offset)
        struct.pack_into('<HH', header, 58, section_size, 3)
        fmt = '<IIQQQQIIQQ'
    else:
        struct.pack_into('<I', header, 32, section_offset)
        struct.pack_into('<HH', header, 46, section_size, 3)
        fmt = '<IIIIIIIIII'
    sections = bytes(section_size)
    sections += struct.pack(fmt, 0, 11, 0, 0, header_size + len(strings), len(table), 2, 0, 1, symbol_size)
    sections += struct.pack(fmt, 0, 3, 0, 0, header_size, len(strings), 0, 0, 1, 0)
    return bytes(header) + strings + table + sections


class ApkAuditTest(unittest.TestCase):
    def test_all_expected_abi_dynamic_exports(self):
        for abi in ABIS:
            self.assertEqual(set(library_info(elf(abi), abi)['requiredExports']), EXPORTS)

    def test_wrong_architecture_is_not_success(self):
        with self.assertRaisesRegex(ValueError, 'class/machine'):
            library_info(elf('arm64-v8a'), 'armeabi-v7a')

    def test_missing_function_is_not_incidental_string_success(self):
        with self.assertRaisesRegex(ValueError, 'missing defined'):
            library_info(elf('arm64-v8a', symbols=EXPORTS - {'writing_shape'}) + b'writing_shape', 'arm64-v8a')

    def test_undefined_functions_are_not_exports(self):
        with self.assertRaisesRegex(ValueError, 'missing defined'):
            library_info(elf('x86_64', defined=0), 'x86_64')

    def test_hidden_functions_are_not_public(self):
        with self.assertRaisesRegex(ValueError, 'missing defined'):
            library_info(elf('x86_64', visibility=2), 'x86_64')

    def test_real_zip_inventory_and_original_font_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            font, apk = root / 'font.ttf', root / 'app.apk'
            font.write_bytes(b'pinned source font fixture')
            def make(bundled, missing=None):
                with zipfile.ZipFile(apk, 'w') as archive:
                    archive.writestr(FONT_ASSET, bundled)
                    for abi in ABIS:
                        archive.writestr(f'lib/{abi}/libflutter.so', b'engine fixture')
                        if abi != missing:
                            archive.writestr(f'lib/{abi}/libwriting_harfbuzz.so', elf(abi))
            make(font.read_bytes())
            report = audit(apk, font)
            self.assertEqual(set(report['libraries']), set(ABIS))
            self.assertFalse(report['deviceLaunchVerified'])
            make(b'changed font')
            with self.assertRaisesRegex(ValueError, 'source bytes changed'):
                audit(apk, font)
            make(font.read_bytes(), missing='armeabi-v7a')
            with self.assertRaisesRegex(ValueError, 'ABI inventory'):
                audit(apk, font)


if __name__ == '__main__':
    unittest.main()
