"""Scale: a generated Python project with 1,000 use cases, 3,000 real pytest tests and 4,000
markers. Proves the contract holds at size.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_scale.py -v -s
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
from conftest import SENTINEL, COMMAND

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AREAS, PER_AREA, TESTS_PER_CASE = int(os.environ.get("UC_SCALE_AREAS", "50")), 20, 3
USE_CASES = AREAS * PER_AREA

BRIDGE = """schema_version: 1
validations:
  - id: pytest
    report: pytest.xml
    run: [python3, -m, pytest, -q, -p, no:cacheprovider, -o, junit_family=xunit1, "--junitxml={report}"]
    transformer: junit
    settings:
      find: file-line
      line_base: 0
"""


def generate(root):
    os.makedirs(os.path.join(root, "use-cases"))
    os.makedirs(os.path.join(root, "src", "shop"))
    os.makedirs(os.path.join(root, "tests"))
    with open(os.path.join(root, "use-cases.yml"), "w") as handle:
        handle.write("schema_version: 1\nroot: true\nprefix: shop\n")
    with open(os.path.join(root, "use-cases-bridge.yml"), "w") as handle:
        handle.write(BRIDGE)
    open(os.path.join(root, "src", "shop", "__init__.py"), "w").close()
    with open(os.path.join(root, "tests", "conftest.py"), "w") as handle:
        handle.write("import sys, os\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))\n")
    for area in range(AREAS):
        name = f"area{area:02d}"
        definitions, source, tests = [f"prefix: {name}\nuse_cases:\n"], [], ["from shop import " + name + "\n\n"]
        for case in range(PER_AREA):
            uc = f"rule{case:02d}"
            full = f"shop.{name}.{uc}"
            definitions.append(
                f"  - id: {uc}\n    title: Rule {case}\n    value_tier: core\n    intent: Rule {case} of {name} holds.\n"
                f"    scenarios:\n      - id: holds\n        when: [Apply the rule.]\n        then: [It holds.]\n"
                f"    validation:\n      - id: unit-tests\n        type: {{ kind: unit }}\n        covers: [holds]\n")
            source.append(f"# {SENTINEL}{full}#logic\ndef {uc}(x):\n    return x + {case}\n# {SENTINEL}end {full}#logic\n\n")
            for number in range(TESTS_PER_CASE):
                tests.append(f"# {SENTINEL}{full}#unit-tests.t{number}\ndef test_{uc}_{number}():\n"
                             f"    assert {name}.{uc}({number}) == {number + case}\n# {SENTINEL}end {full}#unit-tests.t{number}\n\n")
        for rel, parts in ((f"use-cases/{name}.yml", definitions), (f"src/shop/{name}.py", source), (f"tests/test_{name}.py", tests)):
            with open(os.path.join(root, rel), "w") as handle:
                handle.write("".join(parts))


def run_json(ws, *args):
    process = subprocess.run([*COMMAND, "--workspace", ws, "--json", *args], capture_output=True, text=True)
    assert process.returncode == 0, process.stderr
    return json.loads(process.stdout)


@pytest.fixture(scope="module")
def project(tmp_path_factory):
    root = str(tmp_path_factory.mktemp("scale") / "shop")
    generate(root)
    return root


def test_links_at_scale(project):
    links = run_json(project, "links")
    assert len(links["links"]) == USE_CASES * (1 + TESTS_PER_CASE) and links["diagnostics"] == []


def test_validate_run_at_scale(project):
    run = run_json(project, "verify", "--run")
    assert run["errors"] == [] and len(run["results"]) == USE_CASES
    assert all(r["status"] == "pass" for r in run["results"])


def test_status_at_scale(project):
    status = run_json(project, "status")
    assert len(status["use_cases"]) == USE_CASES
    assert all(u["status"] == "verified" for u in status["use_cases"])



def test_search_at_scale(project):
    found = run_json(project, "search", "rule area07", "--page-size", "100")
    assert found["total"] == USE_CASES and found["matches"][0]["use_case"].startswith("shop.area07.")
    following = run_json(project, "search", "--next", found["next"])
    assert following["offset"] == 100

def test_one_edit_stales_exactly_one_use_case_at_scale(project, tmp_path):
    ws = str(tmp_path / "shop")
    shutil.copytree(project, ws, symlinks=True)
    path = os.path.join(ws, "src", "shop", "area07.py")
    with open(path) as handle:
        text = handle.read()
    with open(path, "w") as handle:
        handle.write(text.replace("    return x + 13\n", "    return x + 13  # unchanged behaviour\n"))
    status = run_json(ws, "status")
    stale = [u["use_case"] for u in status["use_cases"] if u["status"] != "verified"]
    assert stale == ["shop.area07.rule13"]
