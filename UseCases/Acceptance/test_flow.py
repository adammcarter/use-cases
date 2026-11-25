"""The whole flow, as the use-case-driven-development skill drives it (chapter 22): every step's check met by real
commands on a real repo with real tests. Proposal, sign-off, red (a real failure), can it fail, green, refactor,
the gate and the results. If a step's check could not be met, an agent following the skill could not finish.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_flow.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
from conftest import SENTINEL, call_core, COMMAND
from test_languages import FIXTURES, env

USE_CASE = "invoicing.billing.item-count"
PROPOSAL = {
    "title": "Count the items on an invoice",
    "save": [{"id": USE_CASE, "title": "Count the items on an invoice", "value_tier": "core",
              "intent": "An invoice says how many items it holds, counting each line's quantity.",
              "scenarios": [{"id": "counts", "when": ["An invoice has 2 widgets and 1 gadget."], "then": ["It holds 3 items."]}],
              "validation": [{"id": "unit-tests", "type": {"kind": "unit"}, "covers": ["counts"]}]}],
    "untouched": ["invoicing.billing.totals"],
    "you_see": {USE_CASE: "an item count on every invoice"},
}
TEST = f'''

# {SENTINEL}{USE_CASE}#unit-tests.counts
def test_an_invoice_counts_its_items():
    invoice = Invoice("exempt").add(LineItem("Widget", Decimal("1"), 2)).add(LineItem("Gadget", Decimal("1")))
    assert invoice.item_count == 3
# {SENTINEL}end {USE_CASE}#unit-tests.counts
'''
CODE = f'''    @property
    # {SENTINEL}{USE_CASE}#count
    def item_count(self) -> int:
        return sum(item.quantity for item in self.items)
    # {SENTINEL}end {USE_CASE}#count

    def apply(self, discount) -> "Invoice":'''


@pytest.fixture(scope="module")
def repo(tmp_path_factory):
    target = tmp_path_factory.mktemp("flow") / "py"
    shutil.copytree(os.path.join(FIXTURES, "python", "3-bridge"), target, ignore=shutil.ignore_patterns("__pycache__", ".pytest_cache"))
    return target


def uc(repo, *args, expect_exit=0):
    return call_core(str(repo), *args, expect_exit=expect_exit, env=env())


def piped(repo, *args, data):
    process = subprocess.run([*COMMAND, "--workspace", str(repo), "--json", *args], input=json.dumps(data),
                             capture_output=True, text=True, encoding="utf-8", env=env())
    assert process.returncode == 0, process.stderr
    return json.loads(process.stdout)


def route(repo):
    entry = next(u for u in uc(repo, "status", USE_CASE)["use_cases"])
    return entry["status"], next(r for r in entry["routes"] if r["route"] == "unit-tests")["status"]


def edit(path, old, new):
    text = path.read_text()
    assert text.count(old) == 1, old
    path.write_text(text.replace(old, new))


def verify(repo):
    ran = uc(repo, "verify", "--run")
    assert ran["errors"] == [], ran["errors"]


# @use-case:flow.whole-flow#acceptance.end-to-end
def test_the_whole_flow(repo):
    if not shutil.which("python3"):
        pytest.skip("needs python3 with pytest")
    # 4 brief and 5 sign-off: the proposal is drawn, signed off and applied as it is
    assert [c["fit"] for c in piped(repo, "render", "proposal", "--file", "-", data=PROPOSAL)["model"]["changes"]] == ["new", "untouched"]
    assert piped(repo, "render", "brief", "--file", "-", data=PROPOSAL)["model"]["cards"][0]["use_case"] == USE_CASE
    assert piped(repo, "apply", "--file", "-", "--dry-run", data=PROPOSAL)["dry_run"] is True
    piped(repo, "apply", "--file", "-", "--approved-by", "Sam", data=PROPOSAL)
    assert uc(repo, "show", USE_CASE)["approval"] == "approved"

    # 6 red: the test is linked, and fails for real (failed, never error)
    tests = repo / "tests" / "test_invoice.py"
    tests.write_text(tests.read_text() + TEST)
    roles = [l["role"] for l in uc(repo, "links", USE_CASE)["links"]]
    assert roles == ["validation"]
    verify(repo)
    assert route(repo) == ("failed", "failed")

    # 6 green: the code is linked, and the route is verified
    source = repo / "src" / "invoicing" / "invoice.py"
    edit(source, '    def apply(self, discount) -> "Invoice":', CODE)
    assert sorted(l["role"] for l in uc(repo, "links", USE_CASE)["links"]) == ["implementation", "validation"]
    verify(repo)
    assert route(repo) == ("verified", "verified")

    # can it fail: a planted defect turns it failed, and reverting it makes it verified again
    edit(source, "return sum(item.quantity for item in self.items)", "return sum(item.quantity for item in self.items) + 1")
    verify(repo)
    assert route(repo) == ("failed", "failed")
    edit(source, "return sum(item.quantity for item in self.items) + 1", "return sum(item.quantity for item in self.items)")

    # 6 refactor: reshaped, markers kept, still verified
    edit(source, "return sum(item.quantity for item in self.items)", "return sum([item.quantity for item in self.items], 0)")
    verify(repo)
    assert route(repo) == ("verified", "verified")

    # 8 prove: the gate passes, and the results are what the person sees
    assert uc(repo, "status", "--gate")["gate"]["passed"] is True
    results = piped(repo, "render", "results", "--file", "-", data=PROPOSAL)["model"]
    assert results["use_cases"] == [{"use_case": USE_CASE, "title": "Count the items on an invoice", "status": "verified",
                                     "checks": [{"label": "unit-tests", "status": "verified"}]}]
    assert uc(repo, "show", USE_CASE)["approval"] == "approved"  # nothing in the build changed what was signed off
# @use-case:end flow.whole-flow#acceptance.end-to-end
