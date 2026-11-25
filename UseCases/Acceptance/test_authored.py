"""Authored files read one way only (chapters 02, 04, 09 §14): YAML typing, duplicate keys, schemas at load,
unique scenario and route ids, the declared root, nested workspaces, and scope placement.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_authored.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
from conftest import SENTINEL, call_core, COMMAND

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROOT = "schema_version: 1\nroot: true\nprefix: app\n"


def use_case(local="toggle", scenario="on-state", title="Dark mode", extra=""):
    return (f"use_cases:\n  - id: {local}\n    title: {title}\n    value_tier: core\n    intent: Readable at night.\n"
            f"    scenarios:\n      - id: {scenario}\n        when: [x]\n        then: [y]\n"
            f"    validation:\n      - id: manual\n        type: {{ kind: acceptance }}\n        covers: [{scenario}]\n"
            f"        procedure:\n          steps: [Check it.]\n{extra}")


def uc(ws, *args, expect_exit=0):
    return call_core(ws, *args, expect_exit=expect_exit)


def workspace(root, files):
    for rel, text in {"use-cases.yml": ROOT, **files}.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(text)
    return str(root)


# ------------------------------------------------------------------ YAML reads the same everywhere


# @use-case:validate.refuses-unsafe-yaml#acceptance.ambiguous-scalars
@pytest.mark.parametrize("value", ["on", "No", "yes", "1:30", "2024-01-01", "1e3", "0o17"])
def test_a_plain_scalar_two_yaml_versions_read_differently_must_be_quoted(tmp_path, value):
    ws = workspace(tmp_path / "a", {"use-cases/ui.yml": use_case(title=value)})
    assert "quote it" in uc(ws, "validate", expect_exit=2)
    ws = workspace(tmp_path / "b", {"use-cases/ui.yml": use_case(title=f'"{value}"')})
    assert uc(ws, "status")["use_cases"][0]["title"] == value
# @use-case:end validate.refuses-unsafe-yaml#acceptance.ambiguous-scalars


def test_scenario_ids_that_yaml_1_1_reads_as_booleans_must_be_quoted(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(scenario="on")})
    assert "quote it" in uc(ws, "validate", expect_exit=2)


# @use-case:validate.refuses-unsafe-yaml#acceptance.ambiguous-scalars
def test_a_key_two_yaml_versions_read_differently_must_be_quoted(tmp_path):
    approved = '    approved:\n      by: Sam\n      {key}: "2026-10-11"\n      behaviour: ' + "a" * 64 + "\n"
    ws = workspace(tmp_path / "a", {"use-cases/ui.yml": use_case(extra=approved.format(key="on"))})
    assert "quote it" in uc(ws, "validate", expect_exit=2)
    ws = workspace(tmp_path / "b", {"use-cases/ui.yml": use_case(extra=approved.format(key='"on"'))})
    assert uc(ws, "status")["use_cases"][0]["title"] == "Dark mode"
# @use-case:end validate.refuses-unsafe-yaml#acceptance.ambiguous-scalars


def test_a_sign_off_day_is_a_real_calendar_date(tmp_path):
    approved = '    approved:\n      by: Sam\n      "on": "2026-02-30"\n      behaviour: ' + "a" * 64 + "\n"
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(extra=approved)})
    assert "2026-02-30" in uc(ws, "validate", expect_exit=2)


def test_a_name_ending_in_a_line_break_is_invalid(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(local='"toggle\\n"')})
    assert "use-cases/ui.yml" in uc(ws, "validate", expect_exit=2)


# @use-case:validate.refuses-unsafe-yaml#acceptance.ambiguous-scalars
@pytest.mark.parametrize("change, said", [
    (lambda text: text + "---\nuse_cases: []\n", "single document"),
    (lambda text: text.replace("steps: [Check it.]", "steps: [!!str Check it.]"), "tag"),
    (lambda text: text.replace("steps: [Check it.]", "steps: !!seq [Check it.]"), "tag"),
    (lambda text: text.replace("steps: [Check it.]", "steps: [!note Check it.]"), "tag"),
    (lambda text: text.replace("steps: [Check it.]", "<<: {steps: [Check it.]}"), "quote it"),
])
def test_yaml_that_readers_take_differently_is_refused(tmp_path, change, said):
    ws = workspace(tmp_path, {"use-cases/ui.yml": change(use_case())})
    assert said in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.refuses-unsafe-yaml#acceptance.ambiguous-scalars


# @use-case:validate.refuses-unsafe-yaml#acceptance.unsafe-yaml
@pytest.mark.parametrize("change, said", [
    (lambda text: text + "1: x\n", "quote it"),
    (lambda text: text + "~: x\n", "quote it"),
    (lambda text: text.replace("steps: [Check it.]", "steps: [.inf]"), "quote it"),
    (lambda text: text.replace("steps: [Check it.]", "steps: [-.Inf]"), "quote it"),
    (lambda text: text.replace("steps: [Check it.]", "steps: [.nan]"), "quote it"),
    (lambda text: text.replace("steps: [Check it.]", "steps: [1.0e+400]"), "quote it"),
    (lambda text: text.replace("steps: [Check it.]", "steps: " + "[" * 65 + "x" + "]" * 65), "64 levels"),
    (lambda text: "".join(f"l{n}: &l{n} [" + ", ".join([f"*l{n - 1}" if n else "x"] * 10) + "]\n" for n in range(7)) + text,
     "100,000 values"),
])
def test_yaml_no_reader_can_take_one_way_or_safely_is_refused(tmp_path, change, said):
    ws = workspace(tmp_path, {"use-cases/ui.yml": change(use_case())})
    assert said in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.refuses-unsafe-yaml#acceptance.unsafe-yaml


# @use-case:validate.refuses-unsafe-yaml#acceptance.ordinary-yaml
@pytest.mark.parametrize("change", [
    lambda text: text.replace("steps: [Check it.]", "steps:\n            - |\n              Check it.\n              Twice.\n"),
    lambda text: text.replace("when: [x]", "when: &both [x]").replace("then: [y]", "then: *both"),
    lambda text: "\ufeff" + text,
])
def test_multi_line_text_aliases_and_a_byte_order_mark_are_ordinary_yaml(tmp_path, change):
    ws = workspace(tmp_path, {"use-cases/ui.yml": change(use_case())})
    assert uc(ws, "validate")["use_cases"] == 1
# @use-case:end validate.refuses-unsafe-yaml#acceptance.ordinary-yaml


# @use-case:validate.refuses-unsafe-yaml#acceptance.duplicate-keys
def test_a_duplicate_key_is_invalid(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case().replace("    title: Dark mode\n", "    title: Dark mode\n    title: Night mode\n")})
    assert "duplicate key 'title'" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.refuses-unsafe-yaml#acceptance.duplicate-keys


# @use-case:validate.draft-or-ready#acceptance.wrong-type-is-invalid
def test_a_value_of_the_wrong_type_is_invalid_not_draft(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(title="42")})
    assert "is not of type 'string'" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.draft-or-ready#acceptance.wrong-type-is-invalid


# @use-case:validate.workspace-layout-rules#acceptance.stray-files
def test_a_file_in_the_definitions_folder_that_is_not_a_definition_is_invalid(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(), "use-cases/ci.yml": "jobs:\n  build: {}\n"})
    assert "use-cases/ci.yml" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.stray-files


# ------------------------------------------------------------------ ids are unique where they are used


# @use-case:validate.refuses-broken-structure#acceptance.duplicate-ids
@pytest.mark.parametrize("kind, extra", [
    ("scenario", None),
    ("route", "      - id: manual\n        type: { kind: e2e }\n        covers: [on-state]\n        gates_verification: false\n"),
])
def test_two_scenarios_or_two_routes_with_one_id_are_invalid(tmp_path, kind, extra):
    text = use_case() + (extra or "")
    if kind == "scenario":
        text = text.replace("        then: [y]\n", "        then: [y]\n      - id: on-state\n        when: [z]\n        then: [w]\n", 1)
    else:
        text = text.replace("        procedure:\n          steps: [Check it.]\n", "        procedure:\n          steps: [Check it.]\n" + extra, 1)
    ws = workspace(tmp_path, {"use-cases/ui.yml": text})
    assert f"two {kind}s with id" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.refuses-broken-structure#acceptance.duplicate-ids


# ------------------------------------------------------------------ one root, stable ids


# @use-case:validate.workspace-layout-rules#acceptance.root-says-root
def test_the_root_must_say_it_is_the_root(tmp_path):
    ws = workspace(tmp_path, {"use-cases.yml": "schema_version: 1\nprefix: app\n", "use-cases/ui.yml": use_case()})
    assert "root: true" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.root-says-root


# @use-case:cli.finds-the-workspace#acceptance.child-scope-named
def test_pointing_at_a_child_scope_is_refused_so_ids_never_shift(tmp_path):
    ws = workspace(tmp_path, {"auth/use-cases.yml": "schema_version: 1\nprefix: auth\n", "auth/use-cases/login.yml": use_case("login")})
    assert [u["use_case"] for u in uc(ws, "status")["use_cases"]] == ["app.auth.login"]
    assert "child scope" in uc(os.path.join(ws, "auth"), "validate", expect_exit=2)
# @use-case:end cli.finds-the-workspace#acceptance.child-scope-named


# @use-case:cli.finds-the-workspace#acceptance.nested-root
def test_a_vendored_workspace_is_its_own_and_never_entered(tmp_path):
    vendored = {"vendor/auth/use-cases.yml": "schema_version: 1\nroot: true\nprefix: auth\n",
                "vendor/auth/use-cases/login.yml": use_case("login"),
                "vendor/auth/src/login.js": f"// {SENTINEL}auth.login#code\nx\n// {SENTINEL}end auth.login#code\n"}
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(), **vendored})
    host = uc(ws, "status")
    assert [u["use_case"] for u in host["use_cases"]] == ["app.toggle"]  # its use cases and markers stay its own
    assert [u["use_case"] for u in uc(os.path.join(ws, "vendor", "auth"), "status")["use_cases"]] == ["auth.login"]
# @use-case:end cli.finds-the-workspace#acceptance.nested-root


# @use-case:validate.workspace-layout-rules#acceptance.stray-files
def test_a_scope_inside_another_scopes_definitions_is_invalid(tmp_path):
    ws = workspace(tmp_path, {"use-cases/billing/invoice.yml": use_case("invoice"),
                              "use-cases/billing/use-cases.yml": "schema_version: 1\nprefix: billing\n"})
    assert "which holds the root scope's definitions" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.stray-files


# @use-case:validate.workspace-layout-rules#acceptance.stray-files
@pytest.mark.parametrize("name", ["ui.YML", "ui.Yaml"])
def test_a_definition_file_ending_in_upper_case_is_refused_never_skipped(tmp_path, name):
    ws = workspace(tmp_path, {f"use-cases/{name}": use_case()})
    assert f"use-cases/{name}" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.stray-files


def test_a_missing_use_cases_folder_reads_as_an_empty_one(tmp_path):
    # git never stores an empty folder: missing and empty must give one answer on every checkout
    assert uc(workspace(tmp_path, {}), "validate")["use_cases"] == 0


SYMLINKS = pytest.mark.skipif(os.name == "nt", reason="making a symlink on Windows needs a privilege the runner lacks")


def test_a_root_workspace_inside_another_scopes_definitions_is_invalid(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(), "use-cases/vendor/use-cases.yml": ROOT})
    assert "use-cases/vendor/use-cases.yml" in uc(ws, "validate", expect_exit=2)


# @use-case:validate.workspace-layout-rules#acceptance.no-symlinks
@SYMLINKS
@pytest.mark.parametrize("kind", ["file", "folder"])
def test_any_symlink_inside_a_use_cases_dir_is_invalid(tmp_path, kind):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(), "elsewhere/more.yml": use_case("more")})
    target = os.path.join(ws, "elsewhere", "more.yml") if kind == "file" else os.path.join(ws, "elsewhere")
    os.symlink(target, os.path.join(ws, "use-cases", "more.yml" if kind == "file" else "more"))
    assert "use-cases/more" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.no-symlinks


# @use-case:validate.workspace-layout-rules#acceptance.no-symlinks
@SYMLINKS
def test_a_use_cases_dir_that_is_a_symlink_is_invalid(tmp_path):
    ws = workspace(tmp_path, {"use-cases.yml": ROOT + "use_cases_dir: specs\n", "real/ui.yml": use_case()})
    os.symlink(os.path.join(ws, "real"), os.path.join(ws, "specs"))
    assert "specs" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.no-symlinks


# @use-case:validate.workspace-layout-rules#acceptance.no-symlinks
@SYMLINKS
def test_a_use_cases_yml_that_is_a_symlink_is_invalid(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(), "shared.yml": "schema_version: 1\nprefix: svc\n"})
    os.makedirs(os.path.join(ws, "svc"))
    os.symlink(os.path.join(ws, "shared.yml"), os.path.join(ws, "svc", "use-cases.yml"))
    assert "svc/use-cases.yml" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.no-symlinks


@pytest.mark.parametrize("files, named", [
    ({"use-cases.yml": ROOT + "use_cases_dir: specs\n", "specs": "not a folder\n"}, "specs"),
    ({"use-cases.yml": ROOT + "use_cases_dir: build/specs\ndiscovery:\n  exclude: [build]\n", "build/specs/ui.yml": use_case()},
     "build/specs"),
    ({"use-cases.yml": ROOT + "use_cases_dir: svc/use-cases\n", "svc/use-cases.yml": "schema_version: 1\nprefix: svc\n",
      "svc/use-cases/ui.yml": use_case()}, "svc/use-cases"),
])
def test_a_use_cases_dir_that_cannot_be_read_one_way_is_invalid_never_skipped(tmp_path, files, named):
    # a file, an excluded folder, or a folder two scopes would own
    assert named in uc(workspace(tmp_path, files), "validate", expect_exit=2)


# @use-case:validate.workspace-layout-rules#acceptance.spelling-matches-disk
@pytest.mark.parametrize("files, on_disk", [
    ({"use-cases.yml": ROOT + "use_cases_dir: Specs\n", "specs/ui.yml": use_case()}, "specs"),
    ({"use-cases.yml": ROOT + "use_cases_dir: specs/Inner\n", "specs/inner/ui.yml": use_case()}, "specs/inner"),
    ({"Use-Cases/ui.yml": use_case()}, "Use-Cases"),
])
def test_a_use_cases_dir_spelled_with_other_case_than_the_disk_is_invalid_naming_the_disk(tmp_path, files, on_disk):
    # decided by listing the parent folder, so a case-insensitive and a case-sensitive system give the same answer
    assert on_disk in uc(workspace(tmp_path, files), "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.spelling-matches-disk


# @use-case:validate.workspace-layout-rules#acceptance.spelling-matches-disk
def test_a_use_cases_dir_spelled_in_another_unicode_form_than_the_disk_is_invalid(tmp_path):
    decomposed, composed = "spe\u0301cs", "sp\u00e9cs"  # the same word to a reader, different bytes
    ws = workspace(tmp_path, {"use-cases.yml": ROOT + f"use_cases_dir: {decomposed}\n", f"{composed}/ui.yml": use_case()})
    if composed not in os.listdir(ws):
        pytest.skip("this file system rewrites the Unicode form of a name")
    assert composed in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.spelling-matches-disk


# @use-case:validate.workspace-layout-rules#acceptance.spelling-matches-disk
def test_a_child_use_cases_yml_spelled_with_other_case_is_invalid_naming_the_disk(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case(), "svc/Use-Cases.yml": "schema_version: 1\nprefix: svc\n"})
    assert "svc/Use-Cases.yml" in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.workspace-layout-rules#acceptance.spelling-matches-disk


def test_a_root_use_cases_yml_spelled_with_other_case_is_not_a_workspace_root(tmp_path):
    with open(tmp_path / "Use-Cases.yml", "w") as handle:
        handle.write(ROOT)
    assert "Use-Cases.yml" in uc(str(tmp_path), "validate", expect_exit=2)


# @use-case:validate.discovery-exclusions#acceptance.exclusion-into-definitions
@pytest.mark.parametrize("pattern", ["use-cases/old.yml", "use-cases/archive/**"])
def test_an_exclusion_that_reaches_inside_a_use_cases_dir_is_invalid_naming_the_pattern(tmp_path, pattern):
    ws = workspace(tmp_path, {"use-cases.yml": ROOT + f"discovery:\n  exclude: [{pattern}]\n", "use-cases/ui.yml": use_case(),
                              "use-cases/old.yml": use_case("old"), "use-cases/archive/a.yml": use_case("archived")})
    assert pattern in uc(ws, "validate", expect_exit=2)
# @use-case:end validate.discovery-exclusions#acceptance.exclusion-into-definitions


# @use-case:validate.discovery-exclusions#acceptance.excluded-folder
def test_an_exclusion_outside_every_use_cases_dir_stays_fine_and_is_never_entered(tmp_path):
    ws = workspace(tmp_path, {"use-cases.yml": ROOT + "discovery:\n  exclude: [vendor/**]\n", "use-cases/ui.yml": use_case(),
                              "vendor/use-cases.yml": "schema_version: 1\nprefix: v\n", "vendor/use-cases/x.yml": "not: [valid\n"})
    assert uc(ws, "validate")["use_cases"] == 1
# @use-case:end validate.discovery-exclusions#acceptance.excluded-folder


@pytest.mark.skipif(not hasattr(os, "mkfifo"), reason="a pipe in the file system is POSIX only")
def test_a_pipe_inside_a_use_cases_dir_is_invalid_and_never_opened(tmp_path):
    ws = workspace(tmp_path, {"use-cases/ui.yml": use_case()})
    os.mkfifo(os.path.join(ws, "use-cases", "pipe.yml"))
    assert "use-cases/pipe.yml" in uc(ws, "validate", expect_exit=2)


def test_use_cases_dir_may_not_hold_its_own_config(tmp_path):
    ws = workspace(tmp_path, {"use-cases.yml": ROOT + "use_cases_dir: .\n", "ui.yml": use_case()})
    assert "must not contain this scope's own use-cases.yml" in uc(ws, "validate", expect_exit=2)


# ------------------------------------------------------------------ a note after unquoted text (chapter 02, ADR 017)


# @use-case:validate.refuses-unsafe-yaml#acceptance.unquoted-note
@pytest.mark.parametrize("title, steps", [
    ("Dark mode", "[Check it.]\n        # a note on its own line is fine\n"),
    ('"Dark mode #2"', "[Check it.]\n"),  # a quoted # is text
    ('"Dark mode"  # a note after quoted text loses nothing', "[Check it.]\n"),
])
def test_quoted_text_and_notes_on_their_own_line_are_read_as_written(tmp_path, title, steps):
    ws = workspace(tmp_path, {"use-cases/a.yml": "prefix: dark\n" + use_case(title=title).replace("[Check it.]\n", steps)})
    shown = uc(ws, "show", "app.dark.toggle")["definition"]
    assert shown["title"] == title.split("  #")[0].strip('"')
# @use-case:end validate.refuses-unsafe-yaml#acceptance.unquoted-note


# @use-case:validate.refuses-unsafe-yaml#acceptance.unquoted-note
def test_unquoted_text_followed_by_a_note_is_refused_never_cut(tmp_path):
    text = "prefix: dark\n" + use_case().replace("    procedure:\n          steps: [Check it.]\n",
                                                  "    procedure:\n          steps:\n            - Check medal #4 shows\n")
    ws = workspace(tmp_path, {"use-cases/a.yml": text})
    message = uc(ws, "validate", expect_exit=2)
    assert "use-cases/a.yml:17: 'Check medal' is followed by '#4 shows'" in message and "quote the whole text" in message
# @use-case:end validate.refuses-unsafe-yaml#acceptance.unquoted-note


# @use-case:validate.refuses-unsafe-yaml#acceptance.ordinary-yaml
def test_settings_files_keep_their_notes(tmp_path):
    ws = workspace(tmp_path, {"use-cases.yml": ROOT.replace("prefix: app", "prefix: app   # the namespace"),
                              "use-cases/a.yml": "prefix: dark\n" + use_case()})
    assert uc(ws, "validate")["valid"] is True
# @use-case:end validate.refuses-unsafe-yaml#acceptance.ordinary-yaml


# @use-case:validate.refuses-unsafe-yaml#acceptance.unsafe-yaml
def test_use_case_input_is_held_to_the_same_rule(tmp_path):
    ws = workspace(tmp_path, {"use-cases/a.yml": "prefix: dark\n" + use_case()})
    process = subprocess.run([*COMMAND, "--workspace", ws, "save", "--file", "-"],
                             input="id: app.dark.contrast\ntitle: High contrast   # for low vision\n", capture_output=True, text=True)
    assert process.returncode == 2 and "is followed by '# for low vision'" in process.stderr
# @use-case:end validate.refuses-unsafe-yaml#acceptance.unsafe-yaml

