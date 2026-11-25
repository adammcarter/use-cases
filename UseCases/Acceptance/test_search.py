"""Search (chapter 16): words or a whole use case, filters, fields, ranking and pages. Deterministic and offline:
the same search on the same files always gives the same pages, and a page from files that changed is refused.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_search.py -v
"""

import json
import subprocess
import sys

import pytest
from conftest import call_core, COMMAND


def use_case(local, title, when, tier="core", out_of_scope=None, ready=True):
    text = f"  - id: {local}\n    title: {title}\n    value_tier: {tier}\n"
    if ready:
        text += (f"    intent: {title}.\n    scenarios:\n      - id: main\n        when: [{when}]\n        then: [It works.]\n"
                 f"    validation:\n      - id: manual\n        type: {{ kind: acceptance }}\n        covers: [main]\n"
                 f"        procedure:\n          steps: [Check it.]\n")
    if out_of_scope:
        text += f"    out_of_scope: [{out_of_scope}]\n"
    return text


@pytest.fixture
def ws(tmp_path):
    (tmp_path / "use-cases" / "feed").mkdir(parents=True)
    (tmp_path / "use-cases.yml").write_text("schema_version: 1\nroot: true\nprefix: app\n")
    (tmp_path / "use-cases" / "feed" / "post.yml").write_text("prefix: feed.post\nuse_cases:\n"
        + use_case("like", "Double tap to like a post", "The user taps a post twice", tier="critical")
        + use_case("unlike", "Undo a like", "The user double-taps a liked post again"))
    (tmp_path / "use-cases" / "feed" / "media.yml").write_text("prefix: feed.media\nuse_cases:\n"
        + use_case("zoom", "Zoom a photo", "The user pinches a photo", out_of_scope="Double tap to zoom"))
    (tmp_path / "use-cases" / "settings.yml").write_text("prefix: settings\nuse_cases:\n"
        + use_case("theme", "Switch to a dark theme", "", tier="supporting", ready=False))
    (tmp_path / "use-case-groups.yml").write_text("schema_version: 1\ngroups:\n  social:\n    include: { prefixes: [app.feed.post] }\n")
    return tmp_path


def search(ws, *args, expect_exit=0):
    return call_core(str(ws), "search", *args, expect_exit=expect_exit)


def found(ws, *args):
    return [m["use_case"] for m in search(ws, *args)["matches"]]


# ------------------------------------------------------------------ the query


def test_words_rank_a_title_above_a_scenario_and_say_why(ws):
    result = search(ws, "double tap")
    assert [m["use_case"] for m in result["matches"]] == ["app.feed.post.like", "app.feed.media.zoom", "app.feed.post.unlike"]
    top = result["matches"][0]
    assert top["why"][0] == {"field": "title", "text": "Double tap to like a post"} and top["status"] == "unverified"
    assert top["value_tier"] == "critical" and top["file"] == "use-cases/feed/post.yml" and 0 < top["score"] <= 1
    scores = [m["score"] for m in result["matches"]]
    assert scores == sorted(scores, reverse=True) and result["total"] == len(result["matches"])


def test_typos_are_forgiven_unless_exact(ws):
    assert "app.feed.media.zoom" in found(ws, "phtoo")
    assert found(ws, "phtoo", "--exact") == []
    assert "app.feed.post.like" in found(ws, "lik")  # the start of a word


def test_a_phrase_must_appear_as_written(ws):
    assert found(ws, '"double tap"') == ["app.feed.post.like", "app.feed.media.zoom"]
    assert "app.feed.post.unlike" in found(ws, '"double taps"')  # double-taps: punctuation is not a word
    assert found(ws, '"tap double"') == []
    assert found(ws, 'double "pinches a photo"') == ["app.feed.media.zoom"]  # beside other words, a phrase is still required


def test_a_minus_word_leaves_use_cases_out(ws):
    assert "app.feed.media.zoom" in found(ws, "double")
    assert "app.feed.media.zoom" not in found(ws, "--", "double -zoom")
    assert "app.feed.media.zoom" not in found(ws, "--", 'double -"to zoom"')


@pytest.mark.parametrize("query, message", [("-zoom", "at least one word"), ('"unclosed', "unclosed")])
def test_a_query_with_nothing_to_look_for_is_refused(ws, query, message):
    assert message in search(ws, "--", query, expect_exit=2)


def test_search_needs_words_or_like_never_both(ws, tmp_path):
    assert "needs words" in search(ws, expect_exit=2)
    draft = tmp_path / "draft.yml"
    draft.write_text("title: Tap twice\n")
    assert "not both" in search(ws, "tap", "--like", str(draft), expect_exit=2)


def test_the_same_search_gives_the_same_answer(ws):
    assert search(ws, "the user") == search(ws, "the user")
    tied = [m for m in search(ws, "photo post")["matches"]]
    for a, b in zip(tied, tied[1:]):
        assert (-a["score"], a["use_case"]) <= (-b["score"], b["use_case"])  # best first, ties by id


def test_nothing_found_is_not_an_error(ws):
    assert search(ws, "spaceship") == {"output_version": 1, "command": "search", "total": 0, "offset": 0, "page_size": 20,
                                       "matches": [], "next": None}


# ------------------------------------------------------------------ --like


def test_like_finds_use_cases_like_a_draft_and_never_itself(ws, tmp_path):
    draft = tmp_path / "draft.yml"
    draft.write_text("id: app.feed.post.like\ntitle: Tap a photo twice to like it\nscenarios:\n"
                     "  - id: s\n    when: [The user taps a photo twice]\n")  # a draft: nothing else is needed
    result = found(ws, "--like", str(draft))
    assert "app.feed.post.like" not in result and result[0] in ("app.feed.media.zoom", "app.feed.post.unlike")
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "--json", "search", "--like", "-"],
                             input=json.dumps({"title": "Zoom into a photo"}), capture_output=True, text=True, encoding="utf-8")
    assert json.loads(process.stdout)["matches"][0]["use_case"] == "app.feed.media.zoom"


def test_like_needs_some_words(ws, tmp_path):
    draft = tmp_path / "draft.yml"
    draft.write_text("id: app.x.y\n")
    assert "needs a use case with some text" in search(ws, "--like", str(draft), expect_exit=2)


# ------------------------------------------------------------------ --in: which fields


def test_in_limits_the_fields_searched(ws):
    assert found(ws, "zoom", "--in", "out_of_scope") == ["app.feed.media.zoom"]
    assert found(ws, "twice", "--in", "title") == []
    assert found(ws, "twice", "--in", "scenarios") == ["app.feed.post.like"]
    assert found(ws, "manual", "--in", "validation")  # route ids and procedure steps
    assert "--in takes" in search(ws, "x", "--in", "tags", expect_exit=2)


def test_an_out_of_scope_match_is_always_labelled(ws):
    zoom = next(m for m in search(ws, "double tap")["matches"] if m["use_case"] == "app.feed.media.zoom")
    assert {"field": "out_of_scope", "text": "Double tap to zoom"} in zoom["why"]
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "search", "zoom"], capture_output=True,
                             text=True, encoding="utf-8")
    assert "also out of scope" in process.stdout


# ------------------------------------------------------------------ filters: AND across flags, OR inside one


def test_filters_keep_only_what_they_name(ws):
    assert found(ws, "the", "--under", "app.feed.post") == ["app.feed.post.like", "app.feed.post.unlike"]
    assert found(ws, "the", "--group", "social") == ["app.feed.post.like", "app.feed.post.unlike"]
    assert found(ws, "the", "--tier", "critical") == ["app.feed.post.like"]
    assert found(ws, "a", "--tier", "critical,supporting") == ["app.feed.post.like", "app.settings.theme"]
    assert found(ws, "theme", "--state", "draft") == ["app.settings.theme"]
    assert found(ws, "theme", "--state", "verified") == []
    assert found(ws, "the", "--under", "app.feed", "--tier", "core") == ["app.feed.media.zoom", "app.feed.post.unlike"]


@pytest.mark.parametrize("args, message", [
    (["--under", "app.nope"], "no use case or id prefix"),
    (["--group", "nope"], "no group"),
    (["--tier", "urgent"], "--tier takes"),
    (["--state", "green"], "--state takes"),
])
def test_an_unknown_filter_value_is_refused(ws, args, message):
    assert message in search(ws, "tap", *args, expect_exit=2)


def test_full_carries_exactly_what_show_returns(ws):
    match = search(ws, "zoom", "--full")["matches"][0]
    assert match["definition"] == call_core(str(ws), "show", match["use_case"])["definition"]
    assert "definition" not in search(ws, "zoom")["matches"][0]


# ------------------------------------------------------------------ pages


def test_pages_cover_every_match_once_in_order(ws):
    everything = search(ws, "the", "--page-size", "100")["matches"]
    pages, page = [], search(ws, "the", "--page-size", "1")
    while True:
        assert page["total"] == len(everything) and page["offset"] == len(pages) and page["matches"]  # never an empty page
        pages += page["matches"]
        if page["next"] is None:
            break
        page = search(ws, "--next", page["next"])
    assert pages == everything and len(pages) > 2


def test_next_carries_the_whole_search(ws):
    first = search(ws, "the", "--tier", "core", "--in", "scenarios", "--page-size", "1")
    second = search(ws, "--next", first["next"])
    assert second["matches"] and all(m["value_tier"] == "core" for m in second["matches"])
    assert "--next continues a search" in search(ws, "--next", first["next"], "--tier", "critical", expect_exit=2)
    assert "--next continues a search" in search(ws, "the", "--next", first["next"], expect_exit=2)


def test_a_page_from_use_cases_that_changed_is_refused(ws):
    first = search(ws, "the", "--page-size", "1")
    path = ws / "use-cases" / "feed" / "media.yml"
    path.write_text(path.read_text().replace("Zoom a photo", "Zoom into a photo"))
    assert "changed since this search" in search(ws, "--next", first["next"], expect_exit=2)


def test_a_new_verdict_between_pages_is_a_change_too(ws):
    first = search(ws, "the", "--page-size", "1")
    call_core(str(ws), "record", "app.feed.post.like", "manual", "pass")
    assert "changed since this search" in search(ws, "--next", first["next"], expect_exit=2)


@pytest.mark.parametrize("value", ["garbage", "eyJ2IjoyfQ"])
def test_a_token_this_command_did_not_make_is_refused(ws, value):
    assert "--next takes a token" in search(ws, "--next", value, expect_exit=2)


@pytest.mark.parametrize("size", ["0", "101"])
def test_page_size_is_one_to_a_hundred(ws, size):
    assert "--page-size is 1 to 100" in search(ws, "the", "--page-size", size, expect_exit=2)


def test_people_see_best_first_with_why_and_where_they_are(ws):
    process = subprocess.run([*COMMAND, "--workspace", str(ws), "search", "the", "--page-size", "2"],
                             capture_output=True, text=True, encoding="utf-8")
    lines = process.stdout.splitlines()
    assert process.returncode == 0 and "1–2 of" in lines[-2] and lines[-1].startswith("→ use-cases search --next ")
    assert all(": \"" in line for line in lines[:2])
