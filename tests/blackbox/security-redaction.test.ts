// The black-box oracle for security/redaction.yml.
//
// Redaction happens at APPEND time, on the way into a ledger that is
// append-only and usually committed. That is why it is worth a black-box test
// rather than only a unit test of the matcher: what matters is not that the
// regexes fire, but that a secret handed to `uc evidence record` cannot be read
// back out of the stored event.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { runUcJson } from "../helpers/uc-binary";

const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

const WORKSPACE_CONFIG = `schema_version: 1
workspace_id: probe
component_id: probe
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
`;

const MATRIX = `schema_version: 1
feature:
  id: probe.core
  name: Probe
  summary: Probe.
use_cases:
  - id: probe.core.alpha
    title: Alpha
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so evidence can be recorded against it.
    preconditions: [Nothing.]
    trigger: An agent records evidence.
    scenarios:
      - id: probe.core.alpha.golden_runs
        kind: steps
        steps: [Record it.]
        observable_outcomes: [It is stored redacted.]
    observable_outcomes: [Secrets never reach the ledger.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`;

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-redaction-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), MATRIX);
  return { dir, env };
}

let recordCounter = 0;

/** Record a summary and hand back what the ledger actually stored. */
function storedSummary(workspace: Workspace, summary: string): string {
  recordCounter += 1;
  const { envelope } = runUcJson<{ event: { payload: { summary: string } } }>(
    ["evidence", "record", "--repo", ".", "--use-case", "probe.core.alpha",
      "--summary", summary, "--idempotency-key", `redaction-${recordCounter}`],
    { cwd: workspace.dir, env: workspace.env }
  );
  expect(envelope.ok, "the record must be appended").toBe(true);
  return envelope.data.event.payload.summary;
}

//: @use-case:security.redaction.secrets_never_reach_an_append_only_ledger#blackbox
describe("security.redaction.secrets_never_reach_an_append_only_ledger", () => {
  // golden_labelled_assignments. The LABEL survives so a reader can still see
  // what kind of thing was removed; the value does not. Its case is preserved
  // too, and the separator is normalised to `=` even when the input used a
  // colon — both measured through the CLI rather than read off the matcher.
  test("labelled secret assignments are redacted, keeping the label and its case", () => {
    const workspace = makeWorkspace();
    const stored = storedSummary(
      workspace,
      "SECRET: hunter2 and token=abc123def and password: pw and api_key: k9"
    );

    expect(stored).toContain("SECRET=[redacted]");
    expect(stored).toContain("token=[redacted]");
    expect(stored).toContain("password=[redacted]");
    expect(stored).toContain("api_key=[redacted]");
    for (const secret of ["hunter2", "abc123def", "k9"]) {
      expect(stored, `${secret} must not survive`).not.toContain(secret);
    }
  });

  // golden_vendor_token_shapes. Each keeps enough prefix to identify what kind
  // of credential it was, which is what makes the record useful to act on.
  test("vendor token shapes are redacted with their prefix left intact", () => {
    const workspace = makeWorkspace();
    const stored = storedSummary(
      workspace,
      "openai sk-ABCDEFGH12345678 github ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345 aws AKIAIOSFODNN7EXAMPLE"
    );

    expect(stored).toContain("sk-[redacted]");
    expect(stored).toContain("ghp_[redacted]");
    expect(stored).toContain("AKIA[redacted]");
    for (const secret of ["ABCDEFGH12345678", "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", "IOSFODNN7EXAMPLE"]) {
      expect(stored, `${secret} must not survive`).not.toContain(secret);
    }
  });

  // bad_legitimate_prose_is_not_mangled. Over-redaction is its own failure:
  // records nobody can read are records nobody trusts.
  test("text with no secret pattern is stored verbatim", () => {
    const workspace = makeWorkspace();
    const prose = "The checkout flow worked and the receipt rendered correctly.";
    expect(storedSummary(workspace, prose)).toBe(prose);
  });

  // edge_multiple_secrets_in_one_string. Every match, not just the first.
  test("every distinct secret in one string is redacted, not only the first", () => {
    const workspace = makeWorkspace();
    const stored = storedSummary(
      workspace,
      "first token=aaaaaaaa then sk-BBBBBBBB12345678 then AKIAIOSFODNN7EXAMPLE end"
    );

    expect(stored).toContain("token=[redacted]");
    expect(stored).toContain("sk-[redacted]");
    expect(stored).toContain("AKIA[redacted]");
    for (const secret of ["aaaaaaaa", "BBBBBBBB12345678", "IOSFODNN7EXAMPLE"]) {
      expect(stored, `${secret} must not survive`).not.toContain(secret);
    }
    // The surrounding prose is untouched, so the record still reads.
    expect(stored.startsWith("first ")).toBe(true);
    expect(stored.endsWith(" end")).toBe(true);
  });
});
//: @use-case:end security.redaction.secrets_never_reach_an_append_only_ledger#blackbox
