"""Helpers ring: transformers are programs in any language, links can come from a naming
convention instead of markers, a whole script can be a check, and commands run where told.

A small JavaScript project is built per test. Needs node. Run from the repository root:

    uv run --with pyyaml --with pytest pytest UseCases/Acceptance/test_helpers.py -v
"""

import json
import os
import subprocess
import sys

import pytest
from conftest import SENTINEL, POSIX_ONLY, windows_launcher, call_core, COMMAND, transformer_program, record_exchanges

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

USE_CASES = """
prefix: math
use_cases:
  - id: add
    title: Add numbers
    value_tier: core
    intent: Two numbers add up.
    scenarios:
      - id: adds
        when: [Add two numbers.]
        then: [The sum is returned.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [adds]
  - id: divide
    title: Divide numbers
    value_tier: core
    intent: One number divides another.
    scenarios:
      - id: divides
        when: [Divide two numbers.]
        then: [The quotient is returned.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [divides]
  - id: style
    title: Code style
    value_tier: supporting
    intent: The code follows the house style.
    scenarios:
      - id: clean
        when: [Check the code.]
        then: [No style problems are found.]
    validation:
      - id: checks
        type: { kind: custom, name: style-check }
        covers: [clean]
        bindings:
          - id: script
            kind: manual
            locator: { file: scripts/check.sh }
"""

TESTS = """import { test } from "node:test";
import assert from "node:assert/strict";
import { add, divide } from "../src/math.js";

test("demo.math.add#unit-tests.adds-numbers", () => {
  assert.equal(add(2, 3), 5);
});

test("demo.math.divide#unit-tests.divides", () => {
  assert.equal(divide(6, 3), 2);
});
"""

BRIDGE = """schema_version: 1
links:
  - transformer: test-names
    settings:
      files: "test/**/*.js"
      pattern: 'test\\("(?P<id>[^"]+)"'
      block: braces
validations:
  - id: unit-tests
    report: unit.xml
    run: [node, --test, --test-reporter=junit, "--test-reporter-destination={report}"]
    transformer: junit
    settings:
      find: pattern
      files: "test/**/*.js"
      patterns: ['"{name}"']
  - id: style
    report: style.txt
    run: [sh, -c, 'sh scripts/check.sh > "$1"', sh, "{report}"]
    transformer: exit-code
    settings:
      file: scripts/check.sh
"""

FILES = {
    "use-cases.yml": "schema_version: 1\nroot: true\nprefix: demo\n",
    "use-cases/math.yml": USE_CASES,
    "use-cases-bridge.yml": BRIDGE,
    "package.json": '{ "type": "module" }\n',
    "src/math.js": "export const add = (a, b) => a + b;\nexport const divide = (a, b) => a / b;\n",
    "test/math.test.js": TESTS,
    "scripts/check.sh": 'if [ -e FAIL ]; then echo "style problems"; exit 1; fi\necho clean\n',
}


def uc(ws, *args, expect_exit=0):
    return call_core(ws, *args, expect_exit=expect_exit)


def status(ws):
    return {u["use_case"]: u["status"] for u in uc(ws, "status")["use_cases"]}


def didnt_run(run):
    return {d["use_case"] for d in run["diagnostics"] if isinstance(d, dict) and d.get("problem") == "its test didn't run"}


def node_tests(ws, started, *extra):
    """Your own test step: the tests write their report where `--start` said."""
    subprocess.run(["node", "--test", *extra, "--test-reporter=junit",
                    f"--test-reporter-destination={started['reports']['unit-tests']}"], cwd=ws, capture_output=True)


def style_check(ws, started):
    subprocess.run(["sh", "-c", 'sh scripts/check.sh > "$1"', "sh", started["reports"]["style"]], cwd=ws)


def replace(ws, rel, old, new):
    path = os.path.join(ws, rel)
    with open(path) as handle:
        text = handle.read()
    assert text.count(old) == 1
    with open(path, "w") as handle:
        handle.write(text.replace(old, new))


@pytest.fixture
def ws(tmp_path):
    root = tmp_path / "demo"
    for rel, content in FILES.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(content)
    return str(root)


# ------------------------------------------------------------------ links by naming convention


# @use-case:bridge.links-transformers#acceptance.test-names
def test_test_names_link_tests_without_any_markers(ws):
    links = {l["use_case"]: l for l in uc(ws, "links")["links"] if l["role"] == "validation" and l["file"].startswith("test/")}
    assert set(links) == {"demo.math.add", "demo.math.divide"}
    assert links["demo.math.add"]["source"] == "transformer"
    assert links["demo.math.add"]["range"] == {"start": 5, "end": 7}  # the whole test block, braces to braces
# @use-case:end bridge.links-transformers#acceptance.test-names


# @use-case:transformers.exit-code#acceptance.exit-code
# @use-case:verify.run#acceptance.one-command
def test_one_run_verifies_named_tests_and_a_script_check(ws):
    run = uc(ws, "verify", "--run")
    assert run["errors"] == []
    assert status(ws) == {"demo.math.add": "verified", "demo.math.divide": "verified", "demo.math.style": "verified"}
# @use-case:end verify.run#acceptance.one-command
# @use-case:end transformers.exit-code#acceptance.exit-code


# @use-case:links.moved-code#acceptance.renamed-test
def test_a_renamed_test_loses_its_link_and_its_use_case_never_passes(ws):
    replace(ws, "test/math.test.js", "demo.math.divide#unit-tests.divides", "divides six by three")
    run = uc(ws, "verify", "--run")
    assert status(ws)["demo.math.divide"] == "unverified"
    assert any("no validation links" in d["problem"] for d in run["diagnostics"]
               if isinstance(d, dict) and d.get("use_case") == "demo.math.divide")
# @use-case:end links.moved-code#acceptance.renamed-test


# @use-case:validate.checks-files-only#acceptance.warnings-never-fail
def test_a_name_for_an_unknown_use_case_is_only_a_warning(ws):
    replace(ws, "test/math.test.js", "demo.math.divide#unit-tests.divides", "demo.math.nope#unit-tests.divides")
    assert any("names no known use case" in d for d in uc(ws, "links")["diagnostics"])
# @use-case:end validate.checks-files-only#acceptance.warnings-never-fail


# ------------------------------------------------------------------ a whole script is the check


# @use-case:transformers.exit-code#acceptance.exit-code
def test_a_failing_script_fails_only_its_own_use_case(ws):
    open(os.path.join(ws, "FAIL"), "w").close()
    uc(ws, "verify", "--run")
    assert status(ws) == {"demo.math.add": "verified", "demo.math.divide": "verified", "demo.math.style": "failed"}
# @use-case:end transformers.exit-code#acceptance.exit-code


# @use-case:status.staleness#acceptance.linked-code
def test_editing_the_script_stales_its_verdict(ws):
    uc(ws, "verify", "--run")
    replace(ws, "scripts/check.sh", "echo clean", "echo all clean")
    assert status(ws)["demo.math.style"] == "stale"
# @use-case:end status.staleness#acceptance.linked-code


# @use-case:transformers.exit-code#acceptance.needs-run
def test_exit_code_gives_no_verdict_without_an_exit_code(ws):
    style_check(ws, uc(ws, "verify", "--start", "--only", "style"))
    run = uc(ws, "verify", "--finish")
    assert run["results"] == [] and "demo.math.style" in didnt_run(run)
    assert any("no exit code" in d for d in run["sources"][0]["diagnostics"])
# @use-case:end transformers.exit-code#acceptance.needs-run


# ------------------------------------------------------------------ start with --only


# @use-case:verify.start-finish#acceptance.only-at-start
def test_start_only_reads_only_what_it_started(ws):
    started = uc(ws, "verify", "--start", "--only", "unit-tests")
    assert started["selected"] == ["unit-tests"] and list(started["reports"]) == ["unit-tests"]
    node_tests(ws, started)
    run = uc(ws, "verify", "--finish")
    assert [s["id"] for s in run["sources"]] == ["unit-tests"] and run["errors"] == []
    assert status(ws) == {"demo.math.add": "verified", "demo.math.divide": "verified", "demo.math.style": "unverified"}
# @use-case:end verify.start-finish#acceptance.only-at-start


# @use-case:verify.open-runs#acceptance.two-open
def test_two_open_runs_must_be_named_and_never_touch_each_other(ws):
    first = uc(ws, "verify", "--start", "--only", "style")
    second = uc(ws, "verify", "--start", "--only", "unit-tests")
    assert first["run_id"] in second["notes"][-1]  # --start says what else is open; it closes nothing
    assert "name one with --run-id" in uc(ws, "verify", "--finish", expect_exit=2)
    node_tests(ws, second)
    run = uc(ws, "verify", "--finish", "--run-id", second["run_id"])
    assert run["run_id"] == second["run_id"] and run["errors"] == []
    aborted = uc(ws, "verify", "--abort")  # the one left open
    assert aborted == {"output_version": 1, "command": "verify", "step": "abort", "run_id": first["run_id"], "aborted": True}
    assert "no started run" in uc(ws, "verify", "--finish", expect_exit=2)
# @use-case:end verify.open-runs#acceptance.two-open


# @use-case:verify.start-finish#acceptance.bridge-changed
def test_finish_refuses_when_the_bridge_settings_changed_since_start(ws):
    uc(ws, "verify", "--start", "--only", "unit-tests")
    replace(ws, "use-cases-bridge.yml", "    report: unit.xml\n", "    report: other.xml\n")
    assert "changed for this run's validations since `--start`" in uc(ws, "verify", "--finish", expect_exit=2)
# @use-case:end verify.start-finish#acceptance.bridge-changed


# @use-case:verify.open-runs#acceptance.locked
def test_a_run_being_finished_cannot_be_finished_twice_at_once(ws, tmp_path):
    import time
    started = uc(ws, "verify", "--start", "--only", "style")
    write_program(ws, "tools/slow-exit-code", "#!/bin/sh\nsleep 2\nexec \"$UC_REAL\" \"$@\"\n")
    replace(ws, "use-cases-bridge.yml", "    transformer: exit-code\n", "    transformer: tools/slow-exit-code\n")
    os.environ["UC_REAL"] = transformer_program("exit-code", tmp_path / "launchers")
    try:
        # settings changed on purpose to slow the transformer, so restart to match
        uc(ws, "verify", "--abort", "--run-id", started["run_id"])
        started = uc(ws, "verify", "--start", "--only", "style")
        style_check(ws, started)
        first = subprocess.Popen([*COMMAND, "--workspace", ws, "--json", "verify", "--finish"], stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True)
        time.sleep(0.8)
        second = subprocess.run([*COMMAND, "--workspace", ws, "--json", "verify", "--finish"], capture_output=True, text=True)
        out, _ = first.communicate(timeout=30)
    finally:
        del os.environ["UC_REAL"]
    assert second.returncode == 2 and "being finished by another process" in second.stderr
    assert json.loads(out)["run_id"] == started["run_id"]
    uc(ws, "status")  # the store is intact
# @use-case:end verify.open-runs#acceptance.locked


# ------------------------------------------------------------------ where commands run


def set_working_dir(ws, working_dir):
    replace(ws, "use-cases-bridge.yml", "  - id: style\n", f"  - id: style\n    working_dir: {working_dir}\n")


# @use-case:verify.commands#acceptance.working-dir
def test_working_dir_is_where_the_command_runs(ws):
    set_working_dir(ws, "scripts")
    replace(ws, "use-cases-bridge.yml", "'sh scripts/check.sh > \"$1\"'", "'sh check.sh > \"$1\"'")
    uc(ws, "verify", "--run", "--only", "style")
    assert status(ws)["demo.math.style"] == "verified"
# @use-case:end verify.commands#acceptance.working-dir


# @use-case:verify.commands#acceptance.working-dir
@pytest.mark.parametrize("working_dir", ["..", "missing", ".use-cases", "/tmp"])
def test_working_dir_outside_the_project_is_refused(ws, working_dir):
    os.makedirs(os.path.join(ws, ".use-cases"), exist_ok=True)
    set_working_dir(ws, working_dir)
    error = uc(ws, "status", expect_exit=2)
    assert "working_dir must be an existing folder inside the project" in error or "is not allowed at validations/1/working_dir" in error
# @use-case:end verify.commands#acceptance.working-dir


# ------------------------------------------------------------------ transformers are programs; none is trusted


def write_program(ws, rel, body, executable=True):
    path = os.path.join(ws, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as handle:
        handle.write(body)
    if executable:
        os.chmod(path, 0o755)
        record_exchanges(path)
        windows_launcher(path, body)


def use_links_program(ws, rel):
    replace(ws, "use-cases-bridge.yml", "  - transformer: test-names\n", f"  - transformer: {rel}\n")


# @use-case:bridge.links-transformers#acceptance.any-language
@pytest.mark.parametrize("link, reason", [
    ({"use_case": "demo.math.add", "binding": "x", "role": "validation", "route": "unit-tests", "file": "../outside.js"}, "inside the project"),
    ({"use_case": "demo.math.add", "binding": "x", "role": "validation", "route": "unit-tests", "file": "src/math.js",
      "range": {"start": 1, "end": 99}}, "outside the file"),
    ({"use_case": "demo.math.nope", "binding": "x", "role": "implementation", "file": "src/math.js"}, "unknown use case"),
    ({"use_case": "demo.math.add", "binding": "x", "role": "validation", "route": "nope", "file": "src/math.js"}, "unknown route"),
    ({"use_case": "demo.math.add", "binding": "x", "role": "validation", "file": "src/math.js"}, "needs a route"),
    ({"use_case": "demo.math.add", "binding": "x", "role": "implementation", "file": ".git/HEAD"}, "excluded folder"),
])
@pytest.mark.broken_transformer
def test_a_links_program_is_trusted_for_nothing(ws, link, reason):
    if link["file"].startswith(".git/"):
        os.makedirs(os.path.join(ws, ".git"), exist_ok=True)
        open(os.path.join(ws, ".git", "HEAD"), "w").write("ref: refs/heads/main\n")
    response = json.dumps({"contract": 1, "links": [link], "diagnostics": []})
    write_program(ws, "tools/links", f"#!/bin/sh\nprintf '%s' '{response}' > \"$3\"\n")
    use_links_program(ws, "tools/links")
    error = uc(ws, "status", expect_exit=2)
    assert reason in error and "bad link" in error
# @use-case:end bridge.links-transformers#acceptance.any-language


# @use-case:bridge.links-transformers#acceptance.any-language
def test_a_links_program_in_any_language_works(ws):
    response = json.dumps({"contract": 1, "diagnostics": [], "links": [
        {"use_case": "demo.math.add", "binding": "adds-numbers", "role": "validation", "route": "unit-tests",
         "file": "test/math.test.js", "range": {"start": 5, "end": 7}}]})
    write_program(ws, "tools/links", f"#!/bin/sh\nprintf '%s' '{response}' > \"$3\"\n")
    use_links_program(ws, "tools/links")
    assert [l["key"] for l in uc(ws, "links")["links"] if l["file"] == "test/math.test.js"] == [
        "demo.math.add#unit-tests.adds-numbers@test/math.test.js:5"]
# @use-case:end bridge.links-transformers#acceptance.any-language


def test_a_program_that_cannot_be_launched_is_a_clear_error(ws):
    write_program(ws, "tools/links", "#!/bin/sh\n", executable=False)
    use_links_program(ws, "tools/links")
    assert "could not be launched" in uc(ws, "status", expect_exit=2)


def test_run_never_reads_a_report_it_did_not_produce(ws):
    replace(ws, "use-cases-bridge.yml", "    run: [sh, -c, 'sh scripts/check.sh > \"$1\"', sh, \"{report}\"]\n", "")
    run = uc(ws, "verify", "--run", "--only", "style")
    assert run["results"] == [] and "no run command" in run["errors"][0]


def set_style_command(ws, command):
    replace(ws, "use-cases-bridge.yml", "    run: [sh, -c, 'sh scripts/check.sh > \"$1\"', sh, \"{report}\"]\n",
            f"    run: {json.dumps(command)}\n")


def console_of(ws, run):
    with open(os.path.join(ws, ".use-cases", "runs", run["run_id"], "outputs", "style", "console.txt")) as handle:
        return handle.read()


# @use-case:verify.commands#acceptance.no-input
def test_commands_get_no_input_and_a_bounded_console(ws):
    set_style_command(ws, ["sh", "-c", 'read line || echo "no input"; head -c 3000000 /dev/zero | tr "\\0" x; echo; exit 0'])
    run = uc(ws, "verify", "--run", "--only", "style")
    console = console_of(ws, run)
    assert console.startswith("no input") and "bytes not kept" in console
    assert len(console.encode()) < 1024 * 1024 + 100
# @use-case:end verify.commands#acceptance.no-input


# @use-case:verify.run-errors#acceptance.signal-timeout
@POSIX_ONLY
def test_a_command_killed_by_a_signal_is_a_run_error(ws):
    set_style_command(ws, ["sh", "-c", "kill -9 $$"])
    run = uc(ws, "verify", "--run", "--only", "style")
    assert "terminated abnormally (signal 9)" in run["errors"][0]
# @use-case:end verify.run-errors#acceptance.signal-timeout


# @use-case:verify.run-errors#acceptance.signal-timeout
def test_a_timeout_stops_the_whole_process_group(ws, tmp_path):
    marker = tmp_path / "survivor"
    set_style_command(ws, ["sh", "-c", f"(sleep 3; touch {marker}) & sleep 30"])
    replace(ws, "use-cases-bridge.yml", "  - id: style\n", "  - id: style\n    timeout_seconds: 1\n")
    run = uc(ws, "verify", "--run", "--only", "style")
    assert "timed out after 1 seconds" in run["errors"][0]
    subprocess.run(["sleep", "4"])
    assert not marker.exists()
# @use-case:end verify.run-errors#acceptance.signal-timeout


NEGATIVES = 'test("demo.math.add#unit-tests.adds-negatives", () => {\n  assert.equal(add(-2, -3), -4);\n});\n\n'


# @use-case:status.judging#acceptance.skipped-test
def test_a_fail_beats_a_test_that_did_not_run(ws):
    replace(ws, "test/math.test.js", 'test("demo.math.divide', NEGATIVES + 'test("demo.math.divide')
    replace(ws, "use-cases-bridge.yml", "    run: [node, --test, --test-reporter=junit,",
            "    run: [node, --test, --test-name-pattern=negatives, --test-reporter=junit,")
    run = uc(ws, "verify", "--run", "--only", "unit-tests")
    add = next(r for r in run["results"] if r["use_case"] == "demo.math.add")
    assert add["status"] == "fail"  # adds-numbers didn't run, but the behaviour is already known to be broken
    assert None in add["links"].values()
    assert status(ws)["demo.math.add"] == "failed"
# @use-case:end status.judging#acceptance.skipped-test


def test_link_warnings_are_kept_with_the_run_and_status_still_reads_it(ws):
    replace(ws, "test/math.test.js", "demo.math.divide#unit-tests.divides", "demo.math.nope#unit-tests.divides")
    run = uc(ws, "verify", "--run")
    assert any("names no known use case" in d["problem"] for d in run["diagnostics"] if "route" not in d)
    assert status(ws)["demo.math.add"] == "verified"


MULTIPLY = """
  - id: multiply
    title: Multiply numbers
    value_tier: core
    intent: Two numbers multiply.
    scenarios:
      - id: multiplies
        when: [Multiply two numbers.]
        then: [The product is returned.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [multiplies]
"""


# @use-case:verify.guard#acceptance.route-added
def test_a_route_added_during_the_run_gets_no_verdict(ws):
    started = uc(ws, "verify", "--start", "--only", "unit-tests")
    with open(os.path.join(ws, "use-cases", "math.yml"), "a") as handle:
        handle.write(MULTIPLY)
    with open(os.path.join(ws, "test", "math.test.js"), "a") as handle:
        handle.write('\ntest("demo.math.multiply#unit-tests.multiplies", () => {\n  assert.equal(2 * 3, 6);\n});\n')
    node_tests(ws, started)
    run = uc(ws, "verify", "--finish")
    assert {"use_case": "demo.math.multiply", "route": "unit-tests", "problem": "code changed during the run"} in run["diagnostics"]
    assert {r["use_case"] for r in run["results"]} == {"demo.math.add", "demo.math.divide"}
# @use-case:end verify.guard#acceptance.route-added


# @use-case:verify.start-finish#acceptance.only-at-start
def test_only_is_chosen_at_start_not_at_finish(ws):
    uc(ws, "verify", "--start")
    assert "--only belongs on" in uc(ws, "verify", "--finish", "--only", "style", expect_exit=2)
# @use-case:end verify.start-finish#acceptance.only-at-start


def test_a_procedure_route_with_links_still_gets_automatic_results(ws):
    replace(ws, "use-cases/math.yml", "        covers: [clean]\n",
            "        covers: [clean]\n        procedure:\n          steps: [Read the style report.]\n")
    uc(ws, "verify", "--run", "--only", "style")
    assert status(ws)["demo.math.style"] == "verified"


# @use-case:validate.discovery-exclusions#acceptance.excluded-folder
def test_only_the_workspace_decides_which_folders_are_skipped(ws):
    """No built-in list of tool folders: a marker in node_modules is found until the workspace excludes it."""
    os.makedirs(os.path.join(ws, "node_modules", "copied"))
    with open(os.path.join(ws, "node_modules", "copied", "math.js"), "w") as handle:
        handle.write(f"// {SENTINEL}demo.math.add#vendored\nexport const add = (a, b) => a + b;\n// {SENTINEL}end demo.math.add#vendored\n")
    def vendored():
        return [l for l in uc(ws, "links")["links"] if l["binding"] == "vendored"]
    assert len(vendored()) == 1
    replace(ws, "use-cases.yml", "prefix: demo\n", 'prefix: demo\ndiscovery:\n  exclude: ["node_modules/**"]\n')
    assert vendored() == []
# @use-case:end validate.discovery-exclusions#acceptance.excluded-folder


# @use-case:bridge.settings#acceptance.transformer-ref
@pytest.mark.parametrize("name, reason", [("no-such-tool", "unknown bundled transformer"), ("../outside/tool", "is not allowed at validations/1/transformer")])
def test_a_transformer_reference_is_checked_when_the_settings_load(ws, name, reason):
    replace(ws, "use-cases-bridge.yml", "    transformer: exit-code\n", f"    transformer: {name}\n")
    assert reason in uc(ws, "status", expect_exit=2)
# @use-case:end bridge.settings#acceptance.transformer-ref


# @use-case:validate.discovery-exclusions#acceptance.history-and-store
def test_version_control_history_is_never_scanned(ws):
    """A commit message that mentions a marker must not break an ordinary repository (ADR 012)."""
    git = ["git", "-c", "user.email=t@example.com", "-c", "user.name=t"]
    subprocess.run(["git", "init", "-q"], cwd=ws, check=True)
    subprocess.run(["git", "add", "-A"], cwd=ws, check=True)
    subprocess.run(git + ["commit", "-q", "-m", f"wip {SENTINEL}demo.math.add#half-written"], cwd=ws, check=True)
    assert status(ws)["demo.math.add"] == "unverified"
# @use-case:end validate.discovery-exclusions#acceptance.history-and-store


# ------------------------------------------------------------------ authored state (chapter 02)


def add_use_case(ws, text):
    with open(os.path.join(ws, "use-cases", "math.yml"), "a") as handle:
        handle.write(text)


# @use-case:record.by-hand#acceptance.refusals
def test_a_draft_is_never_judged_or_recorded(ws):
    add_use_case(ws, "\n  - id: subtract\n    title: Subtract numbers\n    scenarios:\n      - id: subtracts\n"
                     "        when: [Subtract.]\n        then: [The difference.]\n    validation:\n      - id: unit-tests\n"
                     "        type: { kind: unit }\n        covers: [subtracts]\n")
    with open(os.path.join(ws, "test", "math.test.js"), "a") as handle:
        handle.write('\ntest("demo.math.subtract#unit-tests.subtracts", () => {\n  assert.equal(5 - 3, 2);\n});\n')
    run = uc(ws, "verify", "--run")
    assert "demo.math.subtract" not in {r["use_case"] for r in run["results"]}
    draft = next(u for u in uc(ws, "status")["use_cases"] if u["use_case"] == "demo.math.subtract")
    assert draft["state"] == "DRAFT" and draft["status"] == "draft"
    assert draft["missing"] == ["value_tier", "intent"]
    assert "is DRAFT" in uc(ws, "record", "demo.math.subtract", "unit-tests", "pass", expect_exit=2)
# @use-case:end record.by-hand#acceptance.refusals


# @use-case:validate.draft-or-ready#acceptance.uncovered-scenario-is-draft
def test_a_scenario_no_gating_route_covers_keeps_a_use_case_draft(ws):
    replace(ws, "use-cases/math.yml", "        covers: [adds]\n", "        covers: [adds]\n        gates_verification: false\n")
    add = next(u for u in uc(ws, "status")["use_cases"] if u["use_case"] == "demo.math.add")
    assert add["state"] == "DRAFT" and add["missing"] == ["a gating route covering scenario adds"]
# @use-case:end validate.draft-or-ready#acceptance.uncovered-scenario-is-draft


# @use-case:validate.refuses-broken-structure#acceptance.unknown-scenario
def test_covering_an_unknown_scenario_is_invalid(ws):
    replace(ws, "use-cases/math.yml", "        covers: [adds]\n", "        covers: [adds, subtracts]\n")
    assert "covers unknown scenarios ['subtracts']" in uc(ws, "status", expect_exit=2)
# @use-case:end validate.refuses-broken-structure#acceptance.unknown-scenario


def test_plain_verify_asks_which_step(ws):
    error = uc(ws, "verify", expect_exit=2)
    assert "--start" in error and "--finish" in error and "--run" in error


# @use-case:validate.checks-files-only#acceptance.valid-summary
def test_validate_checks_the_files_and_nothing_else(ws):
    checked = uc(ws, "validate")
    assert checked["valid"] is True and checked["use_cases"] == 3 and checked["ready"] == 3 and checked["links"] > 0
    assert not os.path.exists(os.path.join(ws, ".use-cases"))  # it ran no test and wrote nothing
    replace(ws, "use-cases/math.yml", "        covers: [adds]\n", "        covers: [adds, subtracts]\n")
    assert "covers unknown scenarios ['subtracts']" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.checks-files-only#acceptance.valid-summary


# ------------------------------------------------------------------ cancellation (chapter 13 §15)


# @use-case:verify.open-runs#acceptance.cancelled
@POSIX_ONLY
@pytest.mark.parametrize("how", ["SIGINT", "SIGTERM"])
def test_a_cancelled_run_is_sealed_interrupted_with_no_verdicts(ws, tmp_path, how):
    import signal
    import time
    survivor = tmp_path / "survivor"
    set_style_command(ws, ["sh", "-c", f"(sleep 3; touch {survivor}) & sleep 30"])
    process = subprocess.Popen([*COMMAND, "--workspace", ws, "--json", "verify", "--run", "--only", "style"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(1.5)
    process.send_signal(getattr(signal, how))
    out, err = process.communicate(timeout=20)
    assert process.returncode == 130, err
    run = json.loads(out)
    assert run["cancelled"] and run["results"] == [] and "sources not processed: style" in run["notes"][-1]
    with open(os.path.join(ws, ".use-cases", "runs", run["run_id"], "completion.json")) as handle:
        assert json.load(handle)["termination"] == "interrupted"
    time.sleep(3)
    assert not survivor.exists()  # the command and its children were stopped
    assert status(ws)["demo.math.style"] == "unverified"
# @use-case:end verify.open-runs#acceptance.cancelled


# @use-case:verify.open-runs#acceptance.cancelled
@POSIX_ONLY
def test_a_crashed_run_leaves_no_evidence_and_blocks_nothing(ws):
    import signal
    # The run command says it has started on one FIFO, then waits on another; both sit outside the workspace, so
    # nothing but the command opens them.
    started_fifo = os.path.join(os.path.dirname(ws), "started")
    release_fifo = os.path.join(os.path.dirname(ws), "release")
    os.mkfifo(started_fifo)
    os.mkfifo(release_fifo)
    command = ["sh", "-c", 'echo started > "$1" && read line < "$2"', "sh", started_fifo, release_fifo]
    set_style_command(ws, command)
    process = subprocess.Popen([*COMMAND, "--workspace", ws, "--json", "verify", "--run", "--only", "style"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with open(started_fifo) as handle:  # returns once the run is under way and its command is running
        assert handle.readline() == "started\n"
    process.send_signal(signal.SIGKILL)  # no chance to clean up
    process.wait()
    with open(release_fifo, "w") as handle:  # the command, left behind in its own session, ends
        handle.write("go\n")
    runs = os.listdir(os.path.join(ws, ".use-cases", "runs"))
    assert len(runs) == 1 and not os.path.exists(os.path.join(ws, ".use-cases", "runs", runs[0], "completion.json"))
    assert status(ws)["demo.math.style"] == "unverified"  # an unsealed run is never evidence
    assert "no started run" in uc(ws, "verify", "--finish", expect_exit=2)  # its half-written reports are never read
    error = uc(ws, "verify", "--finish", "--run-id", runs[0], expect_exit=2)
    assert "stopped before finishing it" in error and "--abort" in error
    started = uc(ws, "verify", "--start", "--only", "style")  # a --start run beside it is finished as normal
    style_check(ws, started)
    assert uc(ws, "verify", "--finish")["run_id"] == started["run_id"]
    assert uc(ws, "verify", "--abort")["run_id"] == runs[0]
    replace(ws, "use-cases-bridge.yml", f"    run: {json.dumps(command)}\n",
            "    run: [sh, -c, 'sh scripts/check.sh > \"$1\"', sh, \"{report}\"]\n")
    uc(ws, "verify", "--run", "--only", "style")
    assert status(ws)["demo.math.style"] == "verified"  # and it blocks nothing after it
# @use-case:end verify.open-runs#acceptance.cancelled


# ------------------------------------------------------------------ every run owns its reports; nothing is deleted (chapter 12)


# @use-case:bridge.settings#acceptance.names
@pytest.mark.parametrize("report, reason", [
    ("build/unit.xml", "a file or folder name, not a path"), ("../unit.xml", "a file or folder name, not a path"),
    ("..", "validations/0/report"), (".hidden", "validations/0/report"), ("unit.", "validations/0/report"),
    ("con.xml", "validations/0/report"), ("unit tests.xml", "validations/0/report"), ("x" * 65, "validations/0/report")])
def test_a_report_is_a_portable_name_never_a_path(ws, report, reason):
    replace(ws, "use-cases-bridge.yml", "    report: unit.xml\n", f"    report: {json.dumps(report)}\n")
    assert reason in uc(ws, "status", expect_exit=2)
# @use-case:end bridge.settings#acceptance.names


# @use-case:bridge.settings#acceptance.names
@pytest.mark.parametrize("name", ["nul", "com1", "lpt9", "aux"])
def test_a_validation_id_is_a_folder_name_on_every_system(ws, name):
    replace(ws, "use-cases-bridge.yml", "  - id: style\n", f"  - id: {name}\n")
    assert "validations/1/id" in uc(ws, "status", expect_exit=2)
# @use-case:end bridge.settings#acceptance.names


# @use-case:verify.commands#acceptance.report-placeholder
def test_without_a_report_name_the_tests_get_the_folder(ws):
    replace(ws, "use-cases-bridge.yml", "    report: style.txt\n", "")
    set_style_command(ws, ["sh", "-c", 'sh scripts/check.sh > "$1/out.txt"', "sh", "{report}"])
    run = uc(ws, "verify", "--run", "--only", "style")
    assert run["sources"][0]["report"] == "reports/style" and run["errors"] == []
    assert status(ws)["demo.math.style"] == "verified"
# @use-case:end verify.commands#acceptance.report-placeholder


# @use-case:verify.run-errors#acceptance.no-report
def test_an_empty_report_folder_is_no_report(ws):
    replace(ws, "use-cases-bridge.yml", "    report: style.txt\n", "")
    set_style_command(ws, ["sh", "-c", "true"])
    run = uc(ws, "verify", "--run", "--only", "style")
    assert run["results"] == [] and "no report: nothing was written to reports/style" in run["errors"][0]
# @use-case:end verify.run-errors#acceptance.no-report


def run_files(ws, run_id):
    root = os.path.join(ws, ".use-cases", "runs", run_id)
    found = {}
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if name != ".lock":
                with open(os.path.join(dirpath, name), "rb") as handle:
                    found[os.path.relpath(os.path.join(dirpath, name), root)] = handle.read()
    return found


# @use-case:verify.reports-owned-by-run#acceptance.own-reports
def test_every_run_keeps_its_own_reports_and_nothing_is_ever_deleted(ws):
    first = uc(ws, "verify", "--run")
    kept = run_files(ws, first["run_id"])
    assert {"reports/unit-tests/unit.xml", "reports/style/style.txt", "outputs/style/console.txt"} <= {
        k.replace(os.sep, "/") for k in kept}
    open(os.path.join(ws, "FAIL"), "w").close()
    second = uc(ws, "verify", "--run")
    started = uc(ws, "verify", "--start")
    node_tests(ws, started)
    uc(ws, "verify", "--finish")
    assert run_files(ws, first["run_id"]) == kept  # later runs, of either kind, never touch it
    assert sorted(os.listdir(os.path.join(ws, ".use-cases", "runs"))) == sorted([first["run_id"], second["run_id"], started["run_id"]])
    assert uc(ws, "status")["warnings"] == []  # and every sealed run still verifies
# @use-case:end verify.reports-owned-by-run#acceptance.own-reports


def test_run_is_start_then_the_commands_then_finish(ws):
    """--run is --start, the bridge's commands, then --finish, through the same code: the same tests give the same record."""
    ran = uc(ws, "verify", "--run", "--only", "unit-tests")
    started = uc(ws, "verify", "--start", "--only", "unit-tests")
    node_tests(ws, started)
    finished = uc(ws, "verify", "--finish")
    what = lambda run: [{k: v for k, v in r.items() if k != "recorded_at"} for r in run["results"]]
    assert what(ran) == what(finished) and what(ran)
    assert ran["diagnostics"] == finished["diagnostics"] and ran["errors"] == finished["errors"] == []
    assert ran["kind"] == finished["kind"] == "verify"
    extra = {k: v for k, v in ran["sources"][0].items() if k not in finished["sources"][0]}
    assert set(extra) == {"command", "exit_code", "seconds"}
    assert {k: v for k, v in ran["sources"][0].items() if k not in extra} == finished["sources"][0]


def spy_on_the_transformer(ws, tmp_path, then=""):
    seen = tmp_path / "seen.json"
    write_program(ws, "tools/spy", "#!/usr/bin/env python3\nimport json, os, subprocess, sys\n"
                  "request = json.load(open(sys.argv[2]))\n"
                  "path = request['output']['report_path']\n"
                  f"json.dump({{'path': path, 'bytes': open(path).read()}}, open({str(seen)!r}, 'w'))\n"
                  "real = os.environ['UC_REAL']\n"
                  "launch = ['cmd.exe', '/c', real + '.cmd'] if os.name == 'nt' else [real]  # chapter 10 §9\n"
                  "code = subprocess.run([*launch, *sys.argv[1:]]).returncode\n"
                  f"{then}sys.exit(code)\n")
    replace(ws, "use-cases-bridge.yml", "    transformer: exit-code\n", "    transformer: tools/spy\n")
    return seen


def run_with_spy(ws, tmp_path):
    os.environ["UC_REAL"] = transformer_program("exit-code", tmp_path / "launchers")
    try:
        return uc(ws, "verify", "--run", "--only", "style")
    finally:
        del os.environ["UC_REAL"]


# @use-case:verify.reports-owned-by-run#acceptance.sealed-bytes
def test_the_transformer_reads_the_report_where_the_tests_wrote_it_and_those_bytes_are_sealed(ws, tmp_path):
    seen = spy_on_the_transformer(ws, tmp_path)
    run = run_with_spy(ws, tmp_path)
    assert run["errors"] == [] and status(ws)["demo.math.style"] == "verified"
    got = json.loads(seen.read_text())
    folder = os.path.join(ws, ".use-cases", "runs", run["run_id"])
    assert os.path.realpath(got["path"]) == os.path.realpath(os.path.join(folder, "reports", "style", "style.txt"))
    with open(os.path.join(folder, "completion.json")) as handle:
        sealed = json.load(handle)["reports_sha256"]
    import hashlib
    assert sealed == {"style/style.txt": hashlib.sha256(got["bytes"].encode()).hexdigest()}
# @use-case:end verify.reports-owned-by-run#acceptance.sealed-bytes


def test_a_report_that_changes_while_it_is_read_gives_no_results(ws, tmp_path):
    seen = spy_on_the_transformer(ws, tmp_path, then="open(path, 'a').write('late line\\n')\n")
    run = run_with_spy(ws, tmp_path)
    assert run["results"] == [] and "report changed while it was read" in run["errors"][0]
    import hashlib
    with open(os.path.join(ws, ".use-cases", "runs", run["run_id"], "completion.json")) as handle:
        sealed = json.load(handle)["reports_sha256"]["style/style.txt"]
    assert sealed == hashlib.sha256(json.loads(seen.read_text())["bytes"].encode()).hexdigest()  # sealed as it was read


# @use-case:verify.open-runs#acceptance.locked
def test_a_run_in_progress_cannot_be_finished_by_anyone_else(ws):
    import time
    set_style_command(ws, ["sh", "-c", 'sleep 3; sh scripts/check.sh > "$1"', "sh", "{report}"])
    running = subprocess.Popen([*COMMAND, "--workspace", ws, "--json", "verify", "--run", "--only", "style"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(1.5)  # started, commands running
    assert "no started run" in uc(ws, "verify", "--finish", expect_exit=2)  # --finish never takes a --run's run
    assert "being finished by another process" in uc(ws, "verify", "--abort", expect_exit=2)  # and it is locked
    out, err = running.communicate(timeout=30)
    assert running.returncode == 0, err
    assert json.loads(out)["errors"] == [] and status(ws)["demo.math.style"] == "verified"
# @use-case:end verify.open-runs#acceptance.locked


# @use-case:verify.reports-owned-by-run#acceptance.sealed-bytes
def test_a_report_changed_after_the_seal_is_a_warning_never_a_new_verdict(ws):
    run = uc(ws, "verify", "--run", "--only", "style")
    report = os.path.join(ws, ".use-cases", "runs", run["run_id"], "reports", "style", "style.txt")
    with open(report, "a") as handle:
        handle.write("style problems\n")
    reading = uc(ws, "status")
    assert reading["warnings"] == [f"run {run['run_id']}: report style/style.txt changed after it was read"]
    assert status(ws)["demo.math.style"] == "verified"
# @use-case:end verify.reports-owned-by-run#acceptance.sealed-bytes
