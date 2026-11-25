"""Real-world paths and files (chapters 04, 08, 09): spaces, Unicode, case, control characters,
symlinks, missing final newlines, and the one glob dialect.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_paths.py -v
"""

import json
import os
import re
import subprocess
import sys
import unicodedata

import pytest
from conftest import call_core


def symlink(target, link):
    try:
        os.symlink(target, link)
    except (OSError, NotImplementedError):
        pytest.skip("creating symlinks needs a privilege this Windows session lacks")

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

USE_CASES = """
prefix: math
use_cases:
  - id: add
    title: Add numbers
    value_tier: core
    intent: Two numbers add up.
    scenarios:
      - id: adds
        when: [Add two numbers.]
        then: [The sum is returned.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [adds]
"""

BRIDGE = """schema_version: 1
validations:
  - id: unit-tests
    report: unit.xml
    run: [node, --test, --test-reporter=junit, "--test-reporter-destination={report}"]
    transformer: junit
    settings: { find: pattern, files: "**/*.test.js", patterns: ['"{name}"'] }
"""

TEST = 'import { test } from "node:test";\nimport assert from "node:assert/strict";\n\n' \
       '// @use-case:demo.math.add#unit-tests.adds\ntest("adds", () => {\n  assert.equal(2 + 3, 5);\n});\n' \
       '// @use-case:end demo.math.add#unit-tests.adds\n'


def uc(ws, *args, expect_exit=0):
    return call_core(ws, *args, expect_exit=expect_exit)


def workspace(root, test_path, extra_yaml=""):
    files = {"use-cases.yml": "schema_version: 1\nroot: true\nprefix: demo\n", "use-cases/math.yml": USE_CASES + extra_yaml,
             "use-cases-bridge.yml": BRIDGE, "package.json": '{ "type": "module" }\n', "src/math.js": "export const add = (a, b) => a + b;\n",
             test_path: TEST}
    for rel, content in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(content)
    return str(root)


def binding(file):
    return f"    bindings:\n      - id: code\n        kind: manual\n        locator: {{ file: {json.dumps(file)} }}\n"


NAMES = ["My Tests/add test.test.js", "tests/café.test.js"] + ([] if os.name == "nt" else ["tests/a@b:c.test.js"])  # : is not allowed in Windows file names


@pytest.mark.parametrize("test_path", NAMES)
def test_any_file_name_links_and_verifies(tmp_path, test_path):
    ws = workspace(tmp_path / "ws", test_path)
    key = uc(ws, "links")["links"][0]["key"]
    assert key == f"demo.math.add#unit-tests.adds@{test_path}:5"
    run = uc(ws, "verify", "--run")
    assert run["errors"] == [] and [r["status"] for r in run["results"]] == ["pass"]
    assert list(run["results"][0]["links"]) == [key]  # the schema hook checks the key format too


def test_a_named_path_must_match_its_on_disk_case(tmp_path):
    ws = workspace(tmp_path / "ws", "tests/add.test.js", extra_yaml=binding("Src/math.js"))
    assert "spelled 'src" in uc(ws, "status", expect_exit=2)


def test_a_named_path_must_match_its_on_disk_unicode_form(tmp_path):
    nfc = unicodedata.normalize("NFC", "src/café.js")
    nfd = unicodedata.normalize("NFD", "src/café.js")
    ws = workspace(tmp_path / "ws", "tests/add.test.js", extra_yaml=binding(nfd))
    os.makedirs(os.path.join(ws, "src"), exist_ok=True)
    with open(os.path.join(ws, nfc), "w") as handle:
        handle.write("export const x = 1;\n")
    if os.path.exists(os.path.join(ws, nfd)) and nfd in os.listdir(os.path.join(ws, "src")):
        pytest.skip("this file system stored the name in both forms")
    assert "paths must match exactly" in uc(ws, "status", expect_exit=2)


def test_a_file_name_with_a_control_character_is_skipped_with_a_warning(tmp_path):
    ws = workspace(tmp_path / "ws", "tests/add.test.js")
    if os.name == "nt":
        pytest.skip("Windows file names cannot hold a control character")
    with open(os.path.join(ws, "tests", "bad\nname.js"), "w") as handle:
        handle.write("// @use-case:demo.math.add#unit-tests.bad\nx\n// @use-case:end demo.math.add#unit-tests.bad\n")
    found = uc(ws, "links")
    assert all("\n" not in l["file"] for l in found["links"])
    assert any("control character" in d for d in found["diagnostics"])


def test_a_marker_region_on_the_last_line_without_a_newline(tmp_path):
    ws = workspace(tmp_path / "ws", "tests/add.test.js")
    with open(os.path.join(ws, "src", "math.js"), "w") as handle:
        handle.write("// @use-case:demo.math.add#code\nexport const add = (a, b) => a + b;\n// @use-case:end demo.math.add#code")
    link = next(l for l in uc(ws, "links")["links"] if l["binding"] == "code")
    assert link["range"] == {"start": 2, "end": 2}


def test_symlinked_folders_are_never_followed(tmp_path):
    outside = tmp_path / "elsewhere"
    outside.mkdir()
    (outside / "copy.js").write_text("// @use-case:demo.math.add#via-link\nx\n// @use-case:end demo.math.add#via-link\n")
    ws = workspace(tmp_path / "ws", "tests/add.test.js")
    symlink(outside, os.path.join(ws, "linked"))
    assert all(l["binding"] != "via-link" for l in uc(ws, "links")["links"])


def test_a_symlink_contributes_its_target_text_never_the_target(tmp_path):
    """The bytes a Windows checkout without symlinks writes into a plain file: the same fingerprint everywhere."""
    secret = tmp_path / "secret.js"
    secret.write_text("outside the project\n")
    ws = workspace(tmp_path / "ws", "tests/add.test.js", extra_yaml=binding("src/escape.js"))
    symlink("../../secret.js", os.path.join(ws, "src", "escape.js"))
    before = uc(ws, "status")
    secret.write_text("changed outside the project\n")
    after = uc(ws, "status")
    assert before == after  # the target's bytes never count
    plain = workspace(tmp_path / "plain", "tests/add.test.js", extra_yaml=binding("src/escape.js"))
    with open(os.path.join(plain, "src", "escape.js"), "w") as handle:
        handle.write("../../secret.js")  # what a checkout with core.symlinks=false contains
    record = lambda w: uc(w, "record", "demo.math.add", "unit-tests", "pass")["results"][0]["fingerprint"]
    assert record(ws) == record(plain)


# ------------------------------------------------------------------ one glob dialect (chapter 04)


def resource(pattern):
    return f"        resources:\n          - kind: glob\n            pattern: {json.dumps(pattern)}\n"


@pytest.mark.parametrize("pattern, matches", [
    ("fixtures/**/*.json", True),      # ** matches zero folders
    ("fixtures/*.json", True),
    ("*a.json", False),                # * never crosses /: only fixtures/a.json exists
    ("Fixtures/*.json", False),        # case-sensitive everywhere
    ("fixtures/?.json", True),
])
def test_resource_globs_use_the_one_dialect(tmp_path, pattern, matches):
    ws = workspace(tmp_path / "ws", "tests/add.test.js")
    use_cases = os.path.join(ws, "use-cases", "math.yml")
    with open(use_cases) as handle:
        text = handle.read()
    with open(use_cases, "w") as handle:
        handle.write(text.replace("        covers: [adds]\n", "        covers: [adds]\n" + resource(pattern)))
    os.makedirs(os.path.join(ws, "fixtures"))
    with open(os.path.join(ws, "fixtures", "a.json"), "w") as handle:
        handle.write("{}")
    if matches:
        uc(ws, "status")
    else:
        assert "matches nothing" in uc(ws, "status", expect_exit=2)


def with_resource(ws, resources):
    use_cases = os.path.join(ws, "use-cases", "math.yml")
    with open(use_cases) as handle:
        text = handle.read()
    text = re.sub(r"        resources:\n(?:          .*\n)+", "", text)  # replace any resources already written
    with open(use_cases, "w") as handle:
        handle.write(text.replace("        covers: [adds]\n", "        covers: [adds]\n        resources:\n" + resources))


def put(ws, rel, text="{}"):
    os.makedirs(os.path.dirname(os.path.join(ws, rel)), exist_ok=True)
    with open(os.path.join(ws, rel), "w") as handle:
        handle.write(text)


@pytest.mark.parametrize("pattern", [
    "vendor/*.json",                  # discovery.exclude
    ".git/*",                         # a built-in exclusion
    ".use-cases/**",                  # the store
    "use-cases.yml", "use-cases-bridge.yml", "use-cases/*.yml",   # Use Cases' own files
    "nested/*.json",                  # inside a nested workspace
], ids=lambda p: p)
def test_a_resource_glob_matches_only_files_the_scan_reads(tmp_path, pattern):
    ws = workspace(tmp_path / "ws", "tests/add.test.js")
    with open(os.path.join(ws, "use-cases.yml"), "a") as handle:
        handle.write("discovery:\n  exclude: [vendor]\n")
    put(ws, "vendor/a.json")
    put(ws, ".git/HEAD", "ref: x\n")
    put(ws, "nested/use-cases.yml", "schema_version: 1\nroot: true\n")
    put(ws, "nested/a.json")
    with_resource(ws, f"          - kind: glob\n            pattern: {json.dumps(pattern)}\n")
    assert "matches nothing" in uc(ws, "status", expect_exit=2)


def test_an_excluded_file_never_changes_a_globs_fingerprint_but_an_explicit_path_may_name_one(tmp_path):
    ws = workspace(tmp_path / "ws", "tests/add.test.js")
    with open(os.path.join(ws, "use-cases.yml"), "a") as handle:
        handle.write("discovery:\n  exclude: [vendor]\n")
    put(ws, "fixtures/a.json")
    put(ws, "vendor/a.json", "{}")
    with_resource(ws, "          - kind: glob\n            pattern: \"**/*.json\"\n")
    uc(ws, "record", "demo.math.add", "unit-tests", "pass")
    put(ws, "vendor/a.json", '{"changed": true}')
    put(ws, "vendor/b.json")
    assert uc(ws, "status")["use_cases"][0]["status"] == "verified"
    put(ws, "fixtures/a.json", '{"changed": true}')
    assert uc(ws, "status")["use_cases"][0]["status"] == "stale"
    with_resource(ws, "          - kind: file\n            path: vendor/a.json\n")  # explicit: allowed in an excluded folder
    uc(ws, "status")


@pytest.mark.parametrize("pattern", ["build**", "/abs/**", "a//b", "../x/**", "./build/**", "build/"])
def test_a_malformed_pattern_is_invalid(tmp_path, pattern):
    ws = workspace(tmp_path / "ws", "tests/add.test.js")
    with open(os.path.join(ws, "use-cases.yml"), "a") as handle:
        handle.write(f"discovery:\n  exclude: [{json.dumps(pattern)}]\n")
    assert "pattern" in uc(ws, "status", expect_exit=2)
