"""Chapter 12 §31, chapter 16 §20: prune removes whole superseded runs, and no answer of status or the gate changes.
Two real verify runs over the Python fixture's own tests: the second says everything the first said again.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_prune.py -v
"""

import json
import os
import shutil
import subprocess

import pytest
from conftest import COMMAND, call_core, problems
from test_languages import FIXTURES, env

pytestmark = pytest.mark.skipif(not shutil.which("python3"), reason="the fixture's tests run with python3")


def uc(ws, *args, expect_exit=0):
    return call_core(ws, *args, expect_exit=expect_exit, env=env())


def human(ws, *args):
    process = subprocess.run([*COMMAND, "--workspace", ws, *args], capture_output=True, stdin=subprocess.DEVNULL,
                             text=True, encoding="utf-8", env=env())
    assert process.returncode == 0, process.stderr
    return process.stdout.splitlines()


def runs(ws):
    return sorted(os.listdir(os.path.join(ws, ".use-cases", "runs")))


def gate(ws):
    """The gate's exit code and its document: it may exit 1, which is still an answer."""
    process = subprocess.run([*COMMAND, "--workspace", ws, "--json", "status", "--gate"], capture_output=True,
                             stdin=subprocess.DEVNULL, text=True, encoding="utf-8", env=env())
    assert process.returncode in (0, 1), process.stderr
    return process.returncode, without_store(json.loads(process.stdout))


def without_store(document):
    """What prune may change in a status document: the store's own line (its runs and its size)."""
    return {key: value for key, value in document.items() if key != "store"}


@pytest.fixture
def ws(tmp_path):
    target = tmp_path / "py"
    shutil.copytree(os.path.join(FIXTURES, "python", "3-bridge"), target,
                    ignore=shutil.ignore_patterns("__pycache__", ".pytest_cache"))
    return str(target)


@pytest.fixture
def twice(ws):
    """Two verify runs of the same code: the older is superseded by the newer."""
    older = uc(ws, "verify", "--run")["run_id"]
    newer = uc(ws, "verify", "--run")["run_id"]
    assert runs(ws) == [older, newer]
    return ws, older, newer


# @use-case:store.prune#acceptance.no-answer-changes
def test_prune_removes_the_older_run_and_no_answer_of_status_or_the_gate_changes(twice):
    ws, older, newer = twice
    status = uc(ws, "status")
    gated = gate(ws)
    assert status["store"]["runs"] == 2 and status["store"]["superseded"] == 1

    pruned = uc(ws, "prune")

    assert [run["run_id"] for run in pruned["removed"]] == [older]
    assert pruned["dry_run"] is False and pruned["bytes"] == pruned["removed"][0]["bytes"] > 0
    assert runs(ws) == [newer]
    after = uc(ws, "status")
    assert without_store(after) == without_store(status)
    assert after["store"]["runs"] == 1 and after["store"]["superseded"] == 0
    assert gate(ws) == gated
# @use-case:end store.prune#acceptance.no-answer-changes


# @use-case:store.prune#acceptance.dry-run
def test_a_dry_run_names_the_older_run_and_leaves_both(twice):
    ws, older, newer = twice

    preview = uc(ws, "prune", "--dry-run")

    assert preview["dry_run"] is True
    assert [run["run_id"] for run in preview["removed"]] == [older]
    assert runs(ws) == [older, newer]
    assert human(ws, "prune", "--dry-run")[0].startswith(f"would remove  run {older}  ")
# @use-case:end store.prune#acceptance.dry-run


def test_the_documents_follow_the_published_schema(twice):
    ws, older, _ = twice

    for document in (uc(ws, "prune", "--dry-run"), uc(ws, "prune"), uc(ws, "prune"), uc(ws, "status")):
        assert problems(f"cli-{document['command']}.schema.json", document, document["command"]) == []


# @use-case:store.prune#acceptance.dry-run
def test_nothing_to_prune_says_so_and_status_names_the_store(twice):
    ws, older, newer = twice
    lines = human(ws, "status")
    assert any(line.startswith("results: 2 runs · ") and line.endswith(" · 1 superseded") for line in lines)

    human(ws, "prune")

    assert human(ws, "prune") == ["nothing to prune"]
    assert runs(ws) == [newer]
    assert not any("superseded" in line or "prune" in line for line in human(ws, "status"))
# @use-case:end store.prune#acceptance.dry-run


def test_a_run_that_never_finished_is_never_pruned(twice):
    ws, older, newer = twice
    started = uc(ws, "verify", "--start")["run_id"]

    uc(ws, "prune")

    assert runs(ws) == sorted([newer, started])
    uc(ws, "verify", "--abort", "--run-id", started)


# @use-case:store.prune#acceptance.no-answer-changes
def test_a_run_that_holds_the_newest_reason_for_a_route_is_kept_until_a_later_run_says_it_again(tmp_path):
    """A run whose tests did not run has no results, only the reason for each route ("its test didn't run"). A later
    run for one use case leaves that reason the newest for every other route, so the run is kept; a later run with the
    same reasons supersedes it. Either way no note in status changes."""
    ws = str(tmp_path / "shop")
    shutil.copytree(os.path.join(FIXTURES, "monorepo", "3-bridge"), ws)

    def started_and_finished():
        run_id = uc(ws, "verify", "--start")["run_id"]
        uc(ws, "verify", "--finish", "--run-id", run_id)
        return run_id

    reasons = started_and_finished()
    route = uc(ws, "status", "shop.rules.bulk-discount")["use_cases"][0]["routes"][0]["route"]
    recorded = uc(ws, "record", "shop.rules.bulk-discount", route, "pass")["run_id"]
    before = uc(ws, "status")
    assert any("its test didn't run" in (r["note"] or "") for u in before["use_cases"] for r in u["routes"])

    assert uc(ws, "prune")["removed"] == []
    assert without_store(uc(ws, "status")) == without_store(before)

    again = started_and_finished()
    before = uc(ws, "status")
    gated = gate(ws)

    assert [run["run_id"] for run in uc(ws, "prune")["removed"]] == [reasons]
    assert runs(ws) == sorted([recorded, again])
    assert without_store(uc(ws, "status")) == without_store(before)
    assert gate(ws) == gated
# @use-case:end store.prune#acceptance.no-answer-changes


def test_code_back_at_an_older_state_keeps_the_run_that_decides_it(ws):
    """Verify, change the code, verify, put the code back: the first run decides the routes again, so prune keeps it
    and status and the gate answer exactly as before."""
    path = os.path.join(ws, "src", "invoicing", "invoice.py")
    with open(path) as handle:
        original = handle.read()
    assert original.count("        return taken\n") == 1
    uc(ws, "verify", "--run")
    with open(path, "w") as handle:
        handle.write(original.replace("        return taken\n", "        return taken  # after every discount\n"))
    uc(ws, "verify", "--run")
    with open(path, "w") as handle:
        handle.write(original)

    before, gated = uc(ws, "status"), gate(ws)
    pruned = uc(ws, "prune")

    assert pruned["removed"] == [] and pruned["kept"] == []
    assert len(runs(ws)) == 2
    assert uc(ws, "status") == before
    assert gate(ws) == gated


# @use-case:store.prune#acceptance.refused
def test_an_invalid_workspace_is_refused_and_nothing_is_removed(twice):
    ws, older, newer = twice
    with open(os.path.join(ws, "use-cases", "broken.yml"), "w") as handle:
        handle.write("use_cases: [\n")

    message = uc(ws, "prune", expect_exit=2)

    assert message
    assert runs(ws) == [older, newer]
# @use-case:end store.prune#acceptance.refused
