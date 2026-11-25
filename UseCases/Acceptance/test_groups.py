"""Groups (chapter 03) and bridge warnings (chapter 10 §18, chapter 14 §7).

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_groups.py -v
"""

import json
import os
import subprocess
import sys

import pytest
from conftest import call_core

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

IDS = ["login.success", "login.lockout", "checkout.success", "authentication.sso", "auth.reset"]


def use_case(local):
    return (f"  - id: {local}\n    title: {local}\n    value_tier: core\n    intent: {local}.\n"
            f"    scenarios:\n      - id: s\n        when: [x]\n        then: [y]\n"
            f"    validation:\n      - id: manual\n        type: {{ kind: acceptance }}\n        covers: [s]\n"
            f"        procedure:\n          steps: [Check it.]\n")


def uc(ws, *args, expect_exit=0):
    return call_core(ws, *args, expect_exit=expect_exit)


@pytest.fixture
def ws(tmp_path):
    (tmp_path / "use-cases").mkdir()
    (tmp_path / "use-cases.yml").write_text("schema_version: 1\nroot: true\nprefix: app\n")
    for area in ("login", "checkout", "authentication", "auth"):
        locals_ = [i.split(".")[1] for i in IDS if i.startswith(area + ".")]
        (tmp_path / "use-cases" / f"{area}.yml").write_text(f"prefix: {area}\nuse_cases:\n" + "".join(use_case(l) for l in locals_))
    return str(tmp_path)


def groups(ws, text):
    with open(os.path.join(ws, "use-case-groups.yml"), "w") as handle:
        handle.write("schema_version: 1\ngroups:\n" + text)


def members(ws, name):
    return sorted(u["use_case"] for u in uc(ws, "status", "--group", name)["use_cases"])


def test_prefixes_are_namespace_aware(ws):
    groups(ws, "  g:\n    include: { prefixes: [app.auth] }\n")
    assert members(ws, "g") == ["app.auth.reset"]  # never app.authentication.sso


def test_globs_match_whole_segments(ws):
    groups(ws, "  one:\n    include: { globs: [app.*.success] }\n  any:\n    include: { globs: ['**.success'] }\n")
    assert members(ws, "one") == ["app.checkout.success", "app.login.success"]
    assert members(ws, "any") == ["app.checkout.success", "app.login.success"]


def test_exclude_always_wins_and_omitted_include_means_everything(ws):
    groups(ws, "  g:\n    exclude: { prefixes: [app.login], ids: [app.auth.reset] }\n")
    assert members(ws, "g") == ["app.authentication.sso", "app.checkout.success"]


@pytest.mark.parametrize("text, reason", [
    ("  g:\n    include: { ids: [app.nope] }\n", "no use case"),
    ("  g:\n    include: { globs: [app.log*] }\n", "is not allowed at groups/g/include/globs/0"),
    ("  Bad:\n    include: { ids: [app.auth.reset] }\n", "is not allowed at groups"),
    ("  g:\n    members: [app.auth.reset]\n", "Additional properties"),
    ("  g:\n    include: { tags: [x] }\n", "Additional properties"),
    ("  g:\n    include: {}\n", "include selects nothing"),
    ("  g:\n    include: { ids: [] }\n", "include selects nothing"),
])
def test_what_makes_the_groups_file_invalid(ws, text, reason):
    groups(ws, text)
    assert reason in uc(ws, "status", expect_exit=2)


def test_what_only_warns(ws):
    groups(ws, "  g:\n    include: { prefixes: [app.nothing, app.login, app.login] }\n  empty:\n    include: { ids: [app.auth.reset] }\n"
               "    exclude: { ids: [app.auth.reset] }\n")
    warnings = uc(ws, "status")["warnings"]
    assert any("matches nothing" in w for w in warnings)
    assert any("duplicate selector" in w for w in warnings)
    assert any("has no members" in w for w in warnings)


def test_a_group_is_gated_on_its_members_only(ws):
    groups(ws, "  release:\n    include: { prefixes: [app.login] }\n")
    uc(ws, "record", "app.checkout.success", "manual", "fail")  # outside the group: never its gate
    gate = uc(ws, "status", "--group", "release", "--gate")["gate"]
    assert gate["passed"] and [w["use_case"] for w in gate["warning"]] == ["app.login.lockout", "app.login.success"]
    uc(ws, "status", "--group", "release", "--gate", "--strict", expect_exit=1)
    for use_case_id in ("app.login.success", "app.login.lockout"):
        uc(ws, "record", use_case_id, "manual", "pass")
    strict = uc(ws, "status", "--group", "release", "--gate", "--strict")
    assert strict["group"] == "release" and strict["gate"] == {"passed": True, "strict": True, "blocking": [], "warning": []}
    assert strict["summary"] == {"total": 2, "by_status": {"verified": 2}}


def test_renaming_a_group_changes_no_verdict(ws):
    groups(ws, "  release:\n    include: { prefixes: [app.login] }\n")
    uc(ws, "record", "app.login.success", "manual", "pass")
    groups(ws, "  shipping:\n    include: { prefixes: [app.login] }\n")
    assert next(u for u in uc(ws, "status")["use_cases"] if u["use_case"] == "app.login.success")["status"] == "verified"


def test_an_unknown_group_is_refused(ws):
    groups(ws, "  release: { include: { prefixes: [app.login] } }\n")
    assert "no group 'nope'" in uc(ws, "status", "--group", "nope", expect_exit=2)


# ------------------------------------------------------------------ bridge warnings


@pytest.mark.parametrize("bridge, warning", [
    ("schema_version: 1\nvalidations: []\n", "validations is empty"),
    ("schema_version: 1\nvalidations:\n  - id: a\n    report: r.xml\n    transformer: junit\n", "has no run command"),
    ("schema_version: 1\nvalidations:\n  - id: a\n    report: r.xml\n    transformer: junit\n    run: [/usr/bin/true]\n", "absolute path"),
])
def test_bridge_settings_that_are_valid_but_worth_a_warning(ws, bridge, warning):
    with open(os.path.join(ws, "use-cases-bridge.yml"), "w") as handle:
        handle.write(bridge)
    assert any(warning in w for w in uc(ws, "status")["warnings"])
