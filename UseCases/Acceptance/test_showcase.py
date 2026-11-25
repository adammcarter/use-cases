"""Showcases (chapter 23, ADR 035): a showcase is planned, performed and thrown away; what it proved can be kept as an
ordinary verdict on a use case's "try it" check, with its evidence attached. No core change: this proves the existing
commands carry it, and that a kept showcase goes stale like any verdict once what it performed changes.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_showcase.py -v
"""

import os

import pytest
from conftest import call_core

USE_CASE = "shop.cart.drop"


@pytest.fixture
def ws(tmp_path):
    root = tmp_path / "shop"
    (root / "use-cases").mkdir(parents=True)
    (root / "use-cases.yml").write_text("schema_version: 1\nroot: true\nprefix: shop\n")
    (root / "use-cases" / "cart.yml").write_text(
        "prefix: cart\nuse_cases:\n  - id: drop\n    title: Drop a card onto another\n    value_tier: core\n"
        "    intent: A dropped card lands without flashing.\n"
        "    scenarios:\n      - id: drop\n        when: [A card is dropped onto another.]\n        then: [It lands, with no flash.]\n"
        "    validation:\n      - id: try-it\n        type: { kind: acceptance }\n        covers: [drop]\n"
        "        procedure:\n          steps: [Drag a card onto another., Watch the drop.]\n")
    return root


def uc(ws, *args, expect_exit=0):
    return call_core(str(ws), *args, expect_exit=expect_exit)


def try_it(ws):
    entry = uc(ws, "status", USE_CASE)["use_cases"][0]
    return entry["status"], next(r for r in entry["routes"] if r["route"] == "try-it")


# @use-case:showcase.kept#acceptance.kept
def test_a_showcase_kept_as_a_verdict_with_its_evidence(ws, tmp_path):
    assert try_it(ws)[0] == "unverified"  # not seen yet: nothing claims it works
    recording, notes = tmp_path / "drop.mov", tmp_path / "notes.txt"
    recording.write_bytes(b"\x00\x01 a recording of the drop")
    notes.write_text("Tried by Sam, live, on the test build: lands cleanly, no flash.\n")
    run = uc(ws, "record", USE_CASE, "try-it", "pass", "tried by Sam, live, on the test build",
             "--attach", str(recording), str(notes))
    result = run["results"][0]
    assert result["status"] == "pass" and result["message"] == "tried by Sam, live, on the test build"
    assert sorted(a["name"] for a in result["attachments"]) == ["drop.mov", "notes.txt"]
    for attachment in result["attachments"]:  # the evidence is kept with the verdict, by its content
        digest = attachment["blob"].split(":")[1]
        assert os.path.exists(os.path.join(ws, ".use-cases", "runs", run["run_id"], "attachments", "sha256", digest[:2], digest[2:]))
    status, route = try_it(ws)
    assert status == "verified" and route["status"] == "verified"
# @use-case:end showcase.kept#acceptance.kept


# @use-case:showcase.kept#acceptance.stale
def test_a_kept_showcase_goes_stale_when_what_it_performed_changes(ws):
    uc(ws, "record", USE_CASE, "try-it", "pass", "tried by Sam, live")
    path = ws / "use-cases" / "cart.yml"
    path.write_text(path.read_text().replace("Watch the drop.", "Watch the drop, at half speed."))
    assert try_it(ws)[0] == "stale"  # an old showcase never vouches for what it did not perform
# @use-case:end showcase.kept#acceptance.stale


# @use-case:showcase.kept#acceptance.blocks
def test_a_failed_showcase_blocks_the_gate(ws):
    uc(ws, "record", USE_CASE, "try-it", "fail", "the card flashes on drop")
    assert try_it(ws)[0] == "failed"
    assert uc(ws, "status", "--gate", expect_exit=1)["gate"]["passed"] is False
# @use-case:end showcase.kept#acceptance.blocks
