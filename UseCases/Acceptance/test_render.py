"""The canonical layouts (chapter 21 §7, ADR 033): intent, the brief's cards, the proposal and the results, drawn by
the core from what the agent supplies and what the workspace holds, the same in every repo. One proposal file is
rendered, signed off and applied as it is.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_render.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
from conftest import call_core, COMMAND
from test_languages import FIXTURES

DISCOUNTS = {"id": "invoicing.billing.discounts", "title": "Discounts never take a total below zero", "value_tier": "core",
             "intent": "A discount bigger than the invoice brings it to exactly zero.",
             "scenarios": [{"id": "capped-at-zero", "given": ["A 3.00 invoice."], "when": ["A 5.00 fixed discount is applied."],
                            "then": ["The total is 0.00."]},
                           {"id": "percent-cap", "when": ["A 150% discount is applied."], "then": ["The total is 0.00."]}],
             "out_of_scope": ["Negative totals as credit notes."],
             "validation": [{"id": "unit-tests", "type": {"kind": "unit"}, "covers": ["capped-at-zero", "percent-cap"]}]}
PROPOSAL = {"title": "Discounts and refunds", "remove": ["invoicing.billing.tax-regions"],
            "save": [DISCOUNTS, {"id": "invoicing.refunds.partial", "title": "Refund part of an invoice", "value_tier": "critical"}],
            "untouched": ["invoicing.billing.totals"], "you_see": {"invoicing.billing.discounts": "totals never go below 0.00"},
            "decisions": [{"question": "a refund larger than paid", "options": ["refused", "capped at what was paid"]}]}


@pytest.fixture
def ws(tmp_path):
    target = tmp_path / "py"
    shutil.copytree(os.path.join(FIXTURES, "python", "2-use-cases"), target)
    return target


def render(ws, kind, data, expect_exit=0, cwd=None, workspace=True):
    args = [*COMMAND] + (["--workspace", str(ws)] if workspace else []) + ["--json", "render", kind, "--file", "-"]
    process = subprocess.run(args, input=json.dumps(data), capture_output=True, text=True, encoding="utf-8", cwd=cwd)
    assert process.returncode == expect_exit, process.stderr
    return json.loads(process.stdout)


def text(ws, kind, data):
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "render", kind, "--file", "-"],
                             input=json.dumps(data), capture_output=True, text=True, encoding="utf-8")
    assert process.returncode == 0, process.stderr
    return process.stdout


# ------------------------------------------------------------------ intent


def test_intent_is_what_why_who_and_needs_no_workspace(tmp_path):
    out = render(None, "intent", {"what": "Refund part of an invoice", "why": "Customers return single items",
                                  "who": ["support staff", "customers"]}, cwd=tmp_path, workspace=False)
    assert out["text"].splitlines() == ["WHAT   Refund part of an invoice", "WHY    Customers return single items",
                                        "WHO    support staff · customers"]
    assert "intent has `what` and `why`" in render(None, "intent", {"what": "x"}, expect_exit=2, cwd=tmp_path, workspace=False)["error"]["message"]


# ------------------------------------------------------------------ the brief's cards


def test_a_card_for_each_change_with_its_id_top_right(ws):
    out = render(ws, "brief", PROPOSAL)
    assert [c["use_case"] for c in out["model"]["cards"]] == [
        "invoicing.refunds.partial", "invoicing.billing.discounts", "invoicing.billing.tax-regions"]  # untouched: no card
    lines = out["text"].splitlines()
    assert lines[0].endswith(" invoicing.refunds.partial ──┐") and lines[0].startswith("┌─")
    widths = {len(l) for l in lines if l}
    assert widths == {63}  # every row exactly as wide as the card, wrapped text included


def test_a_changed_card_shows_now_and_was_and_its_scenarios(ws):
    card = render(ws, "brief", PROPOSAL)["model"]["cards"][1]
    assert card["fit"] == "changes" and card["tier"] == "core"
    assert card["now"] == DISCOUNTS["intent"] and card["was"].startswith("A discount larger than the invoice")
    assert card["scenarios"] == [{"golden": True, "text": "given A 3.00 invoice: A 5.00 fixed discount is applied → The total is 0.00"},
                                 {"golden": False, "text": "A 150% discount is applied → The total is 0.00"}]
    assert card["not_included"] == ["Negative totals as credit notes."] and card["proven_by"] == ["unit tests"]
    picked = render(ws, "brief", {**PROPOSAL, "golden": {"invoicing.billing.discounts": ["percent-cap"]}})["model"]["cards"][1]
    assert [s["golden"] for s in picked["scenarios"]] == [False, True]


def test_a_replaced_card_shows_what_goes_and_nothing_more(ws):
    card = render(ws, "brief", PROPOSAL)["model"]["cards"][2]
    assert card["fit"] == "replaces" and card["now"] == "Removed." and card["was"].startswith("Each supported region")
    assert card["scenarios"] == [] and card["proven_by"] == []


def test_plain_text_has_no_escape_codes_outside_a_terminal(ws):
    assert "\033[" not in text(ws, "brief", PROPOSAL)
    assert text(ws, "proposal", PROPOSAL).rstrip("\n") == render(ws, "proposal", PROPOSAL)["text"]


# ------------------------------------------------------------------ the proposal


def test_the_proposal_is_the_whole_change_on_one_screen(ws):
    out = render(ws, "proposal", PROPOSAL)
    lines = out["text"].splitlines()
    assert lines[0] == "PROPOSAL · Discounts and refunds"
    assert [l.split()[:2] for l in lines[2:6]] == [["+", "NEW"], ["~", "CHANGES"], ["−", "REPLACES"], ["=", "UNTOUCHED"]]
    assert "you'll see: totals never go below 0.00" in lines[3] and "(checked, stays as it is)" in lines[5]
    assert "YOUR CALL    a refund larger than paid:  1) refused   2) capped at what was paid" in out["text"]
    assert out["model"]["sign_off"] == {"critical": 1, "core": 2}  # untouched is not signed off
    assert "SIGN-OFF     yours: 1 critical, 2 core" in out["text"]
    assert lines[-1].split()[0] == "ids" and lines[-1].endswith("invoicing.billing.totals")


def test_a_change_can_be_called_extends(ws):
    out = render(ws, "proposal", {**PROPOSAL, "fits": {"invoicing.billing.discounts": "extends"}})
    assert [c["fit"] for c in out["model"]["changes"]] == ["new", "extends", "replaces", "untouched"]


@pytest.mark.parametrize("change, message", [
    ({"title": ""}, "has a `title`"),
    ({"fits": {"invoicing.billing.discounts": "new"}}, "extends or changes"),
    ({"decisions": [{"question": "q", "options": ["only one"]}]}, "at least two `options`"),
    ({"colour": "blue"}, "unknown: colour"),
    ({"untouched": ["invoicing.billing.nope"]}, "no use case"),
])
def test_a_bad_proposal_is_refused(ws, change, message):
    assert message in render(ws, "proposal", {**PROPOSAL, **change}, expect_exit=2)["error"]["message"]


# ------------------------------------------------------------------ the same file is applied, then its results drawn


def test_the_proposal_file_is_applied_as_it_is_and_its_results_drawn(ws):
    assert "apply the proposal before its results" in render(ws, "results", PROPOSAL, expect_exit=2)["error"]["message"]
    adds_only = {**PROPOSAL, "remove": []}
    assert "apply the proposal before its results" in render(ws, "results", adds_only, expect_exit=2)["error"]["message"]
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "--json", "apply", "--file", "-"],
                             input=json.dumps(PROPOSAL), capture_output=True, text=True, encoding="utf-8")
    assert process.returncode == 0, process.stderr
    applied = json.loads(process.stdout)["use_cases"]
    shown = [c for c in render(ws, "proposal", {**PROPOSAL, "remove": [], "save": [DISCOUNTS]})["model"]["changes"]]
    assert [u["action"] for u in applied] == ["removed", "created", "replaced"]
    results = render(ws, "results", PROPOSAL)["model"]
    assert [(u["use_case"], u["status"]) for u in results["use_cases"]] == [
        ("invoicing.billing.discounts", "unverified"), ("invoicing.refunds.partial", "draft")]
    assert results["use_cases"][0]["checks"] == [{"label": "unit-tests", "status": "unverified"}]
    assert results["removed"] == ["invoicing.billing.tax-regions"] and results["gate"] is True
    assert shown[0]["fit"] == "changes"  # after apply, the saved use case exists: rendered again it is a change, not new
