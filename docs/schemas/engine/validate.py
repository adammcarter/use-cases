#!/usr/bin/env python3
"""Offline structural checks for the published schemas, examples and fingerprint vectors.

Dependencies: jsonschema[format], PyYAML, and openssl on PATH. No runtime evidence is produced.

    uv run --with 'jsonschema[format]' --with pyyaml python docs/schemas/engine/validate.py
"""
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

import yaml
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

DOCS = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import fingerprint_vectors as fv  # noqa: E402

SCHEMAS = sorted(DOCS.glob("schemas/*/*.schema.json"))
registry = Registry()
for path in SCHEMAS:
    schema = json.loads(path.read_text())
    Draft202012Validator.check_schema(schema)
    registry = registry.with_resource(path.as_uri(), Resource.from_contents(schema))


def validator(relative):
    return Draft202012Validator({"$ref": (DOCS / relative).as_uri()}, registry=registry,
                                format_checker=FormatChecker())


count = 0


def check(name, schema, data, expected=True):
    global count
    errors = list(validator(schema).iter_errors(data))
    assert bool(errors) != expected, f"{name}: expected valid={expected}; " + "; ".join(e.message for e in errors[:3])
    count += 1


P1, P2 = "schemas/authored/", "schemas/engine/"
run_id = "0" * 30 + "2a"
timestamp = "2026-09-25T12:34:56.123Z"
fingerprint = "uc-route-v1-sha256:" + "a" * 64
key = "shop.login.authenticate#unit-tests.valid-credentials@Tests/AuthTests/LoginTests.swift:6"
impl_key = "shop.login.authenticate#check-credentials@Sources/Auth/LoginService.swift:15"

# ---------------------------------------------------------------- authored: use cases
route = {"id": "unit-tests", "type": {"kind": "unit"}, "covers": ["valid-credentials"]}
use_case = {"id": "authenticate", "title": "Authenticate user", "value_tier": "core", "intent": "Sign in.",
            "scenarios": [{"id": "valid-credentials", "when": ["Submit."], "then": ["Signed in."]}],
            "validation": [route]}
doc = {"prefix": "login", "use_cases": [use_case]}
check("use case, no links", P1+"use-cases.schema.json", doc)
manual = {"id": "legacy", "kind": "manual", "locator": {"file": "src/login.py", "start": {"line": 40}, "end": {"line": 78, "column": 2}}}
whole = {"id": "config", "kind": "manual", "locator": {"file": "config/auth.yml"}}
linked = copy.deepcopy(doc)
linked["use_cases"][0]["bindings"] = [manual, whole]
linked["use_cases"][0]["validation"][0].update(
    bindings=[{"id": "t", "kind": "manual", "locator": {"file": "tests/test_login.py"}}],
    resources=[{"kind": "file", "path": "fixtures/users.json"}, {"kind": "glob", "pattern": "schemas/**/*.json"}])
check("use case with manual bindings and resources", P1+"use-cases.schema.json", linked)
procedural = copy.deepcopy(doc)
procedural["use_cases"][0]["validation"][0].update(type={"kind": "acceptance"}, gates_verification=False,
                                                   procedure={"setup": ["Launch."], "steps": ["Sign in."], "reset": []})
check("procedure route", P1+"use-cases.schema.json", procedural)
approved = copy.deepcopy(doc)
approved["use_cases"][0]["approved"] = {"by": "Sam", "on": "2026-10-11", "behaviour": "3f9a" + "0" * 60}
check("an approved use case", P1+"use-cases.schema.json", approved)
for name, mutate in [
    ("runner on a route", lambda d: d["use_cases"][0]["validation"][0].update(runner={"kind": "executable", "executable": "swift"})),
    ("marker binding in YAML", lambda d: d["use_cases"][0].update(bindings=[{"id": "x", "kind": "marker"}])),
    ("procedure with no steps", lambda d: d["use_cases"][0]["validation"][0].update(procedure={"steps": []})),
    ("start without end", lambda d: d["use_cases"][0].update(bindings=[{"id": "x", "kind": "manual", "locator": {"file": "a", "start": {"line": 1}}}])),
    ("unknown resource kind", lambda d: d["use_cases"][0]["validation"][0].update(resources=[{"kind": "url", "path": "x"}])),
    ("absolute binding path", lambda d: d["use_cases"][0].update(bindings=[{"id": "x", "kind": "manual", "locator": {"file": "/etc/passwd"}}])),
    ("binding path spelled ./", lambda d: d["use_cases"][0].update(bindings=[{"id": "x", "kind": "manual", "locator": {"file": "./src/a.js"}}])),
    ("binding path with a trailing /", lambda d: d["use_cases"][0].update(bindings=[{"id": "x", "kind": "manual", "locator": {"file": "src/"}}])),
    ("binding path hiding .. behind a line separator", lambda d: d["use_cases"][0].update(bindings=[{"id": "x", "kind": "manual", "locator": {"file": "a\u2028/../../etc/passwd"}}])),
    ("bad use case id", lambda d: d["use_cases"][0].update(id="Bad_Id")),
    ("an id ending in a line break", lambda d: d["use_cases"][0].update(id=d["use_cases"][0]["id"] + "\n")),
    ("an approval without its fingerprint", lambda d: d["use_cases"][0].update(approved={"by": "Sam", "on": "2026-10-11"})),
    ("an approval with a short fingerprint", lambda d: d["use_cases"][0].update(approved={"by": "Sam", "on": "2026-10-11", "behaviour": "3f9a"})),
    ("an approval on no date", lambda d: d["use_cases"][0].update(approved={"by": "Sam", "on": "yesterday", "behaviour": "a" * 64})),
    ("an approval with a comment", lambda d: d["use_cases"][0].update(approved={"by": "Sam", "on": "2026-10-11", "behaviour": "a" * 64, "note": "ok"})),
]:
    bad = copy.deepcopy(doc)
    mutate(bad)
    check("invalid: " + name, P1+"use-cases.schema.json", bad, False)

# ---------------------------------------------------------------- authored: workspace
workspace = {"schema_version": 1, "prefix": "shop", "use_cases_dir": "use-cases",
             "freshness": {"binding_identity": "content", "normalization": {"ignore": ["line-endings"]}},
             "discovery": {"exclude": ["Generated/**"]}}
check("workspace", P1+"workspace.schema.json", workspace)
check("workspace with the sign-off gate", P1+"workspace.schema.json", {**workspace, "sign_off": "required"})
check("invalid workspace: sign_off optional", P1+"workspace.schema.json", {**workspace, "sign_off": "optional"}, False)
for name, extra in [("recipes", {"recipes": {}}), ("defaults", {"defaults": {}}), ("missing version", None)]:
    bad = {k: v for k, v in workspace.items() if extra is not None or k != "schema_version"}
    bad.update(extra or {})
    check("invalid workspace: " + name, P1+"workspace.schema.json", bad, False)

# ---------------------------------------------------------------- authored: bridge settings
validation = {"id": "auth-tests", "report": "auth-tests.jsonl", "transformer": "swift-testing",
              "run": ["swift", "test", "--experimental-event-stream-output", "{report}", "--experimental-event-stream-version", "0"]}
bridge = {"schema_version": 1, "links": [{"transformer": "tools/links.py", "settings": {}}], "validations": [validation]}
check("bridge settings", P1+"bridge.schema.json", bridge)
check("bridge settings, empty", P1+"bridge.schema.json", {"schema_version": 1})
for name, argument in [("a shell brace group", "a || { b; }"), ("a shell variable", "${HOME}"), ("empty braces", "{ }"),
                       ("braces with a space", "{a b}"), ("JSON text", '{"k": 1}'), ("a word in braces", "awk '{print}' f"),
                       ("a word in braces after a pattern", "sed -n '/x/{p}' f"), ("a mistyped placeholder", "{reprot}")]:
    # the schema only shapes the argument; a near miss of {report} is a core check (chapter 10 section 8)
    check("bridge run argument: " + name, P1+"bridge.schema.json",
          {"schema_version": 1, "validations": [{**validation, "run": ["sh", "-c", argument]}]})
check("bridge validation with working_dir", P1+"bridge.schema.json",
      {"schema_version": 1, "validations": [{**validation, "working_dir": "services/auth"}]})
check("bridge validation without run (read-only)", P1+"bridge.schema.json",
      {"schema_version": 1, "validations": [{k: v for k, v in validation.items() if k != "run"}]})
check("bridge validation without a report name (the tests get the folder)", P1+"bridge.schema.json",
      {"schema_version": 1, "validations": [{k: v for k, v in validation.items() if k != "report"}]})
for name, change in [
    ("report is a path", {"report": ".build/use-cases/auth-tests.jsonl"}),
    ("report inside .use-cases", {"report": ".use-cases/runs/x.jsonl"}),
    ("report escapes", {"report": "../x.jsonl"}),
    ("absolute report", {"report": "/tmp/x.jsonl"}),
    ("report is ..", {"report": ".."}),
    ("hidden report name", {"report": ".x"}),
    ("report name ends in a dot", {"report": "x."}),
    ("report name with a space", {"report": "auth tests.jsonl"}),
    ("report name Windows reserves", {"report": "Con.jsonl"}),
    ("report name too long", {"report": "x" * 65}),
    ("id Windows reserves", {"id": "nul"}),
    ("bad id", {"id": "Auth_Tests"}),
    ("zero timeout", {"timeout_seconds": 0}),
    ("working_dir escapes project", {"working_dir": "../elsewhere"}),
    ("working_dir inside .use-cases", {"working_dir": ".use-cases"}),
    ("absolute working_dir", {"working_dir": "/tmp"}),
]:
    check("invalid bridge: " + name, P1+"bridge.schema.json", {"schema_version": 1, "validations": [{**validation, **change}]}, False)
check("invalid bridge: missing transformer", P1+"bridge.schema.json",
      {"schema_version": 1, "validations": [{k: v for k, v in validation.items() if k != "transformer"}]}, False)

# ---------------------------------------------------------------- transformer contract
link = {"key": key, "source": "marker", "use_case": "shop.login.authenticate", "route": "unit-tests",
        "binding": "valid-credentials", "role": "validation", "file": "Tests/AuthTests/LoginTests.swift",
        "range": {"start": 6, "end": 9}}
resolved = {k: v for k, v in link.items() if k not in ("key", "source")}
check("links request", P2+"transformer-links-request.schema.json",
      {"contract": 1, "job": "links", "use_cases": [], "code_root": "/project", "ignore": ["use-cases.yml"], "settings": {}})
check("links response", P2+"transformer-links-response.schema.json", {"contract": 1, "links": [resolved], "diagnostics": []})
check("invalid links response: validation link without route", P2+"transformer-links-response.schema.json",
      {"contract": 1, "links": [{k: v for k, v in resolved.items() if k != "route"}], "diagnostics": []}, False)
check("invalid links response: implementation link with route", P2+"transformer-links-response.schema.json",
      {"contract": 1, "links": [{**resolved, "role": "implementation"}], "diagnostics": []}, False)
results_request = {"contract": 1, "job": "results", "use_cases": [], "links": [link], "code_root": "/project",
                   "output": {"report_path": f"/project/.use-cases/runs/{run_id}/reports/auth-tests/auth-tests.jsonl", "exit_code": None, "working_dir": "."},
                   "settings": {}}
check("results request (verify --finish)", P2+"transformer-results-request.schema.json", results_request)
check("results request (--run)", P2+"transformer-results-request.schema.json",
      {**results_request, "output": {**results_request["output"], "exit_code": 1}})
check("invalid results request: link without key", P2+"transformer-results-request.schema.json",
      {**results_request, "links": [resolved]}, False)
check("invalid results request: no working_dir", P2+"transformer-results-request.schema.json",
      {**results_request, "output": {"report_path": "/project/r.xml", "exit_code": 0}}, False)
check("invalid results request: core byte offsets leak", P2+"transformer-results-request.schema.json",
      {**results_request, "links": [{**link, "span": [0, 10]}]}, False)
results_response = {"contract": 1, "results": [{"link": key, "status": "pass", "tests": ["AuthTests.LoginTests/validCredentialsAuthenticate()"]}],
                    "unlinked": [{"test": "AuthTests.LoginTests/notTiedToAnyUseCase()", "file": "Tests/AuthTests/LoginTests.swift", "line": 35, "status": "pass"}],
                    "diagnostics": []}
check("results response", P2+"transformer-results-response.schema.json", results_response)
check("invalid results response: a report time (the core never trusts one)", P2+"transformer-results-response.schema.json",
      {**results_response, "report_started_at": 1790180980.2}, False)
for name, change in [("unknown status", {"results": [{"link": key, "status": "skipped"}]}),
                     ("malformed key", {"results": [{"link": "not a key", "status": "pass"}]}),
                     ("wrong contract", {"contract": 2})]:
    check("invalid results response: " + name, P2+"transformer-results-response.schema.json", {**results_response, **change}, False)

# ---------------------------------------------------------------- results store
source = {"id": "auth-tests", "report": "reports/auth-tests/auth-tests.jsonl", "transformer": "swift-testing",
          "command": validation["run"], "exit_code": 1, "seconds": 1.7, "diagnostics": ["2 tests had no source line"]}
manifest = {"run_version": 1, "run_id": run_id, "created_at": timestamp, "kind": "verify", "sources": [source],
            "errors": [], "diagnostics": [{"problem": "its test didn't run", "use_case": "shop.login.remember-me", "route": "unit-tests",
                                           "fingerprint": fingerprint, "links": [key]}],
            "unlinked_tests": results_response["unlinked"], "notes": []}
check("run manifest (--run: the core ran the command)", P2+"run.schema.json", manifest)
check("run manifest, record", P2+"run.schema.json", {**manifest, "kind": "record", "sources": []})
check("run manifest, verify (you ran the tests)", P2+"run.schema.json",
      {**manifest, "kind": "verify", "sources": [{"id": "auth-tests", "report": source["report"], "transformer": "swift-testing",
                                                   "working_dir": "services/auth"}]})
check("run manifest, report folder without a name", P2+"run.schema.json", {**manifest, "sources": [{**source, "report": "reports/auth-tests"}]})
check("invalid run manifest: an exit code with no command", P2+"run.schema.json",
      {**manifest, "sources": [{k: v for k, v in source.items() if k != "command"}]}, False)
for name, report in [("a project path", ".build/use-cases/auth-tests.jsonl"), ("outside reports/", "outputs/auth-tests/x"),
                     ("escapes", "reports/auth-tests/../../run.json")]:
    check("invalid run manifest: report " + name, P2+"run.schema.json", {**manifest, "sources": [{**source, "report": report}]}, False)
check("invalid run manifest: report start time", P2+"run.schema.json",
      {**manifest, "sources": [{**source, "report_started_at": 1790180980.2}]}, False)
for name, change in [("unknown kind", {"kind": "batch"}), ("kind named after the file check", {"kind": "validate"}), ("bad run id", {"run_id": "12"}),
                     ("bad timestamp", {"created_at": "yesterday"})]:
    check("invalid run manifest: " + name, P2+"run.schema.json", {**manifest, **change}, False)
check("invalid run manifest: route without use case", P2+"run.schema.json",
      {**manifest, "diagnostics": [{"problem": "x", "route": "unit-tests"}]}, False)
result = {"record_version": 1, "use_case": "shop.login.authenticate", "route": "unit-tests", "fingerprint": fingerprint,
          "status": "pass", "recorded_at": timestamp, "via": ["auth-tests"], "links": {key: "pass", impl_key.replace("#check", "#unit-tests.other"): None}}
check("route result", P2+"result.schema.json", result)
check("recorded route result", P2+"result.schema.json", {**{k: v for k, v in result.items() if k != "links"}, "via": ["record"], "message": "checked by hand"})
for name, change in [("unknown status", {"status": "skipped"}), ("empty via", {"via": []}), ("bad fingerprint", {"fingerprint": "sha256:x"})]:
    check("invalid route result: " + name, P2+"result.schema.json", {**result, **change}, False)
completion = {"completion_version": 1, "run_id": run_id, "finished_at": timestamp, "termination": "completed",
              "result_count": 1, "manifest_sha256": "a" * 64, "results_sha256": "b" * 64,
              "outputs_sha256": {"auth-tests/console.txt": "d" * 64}, "reports_sha256": {"auth-tests/auth-tests.jsonl": "c" * 64}}
check("completion marker", P2+"completion.schema.json", completion)
check("completion marker, record run", P2+"completion.schema.json", {**completion, "outputs_sha256": {}, "reports_sha256": {}})
check("invalid completion: no outputs digests", P2+"completion.schema.json",
      {k: v for k, v in completion.items() if k != "outputs_sha256"}, False)
check("invalid completion: no reports digests", P2+"completion.schema.json",
      {k: v for k, v in completion.items() if k != "reports_sha256"}, False)
check("invalid completion: report path escapes", P2+"completion.schema.json",
      {**completion, "reports_sha256": {"../x": "c" * 64}}, False)
check("invalid completion: output path escapes", P2+"completion.schema.json",
      {**completion, "outputs_sha256": {"../x": "c" * 64}}, False)
check("invalid completion: unknown termination", P2+"completion.schema.json", {**completion, "termination": "crashed"}, False)
check("completion marker with start stamp", P2+"completion.schema.json", {**completion, "start_sha256": "e" * 64})
check("run order", P2+"run-order.schema.json", {"order_version": 1, "last_run_id": run_id})
start = {"start_version": 1, "run_id": run_id, "started_at": timestamp, "opened_by": "start", "selected": ["auth-tests"], "validations_sha256": "9" * 64,
         "routes": [{"use_case": "shop.login.authenticate", "route": "unit-tests", "fingerprint": fingerprint}],
         "files": {"Tests/AuthTests/LoginTests.swift": "f" * 64}}
check("start stamp", P2+"start.schema.json", start)
check("start stamp, opened by --run", P2+"start.schema.json", {**start, "opened_by": "run"})
check("invalid start stamp: no opener", P2+"start.schema.json", {k: v for k, v in start.items() if k != "opened_by"}, False)
for name, change in [("report time", {"report_started_at": 1790180980.2}), ("no routes", {"routes": None}), ("unknown opener", {"opened_by": "ci"}),
                     ("absolute file", {"files": {"/etc/passwd": "f" * 64}}), ("bad digest", {"files": {"a.swift": "xyz"}})]:
    bad = {**start, **change}
    if change.get("routes", 0) is None:
        bad.pop("routes")
    check("invalid start stamp: " + name, P2+"start.schema.json", bad, False)

# ---------------------------------------------------------------- fingerprints: schema + vectors
for name, build in fv.VECTORS.items():
    check(f"route fingerprint vector {name}", P2+"route-fingerprint.schema.json", build())
bad = fv.vector_b()
bad["route"]["runner"] = {"executable": "swift"}
check("invalid route fingerprint: helper setting in payload", P2+"route-fingerprint.schema.json", bad, False)
bad = fv.vector_c()
bad["freshness_policy"] = fv.POLICY_CONTENT
check("invalid route fingerprint: locators in content mode", P2+"route-fingerprint.schema.json", bad, False)

spec = (DOCS / "design/11-fingerprints-and-freshness.md").read_text()
vectors_section = spec[spec.index("### 89.8"):]
published = re.findall(r"\*\*Vector ([A-Z]) —.*?exactly (\d+) bytes:\s*```json\n(.*?)\n```\s*```text\n(uc-route-v1-sha256:[0-9a-f]{64})\n```",
                       vectors_section, flags=re.S)
assert sorted(v[0] for v in published) == sorted(fv.VECTORS), f"chapter vectors {[v[0] for v in published]}"


def openssl_route_digest(data):
    framed = fv.ROUTE.encode() + b"\x00" + str(len(data)).encode() + b":" + data
    out = subprocess.run(["openssl", "dgst", "-sha256", "-r"], input=framed, capture_output=True, check=True).stdout
    return "uc-route-v1-sha256:" + out.split()[0].decode()


for name, size, text, digest in published:
    data, computed = fv.route_fingerprint(fv.VECTORS[name]())
    assert text.encode() == data, f"vector {name}: chapter bytes differ from the reference script"
    assert int(size) == len(data), f"vector {name}: chapter says {size} bytes, payload is {len(data)}"
    assert computed == digest, f"vector {name}: chapter digest differs from the reference script"
    assert openssl_route_digest(data) == digest, f"vector {name}: openssl disagrees"
    count += 1
framing_rows = re.findall(r"\| (content|workspace) \| ([^|]+)\| ([0-9a-f]{64}) \|", vectors_section)
payload_for = {"empty": b"", "abc": b"abc", "{}": b"{}"}
for kind, label, digest in framing_rows:
    token = "empty" if "empty" in label else "abc" if "abc" in label else "{}"
    domain = fv.CONTENT if kind == "content" else fv.WORKSPACE
    assert fv.framed_digest(domain, payload_for[token]) == digest, f"framing row {kind} {label.strip()}"
    count += 1
assert fv.canonical(fv.ESCAPING_PROBE) in vectors_section, "escaping probe"
count += 1

# a sign-off's fingerprint (approved.behaviour, chapters 02 and 21): framed like the others, 64 lowercase hex
promise_section = spec[spec.index("### 89.9"):]
assert fv.PROMISE in promise_section, "chapter 11 §89.9 names the promise domain"
members = re.search(r"exactly these members:\s*```text\n(.*?)\n```", promise_section, flags=re.S).group(1)
assert sorted(re.findall(r"^(\w+)", members, flags=re.M)) == sorted(fv.promise_vector()), "promise members match §89.9"
promise_data, promise_digest = fv.promise_fingerprint(fv.promise_vector())
assert re.fullmatch(r"[0-9a-f]{64}", promise_digest), "promise fingerprint is 64 lowercase hex"
assert promise_digest == fv.PROMISE_FINGERPRINT, f"promise vector: the script computes {promise_digest}"
promise_framed = fv.PROMISE.encode() + b"\x00" + str(len(promise_data)).encode() + b":" + promise_data
assert subprocess.run(["openssl", "dgst", "-sha256", "-r"], input=promise_framed, capture_output=True,
                      check=True).stdout.split()[0].decode() == promise_digest, "promise vector: openssl disagrees"
count += 1

# ---------------------------------------------------------------- command-line output (chapter 16)
P3 = "schemas/output/"
check("cli error", P3+"cli-error.schema.json",
      {"output_version": 1, "command": "status", "error": {"kind": "invalid", "message": "use-cases/login.yml: bad"}})
check("cli error before any command is known", P3+"cli-error.schema.json",
      {"output_version": 1, "command": None, "error": {"kind": "usage", "message": "invalid choice"}})
for name, bad in [("unknown kind", {"kind": "oops", "message": "x"}), ("no message", {"kind": "usage"})]:
    check("invalid cli error: " + name, P3+"cli-error.schema.json", {"output_version": 1, "command": "status", "error": bad}, False)
check("invalid cli error: output version 2", P3+"cli-error.schema.json",
      {"output_version": 2, "command": "status", "error": {"kind": "usage", "message": "x"}}, False)
route_row = {"route": "unit-tests", "gates": True, "linked": True, "status": "failed", "note": "run 0192f0c4 via unit-tests"}
ready_row = {"use_case": "shop.pay.card", "title": "Pay by card", "state": "READY", "status": "failed", "warnings": [], "routes": [route_row]}
draft_row = {"use_case": "shop.cart.share", "title": None, "state": "DRAFT", "status": "draft", "missing": ["intent"], "warnings": [], "routes": []}
status_doc = {"output_version": 1, "command": "status", "use_cases": [ready_row, draft_row],
              "summary": {"total": 2, "by_status": {"failed": 1, "draft": 1}}, "warnings": []}
check("cli status", P3+"cli-status.schema.json", status_doc)
check("cli status --gate --group", P3+"cli-status.schema.json",
      {**status_doc, "group": "release", "gate": {"passed": False, "strict": False,
                                                   "blocking": [{"use_case": "shop.pay.card", "status": "failed"}], "warning": []}})
for name, change in [("draft with a status", [{**draft_row, "status": "stale"}]),
                     ("ready without routes' shape", [{**ready_row, "routes": [{"route": "x"}]}]),
                     ("ready with missing", [{**ready_row, "missing": ["intent"]}]),
                     ("a draft route status", [{**ready_row, "status": "draft"}])]:
    check("invalid cli status: " + name, P3+"cli-status.schema.json", {**status_doc, "use_cases": change}, False)
check("cli status: approvals and a gate holding sign-offs", P3+"cli-status.schema.json",
      {**status_doc, "use_cases": [{**ready_row, "approval": "changed", "value_tier": "critical"}, {**draft_row, "approval": "unapproved"}],
       "gate": {"passed": False, "strict": False, "blocking": [{"use_case": "shop.pay.card", "status": "failed", "approval": "changed"}],
                "warning": [{"use_case": "shop.pay.wallet", "status": "verified", "approval": "unapproved"}]}})
check("invalid cli status: a gate holding an approved use case", P3+"cli-status.schema.json",
      {**status_doc, "gate": {"passed": False, "strict": False, "warning": [],
                              "blocking": [{"use_case": "shop.pay.card", "status": "verified", "approval": "approved"}]}}, False)
check("invalid cli status: an unknown approval", P3+"cli-status.schema.json",
      {**status_doc, "use_cases": [{**ready_row, "approval": "pending"}]}, False)
check("invalid cli status: gate blocking a draft", P3+"cli-status.schema.json",
      {**status_doc, "gate": {"passed": False, "strict": True, "blocking": [{"use_case": "shop.cart.share", "status": "draft"}], "warning": []}}, False)
check("cli status: the store's line", P3+"cli-status.schema.json",
      {**status_doc, "store": {"runs": 12, "bytes": 471859200, "superseded": 7}})
for name, store in [("no bytes", {"runs": 1, "superseded": 0}), ("negative bytes", {"runs": 1, "bytes": -1, "superseded": 0}),
                    ("an unknown member", {"runs": 1, "bytes": 0, "superseded": 0, "free": 1})]:
    check("invalid cli status store: " + name, P3+"cli-status.schema.json", {**status_doc, "store": store}, False)
prune_doc = {"output_version": 1, "command": "prune", "dry_run": False, "removed": [{"run_id": run_id, "bytes": 7812}],
             "leftovers": [{"folder": ".use-cases/runs/.tmp-prune-" + run_id, "bytes": 100}], "kept": [{"run_id": run_id, "bytes": 9}],
             "left_over": [], "bytes": 7912, "notes": ["run " + run_id + " is in use by another process, so it was kept"]}
check("cli prune", P3+"cli-prune.schema.json", prune_doc)
check("cli prune: nothing to prune", P3+"cli-prune.schema.json", {**prune_doc, "removed": [], "leftovers": [], "bytes": 0, "dry_run": True})
for name, change in [("a short run id", {"removed": [{"run_id": "01a2", "bytes": 1}]}), ("no dry_run", {"dry_run": None}),
                     ("a run without its size", {"removed": [{"run_id": run_id}]}),
                     ("a leftover outside the store", {"leftovers": [{"folder": "src/.tmp-prune-" + run_id, "bytes": 1}]}),
                     ("no leftovers", {"leftovers": None}), ("no kept", {"kept": None})]:
    doc = {k: v for k, v in {**prune_doc, **change}.items() if v is not None}
    check("invalid cli prune: " + name, P3+"cli-prune.schema.json", doc, False)
check("cli validate", P3+"cli-validate.schema.json",
      {"output_version": 1, "command": "validate", "valid": True, "use_cases": 3, "ready": 2, "draft": 1, "links": 9,
       "files": ["use-cases/login.yml"], "warnings": []})
check("invalid cli validate: not valid", P3+"cli-validate.schema.json",
      {"output_version": 1, "command": "validate", "valid": False, "use_cases": 0, "ready": 0, "draft": 0, "links": 0, "files": [], "warnings": []}, False)
check("cli links", P3+"cli-links.schema.json",
      {"output_version": 1, "command": "links", "links": [link], "diagnostics": []})
check("invalid cli links: byte offsets leak", P3+"cli-links.schema.json",
      {"output_version": 1, "command": "links", "links": [{**link, "span": [0, 10]}], "diagnostics": []}, False)
check("cli verify --abort", P3+"cli-verify.schema.json",
      {"output_version": 1, "command": "verify", "step": "abort", "run_id": run_id, "aborted": True})
check("cli verify --finish", P3+"cli-verify.schema.json",
      {"output_version": 1, "command": "verify", "step": "finish", **{k: v for k, v in manifest.items()}, "results": [result]})
check("cli verify --finish with nothing set up", P3+"cli-verify.schema.json",
      {"output_version": 1, "command": "verify", "step": "finish", "results": [], "errors": [], "diagnostics": [], "notes": ["nothing to read"]})
check("invalid cli verify: --start with results", P3+"cli-verify.schema.json",
      {"output_version": 1, "command": "verify", "step": "start", "started": False, "notes": [], "results": []}, False)
check("invalid cli verify: a started run without its report paths", P3+"cli-verify.schema.json",
      {"output_version": 1, "command": "verify", "step": "start", "started": True, "run_id": run_id, "selected": ["t"], "notes": []}, False)
check("cli record", P3+"cli-record.schema.json",
      {"output_version": 1, "command": "record", **{**manifest, "kind": "record", "sources": []}, "results": [result]})
check("invalid cli record: two results", P3+"cli-record.schema.json",
      {"output_version": 1, "command": "record", **{**manifest, "kind": "record", "sources": []}, "results": [result, result]}, False)

init_doc = {"output_version": 1, "command": "init", "workspace": "/work/shop", "created": ["use-cases.yml"], "kept": [],
            "gitignore": "added", "hooks": ["commit"], "notes": [], "dry_run": False}
hooks_doc = {"output_version": 1, "command": "hooks", "hooks_dir": ".git/hooks", "managed": False, "changed": ["push"], "notes": [],
             "dry_run": True,
             "hooks": [{"name": "commit", "event": "pre-commit", "state": "other", "runs": "use-cases validate"},
                       {"name": "push", "event": "pre-push", "state": "installed", "runs": "use-cases status --gate"}]}
check("cli hooks", P3+"cli-hooks.schema.json", hooks_doc)
for name, change in [("unknown hook", {"changed": ["merge"]}), ("unknown state", {"hooks": [{**hooks_doc["hooks"][0], "state": "maybe"}]})]:
    check("invalid cli hooks: " + name, P3+"cli-hooks.schema.json", {**hooks_doc, **change}, False)
check("cli init", P3+"cli-init.schema.json", init_doc)
for name, change in [("unknown gitignore state", {"gitignore": "maybe"}), ("absolute created path", {"created": ["/etc/x"]}),
                     ("a test tool it filled in", {"tool": {"name": "pytest"}})]:
    check("invalid cli init: " + name, P3+"cli-init.schema.json", {**init_doc, **change}, False)
check("invalid cli init: no dry_run", P3+"cli-init.schema.json", {k: v for k, v in init_doc.items() if k != "dry_run"}, False)

definition = {"id": "shop.login.lockout", "title": "Lock an account after failed attempts", "value_tier": "critical",
              "intent": "Repeated wrong passwords lock the account.",
              "scenarios": [{"id": "five-fails", "when": ["Five wrong passwords."], "then": ["The account is locked."]}],
              "validation": [{"id": "unit-tests", "type": {"kind": "unit"}, "covers": ["five-fails"]}]}
show_doc = {"output_version": 1, "command": "show", "use_case": "shop.login.lockout", "file": "use-cases/login.yml",
            "state": "READY", "missing": [], "definition": definition}
check("cli show", P3+"cli-show.schema.json", show_doc)
check("cli show: approved", P3+"cli-show.schema.json",
      {**show_doc, "approval": "approved", "definition": {**definition, "approved": {"by": "Sam", "on": "2026-10-11", "behaviour": "a" * 64}}})
render = lambda kind, model: {"output_version": 1, "command": "render", "kind": kind, "model": model, "text": "…"}
check("cli render intent", P3+"cli-render.schema.json", render("intent", {"what": "Refund part", "why": "Returns", "who": []}))
card = {"use_case": "shop.login.signin", "fit": "changes", "title": "Sign in", "tier": "critical", "now": "Locks after 5 tries.",
        "was": "No limit.", "scenarios": [{"golden": True, "text": "right password → signed in"}], "not_included": ["IP locks"],
        "proven_by": ["unit tests"]}
check("cli render brief", P3+"cli-render.schema.json", render("brief", {"cards": [card]}))
proposal_model = {"title": "Lock accounts", "changes": [{"use_case": "shop.login.signin", "fit": "changes", "title": "Sign in", "tier": "critical",
                                                         "you_see": "a lock message"}, {"use_case": "shop.login.remember", "fit": "untouched", "title": "Remember me"}],
                  "decisions": [{"question": "how long", "options": ["15 minutes", "until unlocked"]}], "sign_off": {"critical": 1}}
check("cli render proposal", P3+"cli-render.schema.json", render("proposal", proposal_model))
check("cli render results", P3+"cli-render.schema.json", render("results", {"title": "Lock accounts", "removed": ["shop.login.unlock-phone"], "gate": True,
      "use_cases": [{"use_case": "shop.login.signin", "title": "Sign in", "status": "verified", "checks": [{"label": "unit-tests", "status": "verified"}]}]}))
for name, doc in [("a card for an untouched use case", render("brief", {"cards": [{**card, "fit": "untouched"}]})),
                  ("a decision with one option", render("proposal", {**proposal_model, "decisions": [{"question": "q", "options": ["only"]}]})),
                  ("a proposal of nothing", render("proposal", {**proposal_model, "changes": []})),
                  ("a model of the wrong kind", render("intent", {"cards": [card]})),
                  ("an unknown kind", render("summary", {"what": "x", "why": "y", "who": []}))]:
    check("invalid cli render: " + name, P3+"cli-render.schema.json", doc, False)
approve_doc = {"output_version": 1, "command": "approve", "by": "Sam", "dry_run": False,
               "use_cases": [{"use_case": "shop.login.lockout", "file": "use-cases/login.yml", "action": "approved"}],
               "changes": [{"path": "use-cases/login.yml", "action": "replace"}]}
check("cli approve", P3+"cli-approve.schema.json", approve_doc)
for name, change in [("no name", {"by": ""}), ("an unknown action", {"use_cases": [{**approve_doc["use_cases"][0], "action": "rejected"}]})]:
    check("invalid cli approve: " + name, P3+"cli-approve.schema.json", {**approve_doc, **change}, False)
check("cli show: a draft", P3+"cli-show.schema.json",
      {**show_doc, "state": "DRAFT", "missing": ["intent"], "definition": {"id": "shop.login.lockout", "title": "Lockout"}})
for name, change in [("a malformed id", {"id": "shop..Lock Out"}), ("an unknown field", {"runner": "swift"}), ("no title", {"title": None})]:
    bad = {k: v for k, v in {**definition, **change}.items() if v is not None}
    check("invalid cli show: " + name, P3+"cli-show.schema.json", {**show_doc, "definition": bad}, False)
save_doc = {"output_version": 1, "command": "save", "use_case": "shop.refunds.partial", "file": "use-cases/refunds.yml",
            "action": "created", "changes": [{"path": "use-cases/refunds.yml", "action": "create"}], "warnings": [], "dry_run": True}
check("cli save", P3+"cli-save.schema.json", save_doc)
check("cli save: unchanged", P3+"cli-save.schema.json", {**save_doc, "action": "unchanged", "changes": [], "dry_run": False})
for name, change in [("unknown action", {"action": "upserted"}), ("an absolute path", {"changes": [{"path": "/etc/x", "action": "create"}]}),
                     ("an unknown change", {"changes": [{"path": "use-cases/refunds.yml", "action": "move"}]}), ("no dry_run", {"dry_run": None})]:
    check("invalid cli save: " + name, P3+"cli-save.schema.json", {k: v for k, v in {**save_doc, **change}.items() if v is not None}, False)
remove_doc = {"output_version": 1, "command": "remove", "use_case": "shop.refunds.partial", "file": "use-cases/refunds.yml",
              "action": "removed", "changes": [{"path": "use-cases/refunds.yml", "action": "delete"}],
              "warnings": ["tests/test_refunds.py:4-9 is still marked for shop.refunds.partial"], "dry_run": False}
check("cli remove", P3+"cli-remove.schema.json", remove_doc)
check("invalid cli remove: action created", P3+"cli-remove.schema.json", {**remove_doc, "action": "created"}, False)
apply_doc = {"output_version": 1, "command": "apply", "dry_run": True, "warnings": [],
             "use_cases": [{"use_case": "shop.share.email", "file": "use-cases/share.yml", "action": "removed"},
                           {"use_case": "shop.share.link", "file": "use-cases/share.yml", "action": "added"}],
             "changes": [{"path": "use-cases/share.yml", "action": "replace"}]}
check("cli apply", P3+"cli-apply.schema.json", apply_doc)
for name, change in [("an empty batch", {"use_cases": []}), ("an unknown action", {"use_cases": [{**apply_doc["use_cases"][0], "action": "renamed"}]}),
                     ("no dry_run", {"dry_run": None})]:
    check("invalid cli apply: " + name, P3+"cli-apply.schema.json", {k: v for k, v in {**apply_doc, **change}.items() if v is not None}, False)

match = {"use_case": "shop.login.lockout", "title": "Lock an account after failed attempts", "file": "use-cases/login.yml",
         "status": "stale", "value_tier": "critical", "score": 0.75,
         "why": [{"field": "title", "text": "Lock an account after failed attempts"},
                 {"field": "scenarios", "where": "five-fails", "text": "Five wrong passwords."}]}
search_doc = {"output_version": 1, "command": "search", "total": 41, "offset": 20, "page_size": 20, "matches": [match],
              "next": "eNodjcsKwjAQAH9F9txD83Kz_RnZbDYqiImmLaj47waP"}
check("cli search", P3+"cli-search.schema.json", search_doc)
check("cli search: the last page, with --full", P3+"cli-search.schema.json",
      {**search_doc, "next": None, "matches": [{**match, "definition": definition}]})
docs_list = {"output_version": 1, "command": "docs", "view": "list",
             "guides": [{"guide": "getting-started", "title": "Getting started", "covers": "init, a first use case, first status."}]}
check("cli docs: the list", P3+"cli-docs.schema.json", docs_list)
check("cli docs: one guide", P3+"cli-docs.schema.json",
      {"output_version": 1, "command": "docs", "view": "guide", "guide": "quirks", "title": "Quirks", "text": "# Quirks\n\nThe gotchas.\n"})
docs_page = {"output_version": 1, "command": "docs", "view": "search", "total": 1, "offset": 0, "page_size": 20, "next": None,
             "matches": [{"guide": "reading-status", "section": "Stale", "text": "A use case is stale when…", "score": 0.5}]}
check("cli docs: a page", P3+"cli-docs.schema.json", docs_page)
for name, doc in [("an unknown view", {**docs_list, "view": "index"}),
                  ("a guide name with spaces", {**docs_list, "guides": [{**docs_list["guides"][0], "guide": "getting started"}]}),
                  ("a list without guides", {**docs_list, "guides": []}),
                  ("a page mixed with a list", {**docs_page, "guides": docs_list["guides"]}),
                  ("a match without its guide", {**docs_page, "matches": [{"section": "Stale", "text": "x", "score": 0.5}]})]:
    check("invalid cli docs: " + name, P3+"cli-docs.schema.json", doc, False)
check("cli search: no matches", P3+"cli-search.schema.json", {**search_doc, "total": 0, "offset": 0, "matches": [], "next": None})
for name, change in [("a zero score", {"score": 0}), ("a score above 1", {"score": 1.5}), ("no reason", {"why": []}),
                     ("an unknown field", {"why": [{"field": "tags", "text": "x"}]}), ("an unknown status", {"status": "green"})]:
    check("invalid cli search: " + name, P3+"cli-search.schema.json", {**search_doc, "matches": [{**match, **change}]}, False)
for name, change in [("a page of 101", {"page_size": 101}), ("a token that is not url-safe", {"next": "a+b/c="}),
                     ("no next", {"next": "__drop__"})]:
    doc = {k: v for k, v in {**search_doc, **change}.items() if v != "__drop__"}
    check("invalid cli search: " + name, P3+"cli-search.schema.json", doc, False)

# ---------------------------------------------------------------- JSON examples published in the chapters


def doc_json(chapter, heading, index=0):
    """The index-th ```json block after a heading, parsed."""
    text = (DOCS / "design" / chapter).read_text()
    blocks = re.findall(r"```json\n(.*?)\n```", text[text.index(heading):], flags=re.S)
    return json.loads(blocks[index])


for name, chapter, heading, index, schema in [
    ("ch.10 links response example", "10-bridge-settings-and-transformers.md", "## 11. Links job", 1, "transformer-links-response"),
    ("ch.10 results response example", "10-bridge-settings-and-transformers.md", "## 13. Results job", 1, "transformer-results-response"),
    ("ch.12 run-order example", "12-results-storage.md", "`run-order.json` contains exactly:", 0, "run-order"),
    ("ch.12 run manifest example", "12-results-storage.md", "## 11. Run manifest", 0, "run"),
    ("ch.12 attachment example", "12-results-storage.md", "## 16. Run-local attachments", 0, "attachment"),
    ("ch.12 result example", "12-results-storage.md", "## 34. Example result", 0, "result"),
    ("ch.12 start stamp example", "12-results-storage.md", "### Start stamp", 0, "start"),
    ("ch.13 verify --start example", "13-verify-flow.md", "## 5. Reference sequence", 0, "cli-verify"),
    ("ch.16 error example", "16-cli-surface.md", "## 5. The JSON contract", 0, "cli-error"),
    ("ch.16 version example", "16-cli-surface.md", "## 7.", 0, "cli-version"),
    ("ch.17 init output example", "17-init.md", "## 8. Output", 0, "cli-init"),
    ("ch.18 hooks output example", "18-hooks.md", "## 5.", 0, "cli-hooks"),
    ("ch.16 show example", "16-cli-surface.md", "## 14.", 0, "cli-show"),
    ("ch.16 save example", "16-cli-surface.md", "## 14.", 1, "cli-save"),
    ("ch.16 apply example", "16-cli-surface.md", "**A batch.**", 0, "cli-apply"),
    ("ch.16 search example", "16-cli-surface.md", "## 15.", 0, "cli-search"),
    ("ch.16 docs example", "16-cli-surface.md", "## 16.", 0, "cli-docs"),
    ("ch.16 prune example", "16-cli-surface.md", "## 20.", 0, "cli-prune"),
]:
    data = doc_json(chapter, heading, index)
    if schema == "attachment":  # a descriptor is checked inside a result
        data, schema = {**result, "attachments": [data]}, "result"
    check(name, (P3 if schema.startswith("cli-") else P2) + schema + ".schema.json", data)


def doc_yaml(path, heading, index=0):
    text = (DOCS / path).read_text()
    blocks = re.findall(r"```yaml\n(.*?)\n```", text[text.index(heading):], flags=re.S)
    return yaml.safe_load(blocks[index])


canonical_use_case = doc_yaml("design/02-use-case-schema.md", "## Canonical example")
check("ch.02 canonical use case", P1+"use-cases.schema.json", {"use_cases": [canonical_use_case]})
chapter_06_routes = doc_yaml("design/06-validation-model.md", "Example:")
check("ch.06 route examples", P1+"use-cases.schema.json",
      {"use_cases": [{**use_case, "scenarios": use_case["scenarios"] + [{"id": "invalid-password", "when": ["x"], "then": ["y"]}],
                      **chapter_06_routes}]})
bridge_example = doc_yaml("design/10-bridge-settings-and-transformers.md", "## 5. File shape")
bridge_example["links"] = [{"transformer": "tools/links.py", "settings": {}}]  # the example shows a placeholder name
check("ch.10 bridge settings example", P1+"bridge.schema.json", bridge_example)

# ---------------------------------------------------------------- examples
examples = 0
FIXTURE_YAML = [p for p in sorted((DOCS.parent / "fixtures").glob("*/[23]-*/**/*.yml"))
                if p.name.startswith("use-case") or "use-cases" in p.parts[-2]]
for path in sorted((DOCS / "examples").glob("*/**/*.yml")) + FIXTURE_YAML:
    schema = {"use-cases.yml": "workspace", "use-case-groups.yml": "use-case-groups",
              "use-cases-bridge.yml": "bridge"}.get(path.name, "use-cases")
    check(str(path.relative_to(DOCS.parent)), P1 + schema + ".schema.json", yaml.safe_load(path.read_text()))
    examples += 1

print(f"{len(SCHEMAS)} schemas: Draft 2020-12 meta-schema valid")
print(f"{count} positive/negative checks passed, including {examples} example YAML files")
print(f"{len(published)} route vectors and {len(framing_rows)} framing rows match the reference script; route vectors also match openssl")
print("References resolved locally; timestamp format assertions enabled")
print("No engine, semantic resolution, run integrity, or execution claims are made")
