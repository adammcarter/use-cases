"""Changing use cases (chapter 16: show, save, remove) and --dry-run on every command that writes files you own.
The YAML stays the truth: one use case's lines change and the rest of the file never does, a new use case goes
where the recommended structure puts it, and nothing that would leave the workspace INVALID is ever written.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_edit.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
import yaml
from conftest import call_core, COMMAND
from test_languages import FIXTURES

BILLING = "use-cases/billing.yml"


@pytest.fixture
def ws(tmp_path):
    target = tmp_path / "py"
    shutil.copytree(os.path.join(FIXTURES, "python", "2-use-cases"), target)
    return target


def uc(ws, *args, expect_exit=0):
    return call_core(str(ws), *args, expect_exit=expect_exit)


def save(ws, definition, *flags, expect_exit=0):
    """Save through stdin, as the agent's tool does. Returns the --json document, refusals included."""
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "--json", "save", "--file", "-", *flags],
                             input=json.dumps(definition), capture_output=True, text=True, encoding="utf-8")
    assert process.returncode == expect_exit, process.stderr
    return json.loads(process.stdout)


def snapshot(ws):
    found = {}
    for dirpath, _, filenames in os.walk(ws):
        for name in filenames:
            path = os.path.join(dirpath, name)
            with open(path, "rb") as handle:
                found[os.path.relpath(path, ws)] = handle.read()
    return found


def ids(ws):
    return sorted(u["use_case"] for u in uc(ws, "status")["use_cases"])


def without_dry_run(document):
    return {k: v for k, v in document.items() if k != "dry_run"}


# ------------------------------------------------------------------ show


# @use-case:edit.show#acceptance.round-trip
def test_show_returns_the_whole_use_case_and_save_takes_it_back_unchanged(ws):
    shown = uc(ws, "show", "invoicing.billing.totals")
    assert shown["file"] == BILLING and shown["definition"]["id"] == "invoicing.billing.totals"
    assert [s["id"] for s in shown["definition"]["scenarios"]] == ["sum-lines", "tax-after-discount", "round-half-up"]
    before = snapshot(ws)
    saved = save(ws, shown["definition"])
    assert saved["action"] == "unchanged" and saved["changes"] == []
    assert snapshot(ws) == before
# @use-case:end edit.show#acceptance.round-trip


# @use-case:edit.show#acceptance.unknown
def test_show_an_unknown_use_case_is_a_usage_error(ws):
    assert "no use case" in uc(ws, "show", "invoicing.billing.nope", expect_exit=2)
# @use-case:end edit.show#acceptance.unknown


# ------------------------------------------------------------------ save: only that use case's lines change


# @use-case:edit.save#acceptance.own-lines
def test_replacing_a_use_case_changes_only_its_own_lines(ws):
    path = ws / BILLING
    path.write_text("# kept: a comment above everything\n" + path.read_text())
    before = path.read_text().splitlines()
    definition = uc(ws, "show", "invoicing.billing.discounts")["definition"]
    definition["title"] = "Discounts never take a total below zero"
    result = save(ws, definition)
    assert result["action"] == "replaced" and result["changes"] == [{"path": BILLING, "action": "replace"}]
    after = path.read_text().splitlines()
    assert len(after) == len(before) and after[0] == "# kept: a comment above everything"
    start, end = before.index("  - id: discounts"), before.index("  - id: tax-regions")
    assert after[:start] == before[:start] and after[end:] == before[end:]  # the other use cases, byte for byte
    changed = [b for a, b in zip(before[start:end], after[start:end]) if a != b]
    assert changed == ["    title: Discounts never take a total below zero"]  # one field changed, one line changed
    assert uc(ws, "validate")["valid"] is True
# @use-case:end edit.save#acceptance.own-lines


def test_a_workspace_with_helpers_is_checked_as_it_is(tmp_path):
    ws = tmp_path / "bridge"  # a bridge file's folders are checked against the copy the plan is tried in
    shutil.copytree(os.path.join(FIXTURES, "python", "3-bridge"), ws)
    definition = uc(ws, "show", "invoicing.billing.totals")["definition"]
    assert save(ws, {**definition, "title": "Total an invoice, to the cent"})["action"] == "replaced"


# @use-case:edit.save#acceptance.placement
def test_a_new_use_case_joins_its_groups_file(ws):
    result = save(ws, {"id": "invoicing.billing.credit-notes", "title": "Issue a credit note"})
    assert result["action"] == "added" and result["file"] == BILLING
    assert "invoicing.billing.credit-notes" in ids(ws)
    assert uc(ws, "show", "invoicing.billing.credit-notes")["file"] == BILLING
# @use-case:end edit.save#acceptance.placement


# @use-case:edit.save#acceptance.placement
@pytest.mark.parametrize("use_case_id, rel, prefix", [
    ("invoicing.refunds.partial", "use-cases/refunds.yml", "refunds"),
    ("invoicing.payments.card.refund", "use-cases/payments/card.yml", "payments.card"),
])
def test_a_new_group_gets_the_file_the_structure_gives_it(ws, use_case_id, rel, prefix):
    result = save(ws, {"id": use_case_id, "title": "New behaviour"})
    assert result["action"] == "created" and result["file"] == rel
    assert result["changes"] == [{"path": rel, "action": "create"}]
    assert yaml.safe_load((ws / rel).read_text()) == {
        "prefix": prefix, "use_cases": [{"id": use_case_id.rsplit(".", 1)[1], "title": "New behaviour"}]}
    assert uc(ws, "show", use_case_id)["file"] == rel
# @use-case:end edit.save#acceptance.placement


def test_a_new_group_in_a_child_scope_goes_into_that_scope(tmp_path):
    root = tmp_path / "mono"
    (root / "use-cases").mkdir(parents=True)
    (root / "packages" / "auth").mkdir(parents=True)
    (root / "use-cases.yml").write_text("schema_version: 1\nroot: true\nprefix: shop\n")
    (root / "use-cases" / "cart.yml").write_text("prefix: cart\nuse_cases:\n  - id: add\n    title: Add to cart\n")
    (root / "packages" / "auth" / "use-cases.yml").write_text("schema_version: 1\nprefix: auth\n")
    assert save(root, {"id": "shop.auth.login.ok", "title": "Log in"})["file"] == "packages/auth/use-cases/login.yml"
    assert save(root, {"id": "shop.orders.list", "title": "List orders"})["file"] == "use-cases/orders.yml"
    assert ids(root) == ["shop.auth.login.ok", "shop.cart.add", "shop.orders.list"]


# @use-case:edit.save#acceptance.placement
def test_a_use_case_straight_under_a_namespace_needs_a_group(ws):
    assert "need a group" in save(ws, {"id": "invoicing.loose", "title": "Loose"}, expect_exit=2)["error"]["message"]
# @use-case:end edit.save#acceptance.placement


# @use-case:edit.save#acceptance.own-lines
def test_the_written_file_reads_like_a_person_wrote_it(ws):
    save(ws, {"validation": [{"covers": ["s"], "type": {"kind": "unit"}, "id": "unit-tests"}],
              "scenarios": [{"then": ["y"], "when": ["x"], "id": "s"}], "title": "Ordered", "id": "invoicing.misc.ordered"})
    text = (ws / "use-cases" / "misc.yml").read_text()
    assert text.startswith("prefix: misc\nuse_cases:\n  - id: ordered\n    title: Ordered\n")
    assert text.index("scenarios:") < text.index("validation:")
    assert "      - id: s\n        when: [x]\n        then: [y]\n" in text and "type: { kind: unit }" in text
# @use-case:end edit.save#acceptance.own-lines


# ------------------------------------------------------------------ nothing invalid is ever written


# @use-case:edit.save#acceptance.never-invalid
@pytest.mark.parametrize("definition, message", [
    ({"id": "orphan", "title": "No group"}, "has no group"),
    ({"title": "No id"}, "full id"),
    ({"id": "invoicing.billing.x", "title": "T", "runner": "swift"}, "runner"),
    ({"id": "invoicing.billing.x", "title": "T", "value_tier": "urgent"}, "urgent"),
    ({"id": "invoicing.billing.x", "title": "T", "scenarios": [{"id": "s", "when": ["x"], "then": ["y"]}],
      "validation": [{"id": "r", "type": {"kind": "unit"}, "covers": ["nope"]}]}, "nope"),
])
def test_an_invalid_use_case_is_refused_and_nothing_is_written(ws, definition, message):
    before = snapshot(ws)
    refused = save(ws, definition, expect_exit=2)
    assert message in refused["error"]["message"] and snapshot(ws) == before
# @use-case:end edit.save#acceptance.never-invalid


# @use-case:edit.save#acceptance.never-invalid
def test_input_that_is_not_one_use_case_is_refused(ws):
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "save", "--file", "-"],
                             input="- id: a.b\n- id: a.c\n", capture_output=True, text=True, encoding="utf-8")
    assert process.returncode == 2 and "one mapping with its full id" in process.stderr
# @use-case:end edit.save#acceptance.never-invalid


# @use-case:edit.save#acceptance.never-invalid
def test_a_change_that_breaks_the_rest_of_the_workspace_is_refused(ws):
    (ws / "use-case-groups.yml").write_text("schema_version: 1\ngroups:\n  money:\n    include: { ids: [invoicing.billing.totals] }\n")
    before = snapshot(ws)
    refused = uc(ws, "remove", "invoicing.billing.totals", expect_exit=2)
    assert "no use case" in refused and snapshot(ws) == before  # the group would name a use case that is gone
    assert uc(ws, "remove", "invoicing.billing.totals", "--dry-run", expect_exit=2)  # the preview is refused the same
# @use-case:end edit.save#acceptance.never-invalid


def test_a_structured_path_that_holds_another_group_is_refused(ws):
    (ws / "use-cases" / "refunds.yml").write_text("prefix: other\nuse_cases:\n  - id: thing\n    title: Thing\n")
    before = snapshot(ws)
    refused = save(ws, {"id": "invoicing.refunds.partial", "title": "P"}, expect_exit=2)
    assert "already exists" in refused["error"]["message"] and snapshot(ws) == before


def test_save_reads_a_yaml_file_too(ws, tmp_path):
    source = tmp_path / "new.yml"
    source.write_text("id: invoicing.billing.credit-notes\ntitle: Issue a credit note\n")
    assert uc(ws, "save", "--file", str(source))["action"] == "added"
    assert "is not a file" in uc(ws, "save", "--file", str(tmp_path / "missing.yml"), expect_exit=2)


# @use-case:edit.save#acceptance.concurrent
def test_two_saves_at_once_never_lose_a_change(ws):
    """Real processes at the same moment: each that says it saved is in the file, and the other is told to run it again."""
    for round in range(10):
        started = []
        for local in ("discounts", "totals"):
            title = f"{local} {round}"
            definition = {**uc(ws, "show", f"invoicing.billing.{local}")["definition"], "title": title}
            process = subprocess.Popen([*COMMAND, "--workspace", str(ws), "--json", "save", "--file", "-"], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
            started.append((title, definition, process))
        for _, definition, process in started:
            process.stdin.write(json.dumps(definition))
            process.stdin.close()
        for title, _, process in started:
            out = process.stdout.read()
            process.wait()
            if process.returncode == 0:
                assert f"    title: {title}\n" in (ws / BILLING).read_text(), f"{title} was saved and then lost"
            else:
                assert "changed since it was read; run it again" in json.loads(out)["error"]["message"]
# @use-case:end edit.save#acceptance.concurrent


# ------------------------------------------------------------------ remove


# @use-case:edit.remove#acceptance.remove
def test_removing_one_of_several_keeps_the_rest_untouched(ws):
    before = (ws / BILLING).read_text().splitlines()
    result = uc(ws, "remove", "invoicing.billing.discounts")
    assert result["action"] == "removed" and result["changes"] == [{"path": BILLING, "action": "replace"}]
    start, end = before.index("  - id: discounts"), before.index("  - id: tax-regions")
    assert (ws / BILLING).read_text().splitlines() == before[:start] + before[end:]
    assert ids(ws) == ["invoicing.billing.tax-regions", "invoicing.billing.totals"]
# @use-case:end edit.remove#acceptance.remove


# @use-case:edit.remove#acceptance.remove
def test_removing_the_last_use_case_removes_its_file_and_keeps_its_verdicts(ws):
    save(ws, {"id": "invoicing.refunds.partial", "title": "Refund part", "value_tier": "core", "intent": "Refunds.",
              "scenarios": [{"id": "s", "when": ["x"], "then": ["y"]}],
              "validation": [{"id": "manual", "type": {"kind": "acceptance"}, "covers": ["s"],
                              "procedure": {"steps": ["Check."]}}]})
    uc(ws, "record", "invoicing.refunds.partial", "manual", "pass")
    runs = sorted(os.listdir(ws / ".use-cases" / "runs"))
    result = uc(ws, "remove", "invoicing.refunds.partial")
    assert result["changes"] == [{"path": "use-cases/refunds.yml", "action": "delete"}]
    assert not (ws / "use-cases" / "refunds.yml").exists()
    assert sorted(os.listdir(ws / ".use-cases" / "runs")) == runs  # a remove never deletes evidence
# @use-case:end edit.remove#acceptance.remove


# @use-case:edit.remove#acceptance.markers-warned
def test_markers_that_still_name_a_removed_use_case_are_warned_about(ws):
    result = uc(ws, "remove", "invoicing.billing.tax-regions", "--dry-run")
    assert result["warnings"] == [f"tests/test_tax.py:{lines} is still marked for invoicing.billing.tax-regions"
                                  for lines in ("9-11", "16-18", "23-25")]  # in file order, the marked lines
# @use-case:end edit.remove#acceptance.markers-warned


# @use-case:edit.remove#acceptance.unknown
def test_remove_an_unknown_use_case_is_a_usage_error(ws):
    assert "no use case" in uc(ws, "remove", "invoicing.billing.nope", expect_exit=2)
# @use-case:end edit.remove#acceptance.unknown


# ------------------------------------------------------------------ --dry-run: writes nothing, says exactly what the real run does


def prepare_for(args, ws):
    subprocess.run(["git", "init", "-q"], cwd=ws, check=True)
    if args[0] == "init":  # an empty folder with code in it: init refuses inside a workspace
        shutil.rmtree(ws / "use-cases")
        (ws / "use-cases.yml").unlink()


# @use-case:edit.dry-run#acceptance.matches
@pytest.mark.parametrize("args", [
    ["remove", "invoicing.billing.discounts"],
    ["init", "--no-input"],
    ["init", "--no-input", "--minimal", "--hooks", "commit"],
    ["hooks", "add", "commit", "push"],
])
def test_dry_run_writes_nothing_and_matches_the_real_run(ws, args):
    prepare_for(args, ws)
    before = snapshot(ws)
    dry = uc(ws, *args, "--dry-run")
    assert dry["dry_run"] is True and snapshot(ws) == before
    real = uc(ws, *args)
    assert real["dry_run"] is False and without_dry_run(dry) == without_dry_run(real)
    assert snapshot(ws) != before
# @use-case:end edit.dry-run#acceptance.matches


# @use-case:edit.dry-run#acceptance.matches
@pytest.mark.parametrize("definition", [
    {"id": "invoicing.refunds.partial", "title": "Refund part"},
    {"id": "invoicing.billing.credit-notes", "title": "Issue a credit note"},
])
def test_save_dry_run_matches_the_real_save(ws, definition):
    before = snapshot(ws)
    dry = save(ws, definition, "--dry-run")
    assert dry["dry_run"] is True and snapshot(ws) == before
    assert without_dry_run(dry) == without_dry_run(save(ws, definition))
# @use-case:end edit.dry-run#acceptance.matches


def test_hooks_remove_dry_run_leaves_the_hook(ws):
    prepare_for(["hooks"], ws)
    uc(ws, "hooks", "add", "commit")
    hook = ws / ".git" / "hooks" / "pre-commit"
    assert uc(ws, "hooks", "remove", "commit", "--dry-run")["changed"] == ["commit"] and hook.exists()
    uc(ws, "hooks", "remove", "commit")
    assert not hook.exists()


# @use-case:edit.dry-run#acceptance.wording
def test_people_see_would_under_dry_run(ws):
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "remove", "invoicing.billing.discounts", "--dry-run"],
                             capture_output=True, text=True, encoding="utf-8")
    assert process.returncode == 0
    assert process.stdout.splitlines()[:2] == ["would remove: invoicing.billing.discounts", f"would update  {BILLING}"]
# @use-case:end edit.dry-run#acceptance.wording


# @use-case:edit.dry-run#acceptance.only-writers
def test_only_commands_that_change_authored_files_take_dry_run(ws):
    for command in (["verify", "--run"], ["record", "--interactive"], ["status"], ["validate"]):
        process = subprocess.run([*COMMAND, "--workspace", str(ws), *command, "--dry-run"],
                                 capture_output=True, text=True, encoding="utf-8", stdin=subprocess.DEVNULL)
        assert process.returncode == 2 and "--dry-run" in process.stderr, command
# @use-case:end edit.dry-run#acceptance.only-writers


# ------------------------------------------------------------------ apply: a batch, all or nothing


def apply(ws, batch, *flags, expect_exit=0):
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "--json", "apply", "--file", "-", *flags],
                             input=json.dumps(batch), capture_output=True, text=True, encoding="utf-8")
    assert process.returncode == expect_exit, process.stderr
    return json.loads(process.stdout)


# @use-case:edit.batch#acceptance.fixed-order
def test_a_batch_runs_delete_then_add_then_update_whatever_order_it_is_written_in(ws):
    batch = {"save": [{"id": "invoicing.billing.discounts", "title": "Discounts never take a total below zero"},
                      {"id": "invoicing.refunds.partial", "title": "Refund part"}],
             "remove": ["invoicing.billing.tax-regions"]}
    result = apply(ws, batch)
    assert [(u["use_case"], u["action"]) for u in result["use_cases"]] == [
        ("invoicing.billing.tax-regions", "removed"), ("invoicing.refunds.partial", "created"),
        ("invoicing.billing.discounts", "replaced")]
    assert result["changes"] == [{"path": BILLING, "action": "replace"}, {"path": "use-cases/refunds.yml", "action": "create"}]
    assert ids(ws) == ["invoicing.billing.discounts", "invoicing.billing.totals", "invoicing.refunds.partial"]
    assert result["warnings"]  # the removed use case's markers
# @use-case:end edit.batch#acceptance.fixed-order


# @use-case:edit.batch#acceptance.fixed-order
def test_a_replace_in_one_batch_never_trips_over_itself(ws):
    (ws / "use-case-groups.yml").write_text("schema_version: 1\ngroups:\n  money:\n    include: { ids: [invoicing.billing.totals] }\n")
    assert "no use case" in uc(ws, "remove", "invoicing.billing.totals", expect_exit=2)  # alone, the group breaks
    (ws / "use-case-groups.yml").write_text("schema_version: 1\ngroups:\n  money:\n    include: { prefixes: [invoicing.billing] }\n")
    definition = {**uc(ws, "show", "invoicing.billing.totals")["definition"], "id": "invoicing.billing.grand-totals"}
    result = apply(ws, {"remove": ["invoicing.billing.totals"], "save": [definition]})
    assert [u["action"] for u in result["use_cases"]] == ["removed", "added"]
    assert "invoicing.billing.grand-totals" in ids(ws) and "invoicing.billing.totals" not in ids(ws)
# @use-case:end edit.batch#acceptance.fixed-order


# @use-case:edit.batch#acceptance.shared-files
def test_emptying_a_file_then_adding_to_its_group_in_one_batch(ws):
    save(ws, {"id": "invoicing.refunds.partial", "title": "Refund part"})
    result = apply(ws, {"remove": ["invoicing.refunds.partial"], "save": [{"id": "invoicing.refunds.full", "title": "Refund all"}]})
    assert result["changes"] == [{"path": "use-cases/refunds.yml", "action": "replace"}]  # one file, changed once
    assert yaml.safe_load((ws / "use-cases" / "refunds.yml").read_text()) == {
        "prefix": "refunds", "use_cases": [{"id": "full", "title": "Refund all"}]}
# @use-case:end edit.batch#acceptance.shared-files



# @use-case:edit.batch#acceptance.shared-files
def test_two_new_use_cases_for_a_new_group_share_one_new_file(ws):
    result = apply(ws, {"save": [{"id": "invoicing.refunds.partial", "title": "Refund part"},
                                 {"id": "invoicing.refunds.full", "title": "Refund all"}]})
    assert [u["action"] for u in result["use_cases"]] == ["created", "added"]
    assert result["changes"] == [{"path": "use-cases/refunds.yml", "action": "create"}]
    assert [u["id"] for u in yaml.safe_load((ws / "use-cases" / "refunds.yml").read_text())["use_cases"]] == ["partial", "full"]
# @use-case:end edit.batch#acceptance.shared-files

# @use-case:edit.batch#acceptance.all-or-nothing
@pytest.mark.parametrize("batch, message", [
    ({}, "a batch is a mapping"),
    ({"remove": [], "save": []}, "a batch is a mapping"),
    ({"rename": ["x"]}, "a batch is a mapping"),
    ({"remove": "invoicing.billing.totals"}, "lists use case ids"),
    ({"remove": ["invoicing.billing.totals"], "save": [{"id": "invoicing.billing.totals", "title": "T"}]}, "at most once"),
    ({"remove": ["invoicing.billing.nope"]}, "no use case"),
    ({"save": [{"id": "invoicing.billing.x", "title": "Fine"}, {"id": "orphan", "title": "No group"}]}, "has no group"),
])
def test_a_bad_batch_writes_nothing_at_all(ws, batch, message):
    before = snapshot(ws)
    refused = apply(ws, batch, expect_exit=2)
    assert message in refused["error"]["message"] and snapshot(ws) == before
# @use-case:end edit.batch#acceptance.all-or-nothing


# @use-case:edit.batch#acceptance.all-or-nothing
def test_one_invalid_change_and_nothing_in_the_batch_is_written(ws):
    before = snapshot(ws)
    refused = apply(ws, {"save": [{"id": "invoicing.billing.credit-notes", "title": "Fine on its own"},
                                  {"id": "invoicing.billing.x", "title": "T", "scenarios": [{"id": "s", "when": ["x"], "then": ["y"]}],
                                   "validation": [{"id": "r", "type": {"kind": "unit"}, "covers": ["nope"]}]}]}, expect_exit=2)
    assert "nope" in refused["error"]["message"] and snapshot(ws) == before
# @use-case:end edit.batch#acceptance.all-or-nothing


# @use-case:edit.dry-run#acceptance.matches
def test_a_batch_dry_run_writes_nothing_and_matches_the_real_run(ws):
    batch = {"remove": ["invoicing.billing.discounts"], "save": [{"id": "invoicing.refunds.partial", "title": "Refund part"}]}
    before = snapshot(ws)
    dry = apply(ws, batch, "--dry-run")
    assert dry["dry_run"] is True and snapshot(ws) == before
    assert without_dry_run(dry) == without_dry_run(apply(ws, batch))
# @use-case:end edit.dry-run#acceptance.matches


# @use-case:edit.batch#acceptance.fixed-order
def test_people_see_the_batch_in_the_order_it_runs(ws):
    path = ws / "batch.yml"
    path.write_text("save:\n  - id: invoicing.refunds.partial\n    title: Refund part\nremove: [invoicing.billing.discounts]\n")
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "apply", "--file", str(path), "--dry-run"],
                             capture_output=True, text=True, encoding="utf-8")
    assert process.stdout.splitlines()[:2] == ["would delete  invoicing.billing.discounts", "would add     invoicing.refunds.partial"]
# @use-case:end edit.batch#acceptance.fixed-order

