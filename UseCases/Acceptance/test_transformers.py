"""What each status means, the same for every transformer (chapter 10 §13), proven on the bundled ones
with synthetic reports: a retried test counts by its final attempt, an expected failure is incomplete,
and a skip is incomplete.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_transformers.py -v
"""

import json
import os
import subprocess

import pytest
from conftest import problems, transformer_argv

KEY = "demo.a#unit-tests.t@tests/test_a.py:3"


def run(transformer, tmp_path, report_name, report, settings=None, source=None):
    code = tmp_path / "code"
    (code / "tests").mkdir(parents=True)
    (code / "tests" / "test_a.py").write_text(source or "import x\n\ndef test_a():\n    pass\n")
    report_path = tmp_path / report_name
    report_path.write_text(report)
    link = {"key": KEY, "source": "marker", "use_case": "demo.a", "route": "unit-tests", "binding": "t", "role": "validation",
            "file": "tests/test_a.py", "range": {"start": 3, "end": 4}}
    request = {"contract": 1, "job": "results", "use_cases": [], "links": [link], "code_root": str(code),
               "output": {"report_path": str(report_path), "exit_code": None, "working_dir": "."}, "settings": settings or {}}
    (tmp_path / "request.json").write_text(json.dumps(request))
    assert not problems("transformer-results-request.schema.json", request, "request")
    subprocess.run([*transformer_argv(transformer), "results", str(tmp_path / "request.json"), str(tmp_path / "response.json")],
                   check=True)
    response = json.loads((tmp_path / "response.json").read_text())
    assert not problems("transformer-results-response.schema.json", response, "response")  # exactly the published shape
    results = response["results"]
    return [r["status"] for r in results if r["link"] == KEY]


def junit(cases):
    return f'<?xml version="1.0"?><testsuite name="s">{cases}</testsuite>'


FILE_LINE = {"find": "file-line", "line_base": 0}


@pytest.mark.parametrize("cases, expected", [
    # a retry plugin (Gradle test-retry, pytest-rerunfailures) writes the test again: the final attempt decides
    ('<testcase classname="t" name="test_a" file="tests/test_a.py" line="2"><failure/></testcase>'
     '<testcase classname="t" name="test_a" file="tests/test_a.py" line="2"/>', "pass"),
    ('<testcase classname="t" name="test_a" file="tests/test_a.py" line="2"/>'
     '<testcase classname="t" name="test_a" file="tests/test_a.py" line="2"><failure/></testcase>', "fail"),
    # Surefire records a flaky pass inside one testcase: it passed in the end
    ('<testcase classname="t" name="test_a" file="tests/test_a.py" line="2"><flakyFailure message="x"/></testcase>', "pass"),
    # pytest xfail: an expected failure is not a pass
    ('<testcase classname="t" name="test_a" file="tests/test_a.py" line="2"><skipped type="pytest.xfail" message="xfail"/></testcase>',
     "incomplete"),
    ('<testcase classname="t" name="test_a" file="tests/test_a.py" line="2"><skipped message="not on this platform"/></testcase>',
     "incomplete"),
])
def test_junit_follows_the_status_rules(tmp_path, cases, expected):
    assert run("junit", tmp_path, "report.xml", junit(cases), FILE_LINE) == [expected]


def swift_events(issue_known, code_root):
    test = {"kind": "test", "payload": {"kind": "function", "id": "M.t()",
            "sourceLocation": {"_filePath": os.path.join(code_root, "tests", "test_a.py"), "line": 3}}}
    issue = {"kind": "event", "payload": {"kind": "issueRecorded", "testID": "M.t()", "issue": {"isKnown": issue_known}}}
    ended = {"kind": "event", "payload": {"kind": "testEnded", "testID": "M.t()"}}
    return [test, issue, ended]


@pytest.mark.parametrize("known, expected", [(True, "incomplete"), (False, "fail")])
def test_swift_testing_treats_a_known_issue_as_an_expected_failure(tmp_path, known, expected):
    code_root = str(tmp_path / "code")
    lines = [json.dumps(e) for e in swift_events(known, code_root)]
    assert run("swift-testing", tmp_path, "events.jsonl", "\n".join(lines) + "\n") == [expected]
