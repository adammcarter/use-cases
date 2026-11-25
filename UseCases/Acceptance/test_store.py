"""Chapter 12: the store is evidence only when sealed and intact, and run IDs only go up.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_store.py -v
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

import pytest
from conftest import COMMAND, call_core

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

USE_CASES = """
use_cases:
  - id: success
    title: Success
    value_tier: core
    intent: Demonstrate success.
    scenarios:
      - id: success
        when: [Perform the action.]
        then: [Success is visible.]
    validation:
      - id: manual
        type: { kind: acceptance }
        covers: [success]
        procedure:
          steps: [Perform the action and observe success.]
"""


def uc(ws, *args, expect_exit=0):
    return call_core(ws, *args, expect_exit=expect_exit)


def route_status(ws):
    return uc(ws, "status")["use_cases"][0]["routes"][0]["status"]


@pytest.fixture
def ws(tmp_path):
    (tmp_path / "use-cases").mkdir()
    (tmp_path / "use-cases.yml").write_text("schema_version: 1\nroot: true\nprefix: example\n")
    (tmp_path / "use-cases" / "success.yml").write_text(USE_CASES)
    return str(tmp_path)


def runs(ws):
    return sorted(os.listdir(os.path.join(ws, ".use-cases", "runs")))


def test_run_ids_only_go_up_and_follow_time_across_machines(ws):
    first = uc(ws, "record", "example.success", "manual", "fail")["run_id"]
    second = uc(ws, "record", "example.success", "manual", "pass")["run_id"]
    assert len(first) == 32 and int(second, 16) > int(first, 16)
    assert abs((int(second, 16) >> 80) - time.time() * 1000) < 60_000  # the top 48 bits are milliseconds since 1970
    assert route_status(ws) == "verified"
    with open(os.path.join(ws, ".use-cases", "run-order.json")) as handle:
        assert json.load(handle) == {"order_version": 1, "last_run_id": second}


def test_a_deleted_run_never_lowers_the_next_id(ws):
    uc(ws, "record", "example.success", "manual", "pass")
    last = uc(ws, "record", "example.success", "manual", "pass")["run_id"]
    shutil.rmtree(os.path.join(ws, ".use-cases", "runs", last))
    assert int(uc(ws, "record", "example.success", "manual", "pass")["run_id"], 16) > int(last, 16)


def test_stores_from_two_machines_merge_and_the_newer_verdict_wins(ws, tmp_path):
    """CI records a pass, a developer later records a fail; copying CI's runs in keeps the fail."""
    ci = str(tmp_path / "ci")
    shutil.copytree(ws, ci)
    uc(ci, "record", "example.success", "manual", "pass")
    time.sleep(0.01)
    uc(ws, "record", "example.success", "manual", "fail")
    for name in os.listdir(os.path.join(ci, ".use-cases", "runs")):
        shutil.copytree(os.path.join(ci, ".use-cases", "runs", name), os.path.join(ws, ".use-cases", "runs", name))
    assert route_status(ws) == "failed"
    uc(ws, "record", "example.success", "manual", "pass")  # allocation continues past both histories


def test_a_copied_store_without_its_allocation_file_keeps_working(ws):
    uc(ws, "record", "example.success", "manual", "pass")
    os.remove(os.path.join(ws, ".use-cases", "run-order.json"))
    uc(ws, "record", "example.success", "manual", "fail")
    assert route_status(ws) == "failed"


@pytest.mark.foreign_store  # this run is written the way a newer core might write one
def test_a_run_from_a_newer_core_is_read_through_its_envelope(ws):
    run_id = uc(ws, "record", "example.success", "manual", "fail")["run_id"]
    folder = os.path.join(ws, ".use-cases", "runs", run_id)
    newer = f"{int(run_id, 16) + 1:032x}"
    newer_folder = os.path.join(ws, ".use-cases", "runs", newer)
    os.makedirs(newer_folder)
    with open(os.path.join(folder, "results.jsonl")) as handle:
        result = json.loads(handle.readline())
    result.update({"record_version": 2, "status": "pass", "confidence": 0.99})
    open(os.path.join(newer_folder, "results.jsonl"), "w").write(json.dumps(result) + "\n")
    open(os.path.join(newer_folder, "run.json"), "w").write(json.dumps({"run_version": 2, "run_id": newer, "something_new": {}}))
    digest = lambda name: hashlib.sha256(open(os.path.join(newer_folder, name), "rb").read()).hexdigest()
    open(os.path.join(newer_folder, "completion.json"), "w").write(json.dumps({
        "completion_version": 2, "run_id": newer, "result_count": 1,
        "manifest_sha256": digest("run.json"), "results_sha256": digest("results.jsonl"), "new_digest_kind": {}}))
    assert route_status(ws) == "verified"  # the newer pass wins, read through the four envelope fields


@pytest.mark.parametrize("target", ["results.jsonl", "run.json", "completion.json"])
def test_a_tampered_sealed_run_is_a_storage_error_not_skipped(ws, target):
    run_id = uc(ws, "record", "example.success", "manual", "fail")["run_id"]
    path = os.path.join(ws, ".use-cases", "runs", run_id, target)
    with open(path) as handle:
        text = handle.read()
    with open(path, "w") as handle:
        handle.write({"results.jsonl": text.replace('"fail"', '"pass"'), "run.json": text.replace("\n", " \n", 1),
                      "completion.json": text.replace('"result_count": 1', '"result_count": 0')}[target])
    assert "is corrupt" in uc(ws, "status", expect_exit=2)


def test_an_unsealed_run_is_never_evidence(ws):
    run_id = uc(ws, "record", "example.success", "manual", "pass")["run_id"]
    os.remove(os.path.join(ws, ".use-cases", "runs", run_id, "completion.json"))
    assert route_status(ws) == "unverified"


def test_a_run_that_never_finished_is_a_workspace_warning_in_both_views_and_never_evidence(ws):
    run_id = uc(ws, "record", "example.success", "manual", "pass")["run_id"]
    assert not [w for w in uc(ws, "status")["warnings"] if "never finished" in w]  # sealed: nothing to say
    os.remove(os.path.join(ws, ".use-cases", "runs", run_id, "completion.json"))
    assert [w for w in uc(ws, "status")["warnings"] if w.startswith(f"run {run_id} never finished")] != []
    assert route_status(ws) == "unverified"
    process = subprocess.run([*COMMAND, "status"], cwd=ws, capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    assert f"warning: run {run_id[:8]} never finished" in process.stdout, process.stdout
    neighbour = run_id[:10] + ("1" if run_id[10] == "0" else "0") + "0" * 21  # another run that never finished, sharing the first 10 digits
    os.makedirs(os.path.join(ws, ".use-cases", "runs", neighbour))
    process = subprocess.run([*COMMAND, "status"], cwd=ws, capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    assert f"warning: run {run_id[:11]} never finished" in process.stdout, process.stdout  # the id grows to name only one run
    assert f"warning: run {neighbour[:11]} never finished" in process.stdout, process.stdout
    shutil.rmtree(os.path.join(ws, ".use-cases", "runs", neighbour))  # not a real run: the suite's store check would refuse it
    uc(ws, "record", "example.success", "manual", "pass")  # a later sealed run still counts, and the warning stays until the folder goes
    assert [w for w in uc(ws, "status")["warnings"] if w.startswith(f"run {run_id} never finished")] != []
    assert route_status(ws) == "verified"


def test_a_stray_folder_in_the_store_is_an_error(ws):
    uc(ws, "record", "example.success", "manual", "pass")
    os.makedirs(os.path.join(ws, ".use-cases", "runs", "latest"))
    assert "not a run folder" in uc(ws, "status", expect_exit=2)


def test_record_refuses_an_unknown_route_or_status(ws):
    assert "no route" in uc(ws, "record", "example.success", "nope", "pass", expect_exit=2)
    assert "status must be one of" in uc(ws, "record", "example.success", "manual", "verified", expect_exit=2)
    assert not os.path.exists(os.path.join(ws, ".use-cases", "runs"))


# ------------------------------------------------------------------ attachments (chapter 12 §16-17)


def test_an_attachment_is_kept_with_its_verdict_by_content(ws, tmp_path):
    evidence = tmp_path / "screen shot.png"
    evidence.write_bytes(b"\x89PNG fake image")
    run = uc(ws, "record", "example.success", "manual", "pass", "looked right", "--attach", str(evidence))
    descriptor = run["results"][0]["attachments"][0]
    assert descriptor["name"] == "screen shot.png" and descriptor["size_bytes"] == 15 and descriptor["media_type"] == "image/png"
    digest = descriptor["blob"].split(":")[1]
    assert open(os.path.join(ws, ".use-cases", "runs", run["run_id"], "attachments", "sha256", digest[:2], digest[2:]), "rb").read() == evidence.read_bytes()
    evidence.write_bytes(b"changed afterwards")
    assert route_status(ws) == "verified"  # the stored copy is the evidence


def test_a_damaged_attachment_is_reported_but_never_rewrites_the_verdict(ws, tmp_path):
    evidence = tmp_path / "log.txt"
    evidence.write_text("all good\n")
    run = uc(ws, "record", "example.success", "manual", "pass", "--attach", str(evidence))
    digest = run["results"][0]["attachments"][0]["blob"].split(":")[1]
    with open(os.path.join(ws, ".use-cases", "runs", run["run_id"], "attachments", "sha256", digest[:2], digest[2:]), "w") as handle:
        handle.write("tampered")
    status = uc(ws, "status")
    assert status["use_cases"][0]["status"] == "verified"
    assert any("is damaged" in w for w in status["warnings"])


def test_two_attachments_with_one_name_are_refused(ws, tmp_path):
    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    (tmp_path / "a" / "log.txt").write_text("1")
    (tmp_path / "b" / "log.txt").write_text("2")
    assert "names must be unique" in uc(ws, "record", "example.success", "manual", "pass", "--attach",
                                        str(tmp_path / "a" / "log.txt"), str(tmp_path / "b" / "log.txt"), expect_exit=2)
