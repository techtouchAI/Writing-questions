#!/usr/bin/env python3
"""Digest `flutter test --reporter json` output into CI-friendly artifacts.

Why this exists: GitHub truncates every check-run annotation at 4 KiB, and the
test suites print thousands of lines. Grepping the expanded reporter output
for failure markers is fragile (emoji/format drift) and silently drops most
failures. The JSON reporter is a stable machine protocol, so this tool parses
it and emits:

  counts.txt           machine-readable totals (one line)
  failing.txt          every failing test as "<file> :: <name>" (sorted)
  excerpt_<i>.txt      per-failure error text (each <= ~3 KiB, annotation-safe)
  p0_<id>.txt          failing P0-GATE-<id> tests (same excerpt format)
  compile_errors.txt   suite load failures (compiler errors), if any
  fixture_timeline.txt every "[fixture]" print, in order (visual job)
  p0gate_timeline.txt  every "[p0-gate]" print, in order (export gate)
  diag.txt             every "[diag]" print, in order (ad-hoc printf debugging)
  summary.md           human-readable digest for the step summary / artifacts

The tool never fails the build: it always exits 0 and writes best-effort
outputs (plus an "unparsed" note) even when the log is not valid JSON.

Local verification (no Flutter needed):
  python3 tool/flutter_test_digest.py --self-test
"""
import json
import os
import re
import sys

# Annotation-safe ceiling: GitHub truncates messages at 4 KiB, so every
# emitted excerpt stays comfortably below that (measured in UTF-8 bytes).
MAX_EXCERPT_BYTES = 3000
MAX_STACK_LINES = 8
MAX_ERRORS_PER_TEST = 3
MAX_PRINT_LINES_PER_TEST = 200
MAX_PRINT_BYTES_IN_EXCERPT = 1200
P0_PATTERN = re.compile(r"P0-GATE-([0-9A-Z]+)")


def _truncate_bytes(text, limit):
    """Truncate to whole UTF-8 characters under `limit` bytes."""
    encoded = text.encode("utf-8")
    if len(encoded) <= limit:
        return text
    cut = encoded[:limit]
    while cut:
        try:
            return cut.decode("utf-8")
        except UnicodeDecodeError:
            cut = cut[:-1]
    return ""


class Digest:
    def __init__(self):
        self.suites = {}  # suite id -> file path
        self.tests = {}  # test id -> {"name":..., "suite":..., "skipped":..., "file":...}
        self.results = {}  # test id -> result string
        self.errors = {}  # test id -> list of (error, stackTrace)
        self.prints = {}  # test id -> console lines (flutter dumps failures here)
        self.prints_dropped = {}  # test id -> lines dropped past the cap
        self.start_times = {}  # test id -> testStart time (ms)
        self.durations = {}  # test id -> seconds between start and done
        self.lines_total = 0
        self.lines_json = 0
        self.done_success = None
        self.timelines = {"fixture": [], "p0-gate": [], "diag": []}

    def suite_file(self, test_id):
        info = self.tests.get(test_id, {})
        return info.get("file") or info.get("suite") or "?"

    def test_name(self, test_id):
        return self.tests.get(test_id, {}).get("name", "test %s" % test_id)

    def handle(self, event):
        kind = event.get("type")
        if kind == "suite":
            suite = event.get("suite") or {}
            path = suite.get("path") or ""
            # Keep the repo-relative tail so annotations stay readable.
            path = re.sub(r"^.*/(test|integration_test|tool)/", r"\1/", path)
            self.suites[suite.get("id")] = path
        elif kind == "testStart":
            test = event.get("test") or {}
            metadata = test.get("metadata") or {}
            suite_id = test.get("suiteID")
            suite_path = self.suites.get(suite_id, "")
            url = test.get("url") or ""
            file_by_url = re.sub(r"^file://", "", url)
            file_by_url = re.sub(r"^.*/(test|integration_test|tool)/", r"\1/", file_by_url)
            # The suite path is authoritative: flutter_test reports test urls
            # such as package:flutter_test/src/widget_tester.dart for widget
            # tests, which would misattribute every failure.
            self.tests[test.get("id")] = {
                "name": test.get("name") or "",
                "suite": suite_path,
                "file": suite_path or file_by_url or "",
                "skipped": bool(metadata.get("skip")),
            }
            if test.get("id") is not None and isinstance(event.get("time"), (int, float)):
                self.start_times[test.get("id")] = event.get("time")
        elif kind == "testDone":
            test_id = event.get("testID")
            if test_id is not None and test_id not in self.results:
                self.results[test_id] = event.get("result") or "unknown"
                start = self.start_times.get(test_id)
                end = event.get("time")
                if (isinstance(start, (int, float)) and
                        isinstance(end, (int, float)) and end >= start):
                    self.durations[test_id] = (end - start) / 1000.0
        elif kind == "error":
            test_id = event.get("testID")
            # Uncapped: excerpts show the first few and note the rest. The
            # first event is often the generic "See exception logs above"
            # while the actionable message arrives in a later event.
            self.errors.setdefault(test_id, []).append((
                str(event.get("error") or ""),
                str(event.get("stackTrace") or ""),
            ))
        elif kind == "print":
            message = str(event.get("message") or "")
            test_id = event.get("testID")
            if test_id is not None:
                bucket = self.prints.setdefault(test_id, [])
                for line in message.splitlines() or [""]:
                    if len(bucket) < MAX_PRINT_LINES_PER_TEST:
                        bucket.append(line)
                    else:
                        self.prints_dropped[test_id] = \
                            self.prints_dropped.get(test_id, 0) + 1
            for line in message.splitlines() or [""]:
                for key in self.timelines:
                    if "[%s]" % key in line:
                        self.timelines[key].append(line.strip())
                        break
        elif kind == "done":
            self.done_success = event.get("success")

    def failures(self):
        """(test_id, is_load_failure) for every non-passing test, stable order."""
        out = []
        for test_id, result in self.results.items():
            if result in ("failure", "error"):
                name = self.test_name(test_id)
                out.append((test_id, name.startswith("loading ")))
        out.sort(key=lambda item: (self.suite_file(item[0]), self.test_name(item[0])))
        return out

    def failure_line(self, test_id, is_load):
        line = "%s :: %s" % (self.suite_file(test_id), self.test_name(test_id))
        if test_id in self.durations:
            line += " [%.1fs]" % self.durations[test_id]
        if is_load:
            line += " (LOAD FAILURE)"
        return line

    def counts(self):
        passed = failed = skipped = 0
        for test_id, result in self.results.items():
            if result == "success":
                if self.tests.get(test_id, {}).get("skipped"):
                    skipped += 1
                else:
                    passed += 1
            elif result in ("failure", "error"):
                failed += 1
        return passed, failed, skipped


def parse_stream(lines):
    digest = Digest()
    for raw in lines:
        digest.lines_total += 1
        line = raw.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if not isinstance(event, dict) or "type" not in event:
            continue
        digest.lines_json += 1
        digest.handle(event)
    return digest


def excerpt_text(digest, test_id):
    lines = [
        "FILE: %s" % digest.suite_file(test_id),
        "TEST: %s" % digest.test_name(test_id),
    ]
    errors = digest.errors.get(test_id) or []
    if not errors:
        lines.append("ERROR: (no error event captured)")
    numbered = len(errors) > 1
    for number, (error, stack) in enumerate(errors[:MAX_ERRORS_PER_TEST], start=1):
        lines.append("ERROR %d:" % number if numbered else "ERROR:")
        lines.append((error or "").strip() or "(empty)")
        if number == 1:
            stack_lines = [ln for ln in (stack or "").splitlines() if ln.strip()]
            if stack_lines:
                lines.append("STACK:")
                lines.extend(stack_lines[:MAX_STACK_LINES])
    if len(errors) > MAX_ERRORS_PER_TEST:
        lines.append("(+%d more error events)" % (len(errors) - MAX_ERRORS_PER_TEST))
    text = "\n".join(lines) + "\n"
    # flutter_test prints the actionable failure ("EXCEPTION CAUGHT BY ...")
    # to the console and reports only "See exception logs above", so the
    # test's own console tail carries the diagnosis.
    prints = digest.prints.get(test_id) or []
    if prints:
        tail = []
        tail_bytes = 0
        for line in reversed(prints):
            line_bytes = len(line.encode("utf-8")) + 1
            if tail_bytes + line_bytes > MAX_PRINT_BYTES_IN_EXCERPT:
                break
            tail.append(line)
            tail_bytes += line_bytes
        tail.reverse()
        omitted = len(prints) - len(tail) + digest.prints_dropped.get(test_id, 0)
        text += "PRINTS (last %d%s):\n" % (
            len(tail), ", +%d earlier" % omitted if omitted else "")
        if tail:
            text += "\n".join(tail) + "\n"
    return _truncate_bytes(text, MAX_EXCERPT_BYTES)


def write_digest(digest, out_dir):
    os.makedirs(out_dir, exist_ok=True)

    def write(name, text):
        with open(os.path.join(out_dir, name), "w", encoding="utf-8") as handle:
            handle.write(text)

    passed, failed, skipped = digest.counts()
    parsed_ok = digest.lines_json > 0
    success = digest.done_success
    if success is None:
        success = parsed_ok and failed == 0
    write("counts.txt", "passed=%d failed=%d skipped=%d suites=%d success=%s parsed_events=%d\n" % (
        passed, failed, skipped, len(digest.suites),
        "true" if success else "false", digest.lines_json))

    failures = digest.failures()
    write("failing.txt", "".join(
        digest.failure_line(tid, load) + "\n" for tid, load in failures))

    for index, (test_id, _) in enumerate(failures, start=1):
        write("excerpt_%03d.txt" % index, excerpt_text(digest, test_id))

    seen_p0 = set()
    for test_id, _ in failures:
        match = P0_PATTERN.search(digest.test_name(test_id))
        if not match or match.group(1) in seen_p0:
            continue
        seen_p0.add(match.group(1))
        write("p0_%s.txt" % match.group(1), excerpt_text(digest, test_id))

    load_failures = [(tid, digest.errors.get(tid) or []) for tid, load in failures if load]
    compile_text = ""
    for test_id, errors in load_failures:
        compile_text += "SUITE-LOAD: %s :: %s\n" % (
            digest.suite_file(test_id), digest.test_name(test_id))
        for error, _ in errors[:1]:
            compile_text += error.strip() + "\n\n"
    write("compile_errors.txt", _truncate_bytes(compile_text, MAX_EXCERPT_BYTES))

    write("fixture_timeline.txt", "".join(
        line + "\n" for line in digest.timelines["fixture"]))
    write("p0gate_timeline.txt", "".join(
        line + "\n" for line in digest.timelines["p0-gate"]))
    write("diag.txt", "".join(
        line + "\n" for line in digest.timelines["diag"]))

    summary = ["# Test digest", "",
               "passed=%d failed=%d skipped=%d suites=%d success=%s" % (
                   passed, failed, skipped, len(digest.suites),
                   "true" if success else "false"), ""]
    if not parsed_ok:
        summary += ["The test log contained no JSON reporter events "
                    "(%d raw lines); the run probably failed before tests "
                    "started. See the raw log artifact." % digest.lines_total, ""]
    if failures:
        summary += ["## Failing tests (%d)" % len(failures), ""]
        for test_id, load in failures:
            summary.append("- `%s`" % digest.failure_line(test_id, load))
        summary.append("")
        summary += ["## First errors (up to 8)", ""]
        for test_id, _ in failures[:8]:
            summary.append("### %s" % digest.test_name(test_id))
            summary.append("")
            summary.append("```")
            errors = digest.errors.get(test_id) or []
            first = errors[0][0].strip() if errors else "(no error event)"
            summary.append(_truncate_bytes(first, 1500))
            summary.append("```")
            summary.append("")
    if digest.timelines["diag"]:
        summary += ["## Diagnostics ([diag], %d lines)" % len(digest.timelines["diag"]), "",
                    "```", *_truncate_bytes(
                        "\n".join(digest.timelines["diag"]), 6000).splitlines(),
                    "```", ""]
    write("summary.md", "\n".join(summary))


SAMPLE_LOG = """\
{"type":"start","time":0,"protocolVersion":"0.1.1"}
{"type":"allSuites","time":1,"count":2}
{"type":"suite","time":2,"suite":{"id":0,"platform":"vm","path":"/home/runner/work/x/test/ok_test.dart"}}
{"type":"suite","time":3,"suite":{"id":1,"platform":"vm","path":"/home/runner/work/x/test/widget/canvas_test.dart"}}
{"type":"group","time":4,"group":{"id":2,"suiteID":0,"name":"","metadata":{},"testCount":1}}
{"type":"testStart","time":5,"test":{"id":3,"name":"ok adds numbers","suiteID":0,"groupIDs":[2],"metadata":{"skip":false},"line":7,"column":3,"url":"file:///home/runner/work/x/test/ok_test.dart"}}
{"type":"testDone","time":9,"testID":3,"result":"success","hidden":false}
{"type":"group","time":10,"group":{"id":4,"suiteID":1,"name":"رسم المعادلات","metadata":{},"testCount":2}}
{"type":"testStart","time":11,"test":{"id":5,"name":"رسم المعادلات Math واحد لكل مقطع","suiteID":1,"groupIDs":[4],"metadata":{"skip":false},"line":100,"column":5,"url":"package:flutter_test/src/widget_tester.dart"}}
{"type":"print","time":12,"testID":5,"messageType":"print","message":"[diag] math widgets: 0"}
{"type":"print","time":12,"testID":5,"messageType":"print","message":"EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK"}
{"type":"error","time":13,"testID":5,"error":"Expected: exactly 7 matching candidates\\n  Actual: Found 0 widgets","stackTrace":"#4 main.<anonymous closure> (file:///home/runner/work/x/test/widget/canvas_test.dart:114:7)\\n#5 testWidgets.<anonymous closure>","isFailure":true}
{"type":"error","time":13,"testID":5,"error":"Test failed. See exception logs above.","stackTrace":"","isFailure":true}
{"type":"testDone","time":14,"testID":5,"result":"failure","hidden":false}
{"type":"testStart","time":15,"test":{"id":6,"name":"loading test/widget/broken_test.dart","suiteID":1,"groupIDs":[4],"metadata":{"skip":false},"line":0,"column":0,"url":"file:///home/runner/work/x/test/widget/broken_test.dart"}}
{"type":"error","time":16,"testID":6,"error":"Failed to load test/widget/broken_test.dart: lib/x.dart:10:3: Error: Undefined name 'foo'.","stackTrace":"","isFailure":false}
{"type":"testDone","time":17,"testID":6,"result":"error","hidden":false}
{"type":"print","time":18,"messageType":"print","message":"[fixture] Editable DOCX: attachment formula-1:started"}
not-json tool banner here
{"type":"done","time":19,"success":false}
"""


def self_test():
    import tempfile
    failures = []
    total = [0]

    def check(label, condition):
        total[0] += 1
        print(("PASS " if condition else "FAIL ") + label)
        if not condition:
            failures.append(label)

    digest = parse_stream(SAMPLE_LOG.splitlines())
    check("parses mixed json/plain lines", digest.lines_json == 19 and digest.lines_total == 20)
    passed, failed, skipped = digest.counts()
    check("counts passed/failed", (passed, failed, skipped) == (1, 2, 0))
    check("done success=false", digest.done_success is False)
    failing = digest.failures()
    check("two failures in file order",
          [digest.test_name(t) for t, _ in failing] == [
              "loading test/widget/broken_test.dart",
              "رسم المعادلات Math واحد لكل مقطع"])
    check("load failure flagged", failing[0][1] is True and failing[1][1] is False)
    check("diag timeline captured", digest.timelines["diag"] == ["[diag] math widgets: 0"])
    check("runner-level print captured",
          digest.timelines["fixture"] == ["[fixture] Editable DOCX: attachment formula-1:started"])

    with tempfile.TemporaryDirectory() as tmp:
        write_digest(digest, tmp)
        names = sorted(os.listdir(tmp))
        for expected in ("counts.txt", "failing.txt", "excerpt_001.txt",
                         "excerpt_002.txt", "compile_errors.txt",
                         "fixture_timeline.txt", "p0gate_timeline.txt",
                         "diag.txt", "summary.md"):
            check("writes " + expected, expected in names)
        counts = open(os.path.join(tmp, "counts.txt"), encoding="utf-8").read().strip()
        check("counts line", counts.startswith("passed=1 failed=2 skipped=0"))
        excerpt = open(os.path.join(tmp, "excerpt_002.txt"), encoding="utf-8").read()
        check("excerpt has file/test/error/stack",
              all(token in excerpt for token in (
                  "test/widget/canvas_test.dart",
                  "Math واحد لكل مقطع",
                  "Expected: exactly 7",
                  "canvas_test.dart:114")))
        check("file prefers suite path over package: url",
              "FILE: test/widget/canvas_test.dart" in excerpt)
        check("excerpt includes later error events",
              "ERROR 2:" in excerpt and "See exception logs above" in excerpt)
        check("excerpt includes the test console tail",
              "EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK" in excerpt)
        failing_text = open(os.path.join(tmp, "failing.txt"), encoding="utf-8").read()
        check("failing lines carry durations", "[0.0s]" in failing_text)
        check("excerpt within annotation budget",
              len(excerpt.encode("utf-8")) <= MAX_EXCERPT_BYTES)
        compile_errors = open(os.path.join(tmp, "compile_errors.txt"), encoding="utf-8").read()
        check("compile error captured", "Undefined name 'foo'" in compile_errors)
        summary = open(os.path.join(tmp, "summary.md"), encoding="utf-8").read()
        check("summary lists failures", "Failing tests (2)" in summary)

    empty = parse_stream(["plain banner", "another line"])
    check("unparsed log tolerated",
          empty.lines_json == 0 and empty.counts() == (0, 0, 0))
    print("SELF-TEST %s (%d checks, %d failed)" % (
        "FAILED" if failures else "PASSED", total[0], len(failures)))
    return 1 if failures else 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    log_path = None
    out_dir = None
    args = iter(argv[1:])
    for arg in args:
        if arg == "--log":
            log_path = next(args, None)
        elif arg == "--out":
            out_dir = next(args, None)
    if not log_path or not out_dir:
        sys.stderr.write("usage: flutter_test_digest.py --log FILE --out DIR\n")
        return 2
    try:
        with open(log_path, encoding="utf-8", errors="replace") as handle:
            digest = parse_stream(handle)
    except OSError as error:
        digest = parse_stream([])
        digest.timelines["diag"].append("[diag] cannot read log: %s" % error)
    # Never fail the build from diagnostics.
    try:
        write_digest(digest, out_dir)
    except OSError as error:
        sys.stderr.write("digest write failed: %s\n" % error)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
