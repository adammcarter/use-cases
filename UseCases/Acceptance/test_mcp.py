"""MCP tools (chapter 20): a real server over stdio, as an agent's host drives it. Every tool is the command
itself: the same document, the same rules, and nothing an agent can do that the command line cannot.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_mcp.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
from jsonschema import Draft202012Validator
from conftest import call_core, COMMAND
from test_languages import FIXTURES, env

TOOLS = ["use_cases_validate_files", "use_cases_status", "use_cases_verify_tests", "use_cases_record_verdict", "use_cases_links",
         "use_cases_search", "use_cases_show", "use_cases_save", "use_cases_remove", "use_cases_apply", "use_cases_approve", "use_cases_render", "use_cases_docs"]


class Host:
    """The agent's side: start `use-cases mcp`, speak JSON-RPC one line at a time."""

    def __init__(self, cwd, environment=None):
        self.process = subprocess.Popen([*COMMAND, "mcp"], cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        text=True, encoding="utf-8", env=environment)
        self.next_id = 0
        started = self.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                              "clientInfo": {"name": "acceptance", "version": "1"}})
        assert started["result"]["capabilities"] == {"tools": {}}
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        self.tools = {t["name"]: t for t in self.request("tools/list")["result"]["tools"]}

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def request(self, method, params=None):
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": self.next_id, "method": method, **({"params": params} if params else {})})
        reply = json.loads(self.process.stdout.readline())
        assert reply["id"] == self.next_id
        return reply

    def call(self, name, **arguments):
        result = self.request("tools/call", {"name": name, "arguments": arguments})["result"]
        if not result["isError"]:  # structured content always follows the tool's own, self-contained output schema
            errors = list(Draft202012Validator(self.tools[name]["outputSchema"]).iter_errors(result["structuredContent"]))
            assert not errors, errors[0].message
            assert json.loads(result["content"][0]["text"]) == result["structuredContent"]
        return result

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=15) == 0


@pytest.fixture
def workspace(tmp_path):
    target = tmp_path / "js"
    shutil.copytree(os.path.join(FIXTURES, "javascript", "3-bridge"), target)
    return target


@pytest.fixture
def host(workspace):
    connection = Host(workspace, env())
    yield connection
    connection.close()


def test_the_tools_are_the_commands_and_nothing_else(host):
    assert sorted(host.tools) == sorted(TOOLS)  # never init, hooks or record --interactive
    for tool in host.tools.values():
        Draft202012Validator.check_schema(tool["inputSchema"])
        Draft202012Validator.check_schema(tool["outputSchema"])
        assert '"$ref": "../' not in json.dumps(tool["outputSchema"]) and ".schema.json" not in json.dumps(tool["outputSchema"])
    assert host.tools["use_cases_record_verdict"]["inputSchema"]["required"] == ["use_case", "route", "status"]


# @use-case:mcp.tools#acceptance.same-documents
def test_a_tool_returns_exactly_the_commands_document(host, workspace):
    for name, arguments, command in (("use_cases_status", {}, ["status"]), ("use_cases_validate_files", {}, ["validate"]),
                                     ("use_cases_links", {"target": "duration.text"}, ["links", "duration.text"])):
        assert host.call(name, **arguments)["structuredContent"] == call_core(str(workspace), *command)
# @use-case:end mcp.tools#acceptance.same-documents


# @use-case:mcp.tools#acceptance.verify
def test_verify_record_and_the_gate_through_tools(host, workspace):
    if not shutil.which("node", path=env()["PATH"]):
        pytest.skip("needs node")
    ran = host.call("use_cases_verify_tests", step="run")["structuredContent"]
    assert ran["step"] == "run" and ran["errors"] == [] and len(ran["results"]) == 2
    gate = host.call("use_cases_status", gate=True, strict=True)
    assert not gate["isError"] and gate["structuredContent"]["gate"]["passed"] is False  # blocked is a document, not an error
    assert host.call("use_cases_status", gate=True)["structuredContent"]["gate"]["passed"] is True
# @use-case:end mcp.tools#acceptance.verify


# @use-case:mcp.tools#acceptance.verify
def test_a_verdict_recorded_by_a_tool_is_a_verdict_like_any_other(tmp_path):
    folder = tmp_path / "w"
    folder.mkdir()
    call_core(str(folder), "init", "--no-input")
    example = folder / "use-cases" / "example.yml"
    example.write_text(example.read_text().replace("    # value_tier: core", "    value_tier: core"))
    connection = Host(folder)
    recorded = connection.call("use_cases_record_verdict", use_case="example.getting-started", route="manual-check", status="pass",
                               message="checked by an agent")
    assert recorded["structuredContent"]["results"][0]["via"] == ["record"]
    assert call_core(str(folder), "status", "example.getting-started")["use_cases"][0]["status"] == "verified"
    connection.close()
# @use-case:end mcp.tools#acceptance.verify


# @use-case:mcp.tools#acceptance.refusals
def test_a_refusal_is_a_tool_error_with_the_error_document(host):
    refused = host.call("use_cases_verify_tests", step="finish")
    document = json.loads(refused["content"][0]["text"])
    assert refused["isError"] and "structuredContent" not in refused
    assert document["error"]["kind"] == "refused" and "no started run" in document["error"]["message"]
# @use-case:end mcp.tools#acceptance.refusals


# @use-case:mcp.tools#acceptance.refusals
@pytest.mark.parametrize("arguments, message", [({}, "needs step"), ({"step": "run", "shell": "rm -rf /"}, "takes no shell")])
def test_bad_arguments_are_refused_before_anything_runs(host, workspace, arguments, message):
    result = host.call("use_cases_verify_tests", **arguments)
    assert result["isError"] and message in result["content"][0]["text"]
    assert not (workspace / ".use-cases").exists()
# @use-case:end mcp.tools#acceptance.refusals


# @use-case:mcp.tools#acceptance.unknown-tool
def test_an_unknown_tool_is_a_protocol_error(host):
    reply = host.request("tools/call", {"name": "use_cases_init", "arguments": {}})
    assert reply["error"]["code"] == -32602
# @use-case:end mcp.tools#acceptance.unknown-tool


# @use-case:mcp.tools#acceptance.changes
def test_show_save_and_remove_through_tools(host, workspace):
    shown = host.call("use_cases_show", use_case="duration.text.parse")["structuredContent"]
    assert shown == call_core(str(workspace), "show", "duration.text.parse")
    definition = {**shown["definition"], "title": "Parse a written duration"}
    before = (workspace / shown["file"]).read_text()
    preview = host.call("use_cases_save", use_case=definition, dry_run=True)["structuredContent"]
    assert preview["dry_run"] is True and (workspace / shown["file"]).read_text() == before
    saved = host.call("use_cases_save", use_case=definition)["structuredContent"]
    assert saved["action"] == "replaced" and {**preview, "dry_run": False} == saved
    assert call_core(str(workspace), "show", "duration.text.parse")["definition"]["title"] == "Parse a written duration"
    removed = host.call("use_cases_remove", use_case="duration.text.parse", dry_run=True)["structuredContent"]
    assert removed["dry_run"] is True and "duration.text.parse" in [u["use_case"] for u in call_core(str(workspace), "status")["use_cases"]]
# @use-case:end mcp.tools#acceptance.changes


# @use-case:mcp.tools#acceptance.changes
def test_a_refused_save_through_a_tool_writes_nothing(host, workspace):
    before = {p: p.read_bytes() for p in workspace.rglob("*.yml")}
    refused = host.call("use_cases_save", use_case={"id": "orphan", "title": "No group"})
    assert refused["isError"] and "has no group" in refused["content"][0]["text"]
    assert {p: p.read_bytes() for p in workspace.rglob("*.yml")} == before
# @use-case:end mcp.tools#acceptance.changes


# @use-case:mcp.tools#acceptance.same-documents
def test_search_through_a_tool_is_the_command(host, workspace):
    through_tool = host.call("use_cases_search", query="parse", tier=["core", "critical"], page_size=1)["structuredContent"]
    assert through_tool == call_core(str(workspace), "search", "parse", "--tier", "core,critical", "--page-size", "1")
    assert host.call("use_cases_search", query="-format parse")["structuredContent"]["total"] >= 1  # a query may start with -
    alone = host.call("use_cases_search", query="-format")  # read as the query, never as a flag
    assert alone["isError"] and "at least one word" in alone["content"][0]["text"]
    if through_tool["next"]:
        following = host.call("use_cases_search", next=through_tool["next"])["structuredContent"]
        assert following["offset"] == 1
    like = host.call("use_cases_search", like={"title": "Parse a duration"})["structuredContent"]
    assert like["matches"][0]["use_case"] == "duration.text.parse"
    refused = host.call("use_cases_search", query="parse", next="x")
    assert refused["isError"] and "--next continues a search" in refused["content"][0]["text"]
# @use-case:end mcp.tools#acceptance.same-documents


# @use-case:mcp.tools#acceptance.same-documents
def test_docs_through_a_tool_is_the_command(host, workspace):
    for arguments, command in (({}, []), ({"query": "quirks"}, ["quirks"]), ({"query": "stale", "page_size": 1}, ["stale", "--page-size", "1"])):
        assert host.call("use_cases_docs", **arguments)["structuredContent"] == call_core(str(workspace), "docs", *command)
# @use-case:end mcp.tools#acceptance.same-documents


# @use-case:mcp.tools#acceptance.changes
def test_a_batch_through_a_tool_is_the_command(host, workspace):
    batch = {"remove": ["duration.text.format"], "save": [{"id": "duration.text.round", "title": "Round a duration"}]}
    preview = host.call("use_cases_apply", dry_run=True, **batch)["structuredContent"]
    assert preview["dry_run"] is True and [u["action"] for u in preview["use_cases"]] == ["removed", "added"]
    assert "duration.text.format" in [u["use_case"] for u in call_core(str(workspace), "status")["use_cases"]]
    assert {**preview, "dry_run": False} == host.call("use_cases_apply", **batch)["structuredContent"]
# @use-case:end mcp.tools#acceptance.changes


def test_a_sign_off_through_a_tool_is_the_command(host, workspace):
    preview = host.call("use_cases_approve", use_cases=["duration.text.parse"], by="Sam", dry_run=True)["structuredContent"]
    assert preview["use_cases"][0]["action"] == "approved" and preview["dry_run"] is True
    assert {**preview, "dry_run": False} == host.call("use_cases_approve", use_cases=["duration.text.parse"], by="Sam")["structuredContent"]
    assert call_core(str(workspace), "show", "duration.text.parse")["approval"] == "approved"
    refused = host.call("use_cases_approve", use_cases=["duration.text.parse"])
    assert refused["isError"] and "needs by" in refused["content"][0]["text"]


def test_a_layout_through_a_tool_is_the_command(host, workspace):
    proposal = {"title": "Rounding", "save": [{"id": "duration.text.round", "title": "Round a duration", "value_tier": "core"}],
                "untouched": ["duration.text.parse"]}
    shown = host.call("use_cases_render", kind="proposal", input=proposal)["structuredContent"]
    assert [c["fit"] for c in shown["model"]["changes"]] == ["new", "untouched"]
    assert shown["text"].splitlines()[0] == "PROPOSAL · Rounding"
    applied = host.call("use_cases_apply", **{k: proposal[k] for k in ("save",)})["structuredContent"]
    assert applied["use_cases"][0]["action"] == "added"

