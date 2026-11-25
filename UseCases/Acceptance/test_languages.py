"""Across languages: the same core, the same contract, eight languages and test tools.

Each fixture's 3-bridge variant (fixtures/<language>/3-bridge) is a realistic repo with use
cases retrofitted and a results transformer configured. Every language runs the same
scenarios. Run from the repository root:

    uv run --with pyyaml --with pytest pytest UseCases/Acceptance/test_languages.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest
from conftest import windows_launcher, call_core, transformer_program, record_exchanges
import yaml

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FIXTURES = os.path.join(REPO, "fixtures")
def env():
    return {**os.environ, "PATH": os.pathsep.join(["/opt/homebrew/opt/openjdk/bin", os.environ["PATH"]])}

# expected: every use case's verdict after a clean run. edit(file, old, new): a one-line change.
LANGUAGES = {
    "python": dict(
        expected={"invoicing.billing.totals": "pass", "invoicing.billing.discounts": "pass",
                  "invoicing.billing.tax-regions": "incomplete"},
        unlinked=2,
        fail=("tests/test_invoice.py", 'invoice.subtotal == Decimal("20.00")', 'invoice.subtotal == Decimal("21.00")', "invoicing.billing.totals"),
        build_break=("src/invoicing/tax.py", "def tax_for(region: str) -> Decimal:", "def tax_for(region: str) -> Decimal"),
        filtered=(["python3", "-m", "pytest", "-q", "-o", "junit_family=xunit1", "--junitxml={report}", "tests/test_tax.py"],
                  ["invoicing.billing.totals", "invoicing.billing.discounts"]),
        # discount_total sits inside the totals region too, so both use cases go stale
        stale=("src/invoicing/invoice.py", "        return taken", "        return taken  # after every discount",
               ["invoicing.billing.discounts", "invoicing.billing.totals"])),
    "javascript": dict(
        expected={"duration.text.parse": "pass", "duration.text.format": "incomplete"},
        unlinked=0,
        fail=("test/duration.test.js", 'assert.equal(parse("1h 30m"), 5_400_000);', 'assert.equal(parse("1h 30m"), 5_400_001);', "duration.text.parse"),
        build_break=("src/duration.js", "export function parse(text) {", "export function parse(text) {{"),
        filtered=(["node", "--test", "--test-name-pattern=^format", "--test-reporter=junit", "--test-reporter-destination={report}"],
                  ["duration.text.parse"]),
        stale=("src/duration.js", 'if (ms === 0) return "0s";', 'if (ms === 0) return "0s"; // nothing to show', "duration.text.format")),
    "c": dict(
        expected={"ringbuf.buffer.fifo": "pass", "ringbuf.buffer.full": "pass"},
        unlinked=1,
        fail=("tests/test_ringbuf.c", "CHECK(ringbuf_pop(&rb, &value) && value == 8);", "CHECK(ringbuf_pop(&rb, &value) && value == 9);", "ringbuf.buffer.fifo"),
        build_break=("src/ringbuf.c", "size_t ringbuf_count(const ringbuf *rb) {", "size_t ringbuf_count(const ringbuf *rb) {{"),
        filtered=(["sh", "-c", 'cmake -S . -B build && cmake --build build --config Debug && ctest --test-dir build -C Debug -R "rejects|overwrite" --output-junit "$1"', "sh", "{report}"],
                  ["ringbuf.buffer.fifo"]),
        stale=("src/ringbuf.c", "    rb->count++;", "    rb->count += 1;", "ringbuf.buffer.fifo")),
    "java": dict(
        expected={"ledger.accounts.deposits": "pass", "ledger.accounts.overdraft": "pass", "ledger.accounts.transfers": "pass"},
        unlinked=2,
        fail=("src/test/java/com/example/ledger/AccountTest.java", 'assertEquals(new BigDecimal("120.50"), account.balance());',
              'assertEquals(new BigDecimal("120.51"), account.balance());', "ledger.accounts.deposits"),
        build_break=("src/main/java/com/example/ledger/Account.java", "    public String id() {", "    public String id() {{"),
        filtered=(["mvn", "-q", "-B", "test", "-Dtest=TransfersTest", "-DjunitDir={report}"], ["ledger.accounts.deposits", "ledger.accounts.overdraft"]),
        stale=("src/main/java/com/example/ledger/Account.java", "        entries.add(new Entry(amount, memo));",
               "        entries.add(new Entry(amount, memo)); // credit", "ledger.accounts.deposits")),
    "kotlin": dict(
        expected={"todo.tasks.completion": "pass", "todo.tasks.agenda": "pass", "todo.tasks.recurring": "incomplete"},
        unlinked=1,
        fail=("src/test/kotlin/com/example/todo/TodoListTest.kt", 'assertEquals(listOf("book flights")', 'assertEquals(listOf("book flight")', "todo.tasks.completion"),
        build_break=("src/main/kotlin/com/example/todo/TodoList.kt", "fun open(): List<Task> =", "fun open(): List<Task> = ="),
        filtered=(["gradle", "test", "-q", "--tests", "com.example.todo.TaskTest", "-PjunitDir={report}"], ["todo.tasks.completion", "todo.tasks.agenda", "todo.tasks.recurring"]),
        stale=("src/main/kotlin/com/example/todo/TodoList.kt", ".thenBy(nullsLast()) { it.due },", ".thenBy(nullsLast()) { it.due }, // undated last", "todo.tasks.agenda")),
    "go": dict(
        expected={"linkshort.links.shorten": "pass", "linkshort.links.expiry": "pass"},
        unlinked=1,
        fail=("shortener/shortener_test.go", 'if code != "fresh" {', 'if code != "stale" {', "linkshort.links.shorten"),
        build_break=("shortener/shortener.go", "func (s *Shortener) Resolve(code string) (string, error) {", "func (s *Shortener) Resolve(code string) (string, error {"),
        filtered=(["sh", "-c", 'go test -json -run TestExpired ./... > "$1"', "sh", "{report}"], ["linkshort.links.shorten"]),
        stale=("shortener/shortener.go", 'return "", ErrNotFound', 'return "", ErrNotFound // unknown code', "linkshort.links.expiry")),
    "rust": dict(
        expected={"exprlex.lexing.literals": "pass", "exprlex.lexing.errors": "pass", "exprlex.lexing.expressions": "incomplete"},
        unlinked=1,
        fail=("src/lib.rs", "Err(LexError { offset: 4, found: '$' })", "Err(LexError { offset: 5, found: '$' })", "exprlex.lexing.errors"),
        build_break=("src/token.rs", "pub struct Token {", "pub struct Token {{"),
        filtered=(["sh", "-c", 'cargo test --no-fail-fast offset > "$1" 2>&1', "sh", "{report}"],
                  ["exprlex.lexing.literals"]),
        stale=("src/lib.rs", "        tokens.push(Token::new(kind, offset));", "        tokens.push(Token::new(kind, offset)); // operator", "exprlex.lexing.expressions")),
    "swift": dict(
        expected={"ratelimit.bucket.take": "pass", "ratelimit.bucket.refill": "pass"},
        unlinked=2,
        fail=("Tests/RateLimitTests/TokenBucketTests.swift", "#expect(bucket.available == 5)", "#expect(bucket.available == 6)", "ratelimit.bucket.take"),
        build_break=("Sources/RateLimit/TokenBucket.swift", "    public var available: Double {", "    public var available: Double"),
        filtered=(["sh", "-c", 'swift test --filter TokenBucketTests --experimental-event-stream-output "$1/events.jsonl" '
                   '--experimental-event-stream-version 0 > "$1/console.txt" 2>&1', "sh", "{report}"],
                  ["ratelimit.bucket.refill"]),
        stale=("Sources/RateLimit/TokenBucket.swift", "        tokens -= count", "        tokens -= count // spend", "ratelimit.bucket.take")),
    "bdd": dict(
        expected={"library.borrowing.borrow": "pass", "library.borrowing.loan-limit": "pass",
                  "library.returns.fines": "pass", "library.returns.renewal": "incomplete"},
        unlinked=2,
        fail=("features/returns.feature", "| 2026-03-22 | 140  |", "| 2026-03-22 | 141  |", "library.returns.fines"),
        build_break=("src/library.js", "export class LoanError extends Error {}", "export class LoanError extends Error {"),
        filtered=(["npx", "cucumber-js", "--no-strict", "--tags", "@returns", "--format", "message:{report}"],
                  ["library.borrowing.borrow", "library.borrowing.loan-limit"]),
        stale=("src/library.js", "  return late > 0 ? late * FINE_PER_DAY : 0;", "  return late > 0 ? late * FINE_PER_DAY : 0; // pence",
               "library.returns.fines")),
}


def node_modules(language):
    """Cucumber is an npm dependency: install it once, then share it with every copy."""
    installed = os.path.join(FIXTURES, language, "1-plain", "node_modules")
    if not os.path.isdir(installed):
        subprocess.run([shutil.which("npm") or "npm", "install", "--no-audit", "--no-fund"], cwd=os.path.dirname(installed), check=True,
                       capture_output=True)
    return installed


# ------------------------------------------------------------------ helpers


def uc(workspace, *args):
    return call_core(workspace, *args, env=env())


def edit(workspace, rel, old, new):
    path = os.path.join(workspace, rel)
    with open(path) as handle:
        text = handle.read()
    assert text.count(old) == 1, f"{old!r} must appear once in {rel}"
    with open(path, "w") as handle:
        handle.write(text.replace(old, new))


def set_run(workspace, run):
    path = os.path.join(workspace, "use-cases-bridge.yml")
    with open(path) as handle:
        bridge = yaml.safe_load(handle)
    bridge["validations"][0]["run"] = run
    with open(path, "w") as handle:
        yaml.safe_dump(bridge, handle, sort_keys=False)


def consoles(ws, run):
    """The run commands' console captures, so a failing check shows why the tool wrote no report."""
    outputs = os.path.join(ws, ".use-cases", "runs", run.get("run_id", ""), "outputs")
    texts = []
    for root, _, files in os.walk(outputs):
        texts += [open(os.path.join(root, f), errors="replace").read()[-3000:] for f in files if f == "console.txt"]
    return "\n".join(texts)


def verdicts(run):
    """Worst verdict per use case across its routes, as the core judged them."""
    order = ["pass", "incomplete", "error", "fail"]
    found = {}
    for result in run["results"]:
        found[result["use_case"]] = max([found.get(result["use_case"], "pass"), result["status"]], key=order.index)
    return found


def no_verdict(run, problem):
    return {d["use_case"] for d in run["diagnostics"] if isinstance(d, dict) and d.get("problem") == problem}


TOOLS = {"python": ["python3"], "javascript": ["node"], "c": ["cmake", "ctest"], "java": ["mvn"], "kotlin": ["gradle"],
         "go": ["go"], "rust": ["cargo"], "swift": ["swift"], "bdd": ["node", "npm"]}


@pytest.fixture
def workspace(tmp_path, request):
    language = request.param
    if language == "bdd" and os.name == "nt":
        pytest.skip("cucumber-js reads --format message:D:\\... as name:path and splits at the drive letter; "
                    "on Windows run it through a wrapper that writes a relative path (catalogue: cucumber-messages)")
    missing = [tool for tool in TOOLS[language] if not shutil.which(tool, path=env()["PATH"])]
    if missing:
        if os.environ.get("UC_REQUIRE_TOOLS") == "all":
            pytest.fail(f"{language} needs {missing}, and UC_REQUIRE_TOOLS=all")
        pytest.skip(f"{language} needs {missing}")
    target = str(tmp_path / language)
    shutil.copytree(os.path.join(FIXTURES, language, "3-bridge"), target)
    if language == "bdd":
        try:
            os.symlink(node_modules(language), os.path.join(target, "node_modules"))
        except OSError:  # Windows without the symlink privilege
            shutil.copytree(node_modules(language), os.path.join(target, "node_modules"))
    return language, target


def languages():
    return pytest.mark.parametrize("workspace", list(LANGUAGES), indirect=True)


# ------------------------------------------------------------------ scenarios


@languages()
def test_one_run_gives_every_use_case_its_verdict(workspace):
    language, ws = workspace
    spec = LANGUAGES[language]
    run = uc(ws, "verify", "--run")
    assert run["errors"] == [], consoles(ws, run)
    assert verdicts(run) == spec["expected"]
    assert len(run["unlinked_tests"]) == spec["unlinked"]
    # freshness on the same workspace: editing linked code stales only its use case
    file, old, new, stale = spec["stale"]
    stale = stale if isinstance(stale, list) else [stale]
    edit(ws, file, old, new)
    status = {u["use_case"]: u["status"] for u in uc(ws, "status")["use_cases"]}
    assert all(status[u] == "stale" for u in stale), status
    passed_elsewhere = [u for u, v in spec["expected"].items() if v == "pass" and u not in stale]
    assert all(status[u] == "verified" for u in passed_elsewhere), status


@languages()
def test_a_failing_test_fails_its_use_case(workspace):
    language, ws = workspace
    file, old, new, use_case = LANGUAGES[language]["fail"]
    edit(ws, file, old, new)
    run = uc(ws, "verify", "--run")
    assert verdicts(run)[use_case] == "fail"


@languages()
def test_a_build_break_is_a_run_error_not_a_failure(workspace):
    language, ws = workspace
    file, old, new = LANGUAGES[language]["build_break"]
    edit(ws, file, old, new)
    run = uc(ws, "verify", "--run")
    assert run["results"] == []
    assert len(run["errors"]) == 1


@languages()
def test_a_filtered_run_never_verifies_what_it_skipped(workspace):
    language, ws = workspace
    command, skipped = LANGUAGES[language]["filtered"]
    set_run(ws, command)
    run = uc(ws, "verify", "--run")
    assert run["errors"] == [], consoles(ws, run)
    judged = verdicts(run)
    for use_case in skipped:
        assert judged.get(use_case) != "pass", f"{use_case} verified although its tests were filtered out"
    assert set(skipped) <= no_verdict(run, "its test didn't run") | {u for u, v in judged.items() if v == "incomplete"}


@languages()
def test_tests_you_ran_yourself_between_start_and_finish(workspace):
    language, ws = workspace
    spec = LANGUAGES[language]
    with open(os.path.join(ws, "use-cases-bridge.yml")) as handle:
        validation = yaml.safe_load(handle)["validations"][0]
    cwd = os.path.join(ws, validation.get("working_dir", "."))

    def run_tests_yourself(started):
        """A CI step: the project's usual test command, writing its report where `--start` said."""
        command = [part.replace("{report}", started["reports"][validation["id"]]) for part in validation["run"]]
        command[0] = shutil.which(command[0], path=env()["PATH"]) or command[0]  # as the core finds it (chapter 14 §7)
        subprocess.run(command, cwd=cwd, env=env(), capture_output=True)

    run_tests_yourself(uc(ws, "verify", "--start"))
    run = uc(ws, "verify", "--finish")
    assert run["errors"] == [], consoles(ws, run)
    assert verdicts(run) == spec["expected"]

    file, old, new, stale = spec["stale"]
    run_tests_yourself(uc(ws, "verify", "--start"))
    edit(ws, file, old, new)  # code edited before --finish read the report
    run = uc(ws, "verify", "--finish")
    stale = set(stale if isinstance(stale, list) else [stale])
    assert stale <= no_verdict(run, "code changed during the run")
    assert not stale & set(verdicts(run))


@languages()
@pytest.mark.broken_transformer  # the responses carry fields contract 1 does not define, on purpose
def test_fields_from_a_future_version_change_nothing(workspace):
    """A newer core may add request fields and a newer transformer may add response fields,
    within contract 1: each side ignores what it does not know (chapter 10), so verdicts are identical."""
    language, ws = workspace
    spec = LANGUAGES[language]
    with open(os.path.join(ws, "use-cases-bridge.yml")) as handle:
        bridge = yaml.safe_load(handle)
    real = transformer_program(bridge["validations"][0]["transformer"], os.path.join(os.path.dirname(ws), "launchers"))
    os.makedirs(os.path.join(ws, "tools"), exist_ok=True)
    shutil.copy(os.path.join(os.path.dirname(__file__), "tools", "future-core"), os.path.join(ws, "tools", "future-core"))
    record_exchanges(os.path.join(ws, "tools", "future-core"))
    windows_launcher(os.path.join(ws, "tools", "future-core"), "#!/usr/bin/env python3\n")
    bridge["validations"][0]["transformer"] = "tools/future-core"
    with open(os.path.join(ws, "use-cases-bridge.yml"), "w") as handle:
        yaml.safe_dump(bridge, handle, sort_keys=False)
    os.environ["UC_WRAPPED_TRANSFORMER"] = os.path.realpath(real)
    try:
        run = uc(ws, "verify", "--run")
    finally:
        del os.environ["UC_WRAPPED_TRANSFORMER"]
    assert run["errors"] == [], consoles(ws, run)
    assert verdicts(run) == spec["expected"]
    assert len(run["unlinked_tests"]) == spec["unlinked"]
