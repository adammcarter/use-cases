"""Every suite, every test: whatever the core wrote to a results store, and every request and
response it exchanged with a transformer, must match the published schemas exactly.

This is what makes the schemas the contract rather than a description of it.
"""

import atexit
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
import yaml
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

# The marker sentinel, built from two parts: the tool scans its own repository for markers.
SENTINEL = "@use-case" + ":"

PUBLISHED = Path(__file__).resolve().parents[2] / "docs" / "schemas"
registry = Registry()
for path in sorted(PUBLISHED.glob("*/*.schema.json")):
    registry = registry.with_resource(path.as_uri(), Resource.from_contents(json.loads(path.read_text())))


def validator(name, folder="engine"):
    return Draft202012Validator({"$ref": (PUBLISHED / folder / name).as_uri()}, registry=registry,
                                format_checker=FormatChecker())


SCHEMAS = {name: validator(name) for name in (
    "run.schema.json", "result.schema.json", "completion.schema.json", "start.schema.json", "run-order.schema.json",
    "transformer-links-request.schema.json", "transformer-links-response.schema.json",
    "transformer-results-request.schema.json", "transformer-results-response.schema.json")}
SCHEMAS.update({f"cli-{name}.schema.json": validator(f"cli-{name}.schema.json", "output")
                for name in ("error", "version", "validate", "status", "verify", "record", "links", "init", "hooks", "show", "save", "remove", "search", "docs", "apply", "approve", "render", "prune")})


def problems(schema, data, where):
    return [f"{where}: {e.message} at {list(e.absolute_path)}" for e in SCHEMAS[schema].iter_errors(data)]


FOREIGN = set()  # per-test folders holding stores written the way a future core might


def check_store(store):
    found = []
    order = store / "run-order.json"
    if order.exists():
        found += problems("run-order.schema.json", json.loads(order.read_text()), order)
    runs = store / "runs"
    for run in sorted(runs.iterdir()) if runs.is_dir() else []:
        if not re.match(r"^[0-9a-f]{32}$", run.name):
            continue  # not a run: the core itself refuses stray folders
        manifest = json.loads((run / "run.json").read_text())
        found += problems("run.schema.json", manifest, run / "run.json")
        if manifest.get("run_id") != run.name:
            found.append(f"{run}: run_id does not match its folder")
        for number, line in enumerate((run / "results.jsonl").read_text().splitlines(), start=1):
            found += problems("result.schema.json", json.loads(line), f"{run}/results.jsonl:{number}")
        if (run / "start.json").exists():
            found += problems("start.schema.json", json.loads((run / "start.json").read_text()), run / "start.json")
        elif manifest.get("kind") != "record":
            found.append(f"{run}: a {manifest.get('kind')} run has no start.json")
        if (run / "completion.json").exists():
            found += problems("completion.schema.json", json.loads((run / "completion.json").read_text()), run / "completion.json")
    return found


def check_exchanges(folder, requests_only=False):
    found = []
    for exchange in sorted(folder.iterdir()) if folder.is_dir() else []:
        CHECKED["exchanges"] += 1
        job = exchange.name.split("-")[0]
        found += problems(f"transformer-{job}-request.schema.json", json.loads((exchange / "request.json").read_text()), exchange)
        if (exchange / "response.json").exists() and not requests_only:
            try:
                response = json.loads((exchange / "response.json").read_text())
            except ValueError as error:
                found.append(f"{exchange}: response is not JSON: {error}")
                continue
            found += problems(f"transformer-{job}-response.schema.json", response, exchange)
    return found


def check_outputs(folder):
    """Chapter 16 §5: every --json document the core printed matches its command's published schema."""
    found = []
    for path in sorted(folder.iterdir()) if folder.is_dir() else []:
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except ValueError as error:
            found.append(f"{path}: --json printed something that is not one JSON document: {error}")
            continue
        schema = "cli-error.schema.json" if "error" in document else f"cli-{document.get('command')}.schema.json"
        found += problems(schema, document, f"{path} ({document.get('command')})") if schema in SCHEMAS else [f"{path}: no schema {schema}"]
    return found


def check_stores(root):
    found = []
    for store in root.rglob(".use-cases"):
        if store.is_dir():
            found += check_store(store)
    return found


@pytest.fixture(scope="session", autouse=True)
def session_contract(tmp_path_factory):
    """Module-scoped workspaces are built before any per-test hook runs; their exchanges land here."""
    base = tmp_path_factory.getbasetemp()
    os.environ["UC_KEEP_EXCHANGES"] = str(base / "_exchanges")
    os.environ["UC_KEEP_OUTPUTS"] = str(base / "_outputs")
    yield
    found = [f for f in check_stores(base) if not any(str(f).startswith(str(d)) for d in FOREIGN)] + check_exchanges(base / "_exchanges")
    found += check_outputs(base / "_outputs")
    assert not found, "the core broke a published schema:\n" + "\n".join(found[:20])


@pytest.fixture(autouse=True)
def test_contract(request, tmp_path):
    previous = os.environ["UC_KEEP_EXCHANGES"], os.environ["UC_KEEP_OUTPUTS"]
    os.environ["UC_KEEP_EXCHANGES"] = str(tmp_path / "_exchanges")
    os.environ["UC_KEEP_OUTPUTS"] = str(tmp_path / "_outputs")
    yield
    os.environ["UC_KEEP_EXCHANGES"], os.environ["UC_KEEP_OUTPUTS"] = previous
    # a test that feeds the core a broken transformer on purpose still has its requests checked
    broken = request.node.get_closest_marker("broken_transformer") is not None
    foreign = request.node.get_closest_marker("foreign_store") is not None  # a store written as a future core might
    if foreign:
        FOREIGN.add(tmp_path)
    found = ([] if foreign else check_stores(tmp_path)) + check_exchanges(tmp_path / "_exchanges", requests_only=broken)
    found += unrecorded_programs(tmp_path)
    found += [] if foreign else check_outputs(tmp_path / "_outputs")
    assert not found, "the core broke a published schema:\n" + "\n".join(found[:20])


POSIX_ONLY = pytest.mark.skipif(os.name == "nt", reason="POSIX signals: Windows has no SIGINT/SIGTERM delivery to a child "
                                                        "or SIGKILL; cancellation there is a host concern")


def pytest_configure(config):
    config.addinivalue_line("markers", "broken_transformer: the test feeds the core a transformer that breaks the contract")
    config.addinivalue_line("markers", "foreign_store: the test writes a run the way a future core version might")


UNDER_TEST = os.environ.get("USE_CASES_UNDER_TEST")  # the build's use-cases: this suite is its acceptance test (ADR 037)
TRANSFORMERS_UNDER_TEST = os.environ.get("USE_CASES_TRANSFORMERS_UNDER_TEST")  # the build's use-cases-transformers
MISSING = [name for name, value in (("USE_CASES_UNDER_TEST", UNDER_TEST),
                                    ("USE_CASES_TRANSFORMERS_UNDER_TEST", TRANSFORMERS_UNDER_TEST)) if not value]
if MISSING:
    raise pytest.UsageError(
        f"set {' and '.join(MISSING)}: the acceptance suite runs a build of use-cases, pointed at by "
        "USE_CASES_UNDER_TEST (its use-cases) and USE_CASES_TRANSFORMERS_UNDER_TEST (its use-cases-transformers)")

# ---------------------------------------------------------------- exchanges of a build that keeps none (ADR 037)
#
# Every request and response a transformer exchanges with the core is checked against the published schemas. The
# build keeps none of them, so the suite records them from outside: every transformer program is run through a small
# recording wrapper that saves the request before the program runs and the response after it, into UC_KEEP_EXCHANGES.
# Nothing in the product is involved; the variable is only inherited by the wrapper. What the suite cannot wrap is made
# visible, never passed over silently.

RECORDER_MARK = "# uc-exchange-recorder"
RECORDER = """#!/bin/sh
%(mark)s: saves the exchange for the schema checks, then runs the real program unchanged
real=%(real)s
%(job)s
request=$%(request)s
response=$%(response)s
kept=
if [ -n "$UC_KEEP_EXCHANGES" ]; then
  mkdir -p "$UC_KEEP_EXCHANGES"
  kept=$(mktemp -d "$UC_KEEP_EXCHANGES/$job-XXXXXX")
  cp "$request" "$kept/request.json"
fi
"$real" "$@"
code=$?
if [ -n "$kept" ] && [ "$code" -eq 0 ] && [ -f "$response" ]; then
  cp "$response" "$kept/response.json"
fi
exit $code
"""
RECORDING = {"folder": None, "bundled": False, "note": "no exchange is recorded yet"}
CHECKED = {"exchanges": 0, "wrapped": 0}


def _quote(text):
    return "'" + str(text).replace("'", "'\\''") + "'"


def _recorder(real, bundled):
    """A bundled transformer is run as `use-cases-transformers <name> <job> <request> <response>`; a project's own
    program as `<program> <job> <request> <response>` (chapter 10 section 10)."""
    first = 2 if bundled else 1
    return RECORDER % {"mark": RECORDER_MARK, "real": _quote(real), "job": f"job=${first}", "request": first + 1,
                       "response": first + 2}


def _recording_command(under_test):
    """The build under test, copied into a folder of the suite's own with a recording `use-cases-transformers` beside
    it, when the build ships one. The copy is a real file (the build finds its transformers by its real path) and
    everything else beside it is linked."""
    source = Path(under_test).resolve()
    bundled = source.parent / "use-cases-transformers"
    if not bundled.is_file():
        RECORDING["note"] = (f"{bundled} does not exist, so no bundled transformer can run or be recorded; "
                             "project programs are recorded")
        return under_test
    folder = Path(tempfile.mkdtemp(prefix="uc-recording-"))
    atexit.register(shutil.rmtree, folder, True)
    try:
        for entry in source.parent.iterdir():
            if entry.name == bundled.name:
                continue
            target = folder / entry.name
            if entry == source:
                shutil.copy2(entry, target)
            else:
                target.symlink_to(entry)
        wrapper = folder / bundled.name
        wrapper.write_text(_recorder(bundled, bundled=True))
        wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    except OSError as error:
        RECORDING["note"] = f"the recording copy could not be made ({error}): bundled exchanges are NOT recorded"
        return under_test
    RECORDING.update(folder=folder, bundled=True, note=f"bundled transformers are recorded through {folder}")
    return str(folder / source.name)


COMMAND = [_recording_command(UNDER_TEST)]


def record_exchanges(path):
    """Wrap a transformer program a test has just written, so its exchanges are saved for the schema checks. A
    program that cannot be launched (not executable) is left as it is: it has no exchange, and wrapping it would
    change the error the test is about."""
    if not os.access(path, os.X_OK) or os.path.isdir(path):
        return
    with open(path, "rb") as handle:
        original = handle.read()
    if RECORDER_MARK.encode() in original:
        return
    kept = Path(tempfile.mkdtemp(prefix="uc-program-"))
    atexit.register(shutil.rmtree, kept, True)
    real = kept / os.path.basename(path)
    real.write_bytes(original)
    real.chmod(os.stat(path).st_mode)
    with open(path, "w", newline="\n") as handle:
        handle.write(_recorder(real, bundled=False))
    os.chmod(path, os.stat(real).st_mode)
    CHECKED["wrapped"] += 1


def unrecorded_programs(root):
    """A transformer program a test configured that the suite did not wrap: its exchanges would go unchecked, so it
    is a finding, not a silent pass."""
    found = []
    for bridge in Path(root).rglob("use-cases-bridge.yml"):
        try:
            settings = yaml.safe_load(bridge.read_text()) or {}
            named = [entry.get("transformer") for entry in (settings.get("links") or []) + (settings.get("validations") or [])]
        except (OSError, ValueError, AttributeError, yaml.YAMLError):
            continue
        for name in named:
            if not isinstance(name, str) or "/" not in name:
                continue
            program = bridge.parent / name
            if program.is_file() and os.access(program, os.X_OK) and RECORDER_MARK.encode() not in program.read_bytes():
                found.append(f"{program}: a transformer program the suite did not record; wrap it with conftest.record_exchanges")
    return found


def pytest_report_header(config):
    return f"transformer exchanges: {RECORDING['note']}"


def pytest_terminal_summary(terminalreporter):
    terminalreporter.write_line(f"transformer exchanges checked against the schemas: {CHECKED['exchanges']} "
                                f"(project programs wrapped: {CHECKED['wrapped']})")


def transformer_argv(name):
    """The command line that runs the bundled transformer `name`, up to (not including) `<job> <request> <response>`:
    the build's one transformers program, with the transformer's name first (docs/architecture.md §6)."""
    return [TRANSFORMERS_UNDER_TEST, name]


def transformer_program(name, folder):
    """A single path that launches the bundled transformer `name` when called as `<program> <job> <request> <response>`,
    for tests that hand it to something else to launch (a spy, a wrapper): a one-line launcher in `folder` that puts
    the name first (with its .cmd beside it for Windows)."""
    os.makedirs(folder, exist_ok=True)
    program = os.path.join(folder, f"run-{name}")
    with open(program, "w", newline="\n") as handle:
        handle.write(f'#!/bin/sh\nexec "{TRANSFORMERS_UNDER_TEST}" {name} "$@"\n')
    os.chmod(program, 0o755)
    with open(program + ".cmd", "w", newline="\r\n") as handle:
        handle.write(f'@"{TRANSFORMERS_UNDER_TEST}" {name} %*\n')
    return program


def keep_output(argv, stdout):
    """Chapter 16 §5, checked from outside: whatever --json document the command printed is kept for the
    schema checks, so a build that records nothing itself is held to the schemas all the same."""
    keep = os.environ.get("UC_KEEP_OUTPUTS")
    if not keep or "--json" not in argv or [str(part) for part in argv[:len(COMMAND)]] != COMMAND:
        return
    text = stdout.decode("utf-8", "replace") if isinstance(stdout, bytes) else stdout or ""
    if not text.strip() or "--help" in argv or "-h" in argv:
        return
    os.makedirs(keep, exist_ok=True)
    Path(keep, f"harness-{time.time_ns()}.json").write_text(text, encoding="utf-8")


def _run_and_keep(*args, **kwargs):
    process = _run(*args, **kwargs)
    argv = args[0] if args else kwargs.get("args")
    if isinstance(argv, (list, tuple)) and process.stdout is not None:
        keep_output(list(argv), process.stdout)
    return process


_run = subprocess.run
subprocess.run = _run_and_keep


def call_core(workspace, *args, expect_exit=0, env=None):
    """Every suite drives the core the way a script would: --json, and the exit codes of chapter 16 §6.
    Returns the JSON document, or for a refusal the message a person sees on stderr."""
    import subprocess
    process = subprocess.run([*COMMAND, "--workspace", workspace, "--json", *args], capture_output=True, stdin=subprocess.DEVNULL,
                             text=True, encoding="utf-8", env=env)
    document = json.loads(process.stdout) if process.stdout.strip() else None
    if expect_exit == 0 and process.returncode == 1 and "verify" in args:
        # a verify run sealed with run errors exits 1, and only then (chapter 16 §6)
        assert document and document["errors"], process.stderr
        return document
    assert process.returncode == expect_exit, process.stderr
    if expect_exit == 1:  # the gate blocked, or a verify run sealed with run errors: a normal document
        return document
    if expect_exit == 0:
        assert "verify" not in args or not document.get("errors"), "a verify run with run errors must exit 1"
        return document
    assert document and document["error"]["message"] in process.stderr, "--json must also carry the error"
    return process.stderr


def windows_launcher(path, body):
    """Chapter 10 §9: next to a #! program, a <name>.cmd that Windows can launch. Written on every OS, so the
    same test files prove the launcher rule on Windows."""
    first = body.splitlines()[0] if body else ""
    interpreter = "python" if "python" in first else "node" if "node" in first else "sh"
    with open(path + ".cmd", "w", newline="\r\n") as handle:
        handle.write(f'@{interpreter} "%~dp0{os.path.basename(path)}" %*\n')
