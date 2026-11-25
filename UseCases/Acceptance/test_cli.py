"""The command line (chapter 16): the workspace is found by walking up, --json is one document that follows
the published schemas, exit codes mean the same everywhere, status filters and explains, the gate follows its
table, record can ask, and hints guide without ever reaching a script.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_cli.py -v
"""

import json
import os
import subprocess
import sys

import pytest
from conftest import POSIX_ONLY, call_core, COMMAND

GATING = "        procedure:\n          steps: [Check it.]\n"


def use_case(local, draft=False, extra_route=""):
    tier = "" if draft else "    value_tier: core\n"
    return (f"  - id: {local}\n    title: {local.title()}\n{tier}    intent: {local}.\n"
            f"    scenarios:\n      - id: s\n        when: [x]\n        then: [y]\n"
            f"    validation:\n      - id: check\n        type: {{ kind: acceptance }}\n        covers: [s]\n{GATING}{extra_route}")


NON_GATING = ("      - id: extra\n        type: { kind: acceptance }\n        covers: [s]\n        gates_verification: false\n"
              "        procedure:\n          steps: [Look again.]\n")


@pytest.fixture
def ws(tmp_path):
    root = tmp_path / "shop"
    (root / "use-cases").mkdir(parents=True)
    (root / "use-cases.yml").write_text("schema_version: 1\nroot: true\nprefix: shop\n")
    (root / "use-cases" / "pay.yml").write_text("prefix: pay\nuse_cases:\n" + "".join(
        use_case(l, extra_route=NON_GATING if l == "card" else "") for l in ("card", "wallet", "refund", "voucher", "gift")))
    (root / "use-cases" / "cart.yml").write_text("prefix: cart\nuse_cases:\n" + use_case("share", draft=True) + use_case("add"))
    return str(root)


def uc(ws, *args, expect_exit=0):
    return call_core(ws, *args, expect_exit=expect_exit)


def human(cwd, *args, env=None):
    """As a person types it: no --json, no --workspace."""
    process = subprocess.run([*COMMAND, *args], cwd=cwd, capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8",
                             env={**os.environ, **(env or {})})
    return process.returncode, process.stdout, process.stderr


def record(ws, use_case_id, verdict, route="check"):
    uc(ws, "record", use_case_id, route, verdict)


def edit_intent(ws, local):
    path = os.path.join(ws, "use-cases", "pay.yml")
    with open(path) as handle:
        text = handle.read()
    with open(path, "w") as handle:
        handle.write(text.replace(f"    intent: {local}.\n", f"    intent: {local}, changed.\n"))


@pytest.fixture
def every_state(ws):
    """card failed (its non-gating route passes), wallet error, refund stale, voucher incomplete,
    gift unverified, cart.add verified, cart.share draft."""
    record(ws, "shop.pay.card", "fail")
    record(ws, "shop.pay.card", "pass", route="extra")
    record(ws, "shop.pay.wallet", "error")
    record(ws, "shop.pay.refund", "pass")
    edit_intent(ws, "refund")
    record(ws, "shop.pay.voucher", "incomplete")
    record(ws, "shop.cart.add", "pass")
    return ws


# ------------------------------------------------------------------ status: order, filters, detail (§9)


def test_a_checkout_where_nothing_has_run_says_so_in_one_line(ws):
    code, out, _ = human(ws, "status")
    assert code == 0 and out.splitlines() == ["no verdicts in this checkout yet: 6 use cases (1 draft), none run here",
                                              "→ use-cases verify --start   for a baseline, if you want one"]
    assert [u["status"] for u in uc(ws, "status")["use_cases"] if u["state"] == "READY"] == ["unverified"] * 6  # --json unchanged
    assert "shop.pay.card" in human(ws, "status", "--state", "unverified")[1]  # a filtered view lists as ever
    record(ws, "shop.cart.add", "pass")
    assert "no verdicts in this checkout" not in human(ws, "status")[1]



def test_status_lists_worst_first_then_drafts(every_state):
    status = uc(every_state, "status")
    assert [(u["use_case"], u["status"]) for u in status["use_cases"]] == [
        ("shop.pay.card", "failed"), ("shop.pay.wallet", "error"), ("shop.pay.voucher", "incomplete"),
        ("shop.pay.gift", "unverified"), ("shop.pay.refund", "stale"), ("shop.cart.add", "verified"),
        ("shop.cart.share", "draft")]
    assert status["summary"] == {"total": 7, "by_status": {"failed": 1, "error": 1, "incomplete": 1, "unverified": 1,
                                                          "stale": 1, "verified": 1, "draft": 1}}


def test_state_filters_and_a_prefix_narrows(every_state):
    assert [u["use_case"] for u in uc(every_state, "status", "--state", "failed,stale")["use_cases"]] == [
        "shop.pay.card", "shop.pay.refund"]
    assert [u["use_case"] for u in uc(every_state, "status", "--state", "draft")["use_cases"]] == ["shop.cart.share"]
    assert [u["use_case"] for u in uc(every_state, "status", "shop.cart")["use_cases"]] == ["shop.cart.add", "shop.cart.share"]
    assert [u["use_case"] for u in uc(every_state, "status", "shop.pay", "--state", "stale")["use_cases"]] == ["shop.pay.refund"]


def test_one_use_case_in_detail_says_why(every_state):
    code, out, _ = human(every_state, "status", "shop.pay.refund")
    assert code == 0 and "stale" in out and "changed since run" in out and "check" in out
    code, out, _ = human(every_state, "status", "shop.pay.card")
    assert "extra" in out and "no " in out  # the non-gating route is listed, marked as not gating


@pytest.mark.parametrize("args, message", [
    (["status", "--state", "broken"], "unknown: broken"),
    (["status", "shop.nope"], "no use case or id prefix"),
    (["links", "shop.nope"], "no use case or id prefix"),
    (["status", "--gate", "--state", "failed"], "cannot be combined"),
    (["status", "shop.pay.card", "--gate"], "cannot be combined"),
    (["status", "--strict"], "--strict belongs with --gate"),
    (["verify"], "say which step"),
    (["verify", "--finish", "--only", "x"], "--only belongs on"),
    (["record", "shop.pay.card"], "missing: route, status"),
    (["record", "shop.pay.card", "check", "maybe"], "status must be one of"),
    (["nosuch"], "invalid choice"),
])
def test_usage_errors_exit_2_with_kind_usage(ws, args, message):
    process = subprocess.run([*COMMAND, "--workspace", ws, "--json", *args], capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    document = json.loads(process.stdout)
    assert process.returncode == 2 and document["error"]["kind"] == "usage" and message in document["error"]["message"]
    assert message in process.stderr  # a person still sees it


# ------------------------------------------------------------------ the gate (§10)


def gate(ws, *extra, expect_exit):
    return uc(ws, "status", "--gate", *extra, expect_exit=expect_exit)["gate"]


def test_the_default_gate_blocks_failed_error_and_stale_and_warns_on_the_rest(every_state):
    result = gate(every_state, expect_exit=1)
    assert not result["passed"] and not result["strict"]
    assert {(b["use_case"], b["status"]) for b in result["blocking"]} == {
        ("shop.pay.card", "failed"), ("shop.pay.wallet", "error"), ("shop.pay.refund", "stale")}
    assert {(w["use_case"], w["status"]) for w in result["warning"]} == {
        ("shop.pay.voucher", "incomplete"), ("shop.pay.gift", "unverified")}


def test_strict_blocks_everything_not_verified_but_never_a_draft(every_state):
    result = gate(every_state, "--strict", expect_exit=1)
    assert {b["use_case"] for b in result["blocking"]} == {
        "shop.pay.card", "shop.pay.wallet", "shop.pay.refund", "shop.pay.voucher", "shop.pay.gift"}
    assert result["warning"] == []


@pytest.mark.parametrize("verdict, blocks", [("fail", True), ("error", True), ("incomplete", False)])
def test_each_status_on_its_own(ws, verdict, blocks):
    for local in ("card", "wallet", "refund", "voucher", "gift"):
        record(ws, f"shop.pay.{local}", "pass")
    record(ws, "shop.cart.add", "pass")
    record(ws, "shop.pay.card", verdict)
    result = gate(ws, expect_exit=1 if blocks else 0)
    assert result["passed"] is not blocks


def test_stale_alone_blocks(ws):
    for use_case_id in ("shop.pay.card", "shop.pay.wallet", "shop.pay.refund", "shop.pay.voucher", "shop.pay.gift", "shop.cart.add"):
        record(ws, use_case_id, "pass")
    assert gate(ws, "--strict", expect_exit=0)["passed"]
    edit_intent(ws, "card")
    assert gate(ws, expect_exit=1)["blocking"] == [{"use_case": "shop.pay.card", "status": "stale"}]


def test_a_failing_non_gating_route_never_blocks(ws):
    for use_case_id in ("shop.pay.card", "shop.pay.wallet", "shop.pay.refund", "shop.pay.voucher", "shop.pay.gift", "shop.cart.add"):
        record(ws, use_case_id, "pass")
    record(ws, "shop.pay.card", "fail", route="extra")
    assert gate(ws, "--strict", expect_exit=0)["passed"]


def test_an_invalid_workspace_blocks_with_exit_2(ws):
    with open(os.path.join(ws, "use-cases", "cart.yml"), "a") as handle:
        handle.write("    stray: true\n")
    process = subprocess.run([*COMMAND, "--workspace", ws, "--json", "status", "--gate"], capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    assert process.returncode == 2 and json.loads(process.stdout)["error"]["kind"] == "invalid"


# ------------------------------------------------------------------ finding the workspace (§3)


def test_the_workspace_is_found_from_any_folder_below_it(ws):
    below = os.path.join(ws, "use-cases", "deep", "er")
    os.makedirs(below)
    code, out, _ = human(below, "validate")
    assert code == 0 and "valid" in out and "7 use cases" in out


def test_a_child_scope_is_passed_over_on_the_way_up(ws):
    child = os.path.join(ws, "services", "pay")
    os.makedirs(os.path.join(child, "use-cases"))
    with open(os.path.join(child, "use-cases.yml"), "w") as handle:
        handle.write("schema_version: 1\nprefix: svc\n")
    code, out, _ = human(child, "status", "shop.pay", "--quiet")  # found from below: the root's ids, not svc's
    assert code == 0 and "shop.pay.card" in out


def test_a_nested_root_is_its_own_workspace(ws):
    nested = os.path.join(ws, "vendor", "lib")
    os.makedirs(os.path.join(nested, "use-cases"))
    with open(os.path.join(nested, "use-cases.yml"), "w") as handle:
        handle.write("schema_version: 1\nroot: true\nprefix: lib\n")
    code, out, _ = human(nested, "validate")
    assert code == 0 and "0 use cases" in out


def test_no_workspace_above_is_a_clear_refusal(tmp_path):
    code, _, err = human(str(tmp_path), "validate")
    assert code == 2 and "no use-cases.yml with root: true" in err and "use-cases init" in err


def test_a_child_scope_named_directly_is_refused(ws):
    child = os.path.join(ws, "services", "pay")
    os.makedirs(os.path.join(child, "use-cases"))
    with open(os.path.join(child, "use-cases.yml"), "w") as handle:
        handle.write("schema_version: 1\nprefix: svc\n")
    assert "child scope" in uc(child, "validate", expect_exit=2)


# ------------------------------------------------------------------ output, help, version (§4-§7, §13)


def test_plain_use_cases_is_help(ws):
    for args in ([], ["--help"]):
        code, out, _ = human(ws, *args)
        assert code == 0 and "validate" in out and "verify --start" in out and "record --interactive" in out


def test_version(ws):
    process = subprocess.run([*COMMAND, "--version", "--json"], capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    document = json.loads(process.stdout)
    assert document["command"] == "version" and document["contract"] == 1 and document["store"] == 1
    assert human(ws, "--version")[1].startswith("use-cases ")


def test_human_output_leads_with_the_worst_and_ends_with_one_hint(every_state):
    code, out, _ = human(every_state, "status")
    lines = out.strip().splitlines()
    assert code == 0 and lines[0].startswith("✗ failed") and "shop.pay.card" in lines[0]
    assert lines[-1] == "→ use-cases status shop.pay.card   to see why"
    assert sum(1 for l in lines if l.startswith("→")) == 1
    assert "\033[" not in out  # not a terminal: no colour


def test_the_hint_after_status_offers_run_when_a_validation_has_a_run_command_else_start(ws):
    bridge = os.path.join(ws, "use-cases-bridge.yml")
    with open(bridge, "w") as handle:
        handle.write("schema_version: 1\nvalidations:\n  - id: check\n    report: check.txt\n"
                     "    run: [sh, -c, 'true > \"$1\"', sh, \"{report}\"]\n    transformer: exit-code\n    settings:\n      file: src/ok.sh\n")
    assert human(ws, "status")[1].splitlines()[-1] == "→ use-cases verify --run   for a baseline, if you want one"  # nothing has run
    record(ws, "shop.cart.add", "pass")  # now the full list shows; the rest are unverified
    assert human(ws, "status")[1].splitlines()[-1] == "→ use-cases verify --run"
    os.remove(bridge)
    assert human(ws, "status")[1].splitlines()[-1] == "→ use-cases verify --start"


def test_quiet_removes_the_hint_and_json_never_has_one(every_state):
    assert "→" not in human(every_state, "status", "--quiet")[1]
    code, out, _ = human(every_state, "status", "--json")
    assert "→" not in out and json.loads(out)["command"] == "status"


def test_json_is_exactly_one_document_for_every_command(every_state):
    for args in (["validate"], ["status"], ["status", "--gate"], ["links"], ["record", "shop.cart.add", "check", "pass"],
                 ["status", "nosuch"]):
        process = subprocess.run([*COMMAND, "--workspace", every_state, "--json", *args], capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
        document = json.loads(process.stdout)  # one document, nothing else on stdout
        assert document["output_version"] == 1 and document["command"] == args[0]


def test_a_refusal_has_kind_refused(ws):
    with open(os.path.join(ws, "use-cases-bridge.yml"), "w") as handle:
        handle.write("schema_version: 1\nvalidations:\n  - id: t\n    transformer: exit-code\n")
    process = subprocess.run([*COMMAND, "--workspace", ws, "--json", "verify", "--finish"], capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    document = json.loads(process.stdout)
    assert process.returncode == 2 and document["error"]["kind"] == "refused" and "no started run" in document["error"]["message"]


def test_a_draft_cannot_be_recorded_and_that_is_a_refusal(ws):
    process = subprocess.run([*COMMAND, "--workspace", ws, "--json", "record", "shop.cart.share", "check", "pass"],
                             capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    assert process.returncode == 2 and json.loads(process.stdout)["error"]["kind"] == "refused"


# ------------------------------------------------------------------ record --interactive (§12)


def test_interactive_needs_a_terminal(ws):
    process = subprocess.run([*COMMAND, "--workspace", ws, "record", "--interactive"], capture_output=True,
                             text=True, encoding="utf-8", stdin=subprocess.DEVNULL)
    assert process.returncode == 2 and "needs a terminal" in process.stderr
    process = subprocess.run([*COMMAND, "--workspace", ws, "--json", "record", "--interactive"], capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    assert process.returncode == 2 and json.loads(process.stdout)["error"]["kind"] == "usage"


@POSIX_ONLY
def test_interactive_input_that_ends_is_a_refusal_not_a_hang(ws):
    import pty
    leader, follower = pty.openpty()
    process = subprocess.Popen([*COMMAND, "--workspace", ws, "record", "--interactive"],
                               stdin=follower, stdout=follower, stderr=subprocess.PIPE, close_fds=True)
    os.close(follower)
    os.write(leader, b"\x04")  # end of input, as Ctrl-D sends it
    _, err = process.communicate(timeout=15)
    os.close(leader)
    assert process.returncode == 2 and b"input ended" in err


@POSIX_ONLY
def test_interactive_asks_for_each_value_and_shows_the_steps(ws):
    import pty
    import select
    import time
    leader, follower = pty.openpty()
    process = subprocess.Popen([*COMMAND, "--workspace", ws, "record", "--interactive"],
                               stdin=follower, stdout=follower, stderr=follower, close_fds=True)
    os.close(follower)
    seen = b""

    def wait_for(text, timeout=15):
        nonlocal seen
        deadline = time.monotonic() + timeout
        while text.encode() not in seen and time.monotonic() < deadline:
            ready, _, _ = select.select([leader], [], [], 0.2)
            if ready:
                try:
                    seen += os.read(leader, 4096)
                except OSError:
                    break
        assert text.encode() in seen, seen.decode(errors="replace")

    def answer(text):
        """Type only once the prompt is showing: a terminal may drop what was typed before it."""
        nonlocal seen
        deadline = time.monotonic() + 15
        while not seen.rstrip(b" ").endswith(b">") and time.monotonic() < deadline:
            ready, _, _ = select.select([leader], [], [], 0.2)
            if ready:
                seen += os.read(leader, 4096)
        os.write(leader, text.encode() + b"\n")

    wait_for("Use case?")
    assert b"shop.cart.share" not in seen  # only READY use cases are offered
    answer("shop.pay.v")  # an unambiguous prefix
    wait_for("Route?")
    answer("1")
    wait_for("Steps: 1. Check it.")
    wait_for("Result?")
    answer("pass")
    wait_for("Note?")
    answer("checked by hand")
    wait_for("recorded: shop.pay.voucher / check")
    assert process.wait(timeout=15) == 0
    os.close(leader)
    detail = uc(ws, "status", "shop.pay.voucher")["use_cases"][0]
    assert detail["status"] == "verified"


# ------------------------------------------------------------------ code moved out of its markers (chapter 08)


@pytest.mark.parametrize("inside", ["", "\n\n   \n"])
def test_an_emptied_marked_region_is_said_everywhere_people_look(ws, inside):
    os.makedirs(os.path.join(ws, "src"))
    with open(os.path.join(ws, "src", "pay.py"), "w") as handle:
        handle.write(f"# @use-case:shop.pay.card#charge\n{inside}# @use-case:end shop.pay.card#charge\n")
    assert "src/pay.py:2: empty marker region: shop.pay.card#charge" in uc(ws, "links")["diagnostics"]
    entry = next(u for u in uc(ws, "status")["use_cases"] if u["use_case"] == "shop.pay.card")
    assert "src/pay.py:2: its marked region is empty; if the code moved, move its markers with it" in entry["warnings"]
    assert "warning: shop.pay.card: src/pay.py:2: its marked region is empty" in human(ws, "status")[1]  # nothing run yet
    record(ws, "shop.cart.add", "pass")
    assert "warning: shop.pay.card: src/pay.py:2: its marked region is empty" in human(ws, "status")[1]  # the full list
    assert "its marked region is empty" in human(ws, "status", "shop.pay.card")[1]


def test_a_marked_region_with_code_raises_nothing(ws):
    os.makedirs(os.path.join(ws, "src"))
    with open(os.path.join(ws, "src", "pay.py"), "w") as handle:
        handle.write("# @use-case:shop.pay.card#charge\ndef charge(): pass\n# @use-case:end shop.pay.card#charge\n")
    assert uc(ws, "links")["diagnostics"] == []
    assert "marked region is empty" not in human(ws, "status")[1]


# ------------------------------------------------------------------ links <target> (chapter 16 §9, chapter 08)


def test_links_for_an_id_that_is_also_a_prefix_is_that_use_case_alone_and_diagnostics_are_never_filtered(ws):
    with open(os.path.join(ws, "use-cases", "top.yml"), "w") as handle:
        handle.write("use_cases:\n" + use_case("pay"))  # shop.pay, beside shop.pay.card and the rest
    os.makedirs(os.path.join(ws, "src"))
    for rel, text in {"pay.py": "# @use-case:shop.pay#top\nx\n# @use-case:end shop.pay#top\n"
                                "# @use-case:shop.pay.card#charge\ny\n# @use-case:end shop.pay.card#charge\n",
                      "cart.py": "# @use-case:shop.cart.add#put\nz\n# @use-case:end shop.cart.add#put\n# @use-case:BAD\n"}.items():
        with open(os.path.join(ws, "src", rel), "w") as handle:
            handle.write(text)
    everything = uc(ws, "links")
    assert any("malformed" in d for d in everything["diagnostics"])
    exact = uc(ws, "links", "shop.pay")
    assert {l["use_case"] for l in exact["links"]} == {"shop.pay"}
    assert {l["use_case"] for l in uc(ws, "links", "shop.cart")["links"]} == {"shop.cart.add"}
    assert exact["diagnostics"] == everything["diagnostics"] == uc(ws, "links", "shop.cart")["diagnostics"]
    assert uc(ws, "links", "shop.cart.share")["links"] == []  # a use case with no links is still a known target

