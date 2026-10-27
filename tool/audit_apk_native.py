"""Fail if a successful release APK lacks the pinned shaper/face for a Flutter ABI.

Static package/ELF inspection only, NOT a device launch or Android rendering test.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import zipfile

ABIS = {'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183), 'x86_64': (2, 62)}
EXPORTS = {'writing_font_create', 'writing_font_destroy', 'writing_shape', 'writing_glyphs_free'}
FONT_ASSET = 'assets/flutter_assets/assets/fonts/Amiri-Regular.ttf'


def library_info(raw, abi):
    if len(raw) < 64 or raw[:4] != b'\x7fELF' or raw[5] != 1:
        raise ValueError(f'{abi}: not a little-endian ELF')
    cls, machine = raw[4], struct.unpack_from('<H', raw, 18)[0]
    if (cls, machine) != ABIS[abi]:
        raise ValueError(f'{abi}: incorrect ELF class/machine: {cls}/{machine}')
    if cls == 2:
        offset = struct.unpack_from('<Q', raw, 40)[0]
        stride, count = struct.unpack_from('<HH', raw, 58)
        section_format, symbol_format = '<IIQQQQIIQQ', '<IBBHQQ'
    else:
        offset = struct.unpack_from('<I', raw, 32)[0]
        stride, count = struct.unpack_from('<HH', raw, 46)
        section_format, symbol_format = '<IIIIIIIIII', '<IIIBBH'
    sections = [struct.unpack_from(section_format, raw, offset + stride * i) for i in range(count)]
    exports = set()
    for section in sections:
        if section[1] != 11:  # SHT_DYNSYM, not an incidental string in the file.
            continue
        names = sections[section[6]]
        strings = raw[names[4]:names[4] + names[5]]
        entry_size = section[9]
        if entry_size < struct.calcsize(symbol_format):
            raise ValueError(f'{abi}: invalid dynamic symbol stride')
        for position in range(section[4], section[4] + section[5], entry_size):
            symbol = struct.unpack_from(symbol_format, raw, position)
            name = symbol[0]
            info, other, defined = symbol[1:4] if cls == 2 else symbol[3:6]
            if info >> 4 not in (1, 2) or info & 15 != 2 or other & 3 not in (0, 3) or not defined:
                continue
            end = strings.find(b'\0', name)
            if end < 0:
                raise ValueError(f'{abi}: unterminated symbol')
            exports.add(strings[name:end].decode('ascii'))
    if not EXPORTS <= exports:
        raise ValueError(f'{abi}: missing defined public C ABI functions: {sorted(EXPORTS - exports)}')
    return dict(elfClass=cls, machine=machine, requiredExports=sorted(EXPORTS),
        bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def audit(apk, font):
    with zipfile.ZipFile(apk) as archive:
        damaged = archive.testzip()
        if damaged:
            raise ValueError(f'APK CRC failure: {damaged}')
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate APK entries')
        flutter_abis = {name.split('/')[1] for name in names if name.endswith('/libflutter.so')}
        shaper_abis = {name.split('/')[1] for name in names if name.endswith('/libwriting_harfbuzz.so')}
        if flutter_abis != set(ABIS) or shaper_abis != flutter_abis:
            raise ValueError(f'Missing/mismatched ABI inventory: Flutter={flutter_abis}, shaper={shaper_abis}')
        bundled = archive.read(FONT_ASSET)
        if bundled != font.read_bytes():
            raise ValueError('Bundled Amiri source bytes changed')
        libraries = {abi: library_info(archive.read(f'lib/{abi}/libwriting_harfbuzz.so'), abi) for abi in sorted(ABIS)}
    return dict(sourceSha=os.environ.get('GITHUB_SHA'), sourceRun=os.environ.get('GITHUB_RUN_ID'),
        apk=apk.name, apkBytes=apk.stat().st_size, apkSha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
        fontSha256=hashlib.sha256(bundled).hexdigest(), libraries=libraries,
        deviceLaunchVerified=False, limitation='Static package/ELF proof, not Android runtime or visual parity.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--font', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        report = dict(audit(args.apk, args.font), auditPassed=True)
    except Exception as error:
        # A rejected APK is evidence too. Keep the gate failing, but preserve
        # the exact causal error and package identity through the same audited
        # transport instead of relying on inaccessible signed runner-log URLs.
        report = dict(sourceSha=os.environ.get('GITHUB_SHA'),
            sourceRun=os.environ.get('GITHUB_RUN_ID'), auditPassed=False,
            errorType=type(error).__name__, error=str(error),
            deviceLaunchVerified=False,
            apkSha256=hashlib.sha256(args.apk.read_bytes()).hexdigest() if args.apk.is_file() else None)
        args.output.write_text(json.dumps(report, indent=2))
        message = str(error).replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print('::error title=APK native package audit failure::' + message, flush=True)
        raise
    args.output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, separators=(',', ':')))
