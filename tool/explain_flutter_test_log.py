"""Turn a `flutter test --reporter json` log into readable check annotations.

The visual job's probe runs inside a JSON reporter, so anything the test prints
is wrapped in JSON events and never reaches the runner as a workflow command.
When a probe fails, the only readable trace is therefore the log it tees; this
tool lifts the error messages out of it and prints them as annotations, so a
failing diagnostic explains itself instead of just reporting exit code 1.

Usage: python3 tool/explain_flutter_test_log.py <log> [<log> ...]
"""
import json
import pathlib
import sys

MESSAGE_LIMIT = 900


def _escape(text: str) -> str:
    return text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def plain_lines(path: pathlib.Path):
    # A non-JSON log (plain reporter, or a compiler that printed before the
    # reporter started) still carries the reason; surface it.
    for line in path.read_text(errors='replace').splitlines():
        stripped = line.strip()
        if stripped.startswith('{'):
            continue
        if stripped and ('Error:' in stripped or 'error:' in stripped):
            yield stripped


def events(path: pathlib.Path):
    for line in path.read_text(errors='replace').splitlines():
        line = line.strip()
        if not line.startswith('{'):
            continue
        try:
            yield json.loads(line)
        except json.JSONDecodeError:
            continue


def summarise(path: pathlib.Path) -> int:
    problems = 0
    names = {}
    for event in events(path):
        kind = event.get('type')
        if kind == 'testStart':
            test = event.get('test') or {}
            names[test.get('id')] = test.get('name', '?')
        elif kind == 'error':
            problems += 1
            name = names.get(event.get('testID'), '?')
            message = ' '.join(
                str(event.get(key) or '') for key in ('error', 'stackTrace')
            ).strip()
            print(
                f"::error title={_escape(f'{path.name}: {name}')}::"
                + _escape(message[:MESSAGE_LIMIT])
            )
        elif kind == 'testDone' and event.get('result') == 'error':
            problems += 1
            print(
                '::error title='
                + _escape(f'{path.name}: {names.get(event.get("testID"), "?")}')
                + '::test reported error; see the message annotation'
            )
        elif kind == 'print':
            message = str(event.get('message'))
            if 'ELEMENT-GEOMETRY' in message:
                print('::warning title=ELEMENT-GEOMETRY::' + _escape(message[:MESSAGE_LIMIT]))
            elif 'rror' in message and problems < 12:
                problems += 1
                print('::error title=' + _escape(path.name) + '::' + _escape(message[:MESSAGE_LIMIT]))
    return problems


def main(argv) -> int:
    seen = 0
    for raw in argv:
        path = pathlib.Path(raw)
        if not path.is_file():
            print(f'::notice title={_escape(path.name)}::log not produced')
            continue
        seen += summarise(path)
        for line in list(plain_lines(path))[:12]:
            seen += 1
            print('::error title=' + _escape(path.name) + '::' + _escape(line[:MESSAGE_LIMIT]))
    print(f'::notice title=probe log::parsed {len(argv)} log(s), {seen} problem event(s)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
