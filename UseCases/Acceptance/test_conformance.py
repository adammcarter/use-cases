"""Conformance: the core implements chapter 08 (markers, links) and chapter 11 (fingerprints) exactly.

    uv run --with pyyaml --with pytest pytest UseCases/Acceptance/test_conformance.py -v
"""

import codecs
import json
import os
import re
import subprocess

import pytest
from conftest import SENTINEL, POSIX_ONLY, call_core, record_exchanges

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CHAPTER_11 = os.path.join(REPO, "docs", "design", "11-fingerprints-and-freshness.md")

OPEN = f"{SENTINEL}example.success#unit-tests.success"
CLOSE = f"{SENTINEL}end example.success#unit-tests.success"


def published_vectors():
    text = open(CHAPTER_11).read()
    return dict(re.findall(r"\*\*Vector ([A-Z]) —.*?```text\n(uc-route-v1-sha256:[0-9a-f]{64})\n```", text, flags=re.S))


def workspace(tmp_path, files, freshness=None):
    root = tmp_path / "ws"
    config = "schema_version: 1\nroot: true\nprefix: example\n"
    if freshness:
        config += "freshness:\n" + "".join(f"  {line}\n" for line in freshness.splitlines())
    files = {"use-cases.yml": config, **files}
    for rel, content in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode())
    return str(root)


def uc(ws, *args, expect_exit=0):
    return call_core(ws, *args, expect_exit=expect_exit)


def fingerprint(ws, route):
    return uc(ws, "record", "example.success", route, "pass")["results"][0]["fingerprint"]


VECTOR_A_USE_CASE = """
use_cases:
  - id: success
    title: Success
    value_tier: core
    intent: Demonstrate success.
    scenarios:
      - id: success
        when: [Perform the action.]
        then: [Success is visible.]
    validation:
      - id: manual
        type: { kind: acceptance }
        covers: [success]
        procedure:
          steps: [Perform the action and observe success.]
"""

VECTOR_BC_USE_CASE = """
use_cases:
  - id: success
    title: Success
    value_tier: core
    intent: Demonstrate success.
    scenarios:
      - id: success
        when: [Perform the action.]
        then: [Success is visible.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [success]
        resources:
          - kind: file
            path: fixtures/users.json
    bindings:
      - id: implementation
        kind: manual
        locator: { file: src/app.swift }
"""

BC_FILES = {
    "use-cases/success.yml": VECTOR_BC_USE_CASE,
    "src/app.swift": "",
    "fixtures/users.json": "{}",
    "tests/app_tests.swift": f"// {OPEN}\nabc\n// {CLOSE}\n",
}


# ------------------------------------------------------------------ chapter 11 vectors, from real workspaces


def test_vector_a_from_a_workspace(tmp_path):
    ws = workspace(tmp_path, {"use-cases/success.yml": VECTOR_A_USE_CASE})
    assert fingerprint(ws, "manual") == published_vectors()["A"]


def test_vector_b_from_a_workspace(tmp_path):
    assert fingerprint(workspace(tmp_path, BC_FILES), "unit-tests") == published_vectors()["B"]


def test_vector_d_from_a_workspace(tmp_path):
    line = (f"x = /* {OPEN} */ f() + /* {SENTINEL}example.other#inner */ g() /* {SENTINEL}end example.other#inner */"
            f" /* {CLOSE} */\n")
    ws = workspace(tmp_path, {**BC_FILES, "tests/app_tests.swift": line})
    assert fingerprint(ws, "unit-tests") == published_vectors()["D"]


def test_vector_e_from_a_workspace(tmp_path):
    text = (f"// {OPEN}\nabc\n// {SENTINEL}example.other#inner\ndef\n// {SENTINEL}end example.other#inner\n// {CLOSE}\n")
    ws = workspace(tmp_path, {**BC_FILES, "tests/app_tests.swift": text}, freshness="binding_identity: content-and-locator")
    assert fingerprint(ws, "unit-tests") == published_vectors()["E"]


def test_vector_c_from_a_workspace(tmp_path):
    ws = workspace(tmp_path, BC_FILES, freshness="binding_identity: content-and-locator")
    assert fingerprint(ws, "unit-tests") == published_vectors()["C"]


# ------------------------------------------------------------------ marker regions (chapter 08)


def bc_with(tmp_path, tests_file, freshness=None, extra=None):
    return workspace(tmp_path, {**BC_FILES, "tests/app_tests.swift": tests_file, **(extra or {})}, freshness)


def test_decoration_on_sentinel_lines_is_not_content(tmp_path):
    baseline = fingerprint(bc_with(tmp_path / "a", f"// {OPEN}\nabc\n// {CLOSE}\n"), "unit-tests")
    assert fingerprint(bc_with(tmp_path / "b", f"/* {OPEN} */\nabc\n# {CLOSE} ~~~\n"), "unit-tests") == baseline


# @use-case:links.markers#acceptance.nesting
def test_adding_a_nested_marker_never_changes_the_outer_region(tmp_path):
    baseline = fingerprint(bc_with(tmp_path / "a", f"// {OPEN}\nabc\n// {CLOSE}\n"), "unit-tests")
    nested = f"// {OPEN}\n// {SENTINEL}example.other#inner\nabc\n// {SENTINEL}end example.other#inner\n// {CLOSE}\n"
    assert fingerprint(bc_with(tmp_path / "b", nested), "unit-tests") == baseline
# @use-case:end links.markers#acceptance.nesting


# @use-case:links.scan-robustness#acceptance.line-endings
def test_crlf_and_bom_files_resolve(tmp_path):
    ws = bc_with(tmp_path, ("﻿// " + OPEN + "\r\nabc\r\n// " + CLOSE + "\r\n").encode())
    assert [l["range"] for l in uc(ws, "links")["links"] if l["role"] == "validation"] == [{"start": 2, "end": 2}]
# @use-case:end links.scan-robustness#acceptance.line-endings


# @use-case:status.line-endings#acceptance.lf-crlf
def test_lf_and_crlf_checkouts_agree_by_default(tmp_path):
    unix = f"// {OPEN}\nabc\n// {CLOSE}\n"
    windows = unix.replace("\n", "\r\n")
    default = [fingerprint(bc_with(tmp_path / n, t), "unit-tests") for n, t in (("a", unix), ("b", windows))]
    assert default[0] == default[1]
    exact = "normalization:\n  ignore: []"
    strict = [fingerprint(bc_with(tmp_path / n, t, exact), "unit-tests") for n, t in (("c", unix), ("d", windows))]
    assert strict[0] != strict[1]
# @use-case:end status.line-endings#acceptance.lf-crlf


def test_whitespace_normalization(tmp_path):
    policy = "normalization:\n  ignore: [whitespace]"
    a = fingerprint(bc_with(tmp_path / "a", f"// {OPEN}\nabc\n// {CLOSE}\n", policy), "unit-tests")
    b = fingerprint(bc_with(tmp_path / "b", f"// {OPEN}\n  a b\tc  \n// {CLOSE}\n", policy), "unit-tests")
    assert a == b


# @use-case:links.scan-robustness#acceptance.not-utf8
def test_text_that_is_not_utf8_is_skipped_with_a_warning(tmp_path):
    ws = bc_with(tmp_path, f"// {OPEN}\nabc\n// {CLOSE}\n", extra={"legacy/latin1.c": b"/* " + SENTINEL.encode() + b"example.success#x */ caf\xe9 /* " + SENTINEL.encode() + b"end example.success#x */"})
    assert any("unsupported-text" in d for d in uc(ws, "links")["diagnostics"])
# @use-case:end links.scan-robustness#acceptance.not-utf8


# @use-case:links.markers#acceptance.broken-pairs-invalid
@pytest.mark.parametrize("body, reason", [
    (f"// {OPEN}\nabc\n", "never closed"),
    (f"abc\n// {CLOSE}\n", "has no start"),
    (f"// {OPEN}\n// {SENTINEL}example.success#b\n// {CLOSE}\n// {SENTINEL}end example.success#b\n", "cross"),
    (f"// {OPEN}\n// {OPEN}\n// {CLOSE}\n// {CLOSE}\n", "nested inside itself"),
])
def test_broken_marker_structure_is_invalid(tmp_path, body, reason):
    assert reason in uc(bc_with(tmp_path, body), "status", expect_exit=2)
# @use-case:end links.markers#acceptance.broken-pairs-invalid


# @use-case:validate.checks-files-only#acceptance.warnings-never-fail
def test_malformed_and_unknown_markers_only_warn(tmp_path):
    body = f"// {OPEN}\nabc\n// {CLOSE}\n// {SENTINEL}Bad_ID\n// {SENTINEL}example.nope#x\nz\n// {SENTINEL}end example.nope#x\n"
    diagnostics = uc(bc_with(tmp_path, body), "links")["diagnostics"]
    assert any("malformed marker id" in d for d in diagnostics)
    assert any("unknown use case" in d for d in diagnostics)
# @use-case:end validate.checks-files-only#acceptance.warnings-never-fail


# @use-case:links.manual-bindings#acceptance.claimed-twice
def test_a_binding_claimed_twice_is_invalid(tmp_path):
    use_case = VECTOR_BC_USE_CASE.replace("        resources:", "        bindings:\n          - id: success\n            kind: manual\n            locator: { file: src/app.swift }\n        resources:")
    ws = workspace(tmp_path, {**BC_FILES, "use-cases/success.yml": use_case})
    assert "claimed by" in uc(ws, "status", expect_exit=2)
# @use-case:end links.manual-bindings#acceptance.claimed-twice


# ------------------------------------------------------------------ manual ranges and strict mode

# @use-case:status.staleness#acceptance.move
def test_strict_mode_stales_on_moves_content_mode_does_not(tmp_path):
    moved = f"\n\n// {OPEN}\nabc\n// {CLOSE}\n"
    for policy, same in ((None, True), ("binding_identity: content-and-locator", False)):
        a = fingerprint(bc_with(tmp_path / f"a{same}", f"// {OPEN}\nabc\n// {CLOSE}\n", policy), "unit-tests")
        b = fingerprint(bc_with(tmp_path / f"b{same}", moved, policy), "unit-tests")
        assert (a == b) is same
# @use-case:end status.staleness#acceptance.move


# ------------------------------------------------------------------ the sentinel token (chapter 08)


def validation_links(ws):
    return [l for l in uc(ws, "links")["links"] if l["role"] == "validation" and l["file"] != "tests/app_tests.swift"]


# @use-case:links.markers#acceptance.malformed-id
@pytest.mark.parametrize("rel, text", [
    ("page.html", f"<!--{SENTINEL}example.success#unit-tests.html-->\n<p>x</p>\n<!--{SENTINEL}end example.success#unit-tests.html-->\n"),
    ("notebook.ipynb", '{"cells": [{"source": ["# ' + SENTINEL + 'example.success#unit-tests.cell\\n", "x = 1\\n",\n'
                       '"# ' + SENTINEL + 'end example.success#unit-tests.cell\\n"]}]}\n'),
    ("nbsp.js", f"// {SENTINEL}example.success#unit-tests.nbsp note\nx\n// {SENTINEL}end example.success#unit-tests.nbsp\n"),
    ("doubled.js", f"// {SENTINEL}{SENTINEL}example.success#unit-tests.twice\nx\n// {SENTINEL}end example.success#unit-tests.twice\n"),
])
def test_the_id_ends_at_the_first_character_no_id_can_hold(tmp_path, rel, text):
    ws = bc_with(tmp_path, f"// {OPEN}\nabc\n// {CLOSE}\n", extra={rel: text})
    assert [l["file"] for l in validation_links(ws)] == [rel]
# @use-case:end links.markers#acceptance.malformed-id


# @use-case:links.manual-bindings#acceptance.claimed-twice
def test_the_same_binding_twice_on_one_line_is_invalid(tmp_path):
    line = (f"/* {SENTINEL}example.success#unit-tests.x */ a /* {SENTINEL}end example.success#unit-tests.x */ "
            f"/* {SENTINEL}example.success#unit-tests.x */ b /* {SENTINEL}end example.success#unit-tests.x */\n")
    ws = bc_with(tmp_path, f"// {OPEN}\nabc\n// {CLOSE}\n", extra={"src/twice.js": line})
    assert "share the link key" in uc(ws, "status", expect_exit=2)
# @use-case:end links.manual-bindings#acceptance.claimed-twice


# ------------------------------------------------------------------ discovery (chapter 04, ADR 012)


# @use-case:validate.discovery-exclusions#acceptance.excluded-folder
def test_a_folder_pattern_excludes_the_whole_folder(tmp_path):
    vendored = {"vendor/lib/copy.js": f"// {SENTINEL}example.success#unit-tests.v\nx\n// {SENTINEL}end example.success#unit-tests.v\n"}
    ws = bc_with(tmp_path / "a", f"// {OPEN}\nabc\n// {CLOSE}\n", extra=vendored)
    assert [l["binding"] for l in validation_links(ws)] == ["v"]
    ws = bc_with(tmp_path / "b", f"// {OPEN}\nabc\n// {CLOSE}\n", freshness=None, extra=vendored)
    with open(os.path.join(ws, "use-cases.yml"), "a") as handle:
        handle.write("discovery:\n  exclude: [vendor]\n")
    assert validation_links(ws) == []
# @use-case:end validate.discovery-exclusions#acceptance.excluded-folder


# @use-case:validate.discovery-exclusions#acceptance.history-and-store
def test_a_nested_store_is_never_scanned(tmp_path):
    console = {"sub/.use-cases/runs/x/outputs/y/console.txt": f"noise {SENTINEL}end example.success#unit-tests.z\n"}
    ws = bc_with(tmp_path, f"// {OPEN}\nabc\n// {CLOSE}\n", extra=console)
    uc(ws, "status")  # an unmatched end inside a vendored workspace's store would make this INVALID
# @use-case:end validate.discovery-exclusions#acceptance.history-and-store


# ------------------------------------------------------------------ links: warnings, ranges, reads (chapter 08)

CONFIG = "schema_version: 1\nroot: true\nprefix: example\n"
CODE = "one\ntwo\nthree\nfour\nfive\n"


def lines(first, last, file="src/code.py"):
    return f"{{ file: {file}, start: {{ line: {first} }}, end: {{ line: {last} }} }}"


def linked(implementation=(), route=(), other=()):
    """Use case `success` (and `other` when it has bindings) with manual bindings, each an (id, locator) pair."""
    def bindings(items, indent):
        pad = " " * indent
        return f"{pad}bindings:\n" + "".join(f"{pad}  - id: {i}\n{pad}    kind: manual\n{pad}    locator: {l}\n" for i, l in items) if items else ""

    def case(local, own, on_route):
        return (f"  - id: {local}\n    title: {local}\n    value_tier: core\n    intent: Demonstrate {local}.\n"
                f"    scenarios:\n      - id: s\n        when: [x]\n        then: [y]\n"
                f"    validation:\n      - id: unit-tests\n        type: {{ kind: unit }}\n        covers: [s]\n"
                f"{bindings(on_route, 8)}{bindings(own, 4)}")
    return "use_cases:\n" + case("success", implementation, route) + (case("other", other, ()) if other else "")


def warnings_about(ws, word):
    """What the links document and validate both say containing `word`: they must agree."""
    said = [d for d in uc(ws, "links")["diagnostics"] if word in d]
    assert [w for w in uc(ws, "validate")["warnings"] if word in w] == said
    return said


# @use-case:links.manual-bindings#acceptance.excluded-target
@pytest.mark.parametrize("rel, exclude", [("vendor/lib.js", "discovery:\n  exclude: [vendor]\n"), (".git/config", "")])
def test_a_manual_binding_into_excluded_content_warns_and_the_workspace_stays_valid(tmp_path, rel, exclude):
    ws = workspace(tmp_path, {"use-cases.yml": CONFIG + exclude, "use-cases/success.yml": linked([("lib", f"{{ file: {rel} }}")]),
                              rel: "x = 1\n"})
    said = warnings_about(ws, "points at excluded content")
    assert len(said) == 1 and said[0].startswith(rel)
    assert [l["file"] for l in uc(ws, "links")["links"]] == [rel]
# @use-case:end links.manual-bindings#acceptance.excluded-target


# @use-case:links.markers#acceptance.nesting
@pytest.mark.parametrize("given, overlaps", [
    ({"implementation": [("a", lines(1, 3)), ("b", lines(3, 4))]}, 1),
    ({"implementation": [("a", lines(1, 2)), ("b", lines(3, 4))]}, 0),
    ({"route": [("a", lines(1, 3)), ("b", lines(2, 4))]}, 1),
    ({"implementation": [("a", lines(1, 3))], "route": [("b", lines(2, 4))]}, 0),
    ({"implementation": [("a", lines(1, 3))], "other": [("b", lines(2, 4))]}, 0),
], ids=["implementation overlap", "touching only", "same route", "implementation and validation", "two use cases"])
def test_links_of_one_use_case_and_role_that_overlap_warn_and_nothing_else_does(tmp_path, given, overlaps):
    ws = workspace(tmp_path, {"use-cases/success.yml": linked(**given), "src/code.py": CODE})
    assert len(warnings_about(ws, "overlap")) == overlaps
# @use-case:end links.markers#acceptance.nesting


# @use-case:links.markers#acceptance.nesting
def test_nested_markers_of_one_use_case_and_route_overlap(tmp_path):
    inner = "example.success#unit-tests.inner"
    ws = bc_with(tmp_path, f"// {OPEN}\nabc\n// {SENTINEL}{inner}\ndef\n// {SENTINEL}end {inner}\n// {CLOSE}\n")
    assert len(warnings_about(ws, "overlap")) == 1
# @use-case:end links.markers#acceptance.nesting


@pytest.mark.parametrize("end_column, exit_code", [(3, 0), (4, 2)])
def test_a_leading_byte_order_mark_is_not_a_column(tmp_path, end_column, exit_code):
    where = f"{{ file: src/a.txt, start: {{ line: 1, column: 1 }}, end: {{ line: 1, column: {end_column} }} }}"
    ws = workspace(tmp_path, {"use-cases/success.yml": linked([("a", where)]), "src/a.txt": b"\xef\xbb\xbfabc\nxyz\n"})
    uc(ws, "validate", expect_exit=exit_code)


# @use-case:links.manual-bindings#acceptance.missing-file
def test_an_end_column_on_an_empty_line_is_invalid(tmp_path):
    where = "{ file: src/a.txt, start: { line: 1 }, end: { line: 2, column: 1 } }"
    ws = workspace(tmp_path, {"use-cases/success.yml": linked([("a", where)]), "src/a.txt": "a\n\nb\n"})
    assert "column" in uc(ws, "validate", expect_exit=2)
# @use-case:end links.manual-bindings#acceptance.missing-file


# @use-case:links.manual-bindings#acceptance.excluded-target
def test_an_empty_file_bound_whole_warns(tmp_path):
    ws = workspace(tmp_path, {"use-cases/success.yml": linked([("a", "{ file: src/empty.py }"), ("b", "{ file: src/full.py }")]),
                              "src/empty.py": "", "src/full.py": "x = 1\n"})
    said = warnings_about(ws, "empty whole-file binding")
    assert len(said) == 1 and said[0].startswith("src/empty.py")
# @use-case:end links.manual-bindings#acceptance.excluded-target


UNREADABLE = pytest.mark.skipif(os.name == "nt" or (hasattr(os, "getuid") and os.getuid() == 0),
                                reason="an administrator can read any file, and Windows has no mode bits")


# @use-case:links.scan-robustness#acceptance.unreadable
@UNREADABLE
@pytest.mark.parametrize("name", ["secret.py", "locked"])
def test_a_file_or_folder_the_scan_cannot_read_is_invalid_naming_it(tmp_path, name):
    ws = workspace(tmp_path, {"use-cases/success.yml": linked(), "src/secret.py": "y = 2\n", "src/locked/inner.py": "x = 1\n"})
    target = os.path.join(ws, "src", name)
    os.chmod(target, 0)
    try:
        message = uc(ws, "validate", expect_exit=2)
    finally:
        os.chmod(target, 0o755)
    assert f"src/{name}" in message
# @use-case:end links.scan-robustness#acceptance.unreadable


# @use-case:links.scan-robustness#acceptance.special-files
@pytest.mark.skipif(not hasattr(os, "mkfifo"), reason="a pipe in the file system is POSIX only")
def test_a_pipe_in_the_scanned_tree_warns_and_is_never_opened(tmp_path):
    ws = workspace(tmp_path, {"use-cases/success.yml": linked(), "src/a.py": "x = 1\n"})
    os.mkfifo(os.path.join(ws, "src", "pipe.fifo"))
    assert [d for d in warnings_about(ws, "src/pipe.fifo")] != []
# @use-case:end links.scan-robustness#acceptance.special-files


MARKED = f"// {OPEN}\nabc\n// {CLOSE}\n"
WIDE = {
    "utf-16-le": codecs.BOM_UTF16_LE + MARKED.encode("utf-16-le"), "utf-16-be": codecs.BOM_UTF16_BE + MARKED.encode("utf-16-be"),
    "utf-32-le": codecs.BOM_UTF32_LE + MARKED.encode("utf-32-le"), "utf-32-be": codecs.BOM_UTF32_BE + MARKED.encode("utf-32-be"),
}


# @use-case:links.scan-robustness#acceptance.not-utf8
@pytest.mark.parametrize("encoding", sorted(WIDE))
def test_a_file_starting_with_a_utf_16_or_32_byte_order_mark_warns_that_its_markers_cannot_be_read(tmp_path, encoding):
    ws = bc_with(tmp_path, MARKED, extra={"src/wide.txt": WIDE[encoding]})
    said = warnings_about(ws, "src/wide.txt")
    assert len(said) == 1 and "unsupported-text" in said[0]
    assert [l for l in uc(ws, "links")["links"] if l["file"] == "src/wide.txt"] == []
# @use-case:end links.scan-robustness#acceptance.not-utf8


# @use-case:links.list-links#acceptance.ordered
def test_diagnostics_sort_by_path_then_line_as_a_number(tmp_path):
    ws = bc_with(tmp_path, MARKED, extra={"src/x.py": "\n" * 8 + f"# {SENTINEL}BAD\n# {SENTINEL}BAD\n", "src/a.py": "\n" * 19 + f"# {SENTINEL}BAD\n"})
    where = [d.split(": ")[0] for d in uc(ws, "links")["diagnostics"] if "malformed" in d]
    assert where == ["src/a.py:20", "src/x.py:9", "src/x.py:10"]
# @use-case:end links.list-links#acceptance.ordered


# @use-case:links.list-links#acceptance.whole-file-range
@pytest.mark.parametrize("content, last", [("", 1), ("a", 1), ("a\n", 1), ("a\nb", 2), ("a\nb\n", 2), ("a\n\n", 2), ("\n", 1), ("a\r\nb\r\n", 2)])
def test_a_whole_file_links_range_ends_at_the_last_line_holding_bytes(tmp_path, content, last):
    ws = workspace(tmp_path, {"use-cases/success.yml": linked([("a", "{ file: src/a.txt }")]), "src/a.txt": content})
    assert next(l for l in uc(ws, "links")["links"] if l["file"] == "src/a.txt")["range"] == {"start": 1, "end": last}
# @use-case:end links.list-links#acceptance.whole-file-range


# @use-case:links.list-links#acceptance.whole-file-range
@POSIX_ONLY
def test_a_transformers_whole_file_link_has_the_same_range(tmp_path):
    response = json.dumps({"contract": 1, "diagnostics": [], "links": [
        {"use_case": "example.success", "binding": "t", "role": "implementation", "file": "src/a.txt"}]})
    ws = workspace(tmp_path, {"use-cases/success.yml": linked(), "src/a.txt": "a\nb\n",
                              "tools/links": f"#!/bin/sh\nprintf '%s' '{response}' > \"$3\"\n",
                              "use-cases-bridge.yml": "schema_version: 1\nlinks:\n  - transformer: tools/links\n"})
    os.chmod(os.path.join(ws, "tools", "links"), 0o755)
    record_exchanges(os.path.join(ws, "tools", "links"))
    assert next(l for l in uc(ws, "links")["links"] if l["file"] == "src/a.txt")["range"] == {"start": 1, "end": 2}
# @use-case:end links.list-links#acceptance.whole-file-range


# @use-case:links.markers#acceptance.broken-pairs-invalid
@pytest.mark.parametrize("body, reason", [
    (f"// {SENTINEL}example.nope#x\nz\n", "never closed"),
    (f"z\n// {SENTINEL}end example.nope#x\n", "has no start"),
    (f"// {SENTINEL}example.success#nope.x\nz\n", "never closed"),
])
def test_pairing_comes_before_lookup_so_a_broken_marker_for_an_unknown_target_is_still_invalid(tmp_path, body, reason):
    ws = bc_with(tmp_path, MARKED, extra={"src/x.js": body})
    assert reason in uc(ws, "validate", expect_exit=2)
# @use-case:end links.markers#acceptance.broken-pairs-invalid


# @use-case:links.markers#acceptance.malformed-id
@pytest.mark.parametrize("tail", ["T", "_d", "-T"])
def test_an_id_run_followed_by_a_letter_or_underscore_is_malformed_never_a_shorter_id(tmp_path, tail):
    name = f"example.success#unit-tests.sub{tail}"
    body = f"// {SENTINEL}{name}\nx\n// {SENTINEL}end {name}\n"
    ws = bc_with(tmp_path, MARKED, extra={"src/bad.js": body})
    document = uc(ws, "links")
    assert [d for d in document["diagnostics"] if d.startswith("src/bad.js") and "malformed marker id" in d] != []
    assert [l for l in document["links"] if l["file"] == "src/bad.js"] == []
    uc(ws, "validate")  # a malformed marker only warns, and never pairs, so the missing end cannot make it INVALID
# @use-case:end links.markers#acceptance.malformed-id


# @use-case:links.markers#acceptance.pair-links-region
def test_an_id_followed_by_syntax_that_is_not_a_letter_still_links(tmp_path):
    ws = bc_with(tmp_path, MARKED, extra={"page.html": f"<!--{SENTINEL}example.success#unit-tests.html-->\n<p>x</p>\n"
                                                       f"<!--{SENTINEL}end example.success#unit-tests.html-->\n"})
    document = uc(ws, "links")
    assert [l["binding"] for l in document["links"] if l["file"] == "page.html"] == ["html"]
    assert not [d for d in document["diagnostics"] if d.startswith("page.html")]
# @use-case:end links.markers#acceptance.pair-links-region


# @use-case:links.list-links#acceptance.ordered
def test_the_links_document_orders_the_start_line_as_a_number(tmp_path):
    region = f"// {SENTINEL}example.success#again\nx\n// {SENTINEL}end example.success#again\n"
    text = region + "\n" * 2 + region + "\n" * 4 + region
    ws = workspace(tmp_path, {"use-cases/success.yml": linked(), "src/x.js": text})
    assert [l["range"]["start"] for l in uc(ws, "links")["links"] if l["file"] == "src/x.js"] == [2, 7, 14]
    ws = workspace(tmp_path / "ten", {"use-cases/success.yml": linked(), "src/x.js": region + "\n" * 8 + region})
    assert [l["range"]["start"] for l in uc(ws, "links")["links"] if l["file"] == "src/x.js"] == [2, 13]
# @use-case:end links.list-links#acceptance.ordered


# @use-case:links.manual-bindings#acceptance.excluded-target
def test_an_empty_manual_range_is_valid_and_warns(tmp_path):
    where = "{ file: src/a.txt, start: { line: 1, column: 3 }, end: { line: 1, column: 2 } }"
    ws = workspace(tmp_path, {"use-cases/success.yml": linked([("a", where)]), "src/a.txt": "abcd\n"})
    assert len(warnings_about(ws, "empty range")) == 1
# @use-case:end links.manual-bindings#acceptance.excluded-target


# ------------------------------------------------------------------ a route's own definition (chapter 11 §26-29)

TWO_ROUTES = """prefix: shop
use_cases:
  - id: rule
    title: Rule
    value_tier: core
    intent: The rule holds.
    scenarios:
      - id: one
        when: [One happens.]
        then: [One holds.]
      - id: two
        when: [Two happens.]
        then: [Two holds.]
    validation:
      - id: first
        type: { kind: acceptance }
        covers: [one]
        procedure:
          steps: [Check one.]
      - id: second
        type: { kind: acceptance }
        covers: [one, two]
        procedure:
          steps: [Check two.]
"""


def routes_of(ws):
    return {r["route"]: r["status"] for r in call_core(ws, "status", "example.shop.rule")["use_cases"][0]["routes"]}


# @use-case:status.staleness#acceptance.route-changed
@pytest.mark.parametrize("old, new", [
    ("        covers: [one]\n", "        covers: [one, two]\n"),
    ("          steps: [Check one.]\n", "          steps: [Check one, then again.]\n"),
    ("        type: { kind: acceptance }\n        covers: [one]\n", "        type: { kind: integration }\n        covers: [one]\n"),
    ("        covers: [one]\n", "        covers: [one]\n        gates_verification: false\n"),
], ids=["covers", "procedure", "type", "gating"])
def test_changing_one_route_stales_that_route_and_not_the_others(tmp_path, old, new):
    ws = workspace(tmp_path, {"use-cases/rule.yml": TWO_ROUTES})
    for route in ("first", "second"):
        call_core(ws, "record", "example.shop.rule", route, "pass")
    assert routes_of(ws) == {"first": "verified", "second": "verified"}
    assert TWO_ROUTES.count(old) == 1
    (tmp_path / "ws" / "use-cases" / "rule.yml").write_text(TWO_ROUTES.replace(old, new))
    assert routes_of(ws) == {"first": "stale", "second": "verified"}
# @use-case:end status.staleness#acceptance.route-changed
