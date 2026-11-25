"""Sign-off (chapter 21, ADR 032): an approval is recorded on the use case itself, pinned to its promise as it read
then; a later change to the promise reads "changed since approved"; with sign_off: required the gate holds what is
not approved: critical blocks, the rest warn, --strict blocks all, drafts never.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_signoff.py -v
"""

import datetime
import json
import subprocess
import sys

import pytest
import yaml
from conftest import call_core, COMMAND

TODAY = datetime.date.today().isoformat()


def use_case(local, tier):
    return (f"  - id: {local}\n    title: {local}\n    value_tier: {tier}\n    intent: {local}.\n"
            f"    scenarios:\n      - id: s\n        when: [x]\n        then: [y]\n"
            f"    validation:\n      - id: manual\n        type: {{ kind: acceptance }}\n        covers: [s]\n"
            f"        procedure:\n          steps: [Check it.]\n")


@pytest.fixture
def ws(tmp_path):
    root = tmp_path / "shop"
    (root / "use-cases").mkdir(parents=True)
    (root / "use-cases.yml").write_text("schema_version: 1\nroot: true\nprefix: shop\n")
    (root / "use-cases" / "login.yml").write_text("prefix: login\nuse_cases:\n" + use_case("lockout", "critical")
                                                  + use_case("remember", "core") + use_case("hint", "supporting"))
    (root / "use-cases" / "cart.yml").write_text("prefix: cart\nuse_cases:\n  - id: share\n    title: Share a cart\n")  # a draft
    for local in ("lockout", "remember", "hint"):
        call_core(str(root), "record", f"shop.login.{local}", "manual", "pass")  # verified: only sign-off is left to gate
    return root


def uc(ws, *args, expect_exit=0):
    return call_core(str(ws), *args, expect_exit=expect_exit)


def approval(ws, use_case_id):
    return next(u for u in uc(ws, "status")["use_cases"] if u["use_case"] == use_case_id)["approval"]


def require_sign_off(ws):
    (ws / "use-cases.yml").write_text("schema_version: 1\nroot: true\nprefix: shop\nsign_off: required\n")


def edit(ws, old, new):
    path = ws / "use-cases" / "login.yml"
    text = path.read_text()
    assert old in text
    path.write_text(text.replace(old, new, 1))


def gate(ws, *flags):
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "--json", "status", "--gate", *flags],
                             capture_output=True, text=True, encoding="utf-8", stdin=subprocess.DEVNULL)
    assert process.returncode in (0, 1), process.stderr
    g = json.loads(process.stdout)["gate"]
    return ({b["use_case"]: b.get("approval") for b in g["blocking"]}, {w["use_case"]: w.get("approval") for w in g["warning"]},
            process.returncode)


# ------------------------------------------------------------------ recording a sign-off


def test_an_approval_is_recorded_on_the_use_case_itself(ws):
    assert approval(ws, "shop.login.lockout") == "unapproved"
    result = uc(ws, "approve", "shop.login.lockout", "--by", "Kim")
    assert result["use_cases"] == [{"use_case": "shop.login.lockout", "file": "use-cases/login.yml", "action": "approved"}]
    recorded = yaml.safe_load((ws / "use-cases" / "login.yml").read_text())["use_cases"][0]["approved"]
    assert recorded["by"] == "Kim" and recorded["on"] == TODAY and len(recorded["behaviour"]) == 64
    assert approval(ws, "shop.login.lockout") == "approved"
    assert uc(ws, "show", "shop.login.lockout")["approval"] == "approved"
    assert uc(ws, "approve", "shop.login.lockout", "--by", "Sam")["use_cases"][0]["action"] == "unchanged"


@pytest.mark.parametrize("old, new", [
    ("    title: lockout\n", "    title: Lock out after five tries\n"),
    ("    intent: lockout.\n", "    intent: Lock the account.\n"),
    ("    value_tier: critical\n", "    value_tier: supporting\n"),  # downgrading the tier is a change too
    ("        then: [y]\n", "        then: [y, z]\n"),
])
def test_changing_the_promise_reads_changed_since_approved(ws, old, new):
    uc(ws, "approve", "shop.login.lockout", "--by", "Kim")
    edit(ws, old, new)
    assert approval(ws, "shop.login.lockout") == "changed"
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "status", "shop.login"], capture_output=True,
                             text=True, encoding="utf-8")
    assert "changed since approved" in process.stdout


def test_changing_how_it_is_proven_keeps_the_approval(ws):
    uc(ws, "approve", "shop.login.lockout", "--by", "Kim")
    edit(ws, "          steps: [Check it.]\n", "          steps: [Check it on staging.]\n")
    assert approval(ws, "shop.login.lockout") == "approved"


def test_approving_everything_at_once_and_its_rules(ws):
    result = uc(ws, "approve", "--all", "--by", "Kim")
    assert [u["use_case"] for u in result["use_cases"]] == ["shop.cart.share", "shop.login.hint", "shop.login.lockout",
                                                             "shop.login.remember"]
    assert sorted(c["path"] for c in result["changes"]) == ["use-cases/cart.yml", "use-cases/login.yml"]
    assert "not both" in uc(ws, "approve", "shop.login.hint", "--all", "--by", "Kim", expect_exit=2)
    assert "not both" in uc(ws, "approve", "--by", "Kim", expect_exit=2)
    assert "names who signed off" in uc(ws, "approve", "--all", "--by", " ", expect_exit=2)
    assert "no use case" in uc(ws, "approve", "shop.login.nope", "--by", "Kim", expect_exit=2)


def test_an_approve_dry_run_writes_nothing(ws):
    before = (ws / "use-cases" / "login.yml").read_text()
    assert uc(ws, "approve", "--all", "--by", "Kim", "--dry-run")["dry_run"] is True
    assert (ws / "use-cases" / "login.yml").read_text() == before


# ------------------------------------------------------------------ only approve and apply --approved-by write one


def save(ws, definition, expect_exit=0):
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "--json", "save", "--file", "-"],
                             input=json.dumps(definition), capture_output=True, text=True, encoding="utf-8")
    assert process.returncode == expect_exit, process.stderr
    return json.loads(process.stdout)


def test_save_never_writes_an_approval(ws):
    uc(ws, "approve", "shop.login.lockout", "--by", "Kim")
    shown = uc(ws, "show", "shop.login.lockout")["definition"]
    assert save(ws, shown)["action"] == "unchanged"  # show then save: the approval comes back as it was
    forged = {**shown, "title": "Changed", "approved": {**shown["approved"], "by": "Someone"}}
    assert "never by save" in save(ws, forged, expect_exit=2)["error"]["message"]
    fresh = {"id": "shop.login.new", "title": "New", "approved": shown["approved"]}
    assert "never by save" in save(ws, fresh, expect_exit=2)["error"]["message"]


def test_a_save_without_one_keeps_the_approval_so_the_change_shows(ws):
    uc(ws, "approve", "shop.login.lockout", "--by", "Kim")
    shown = uc(ws, "show", "shop.login.lockout")["definition"]
    save(ws, {k: v for k, v in shown.items() if k != "approved"} | {"title": "Lock out after five tries"})
    assert approval(ws, "shop.login.lockout") == "changed"


def test_a_signed_off_batch_approves_each_use_case_it_saves(ws):
    shown = uc(ws, "show", "shop.login.lockout")["definition"]
    batch = {"remove": ["shop.login.hint"], "save": [{**shown, "title": "Lock out after five tries"},
                                                     {"id": "shop.login.reset", "title": "Reset a password"}]}
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "--json", "apply", "--file", "-", "--approved-by", "Kim"],
                             input=json.dumps(batch), capture_output=True, text=True, encoding="utf-8")
    assert process.returncode == 0, process.stderr
    assert approval(ws, "shop.login.lockout") == "approved" and approval(ws, "shop.login.reset") == "approved"
    assert approval(ws, "shop.login.remember") == "unapproved"  # not in the batch


# ------------------------------------------------------------------ the gate


def test_without_sign_off_required_approvals_never_gate(ws):
    assert gate(ws) == ({}, {}, 0) and gate(ws, "--strict") == ({}, {}, 0)


def test_with_sign_off_required_critical_blocks_the_rest_warn_strict_blocks_all(ws):
    require_sign_off(ws)
    assert gate(ws) == ({"shop.login.lockout": "unapproved"},
                        {"shop.login.hint": "unapproved", "shop.login.remember": "unapproved"}, 1)
    assert gate(ws, "--strict")[0] == {"shop.login.lockout": "unapproved", "shop.login.remember": "unapproved",
                                       "shop.login.hint": "unapproved"}
    uc(ws, "approve", "--all", "--by", "Kim")
    assert gate(ws) == ({}, {}, 0) and gate(ws, "--strict") == ({}, {}, 0)  # the draft never blocked either way


def test_a_changed_critical_promise_blocks_until_approved_again(ws):
    require_sign_off(ws)
    uc(ws, "approve", "--all", "--by", "Kim")
    edit(ws, "    intent: lockout.\n", "    intent: Lock the account.\n")
    assert gate(ws)[0] == {"shop.login.lockout": "changed"}
    uc(ws, "record", "shop.login.lockout", "manual", "pass")  # the intent change staled its verdict; verified again
    uc(ws, "approve", "shop.login.lockout", "--by", "Kim")
    assert gate(ws) == ({}, {}, 0)


def test_people_see_why_the_gate_holds(ws):
    require_sign_off(ws)
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "status", "--gate"], capture_output=True,
                             text=True, encoding="utf-8")
    assert process.returncode == 1
    assert "shop.login.lockout" in process.stdout and "(not approved)" in process.stdout
    assert "1 block (1 not approved)" in process.stdout


def test_sign_off_is_root_only(ws):
    child = ws / "services" / "pay"
    (child / "use-cases").mkdir(parents=True)
    (child / "use-cases.yml").write_text("schema_version: 1\nprefix: pay\nsign_off: required\n")
    assert "sign_off is root-only" in uc(ws, "validate", expect_exit=2)


def test_not_approved_is_said_only_where_it_gates(ws):
    detail = lambda: subprocess.run([*COMMAND, "--workspace", str(ws), "status", "shop.login.lockout"],
                                    capture_output=True, text=True, encoding="utf-8").stdout
    assert "sign-off" not in detail()  # no gate: an unapproved use case is the normal case, nothing to say
    require_sign_off(ws)
    assert "sign-off: not approved" in detail()
