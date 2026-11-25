#!/usr/bin/env python3
"""Reference computation of the chapter 11 section 89 conformance vectors.

Standard library only. It implements canonical JSON, hash framing, content
references and the three route payloads the chapter publishes, then prints each
payload with its fingerprint. validate.py imports it to check that the chapter
text and this script agree.

    python docs/schemas/engine/fingerprint_vectors.py
"""

import hashlib
import json

CONTENT = "use-cases/content/v1"
ROUTE = "use-cases/route/v1"
WORKSPACE = "use-cases/workspace/v1"


def canonical(value):
    """Canonical JSON: sorted keys by UTF-8 bytes, no whitespace, \\u00xx for controls."""
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        out = ['"']
        for ch in value:
            if ch == '"':
                out.append('\\"')
            elif ch == "\\":
                out.append("\\\\")
            elif ord(ch) < 0x20:
                out.append("\\u%04x" % ord(ch))
            else:
                out.append(ch)
        out.append('"')
        return "".join(out)
    if isinstance(value, list):
        return "[" + ",".join(canonical(v) for v in value) + "]"
    if isinstance(value, dict):
        keys = sorted(value, key=lambda k: k.encode("utf-8"))
        return "{" + ",".join(canonical(k) + ":" + canonical(value[k]) for k in keys) + "}"
    raise TypeError(f"unsupported value {value!r}")


def framed_digest(domain, payload):
    framing = domain.encode("utf-8") + b"\x00" + str(len(payload)).encode("ascii") + b":" + payload
    return hashlib.sha256(framing).hexdigest()


def content_reference(data):
    return {"algorithm": "sha256", "byte_length": len(data), "digest": framed_digest(CONTENT, data)}


def route_fingerprint(payload):
    data = canonical(payload).encode("utf-8")
    return data, "uc-route-v1-sha256:" + framed_digest(ROUTE, data)


POLICY_CONTENT = {"binding_identity": "content", "normalization": {"ignore": ["line-endings"]}}  # the default policy
POLICY_STRICT = {"binding_identity": "content-and-locator", "normalization": {"ignore": ["line-endings"]}}
SCENARIO = {"given": [], "id": "success", "then": ["Success is visible."], "when": ["Perform the action."]}


def vector_a():
    """Procedural route; no links at all (links are optional)."""
    return {
        "fingerprint_version": 1,
        "freshness_policy": POLICY_CONTENT,
        "use_case_id": "example.success",
        "route_id": "manual",
        "intent": "Demonstrate success.",
        "covered_scenarios": [SCENARIO],
        "route": {
            "type": {"kind": "acceptance"},
            "covers": ["success"],
            "gates_verification": True,
            "procedure": {"setup": [], "steps": ["Perform the action and observe success."], "reset": []},
        },
        "implementation_links": [],
        "validation_links": [],
        "resources": [],
    }


def vector_b():
    """Automated route in content mode: an empty implementation link, one marker region holding
    "abc" and its line break, and one resource. The workspace in section 89.8 produces exactly this."""
    return {
        "fingerprint_version": 1,
        "freshness_policy": POLICY_CONTENT,
        "use_case_id": "example.success",
        "route_id": "unit-tests",
        "intent": "Demonstrate success.",
        "covered_scenarios": [SCENARIO],
        "route": {"type": {"kind": "unit"}, "covers": ["success"], "gates_verification": True, "procedure": None},
        "implementation_links": [{"id": "implementation", "regions": [content_reference(b"")]}],
        "validation_links": [{"id": "success", "regions": [content_reference(b"abc\n")]}],
        "resources": [{"file": "fixtures/users.json", "content": content_reference(b"{}")}],
    }


def vector_c():
    """Vector B's inputs under content-and-locator: kind and byte locators join each region.
    src/app.swift is an empty file bound whole; tests/app_tests.swift is
    "// @use-case:example.success#unit-tests.success\nabc\n// @use-case:end example.success#unit-tests.success\n",
    so the marker region (the line between the sentinel lines) is bytes 48-52."""
    payload = vector_b()
    payload["freshness_policy"] = POLICY_STRICT
    payload["implementation_links"] = [{
        "id": "implementation", "kind": "manual",
        "regions": [{"locator": {"file": "src/app.swift", "start_byte": 0, "end_byte": 0}, "content": content_reference(b"")}],
    }]
    payload["validation_links"] = [{
        "id": "success", "kind": "marker",
        "regions": [{"locator": {"file": "tests/app_tests.swift", "start_byte": 48, "end_byte": 52}, "content": content_reference(b"abc\n")}],
    }]
    return payload


OPEN = "@use-case:example.success#unit-tests.success"
CLOSE = "@use-case:end example.success#unit-tests.success"
INNER_OPEN, INNER_CLOSE = "@use-case:example.other#inner", "@use-case:end example.other#inner"

# Vector D's validation file: one same-line pair with a nested pair inside it.
FILE_D = f"x = /* {OPEN} */ f() + /* {INNER_OPEN} */ g() /* {INNER_CLOSE} */ /* {CLOSE} */\n".encode()
# Vector E's validation file: a line-mode pair whose region holds a nested pair's sentinel lines.
FILE_E = f"// {OPEN}\nabc\n// {INNER_OPEN}\ndef\n// {INNER_CLOSE}\n// {CLOSE}\n".encode()


def vector_d():
    """Same-line mode: the bytes between the outer tokens, less each nested token (chapter 08). Comment syntax
    around the nested tokens stays."""
    payload = vector_b()
    payload["validation_links"] = [{"id": "success", "regions": [content_reference(b" */ f() + /*  */ g() /*  */ /* ")]}]
    return payload


def vector_e():
    """Line mode under content-and-locator: the locator spans the whole region, while the content leaves out
    the nested sentinel lines, so it is not contiguous."""
    payload = vector_c()
    lines = FILE_E.split(b"\n")
    start = len(lines[0]) + 1
    end = len(FILE_E) - len(lines[-2]) - 1 - len(lines[-1])
    payload["validation_links"] = [{
        "id": "success", "kind": "marker",
        "regions": [{"locator": {"file": "tests/app_tests.swift", "start_byte": start, "end_byte": end},
                     "content": content_reference(b"abc\ndef\n")}],
    }]
    return payload


VECTORS = {"A": vector_a, "B": vector_b, "C": vector_c, "D": vector_d, "E": vector_e}

PROMISE = "use-cases/promise/v1"


def promise_fingerprint(payload):
    """A sign-off's fingerprint (`approved.behaviour`, chapters 02 and 21): the canonical promise payload, framed
    with the promise domain like the other fingerprints, SHA-256, 64 lowercase hex with no prefix."""
    data = canonical(payload).encode("utf-8")
    return data, framed_digest(PROMISE, data)


def promise_vector():
    """Section 89.9: seven members, the use case's fully resolved id, title, description, value_tier, intent,
    scenarios (id, given, when, then, in authored order) and out_of_scope. Every member is written: an absent list
    is [], an absent text is null. Routes, bindings and links are not part of it."""
    return {
        "id": "example.success",
        "title": "Success",
        "description": None,
        "value_tier": "core",
        "intent": "Demonstrate success.",
        "scenarios": [
            {"id": "success", "given": [], "when": ["Perform the action."], "then": ["Success is visible."]},
            {"id": "failure", "given": ["The service is down."], "when": ["Perform the action."], "then": ["A clear error is shown."]},
        ],
        "out_of_scope": ["Retries."],
    }


PROMISE_FINGERPRINT = "ba2fbe04bc7c271e32485c62b149f1727f6be53f313c587795cbb3d26f20f17a"

FRAMING = [
    ("content", CONTENT, b""),
    ("content", CONTENT, b"abc"),
    ("workspace", WORKSPACE, b"{}"),
]

ESCAPING_PROBE = {"a": "é", "z": "\n\"\\"}


def main():
    print("escaping probe:", canonical(ESCAPING_PROBE))
    for kind, domain, data in FRAMING:
        print(f"{kind} {data!r} length {len(data)}: {framed_digest(domain, data)}")
    for name, build in VECTORS.items():
        data, fingerprint = route_fingerprint(build())
        print(f"\nvector {name}: {len(data)} bytes\n{data.decode('utf-8')}\n{fingerprint}")
    data, fingerprint = promise_fingerprint(promise_vector())
    print(f"\npromise vector: {len(data)} bytes\n{data.decode('utf-8')}\n{fingerprint}")


if __name__ == "__main__":
    main()
