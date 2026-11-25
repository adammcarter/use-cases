"""use-cases init (chapter 17): a workspace from nothing, never overwriting, the example never blocking,
and base files only: never a test command filled in on anyone's behalf.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_init.py -v
"""

import os
import shutil
import subprocess
import sys

import pytest
import yaml
from conftest import call_core, COMMAND
from test_languages import FIXTURES


@pytest.fixture
def repo(tmp_path):
    """The folder to set up; tmp_path itself also holds the harness's output log."""
    folder = tmp_path / "repo"
    folder.mkdir()
    return folder


def init(folder, *args, expect_exit=0):
    return call_core(str(folder), "init", *args, expect_exit=expect_exit)


def read(folder, rel):
    with open(os.path.join(folder, rel), encoding="utf-8") as handle:
        return handle.read()


# ------------------------------------------------------------------ what it creates (§2, §4, §7)


def test_an_empty_folder_becomes_a_valid_workspace_with_a_draft_example(repo):
    made = init(repo)
    assert made["created"] == ["use-cases.yml", "use-cases/example.yml", "use-case-groups.yml", "use-cases-bridge.yml"]
    assert made["gitignore"] == "skipped" and made["notes"]
    checked = call_core(str(repo), "validate")
    assert checked["use_cases"] == 1 and checked["draft"] == 1
    status = call_core(str(repo), "status")["use_cases"]
    assert [(u["use_case"], u["status"]) for u in status] == [("example.getting-started", "draft")]
    for strict in ([], ["--strict"]):  # the example never blocks a gate
        assert call_core(str(repo), "status", "--gate", *strict)["gate"]["passed"]
    assert call_core(str(repo), "status", "--group", "smoke")["summary"]["total"] == 1


def test_minimal_writes_the_workspace_file_alone(repo):
    made = init(repo, "--minimal")
    assert made["created"] == ["use-cases.yml"]
    assert sorted(os.listdir(repo)) == ["use-cases.yml"]
    assert call_core(str(repo), "validate")["use_cases"] == 0


def test_no_root_prefix_unless_asked_and_both_forms_give_the_same_ids(tmp_path):
    full, minimal, named = tmp_path / "full", tmp_path / "minimal", tmp_path / "named"
    for folder, args in ((full, []), (minimal, ["--minimal"]), (named, ["--prefix", "shop"])):
        folder.mkdir()
        init(folder, *args)
    assert "\nprefix:" not in read(full, "use-cases.yml") and "# prefix: shop" in read(full, "use-cases.yml")
    assert read(full, "use-cases.yml") == read(minimal, "use-cases.yml")
    shutil.copytree(full / "use-cases", minimal / "use-cases")  # the same use case file in each
    ids = lambda folder: [u["use_case"] for u in call_core(str(folder), "status")["use_cases"]]
    assert ids(full) == ids(minimal) == ["example.getting-started"]
    assert ids(named) == ["shop.example.getting-started"]


@pytest.mark.parametrize("prefix", ["Shop", "shop_", "shop..app", "-shop"])
def test_an_invalid_prefix_is_a_usage_error(repo, prefix):
    assert "not a valid prefix" in init(repo, f"--prefix={prefix}", expect_exit=2)
    assert os.listdir(repo) == []


# ------------------------------------------------------------------ never overwrites (§3)


def test_it_never_overwrites_and_a_second_run_keeps_everything(repo):
    (repo / "use-case-groups.yml").write_text("schema_version: 1\ngroups:\n  mine:\n    include: {prefixes: [example]}\n")
    before = read(repo, "use-case-groups.yml")
    first = init(repo)
    assert "use-case-groups.yml" in first["kept"] and read(repo, "use-case-groups.yml") == before
    second = init(repo)
    assert second["created"] == [] and sorted(second["kept"]) == sorted(
        ["use-cases.yml", "use-cases/example.yml", "use-case-groups.yml", "use-cases-bridge.yml"])


def test_an_existing_workspace_gains_only_what_it_lacks(tmp_path):
    ws = tmp_path / "py"
    shutil.copytree(os.path.join(FIXTURES, "python", "2-use-cases"), ws)
    before = call_core(str(ws), "status")["use_cases"]
    made = init(ws)
    assert made["created"] == ["use-cases-bridge.yml"] and made["kept"] == ["use-cases.yml"]
    assert not (ws / "use-cases" / "example.yml").exists() and not (ws / "use-case-groups.yml").exists()
    assert [u["use_case"] for u in call_core(str(ws), "status")["use_cases"]] == [u["use_case"] for u in before]


def test_inside_a_workspace_is_refused(repo):
    init(repo, "--minimal")
    below = repo / "services" / "pay"
    below.mkdir(parents=True)
    process = subprocess.run([*COMMAND, "--workspace", str(below), "--json", "init"], capture_output=True, stdin=subprocess.DEVNULL,
                             text=True, encoding="utf-8")
    assert process.returncode == 2 and "inside the workspace" in process.stderr and '"refused"' in process.stdout
    assert os.listdir(below) == []


def test_a_child_scope_file_is_left_alone(repo):
    (repo / "use-cases.yml").write_text("schema_version: 1\nprefix: svc\n")
    assert "not a workspace root" in init(repo, expect_exit=2)
    assert read(repo, "use-cases.yml") == "schema_version: 1\nprefix: svc\n"


# ------------------------------------------------------------------ .gitignore (§6)


def test_gitignore_gains_one_line_once_when_version_control_is_there(repo):
    (repo / ".git").mkdir()
    (repo / ".gitignore").write_text("node_modules/")  # no trailing newline
    assert init(repo, "--minimal")["gitignore"] == "added"
    assert read(repo, ".gitignore") == "node_modules/\n.use-cases/\n"
    assert init(repo, "--minimal")["gitignore"] == "present"
    assert read(repo, ".gitignore").count(".use-cases") == 1


@pytest.mark.parametrize("line", [".use-cases", ".use-cases/", "/.use-cases", "/.use-cases/"])
def test_an_existing_exclusion_is_recognised(repo, line):
    (repo / ".gitignore").write_text(f"{line}\n")
    assert init(repo, "--minimal")["gitignore"] == "present"
    assert read(repo, ".gitignore") == f"{line}\n"


# ------------------------------------------------------------------ base files only (§5)


@pytest.mark.parametrize("language", ["python", "javascript", "go", "rust", "c", "java", "kotlin", "swift", "bdd"])
def test_init_never_writes_a_test_command_whatever_the_codebase(tmp_path, language):
    ws = tmp_path / language
    shutil.copytree(os.path.join(FIXTURES, language, "1-plain"), ws, ignore=shutil.ignore_patterns("node_modules"))
    init(ws)
    bridge = read(ws, "use-cases-bridge.yml")
    assert yaml.safe_load(bridge) == {"schema_version": 1}  # a template: no validation, no command
    assert "# validations:" in bridge and "your, test, command" in bridge
    assert call_core(str(ws), "verify", "--run")["notes"]  # nothing set up, so nothing runs


def test_the_human_output_lists_what_it_made_and_one_next_step(repo):
    process = subprocess.run([*COMMAND, "init"], cwd=repo, capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    lines = process.stdout.strip().splitlines()
    assert process.returncode == 0 and "a commented template: add your own test command" in process.stdout
    assert lines[-1] == "→ use-cases status"
