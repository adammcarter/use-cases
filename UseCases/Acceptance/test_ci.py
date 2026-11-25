"""CI (chapter 19): the two-step recipe from a clean checkout, tests split across machines giving the same
verdicts as one run, and every command in the CI recipes being a real command.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_ci.py -v
"""

import os
import re
import shutil
import subprocess

import pytest
import yaml
from conftest import call_core
from test_languages import FIXTURES, LANGUAGES, env, verdicts

DOCS = os.path.join(os.path.dirname(FIXTURES), "docs")


def needs(*tools):
    missing = [t for t in tools if not shutil.which(t, path=env()["PATH"])]
    if missing:
        if os.environ.get("UC_REQUIRE_TOOLS") == "all":
            pytest.fail(f"needs {missing}, and UC_REQUIRE_TOOLS=all")
        pytest.skip(f"needs {missing}")


def checkout(tmp_path, language, name):
    """A clean checkout of one commit, as each CI job gets."""
    target = tmp_path / name
    shutil.copytree(os.path.join(FIXTURES, language, "3-bridge"), target, ignore=shutil.ignore_patterns("__pycache__", ".use-cases"))
    return target


# ------------------------------------------------------------------ the recipe from a clean checkout (§2, §3)


# @use-case:ci.recipe#acceptance.clean-checkout
def test_the_recipe_from_a_clean_checkout(tmp_path):
    needs("node")
    job = checkout(tmp_path, "javascript", "job")
    assert not (job / ".use-cases").exists()
    ran = call_core(str(job), "verify", "--run", env=env())
    assert ran["errors"] == []
    gate = call_core(str(job), "status", "--gate")
    assert gate["gate"]["passed"]
    assert "stale" not in gate["summary"]["by_status"]  # nothing is ever stale from a clean checkout
# @use-case:end ci.recipe#acceptance.clean-checkout


# @use-case:verify.run#acceptance.failing-test-is-verdict
def test_a_failing_test_fails_the_gate_not_verify(tmp_path):
    needs("node")
    job = checkout(tmp_path, "javascript", "job")
    spec = LANGUAGES["javascript"]["fail"]
    path = job / spec[0]
    path.write_text(path.read_text().replace(spec[1], spec[2], 1))
    assert call_core(str(job), "verify", "--run", env=env())["errors"] == []  # exit 0: the failing test is a verdict
    gate = call_core(str(job), "status", "--gate", expect_exit=1)["gate"]
    assert {b["use_case"] for b in gate["blocking"]} == {spec[3]}
# @use-case:end verify.run#acceptance.failing-test-is-verdict


# ------------------------------------------------------------------ tests split across machines (§6)


# @use-case:ci.recipe#acceptance.shards
def test_tests_split_across_machines_are_one_run(tmp_path):
    """Start on one machine, test in two shards on two others, finish on a fourth: the verdicts are those of one run."""
    needs("python3")
    base = checkout(tmp_path, "python", "commit")
    bridge = base / "use-cases-bridge.yml"
    bridge.write_text(bridge.read_text().replace("    report: pytest.xml\n", ""))  # {report} is the folder
    machines = {name: shutil.copytree(base, tmp_path / name) for name in ("start", "shard-1", "shard-2", "finish")}

    started = call_core(str(machines["start"]), "verify", "--start")
    run = f".use-cases/runs/{started['run_id']}"
    shutil.copytree(machines["start"] / run, machines["finish"] / run)  # the start job's artifact

    for shard, tests in (("shard-1", "tests/test_invoice.py"), ("shard-2", "tests/test_tax.py")):
        subprocess.run(["python3", "-m", "pytest", "-q", "-o", "junit_family=xunit1", tests, f"--junitxml={shard}.xml"],
                       cwd=machines[shard], capture_output=True, env=env())
        shutil.copy(machines[shard] / f"{shard}.xml", machines["finish"] / run / "reports" / "pytest")

    finished = call_core(str(machines["finish"]), "verify", "--finish", "--run-id", started["run_id"], env=env())
    assert finished["errors"] == [] and verdicts(finished) == LANGUAGES["python"]["expected"]
    assert sorted(os.listdir(machines["finish"] / run / "reports" / "pytest")) == ["shard-1.xml", "shard-2.xml"]
# @use-case:end ci.recipe#acceptance.shards


# @use-case:ci.recipe#acceptance.shards
def test_overlapping_shard_files_merge_into_one_verdict_each(tmp_path):
    needs("python3")
    base = checkout(tmp_path, "python", "commit")
    bridge = base / "use-cases-bridge.yml"
    bridge.write_text(bridge.read_text().replace("    report: pytest.xml\n", ""))
    started = call_core(str(base), "verify", "--start")
    folder = base / ".use-cases" / "runs" / started["run_id"] / "reports" / "pytest"
    # one shard runs every test and another a subset: a test reported twice still gives one verdict per link
    subprocess.run(["python3", "-m", "pytest", "-q", "-o", "junit_family=xunit1", "tests", f"--junitxml={folder / 'a.xml'}"],
                   cwd=base, capture_output=True, env=env())
    subprocess.run(["python3", "-m", "pytest", "-q", "-o", "junit_family=xunit1", "tests", "-k", "not invoice and not total",
                    "-p", "no:cacheprovider", f"--junitxml={folder / 'b.xml'}"], cwd=base, capture_output=True, env=env())
    finished = call_core(str(base), "verify", "--finish", env=env())
    assert finished["errors"] == []
    assert verdicts(finished) == LANGUAGES["python"]["expected"]
# @use-case:end ci.recipe#acceptance.shards


# ------------------------------------------------------------------ the recipes (§7)


def recipe_texts():
    folder = os.path.join(DOCS, "ci")
    return {name: open(os.path.join(folder, name), encoding="utf-8").read() for name in sorted(os.listdir(folder))
            if name.endswith(".md")} | {"19-ci.md": open(os.path.join(DOCS, "design", "19-ci.md"), encoding="utf-8").read()}


def test_every_recipe_block_is_yaml_that_parses():
    for name, text in recipe_texts().items():
        for block in re.findall(r"```yaml\n(.*?)\n```", text, flags=re.S):
            yaml.safe_load(block)
