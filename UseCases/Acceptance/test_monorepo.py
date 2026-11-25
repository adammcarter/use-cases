"""A mixed-language monorepo: nested scopes, several test tools in one run, and one
use case proved by tests in two languages.

fixtures/monorepo/3-bridge: catalog/ (shared prices), pricing/ (Python), checkout/ (Go),
storefront/ (JavaScript). Run from the repository root:

    uv run --with pyyaml --with pytest pytest UseCases/Acceptance/test_monorepo.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
from conftest import call_core

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MONOREPO = os.path.join(REPO, "fixtures", "monorepo", "3-bridge")

CROSS = "shop.rules.bulk-discount"
PRICING = ["shop.pricing.quotes.flat-price", "shop.pricing.quotes.unknown-items"]
CHECKOUT = ["shop.checkout.cart.total", "shop.checkout.cart.unknown-items"]
STOREFRONT = ["shop.storefront.labels.money", "shop.storefront.labels.savings"]
EVERY = [CROSS] + PRICING + CHECKOUT + STOREFRONT


def uc(workspace, *args, expect_exit=0):
    return call_core(workspace, *args, expect_exit=expect_exit)


def status(workspace):
    return {u["use_case"]: u for u in uc(workspace, "status")["use_cases"]}


def routes(use_case):
    return {c["route"]: c["status"] for c in use_case["routes"]}


def edit(workspace, rel, old, new):
    path = os.path.join(workspace, rel)
    with open(path) as handle:
        text = handle.read()
    assert text.count(old) == 1, f"{old!r} must appear once in {rel}"
    with open(path, "w") as handle:
        handle.write(text.replace(old, new))


def didnt_run(run):
    return {(d["use_case"], d["route"]) for d in run["diagnostics"]
            if isinstance(d, dict) and d.get("problem") == "its test didn't run"}


@pytest.fixture
def ws(tmp_path):
    target = str(tmp_path / "shop")
    shutil.copytree(MONOREPO, target)
    return target


@pytest.fixture(scope="module")
def validated(tmp_path_factory):
    target = str(tmp_path_factory.mktemp("validated") / "shop")
    shutil.copytree(MONOREPO, target)
    return target, uc(target, "verify", "--run")


# ------------------------------------------------------------------ nested scopes


def test_nested_scopes_compose_one_namespace(ws):
    assert sorted(status(ws)) == sorted(EVERY)


def test_bridge_settings_below_the_root_are_refused(ws):
    shutil.copy(os.path.join(ws, "use-cases-bridge.yml"), os.path.join(ws, "pricing", "use-cases-bridge.yml"))
    assert "root-only" in uc(ws, "status", expect_exit=2)


# ------------------------------------------------------------------ one run, three languages


def test_one_run_verifies_every_service(validated):
    workspace, run = validated
    assert run["errors"] == [] and len(run["sources"]) == 3
    assert all(u["status"] == "verified" for u in status(workspace).values())
    assert [t["test"] for t in run["unlinked_tests"]] == ["tests.test_catalog/test_catalog_is_priced_in_pounds"]


def test_a_use_case_proved_in_two_languages_merges_both_runs(validated):
    _, run = validated
    cross = {r["route"]: r["via"] for r in run["results"] if r["use_case"] == CROSS}
    assert cross == {"pricing-quotes": ["pricing-tests"], "checkout-totals": ["checkout-tests"]}


# ------------------------------------------------------------------ one source at a time


def test_running_one_service_never_verifies_the_other_half(ws):
    run = uc(ws, "verify", "--run", "--only", "pricing-tests")
    assert (CROSS, "checkout-totals") in didnt_run(run)
    now = status(ws)
    assert now[CROSS]["status"] != "verified"
    assert routes(now[CROSS])["pricing-quotes"] == "verified"
    assert all(now[u]["status"] == "verified" for u in PRICING)
    assert all(now[u]["status"] == "unverified" for u in CHECKOUT + STOREFRONT)


def test_unknown_only_names_are_refused_before_anything_runs(ws):
    assert "unknown validations" in uc(ws, "verify", "--run", "--only", "nope", expect_exit=2)
    assert not os.path.exists(os.path.join(ws, ".use-cases", "runs"))


def test_a_go_failure_fails_the_shared_use_case_even_though_python_passed(ws):
    edit(ws, "checkout/cart/cart_test.go", "}{{4, 5000}, {5, 5625}, {12, 12750}}", "}{{4, 5000}, {5, 5626}, {12, 12750}}")
    uc(ws, "verify", "--run")
    now = status(ws)
    assert routes(now[CROSS]) == {"pricing-quotes": "verified", "checkout-totals": "failed"}
    assert now[CROSS]["status"] == "failed"
    assert all(now[u]["status"] == "verified" for u in PRICING + CHECKOUT + STOREFRONT)


def test_a_go_build_break_leaves_python_and_javascript_verdicts_intact(ws):
    edit(ws, "checkout/cart/cart.go", "func (c Catalog) Total(lines []Line) (int, error) {", "func (c Catalog) Total(lines []Line) (int, error {")
    run = uc(ws, "verify", "--run")
    assert len(run["errors"]) == 1 and run["errors"][0].startswith("checkout-tests:")
    now = status(ws)
    assert all(now[u]["status"] == "verified" for u in PRICING + STOREFRONT)
    assert all(now[u]["status"] == "unverified" for u in CHECKOUT)
    assert routes(now[CROSS]) == {"pricing-quotes": "verified", "checkout-totals": "unverified"}


# ------------------------------------------------------------------ freshness across services


def test_editing_the_shared_catalog_stales_both_languages_routes(validated, tmp_path):
    workspace = str(tmp_path / "after")
    shutil.copytree(validated[0], workspace)
    edit(workspace, "catalog/prices.json", '"min": 20, "percent": 25', '"min": 20, "percent": 30')
    now = status(workspace)
    assert routes(now[CROSS]) == {"pricing-quotes": "stale", "checkout-totals": "stale"}
    # Declared-input boundary: these tests read the catalog too, but their use cases don't declare it.
    assert all(now[u]["status"] == "verified" for u in PRICING + CHECKOUT)


def test_editing_one_service_leaves_the_others_verified(validated, tmp_path):
    workspace = str(tmp_path / "after")
    shutil.copytree(validated[0], workspace)
    edit(workspace, "storefront/src/labels.js", "  if (saved <= 0) return \"\";", "  if (saved <= 0) return \"\"; // full price")
    now = status(workspace)
    assert now["shop.storefront.labels.savings"]["status"] == "stale"
    assert all(now[u]["status"] == "verified" for u in EVERY if u != "shop.storefront.labels.savings")
