"""The guides (chapter 16, docs): shipped with the tool, listed, shown by name, searched by section exactly as search
ranks use cases, and held true: every command and flag a guide names must exist.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_docs.py -v
"""

import json
import subprocess

import pytest
from conftest import COMMAND


GUIDES = ["getting-started", "writing-use-cases", "finding", "linking", "verifying", "reading-status", "ci-and-hooks", "quirks"]


def run(folder, *args, expect_exit=0):
    """docs needs no workspace: run it from a folder that is not one."""
    process = subprocess.run([*COMMAND, "--json", "docs", *args], cwd=folder, capture_output=True, text=True,
                             encoding="utf-8", stdin=subprocess.DEVNULL)
    assert process.returncode == expect_exit, process.stderr
    return json.loads(process.stdout)


# @use-case:docs.guides#acceptance.list
def test_the_list_is_every_guide_in_order_and_needs_no_workspace(tmp_path):
    listed = run(tmp_path)
    assert listed["view"] == "list" and [g["guide"] for g in listed["guides"]] == GUIDES
    assert all(g["title"] and g["covers"] for g in listed["guides"])
# @use-case:end docs.guides#acceptance.list


# @use-case:docs.guides#acceptance.search
def test_words_find_sections_ranked_as_search_ranks(tmp_path):
    found = run(tmp_path, "stale")
    assert found["view"] == "search" and found["matches"][0]["guide"] == "reading-status"
    assert run(tmp_path, "stlae")["matches"][0]["guide"] == "reading-status"  # typos forgiven
    assert run(tmp_path, "stlae", "--exact")["matches"] == []
    assert [m["guide"] for m in run(tmp_path, '"need quotes"')["matches"]] == ["quirks"]
    sections = lambda *words: [(m["guide"], m["section"]) for m in run(tmp_path, "--page-size", "100", *words)["matches"]]
    every = sections("verify")
    without = sections("--", "verify -verify")  # a minus word leaves out the sections that mention it, and only those
    assert set(without) < set(every)
    assert sections("--", "verify -spaceship") == every
    assert run(tmp_path, "spaceship")["matches"] == []  # nothing found is not an error
# @use-case:end docs.guides#acceptance.search


# @use-case:docs.guides#acceptance.search
def test_pages_and_the_next_token(tmp_path):
    everything = run(tmp_path, "the", "--page-size", "100")["matches"]
    pages, page = [], run(tmp_path, "the", "--page-size", "1")
    while True:
        assert page["matches"] and page["total"] == len(everything)
        pages += page["matches"]
        if page["next"] is None:
            break
        page = run(tmp_path, "--next", page["next"])
    assert pages == everything and len(pages) > 1
    first = run(tmp_path, "the", "--page-size", "1")
    assert "--next continues" in subprocess.run([*COMMAND, "docs", "--next", first["next"], "--exact"], cwd=tmp_path,
                                                 capture_output=True, text=True).stderr
    assert run(tmp_path, "--next", "garbage", expect_exit=2)["error"]["kind"] == "usage"
# @use-case:end docs.guides#acceptance.search
