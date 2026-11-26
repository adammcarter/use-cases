"""The whole contract against a real Swift package (`sample-swift-project/`): one run gives every use case its verdict,
the guard, freshness, manual bindings, resources and broken transformers.

Each test pins one claim and can fail. Run from the repository root:

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_swift_project.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
from conftest import windows_launcher, call_core, COMMAND, transformer_argv, record_exchanges

HERE = os.path.dirname(os.path.abspath(__file__))
WORKSPACE = os.path.join(HERE, "sample-swift-project")
FIXTURES = os.path.join(HERE, "fixtures")
SWIFT_REPORT_FLAGS = ["--experimental-event-stream-output", "{report}", "--experimental-event-stream-version", "0"]

if not shutil.which("swift"):
    if os.environ.get("UC_REQUIRE_TOOLS") == "all":
        raise RuntimeError("test_swift_project.py needs swift, and UC_REQUIRE_TOOLS=all")
    pytest.skip("test_swift_project.py runs a real Swift package; swift is not installed", allow_module_level=True)


# ------------------------------------------------------------------ helpers


def clone(source, target):
    shutil.copytree(source, target, symlinks=True)
    return target


def fresh(target):
    """A copy of the sample project with no results in it."""
    clone(WORKSPACE, target)
    shutil.rmtree(os.path.join(target, ".use-cases"), ignore_errors=True)
    return target


def uc(workspace, *args, expect_exit=0):
    return call_core(workspace, *args, expect_exit=expect_exit)


def status_of(workspace):
    report = uc(workspace, "status")["use_cases"]
    return {
        u["use_case"].split(".")[-1]: {"status": u["status"], **{c["route"]: c for c in u["routes"]}}
        for u in report
    }


def write_bridge(workspace, validations):
    lines = ["schema_version: 1", "validations:"]
    for v in validations:
        lines.append(f"  - id: {v['id']}")
        lines.append(f"    report: {v.get('report', v['id'] + '.jsonl')}")
        if "run" in v:
            lines.append(f"    run: {json.dumps(v['run'])}")
        lines.append(f"    transformer: {v['transformer']}")
    with open(os.path.join(workspace, "use-cases-bridge.yml"), "w") as handle:
        handle.write("\n".join(lines) + "\n")


def edit(workspace, rel, old, new):
    path = os.path.join(workspace, rel)
    with open(path) as handle:
        text = handle.read()
    assert old in text, f"{old!r} not in {rel}"
    with open(path, "w") as handle:
        handle.write(text.replace(old, new, 1))


@pytest.fixture
def ws(tmp_path):
    return fresh(str(tmp_path / "ws"))


@pytest.fixture(scope="module")
def validated(tmp_path_factory):
    """One real `swift test` run, shared read-only; tests clone it before changing anything."""
    workspace = fresh(str(tmp_path_factory.mktemp("validated") / "ws"))
    run = uc(workspace, "verify", "--run")
    return workspace, run


@pytest.fixture
def after_run(validated, tmp_path):
    return clone(validated[0], str(tmp_path / "after"))


# ------------------------------------------------------------------ boundary 1: use cases stand alone


# @use-case:validate.refuses-broken-structure#acceptance.no-tool-in-use-case
@pytest.mark.parametrize("field", ["runner"])
def test_loader_refuses_tech_fields_in_a_use_case(ws, field):
    edit(ws, "use-cases/login.yml", "    value_tier: critical\n", f"    value_tier: critical\n    {field}: []\n")
    error = uc(ws, "status", expect_exit=2)
    assert "names code or tools" in error and field in error
# @use-case:end validate.refuses-broken-structure#acceptance.no-tool-in-use-case


# @use-case:validate.refuses-broken-structure#acceptance.no-tool-in-use-case
def test_loader_refuses_tech_fields_in_a_check(ws):
    edit(ws, "use-cases/login.yml", "        covers: [three-failures]\n",
         "        covers: [three-failures]\n        runner: { executable: swift }\n")
    assert "names code or tools" in uc(ws, "status", expect_exit=2)
# @use-case:end validate.refuses-broken-structure#acceptance.no-tool-in-use-case


# @use-case:bridge.no-settings#acceptance.core-alone
def test_core_alone_needs_no_bridge_settings(ws):
    """No extras set up: links still come from markers, verdicts can be recorded, status works."""
    os.remove(os.path.join(ws, "use-cases-bridge.yml"))
    links = uc(ws, "links")["links"]
    assert any(l["key"].startswith("shop.login.authenticate#unit-tests.valid-credentials") for l in links)
    uc(ws, "record", "shop.login.lockout", "unit-tests", "pass", "checked by hand")
    assert status_of(ws)["lockout"]["unit-tests"]["status"] == "verified"
    run = uc(ws, "verify", "--finish")
    assert run["results"] == [] and "use-cases record" in run["notes"][0]
# @use-case:end bridge.no-settings#acceptance.core-alone


# ------------------------------------------------------------------ manual bindings: optional, in the use case YAML


LOCKOUT_CHECK = "        covers: [three-failures]\n"


def bind_lockout(ws, use_case_bindings="", check_bindings=""):
    if use_case_bindings:
        edit(ws, "use-cases/login.yml", "    value_tier: critical\n", "    value_tier: critical\n" + use_case_bindings)
    if check_bindings:
        edit(ws, "use-cases/login.yml", LOCKOUT_CHECK, LOCKOUT_CHECK + check_bindings)


HELPER_BINDING = """    bindings:
      - id: helper
        kind: manual
        locator: { file: Sources/Auth/LoginService.swift, start: { line: 43 }, end: { line: 43 } }
"""


def test_a_manual_binding_links_code_with_no_marker_and_goes_stale(ws):
    bind_lockout(ws, use_case_bindings=HELPER_BINDING)
    keys = [l["key"] for l in uc(ws, "links")["links"]]
    assert "shop.login.lockout#helper@Sources/Auth/LoginService.swift:43" in keys
    uc(ws, "record", "shop.login.lockout", "unit-tests", "pass")
    assert status_of(ws)["lockout"]["unit-tests"]["status"] == "verified"
    edit(ws, "Sources/Auth/LoginService.swift", "{ 42 }", "{ 43 }")
    assert status_of(ws)["lockout"]["unit-tests"]["status"] == "stale"


# @use-case:links.manual-bindings#acceptance.missing-file
def test_a_manual_binding_to_a_missing_file_is_refused(ws):
    bind_lockout(ws, use_case_bindings=HELPER_BINDING.replace("LoginService.swift", "Nope.swift"))
    assert "is missing" in uc(ws, "status", expect_exit=2)
# @use-case:end links.manual-bindings#acceptance.missing-file


def test_marker_bindings_need_no_yaml_entry(ws):
    bind_lockout(ws, use_case_bindings="    bindings:\n      - id: x\n        kind: marker\n")
    assert "need no entry" in uc(ws, "status", expect_exit=2)


# @use-case:links.manual-bindings#acceptance.binding-links
def test_a_manual_binding_around_a_test_receives_its_result(ws):
    bind_lockout(ws, check_bindings="""        bindings:
          - id: helper-test
            kind: manual
            locator: { file: Tests/AuthTests/LoginTests.swift, start: { line: 35 }, end: { line: 37 } }
""")
    run = uc(ws, "verify", "--run")
    lockout = next(r for r in run["results"] if r["use_case"] == "shop.login.lockout")
    assert lockout["links"]["shop.login.lockout#unit-tests.helper-test@Tests/AuthTests/LoginTests.swift:35"] == "pass"
    assert lockout["status"] == "fail"  # its marked test still fails
# @use-case:end links.manual-bindings#acceptance.binding-links


# ------------------------------------------------------------------ resources: freshness only, never expect a result


FIXTURE_RESOURCE = "        resources:\n          - kind: file\n            path: Fixtures/users.json\n"


def add_fixture(ws):
    os.makedirs(os.path.join(ws, "Fixtures"), exist_ok=True)
    with open(os.path.join(ws, "Fixtures", "users.json"), "w") as handle:
        handle.write('{"sam@example.com": "correct-password"}\n')
    edit(ws, "use-cases/login.yml", "        covers: [valid-credentials, invalid-password]\n",
         "        covers: [valid-credentials, invalid-password]\n" + FIXTURE_RESOURCE)


def test_a_resource_never_expects_a_result(ws):
    add_fixture(ws)
    run = uc(ws, "verify", "--run")
    authenticate = next(r for r in run["results"] if r["use_case"] == "shop.login.authenticate")
    assert authenticate["status"] == "pass"  # the fixture is not a missing test


# @use-case:status.resources#acceptance.resources
def test_editing_a_resource_makes_its_route_stale(ws):
    add_fixture(ws)
    uc(ws, "record", "shop.login.authenticate", "unit-tests", "pass")
    assert status_of(ws)["authenticate"]["unit-tests"]["status"] == "verified"
    with open(os.path.join(ws, "Fixtures", "users.json"), "w") as handle:
        handle.write('{"sam@example.com": "changed"}\n')
    assert status_of(ws)["authenticate"]["unit-tests"]["status"] == "stale"
# @use-case:end status.resources#acceptance.resources


# @use-case:status.resources#acceptance.missing
def test_a_missing_resource_is_refused(ws):
    edit(ws, "use-cases/login.yml", "        covers: [valid-credentials, invalid-password]\n",
         "        covers: [valid-credentials, invalid-password]\n" + FIXTURE_RESOURCE)
    assert "missing" in uc(ws, "status", expect_exit=2)
# @use-case:end status.resources#acceptance.missing


# @use-case:validate.draft-or-ready#acceptance.ready-without-links
def test_links_are_never_required_to_be_ready(ws):
    """A use case with no links at all is still judged normally, with a warning."""
    for rel in ["Sources/Auth/LoginService.swift", "Tests/AuthTests/LoginTests.swift", "Tests/SessionTests/RememberMeTests.swift"]:
        path = os.path.join(ws, rel)
        with open(path) as handle:
            kept = [line for line in handle if "@use-case" not in line]
        with open(path, "w") as handle:
            handle.writelines(kept)
    uc(ws, "record", "shop.login.lockout", "unit-tests", "pass", "checked by hand")
    lockout = next(u for u in uc(ws, "status")["use_cases"] if u["use_case"] == "shop.login.lockout")
    assert lockout["status"] == "verified"
    assert any("no implementation links" in w for w in lockout["warnings"])
    assert any("only `use-cases record` can verify it" in w for w in lockout["warnings"])
# @use-case:end validate.draft-or-ready#acceptance.ready-without-links


# ------------------------------------------------------------------ boundary 3: transformers


def test_links_job_is_deterministic(ws):
    first = subprocess.run([*COMMAND, "--workspace", ws, "--json", "links"], capture_output=True).stdout
    second = subprocess.run([*COMMAND, "--workspace", ws, "--json", "links"], capture_output=True).stdout
    assert first == second and b"unit-tests.valid-credentials" in first


# @use-case:transformers.swift#acceptance.saved-report
def test_swift_transformer_alone_against_a_saved_report(tmp_path):
    """No Swift needed: a transformer is a pure conversion."""
    with open(os.path.join(FIXTURES, "links.json")) as handle:
        links = json.load(handle)
    request = {
        "contract": 1, "job": "results", "use_cases": [], "links": links, "settings": {},
        "output": {"report_path": os.path.join(FIXTURES, "auth-tests-report.jsonl"), "exit_code": 1},
        "code_root": "/FROZEN",
    }
    request_path, response_path = tmp_path / "request.json", tmp_path / "response.json"
    request_path.write_text(json.dumps(request))
    subprocess.run([*transformer_argv("swift-testing"), "results", str(request_path), str(response_path)], check=True)
    with open(os.path.join(FIXTURES, "expected-results.json")) as handle:
        assert json.loads(response_path.read_text()) == json.load(handle)
# @use-case:end transformers.swift#acceptance.saved-report


# ------------------------------------------------------------------ one run, every verdict


# @use-case:verify.run#acceptance.one-command
def test_one_command_gives_every_use_case_its_verdict(validated):
    workspace, run = validated
    assert len(run["sources"]) == 1 and run["errors"] == []
    status = status_of(workspace)
    assert status["authenticate"]["unit-tests"]["status"] == "verified"
    assert status["lockout"]["unit-tests"]["status"] == "failed"
    assert status["password-reset"]["unit-tests"]["status"] == "incomplete"
# @use-case:end verify.run#acceptance.one-command


# @use-case:status.judging#acceptance.not-run
def test_a_marked_test_the_command_skips_is_never_a_pass(validated):
    workspace, _ = validated
    remember = status_of(workspace)["remember-me"]["unit-tests"]
    assert remember["status"] == "unverified"
    assert "its test didn't run" in remember["note"]
# @use-case:end status.judging#acceptance.not-run


# @use-case:verify.unlinked-tests#acceptance.unlinked
def test_tests_without_a_use_case_are_reported(validated):
    _, run = validated
    assert [t["test"].split("/")[1] for t in run["unlinked_tests"]] == ["notTiedToAnyUseCase()"]
# @use-case:end verify.unlinked-tests#acceptance.unlinked


def test_tests_without_a_use_case_are_told_to_a_person(ws):
    process = subprocess.run([*COMMAND, "--workspace", ws, "verify", "--run"], capture_output=True,
                             stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    assert process.returncode == 0, process.stderr
    lines = process.stdout.splitlines()
    assert lines[0].endswith("· 1 not tied to a use case"), lines
    block = lines.index("test not tied to a use case")
    assert "notTiedToAnyUseCase()" in lines[block + 1]
    assert lines[block + 1].split("  ")[1].count(":") == 1, "a place is file:line"


def test_the_old_false_pass_cannot_happen(ws):
    """Today's example command matches no test and exits 0. It must verify nothing."""
    write_bridge(ws, [{"id": "old-filter", "transformer": "swift-testing",
                       "run": ["swift", "test", "--filter", "shop.login.authenticate", *SWIFT_REPORT_FLAGS]}])
    run = uc(ws, "verify", "--run")
    assert run["sources"][0]["exit_code"] == 0
    assert run["results"] == []
    assert {d["problem"] for d in run["diagnostics"] if isinstance(d, dict)} == {"its test didn't run"}
    assert all(u["status"] != "verified" for u in status_of(ws).values())


# @use-case:verify.run#acceptance.merge
def test_results_from_every_command_merge_before_judging(ws):
    write_bridge(ws, [
        {"id": "auth-tests", "transformer": "swift-testing", "run": ["swift", "test", "--filter", "AuthTests", *SWIFT_REPORT_FLAGS]},
        {"id": "session-tests", "transformer": "swift-testing", "run": ["swift", "test", "--filter", "SessionTests", *SWIFT_REPORT_FLAGS]},
    ])
    uc(ws, "verify", "--run")
    status = status_of(ws)
    assert status["remember-me"]["unit-tests"]["status"] == "verified"
    assert status["authenticate"]["unit-tests"]["status"] == "verified"
# @use-case:end verify.run#acceptance.merge


# @use-case:verify.run-errors#acceptance.build-break
def test_a_build_break_gives_no_verdicts_and_one_run_error(ws):
    edit(ws, "Sources/Auth/LoginService.swift", "public func unrelatedHelper() -> Int { 42 }", "public func unrelatedHelper( {")
    run = uc(ws, "verify", "--run")
    assert run["sources"][0]["exit_code"] != 0
    assert run["results"] == []
    assert len(run["errors"]) == 1
    assert all(u["status"] in ("unverified", "not linked") for u in status_of(ws).values())
# @use-case:end verify.run-errors#acceptance.build-break


# @use-case:verify.reports-owned-by-run#acceptance.own-reports
def test_the_report_is_kept_in_the_run_that_read_it(validated):
    workspace, run = validated
    assert run["sources"][0]["report"] == "reports/auth-tests/auth-tests.jsonl"
    assert os.path.getsize(os.path.join(workspace, ".use-cases", "runs", run["run_id"], "reports", "auth-tests", "auth-tests.jsonl"))
# @use-case:end verify.reports-owned-by-run#acceptance.own-reports


# ------------------------------------------------------------------ runs in place, no frozen copy


def swift_after(edit_command):
    """A command that edits the project mid-run, then runs the tests normally."""
    tests = "swift test --filter AuthTests --experimental-event-stream-output \"$1\" --experimental-event-stream-version 0"
    return {"id": "auth-tests", "transformer": "swift-testing",
            "run": ["sh", "-c", f"{edit_command} && {tests}", "sh", "{report}"]}


# @use-case:verify.commands#acceptance.real-project
def test_runs_in_the_real_project_not_a_copy(validated):
    workspace, run = validated
    assert os.path.isdir(os.path.join(workspace, ".build"))  # swift test built right here
    assert "freeze_seconds" not in run
# @use-case:end verify.commands#acceptance.real-project


# @use-case:verify.guard#acceptance.changed-during
def test_linked_code_edited_during_the_run_gives_no_verdict(ws):
    write_bridge(ws, [swift_after("perl -pi -e 's/user-1\"\\)/user-9\")/' Sources/Auth/LoginService.swift")])
    run = uc(ws, "verify", "--run")
    verdicts = {r["use_case"].split(".")[-1] for r in run["results"]}
    changed = [d for d in run["diagnostics"] if isinstance(d, dict) and d["problem"] == "code changed during the run"]
    # only authenticate's linked region holds that line; the same file's other regions are unchanged
    assert {d["use_case"].split(".")[-1] for d in changed} == {"authenticate"}
    assert "authenticate" not in verdicts and {"lockout", "password-reset"} <= verdicts
# @use-case:end verify.guard#acceptance.changed-during


# @use-case:verify.guard#acceptance.unlinked-edit
def test_an_unlinked_edit_during_the_run_keeps_every_verdict(ws):
    write_bridge(ws, [swift_after("printf '// notes\\n' >> Sources/Auth/LoginService.swift")])
    run = uc(ws, "verify", "--run")
    assert not [d for d in run["diagnostics"] if isinstance(d, dict) and d["problem"] == "code changed during the run"]
    assert {"authenticate", "lockout", "password-reset"} <= {r["use_case"].split(".")[-1] for r in run["results"]}
# @use-case:end verify.guard#acceptance.unlinked-edit


def test_an_intent_edit_during_the_run_only_affects_that_use_case(ws):
    write_bridge(ws, [swift_after("perl -pi -e 's/reject anyone without them/reject the rest/' use-cases/login.yml")])
    run = uc(ws, "verify", "--run")
    verdicts = {r["use_case"].split(".")[-1]: r["status"] for r in run["results"]}
    assert "authenticate" not in verdicts
    assert verdicts["lockout"] == "fail"


# ------------------------------------------------------------------ `verify`: you ran the tests yourself


def run_tests_yourself(workspace, started):
    """What a CI step does: run the tests, writing the report where `--start` said."""
    subprocess.run(["swift", "test", "--filter", "AuthTests", "--experimental-event-stream-output",
                    started["reports"]["auth-tests"], "--experimental-event-stream-version", "0"],
                   cwd=workspace, capture_output=True)


# @use-case:verify.start-finish#acceptance.own-step
def test_validate_uses_the_report_from_tests_you_ran_yourself(ws, validated):
    started = uc(ws, "verify", "--start")
    run_tests_yourself(ws, started)
    run = uc(ws, "verify", "--finish")
    assert run["run_id"] == started["run_id"]
    assert "exit_code" not in run["sources"][0]  # nothing was run by use-cases
    assert {r["use_case"]: r["status"] for r in run["results"]} == {r["use_case"]: r["status"] for r in validated[1]["results"]}
# @use-case:end verify.start-finish#acceptance.own-step


# @use-case:verify.start-finish#acceptance.finish-without-start
def test_finish_without_a_start_is_refused(ws):
    assert "no started run" in uc(ws, "verify", "--finish", expect_exit=2)
    assert status_of(ws)["authenticate"]["status"] == "unverified"
# @use-case:end verify.start-finish#acceptance.finish-without-start


# @use-case:verify.reports-owned-by-run#acceptance.never-earlier
def test_a_new_run_never_reads_an_earlier_runs_report(ws):
    first = uc(ws, "verify", "--start")
    run_tests_yourself(ws, first)
    uc(ws, "verify", "--finish")
    second = uc(ws, "verify", "--start")
    assert second["reports"]["auth-tests"] != first["reports"]["auth-tests"]
    run = uc(ws, "verify", "--finish")
    assert run["results"] == [] and "no report" in run["errors"][0]
    assert os.path.getsize(first["reports"]["auth-tests"])  # and the first run still has its own
# @use-case:end verify.reports-owned-by-run#acceptance.never-earlier


def test_validate_never_runs_tests(ws, tmp_path):
    ran = tmp_path / "ran.txt"
    write_bridge(ws, [{"id": "auth-tests", "transformer": "swift-testing", "run": ["touch", str(ran)]}])
    uc(ws, "verify", "--start")
    run = uc(ws, "verify", "--finish")
    assert not ran.exists()
    assert run["results"] == [] and "no report" in run["errors"][0] and "the path `--start` gave" in run["errors"][0]


# @use-case:verify.guard#acceptance.changed-during
def test_code_changed_during_the_run_gives_no_verdict(ws):
    run_tests_yourself(ws, uc(ws, "verify", "--start"))
    edit(ws, "Sources/Auth/LoginService.swift", 'User(id: "user-1")', 'User(id: "user-9")')
    run = uc(ws, "verify", "--finish")
    changed = {d["use_case"].split(".")[-1] for d in run["diagnostics"]
               if isinstance(d, dict) and d["problem"] == "code changed during the run"}
    assert changed == {"authenticate"}
    assert "authenticate" not in {r["use_case"].split(".")[-1] for r in run["results"]}
    assert status_of(ws)["authenticate"]["unit-tests"]["status"] == "unverified"  # nothing speaks for the new code
# @use-case:end verify.guard#acceptance.changed-during


# @use-case:verify.open-runs#acceptance.locked
def test_a_finished_run_cannot_be_finished_again(ws):
    run_tests_yourself(ws, uc(ws, "verify", "--start"))
    uc(ws, "verify", "--finish")
    assert "no started run" in uc(ws, "verify", "--finish", expect_exit=2)
# @use-case:end verify.open-runs#acceptance.locked


# @use-case:verify.reports-owned-by-run#acceptance.never-earlier
def test_run_never_reads_a_report_left_by_an_earlier_run(ws):
    run_tests_yourself(ws, uc(ws, "verify", "--start"))
    uc(ws, "verify", "--finish")
    write_bridge(ws, [{"id": "auth-tests", "transformer": "swift-testing", "run": ["true"]}])
    run = uc(ws, "verify", "--run")
    assert run["results"] == [] and "no report" in run["errors"][0]
# @use-case:end verify.reports-owned-by-run#acceptance.never-earlier


# ------------------------------------------------------------------ transformer misbehaving


# @use-case:verify.run-errors#acceptance.broken-transformer
@pytest.mark.parametrize("body, reason", [
    ("open(sys.argv[3], 'w').write('not json')", "malformed output"),
    ("json.dump({'contract': 1, 'results': [{'link': 'made-up', 'status': 'fail'}]}, open(sys.argv[3], 'w'))", "does not exist"),
    ("sys.exit(3)", "exited 3"),
])
@pytest.mark.broken_transformer
def test_a_broken_transformer_fails_the_run_not_the_use_cases(ws, body, reason):
    os.makedirs(os.path.join(ws, "bad"))
    program = os.path.join(ws, "bad", "transformer")
    with open(program, "w") as handle:
        handle.write(f"#!/usr/bin/env python3\nimport json, sys\n{body}\n")
    os.chmod(program, 0o755)
    record_exchanges(program)
    windows_launcher(program, f"#!/usr/bin/env python3\nimport json, sys\n{body}\n")
    write_bridge(ws, [{"id": "broken", "transformer": "bad/transformer", "run": ["sh", "-c", 'echo x > "$1"', "sh", "{report}"]}])
    run = uc(ws, "verify", "--run")
    assert run["results"] == []
    assert len(run["errors"]) == 1 and reason in run["errors"][0]
    assert all(u["status"] != "failed" for u in status_of(ws).values())
# @use-case:end verify.run-errors#acceptance.broken-transformer


# ------------------------------------------------------------------ freshness


# @use-case:status.staleness#acceptance.linked-code
def test_editing_linked_code_makes_it_stale(after_run):
    edit(after_run, "Sources/Auth/LoginService.swift", 'return User(id: "user-1")', 'return User(id: "user-2")')
    status = status_of(after_run)
    assert status["authenticate"]["unit-tests"]["status"] == "stale"
    assert status["lockout"]["unit-tests"]["status"] == "failed"  # other use cases untouched
# @use-case:end status.staleness#acceptance.linked-code


# @use-case:status.staleness#acceptance.linked-code
def test_editing_a_linked_test_makes_it_stale(after_run):
    edit(after_run, "Tests/AuthTests/LoginTests.swift", 'password: "wrong")\n        }', 'password: "nope")\n        }')
    assert status_of(after_run)["authenticate"]["unit-tests"]["status"] == "stale"
# @use-case:end status.staleness#acceptance.linked-code


# @use-case:status.staleness#acceptance.unlinked-code
def test_editing_unlinked_code_changes_nothing(after_run):
    edit(after_run, "Sources/Auth/LoginService.swift", "{ 42 }", "{ 43 }")
    assert status_of(after_run)["authenticate"]["unit-tests"]["status"] == "verified"
# @use-case:end status.staleness#acceptance.unlinked-code


# @use-case:status.staleness#acceptance.promise
def test_intent_change_is_stale_title_change_is_not(after_run):
    edit(after_run, "use-cases/login.yml", "title: Authenticate user", "title: Sign in")
    assert status_of(after_run)["authenticate"]["unit-tests"]["status"] == "verified"
    edit(after_run, "use-cases/login.yml", "and reject anyone without them.", "and reject everyone else.")
    assert status_of(after_run)["authenticate"]["unit-tests"]["status"] == "stale"
# @use-case:end status.staleness#acceptance.promise


# @use-case:status.staleness#acceptance.move
def test_moving_linked_code_without_changing_it_stays_verified(after_run):
    edit(after_run, "Sources/Auth/LoginService.swift", "public final class LoginService {",
         "// a new comment line shifts everything down\npublic final class LoginService {")
    assert status_of(after_run)["authenticate"]["unit-tests"]["status"] == "verified"
# @use-case:end status.staleness#acceptance.move


# ------------------------------------------------------------------ manual checks


# @use-case:record.by-hand#acceptance.record
def test_manual_verdict_needs_no_transformer_and_respects_gating(after_run):
    uc(after_run, "record", "shop.login.authenticate", "manual-login-check", "fail", "dashboard never loads")
    status = status_of(after_run)["authenticate"]
    assert status["manual-login-check"]["status"] == "failed"
    assert status["status"] == "verified"  # non-gating check cannot lower the use case
# @use-case:end record.by-hand#acceptance.record
