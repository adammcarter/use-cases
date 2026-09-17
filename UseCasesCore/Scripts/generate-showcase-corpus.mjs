// Regenerates `Tests/UseCasesCoreTests/Showcase/ShowcaseGoldenCorpus.swift` by
// running every case below through the REAL TypeScript in
// `packages/core/dist/showcase` (and the markers keyring and signature code it
// calls), against REAL temporary workspaces, and recording exactly what it
// returns, throws and writes.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-showcase-corpus.mjs
//
// The TypeScript is the oracle (ADR 0007 decision 8). The script refuses to
// run against a `dist` older than its `src`.
//
// Nondeterminism is isolated the way the Swift side injects it: `Date` (both
// `Date.now()` and `new Date()`) reads a clock this script sets per step, and
// `crypto.randomUUID` returns the value this script sets per step, patched into
// the live ESM binding with `syncBuiltinESMExports` BEFORE the core is
// imported. Every key is derived from a constant seed: these are fixtures, not
// secrets. ECDSA signatures are randomised by node, so a regeneration changes
// their bytes but never whether they verify.
//
// Ledger files are carried as TEXT so their key order is exactly what the code
// under test wrote, and the corpus is emitted ASCII-only. Absolute paths are
// replaced by `<workspace>`.
import {
  appendFileSync,
  cpSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync
} from "node:fs";
import { createRequire, syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const coreRoot = join(repositoryRoot, "packages/core");
const testsDirectory = join(packageRoot, "Tests/UseCasesCoreTests/Showcase");

const PORTED = [
  "showcase/appendShowcaseEvent",
  "showcase/approvalToken",
  "showcase/replayRun",
  "showcase/approvalAuthority",
  "showcase/types",
  "showcase/approvalTiers",
  "showcase/approvalBinding",
  "showcase/jsonlLedger",
  "showcase/approvalPolicy",
  "showcase/planBinding",
  "showcase/results",
  "showcase/approval",
  "showcase/revisionEpochs",
  "showcase/startRun",
  "showcase/index",
  "markers/keyring",
  "markers/proofSignature",
  "markers/canonicalJson",
  "durableWrite",
  "redact"
];

for (const name of PORTED) {
  const source = statSync(join(coreRoot, "src", `${name}.ts`)).mtimeMs;
  const built = statSync(join(coreRoot, "dist", `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/${name}.js is older than src; rebuild packages/core first`);
  }
}

// ---------------------------------------------------------------------------
// Isolated nondeterminism: installed before the core is imported
// ---------------------------------------------------------------------------

const RealDate = Date;
let clockMilliseconds = null;
function now() {
  if (clockMilliseconds === null) {
    throw new Error("the clock was read with no fixed instant set");
  }
  return clockMilliseconds;
}
class ControlledDate extends RealDate {
  constructor(...args) {
    if (args.length === 0) {
      super(now());
    } else {
      super(...args);
    }
  }
  static now() {
    return now();
  }
}
globalThis.Date = ControlledDate;

const require = createRequire(import.meta.url);
const nodeCrypto = require("node:crypto");
let fixedUUID = null;
nodeCrypto.randomUUID = () => {
  if (fixedUUID === null) {
    throw new Error("randomUUID was called with no fixed value set");
  }
  return fixedUUID;
};
syncBuiltinESMExports();

const { createECDH, createHash, createPrivateKey, createPublicKey, sign } = nodeCrypto;

const core = await import(join(coreRoot, "dist/index.js"));
const canonicalModule = await import(join(coreRoot, "dist/markers/canonicalJson.js"));
const signatureModule = await import(join(coreRoot, "dist/markers/proofSignature.js"));
const {
  appendShowcaseAction,
  appendShowcaseApproval,
  appendShowcaseEpoch,
  appendShowcaseFailureDecision,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  buildWebAuthnApprovalToken,
  computeApprovalBindingFromEvents,
  computePresentationPlanHash,
  computeRunApprovalBinding,
  correctShowcaseVerdict,
  finishShowcaseRun,
  keyringAssuranceTierResolver,
  keyringResolver,
  keyringWebAuthnCredentialResolver,
  loadPresentationPlanFile,
  loadUseCaseMatrix,
  mintApprovalRequest,
  parseKeyring,
  pauseShowcaseRun,
  readShowcaseEvents,
  rejectShowcaseApproval,
  replayEvidence,
  replayShowcaseRun,
  resolveWorkspaceContext,
  resumeShowcaseRun,
  selectShowcasePlan,
  signApprovalToken,
  startShowcaseRun,
  verifyApprovalToken
} = core;
const { canonicalJson } = canonicalModule;
const { approvalAssuranceFloorForPlan } = await import(join(coreRoot, "dist/showcase/approvalPolicy.js"));
const { signEvent } = signatureModule;

// ---------------------------------------------------------------------------
// Fixture keys from constant seeds
// ---------------------------------------------------------------------------

const seed = (label) => createHash("sha256").update(`showcase-corpus ${label}`).digest();
const base64url = (bytes) => Buffer.from(bytes).toString("base64url");

function ed25519Key(label) {
  const der = Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed(label)]);
  const privateKey = createPrivateKey({ key: der, format: "der", type: "pkcs8" });
  const publicKey = createPublicKey(privateKey);
  return {
    privateKey,
    private_pem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
    public_pem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    spki: base64url(publicKey.export({ type: "spki", format: "der" }))
  };
}

function ecKey(label, curve, opensslCurve) {
  const d = seed(label);
  const ecdh = createECDH(opensslCurve);
  const scalar = curve === "P-521" ? Buffer.concat([Buffer.alloc(34), d]).subarray(-66) : curve === "P-384" ? Buffer.concat([Buffer.alloc(16), d]) : d;
  ecdh.setPrivateKey(scalar);
  const point = ecdh.getPublicKey();
  const size = (point.length - 1) / 2;
  const jwk = {
    kty: "EC",
    crv: curve,
    d: base64url(scalar),
    x: base64url(point.subarray(1, 1 + size)),
    y: base64url(point.subarray(1 + size))
  };
  const privateKey = createPrivateKey({ key: jwk, format: "jwk" });
  const publicKey = createPublicKey(privateKey);
  return { privateKey, spki: base64url(publicKey.export({ type: "spki", format: "der" })) };
}

const KEYS = {
  human: ed25519Key("human ed25519 key"),
  automation: ed25519Key("automation ed25519 key"),
  same_channel: ed25519Key("same channel ed25519 key"),
  stranger: ed25519Key("stranger ed25519 key"),
  webauthn_ed25519: ed25519Key("webauthn ed25519 credential")
};
const EC_KEYS = {
  p256: ecKey("webauthn p256 credential", "P-256", "prime256v1"),
  p384: ecKey("webauthn p384 credential", "P-384", "secp384r1"),
  p521: ecKey("webauthn p521 credential", "P-521", "secp521r1"),
  secp256k1: ecKey("webauthn secp256k1 credential", "secp256k1", "secp256k1")
};

// Ed448 from a constant 57-byte seed: node verifies it, swift-crypto has no Ed448.
const ED448_KEY = (() => {
  const material = Buffer.concat([seed("webauthn ed448 credential a"), seed("webauthn ed448 credential b")]).subarray(0, 57);
  const der = Buffer.concat([Buffer.from("3047020100300506032b6571043b0439", "hex"), material]);
  const privateKey = createPrivateKey({ key: der, format: "der", type: "pkcs8" });
  return { privateKey, spki: base64url(createPublicKey(privateKey).export({ type: "spki", format: "der" })) };
})();
KEYS.webauthn_ed448 = ED448_KEY;

const ed25519Entry = (keyId, key, tier, extra = {}) => ({
  key_id: keyId,
  algorithm: "ed25519",
  public_key: key.public_pem,
  valid_from: "2026-01-01T00:00:00Z",
  valid_until: null,
  status: "active",
  max_assurance_tier: tier,
  ...extra
});
const webauthnEntry = (credentialId, alg, spki, extra = {}) => ({
  credential_id: credentialId,
  algorithm: "webauthn",
  credential_public_key_alg: alg,
  credential_public_key_spki: spki,
  valid_from: "2026-01-01T00:00:00Z",
  valid_until: null,
  status: "active",
  max_assurance_tier: "webauthn_hardware",
  ...extra
});

const KEYRINGS = {
  main: {
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys: [
      ed25519Entry("human-key", KEYS.human, "trusted_host_user_presence"),
      ed25519Entry("automation-key", KEYS.automation, "untrusted_automation"),
      ed25519Entry("same-channel-key", KEYS.same_channel, "same_channel_operator_confirmation"),
      ed25519Entry("expired-key", KEYS.stranger, "trusted_host_user_presence", { valid_until: "2026-02-01T00:00:00Z" }),
      ed25519Entry("revoked-key", KEYS.stranger, "trusted_host_user_presence", { status: "revoked" }),
      webauthnEntry("credential-es256", -7, EC_KEYS.p256.spki),
      webauthnEntry("credential-ed25519", -8, KEYS.webauthn_ed25519.spki),
      webauthnEntry("credential-p256-declared-eddsa", -8, EC_KEYS.p256.spki),
      webauthnEntry("credential-ed25519-declared-es256", -7, KEYS.webauthn_ed25519.spki),
      webauthnEntry("credential-p384", -7, EC_KEYS.p384.spki),
      webauthnEntry("credential-p521", -8, EC_KEYS.p521.spki),
      webauthnEntry("credential-bad-spki", -7, "AAAA"),
      webauthnEntry("credential-revoked", -7, EC_KEYS.p256.spki, { status: "revoked" })
    ]
  }
};
for (const [name, value] of Object.entries(KEYRINGS)) {
  parseKeyring(value, `${name}.json`);
}

function resolversFor(args) {
  const keyring = args.keyring === undefined ? undefined : KEYRINGS[args.keyring];
  return {
    resolver: keyring && args.resolver !== false ? keyringResolver(keyring) : undefined,
    tierResolver: keyring && args.tier_resolver ? keyringAssuranceTierResolver(keyring) : undefined,
    webauthnCredentialResolver: keyring && args.webauthn_resolver ? keyringWebAuthnCredentialResolver(keyring) : undefined
  };
}

// ---------------------------------------------------------------------------
// WebAuthn assertions, signed for real
// ---------------------------------------------------------------------------

const sha256 = (bytes) => createHash("sha256").update(bytes).digest();
const challengeFor = (binding) => base64url(sha256(canonicalJson(binding)));

function assertion(binding, options = {}) {
  const credentialId = options.credential_id ?? "credential-es256";
  const flags = options.flags ?? 0x05;
  const authenticatorData = options.authenticator_data ?? Buffer.concat([sha256("localhost"), Buffer.from([flags]), Buffer.from([0, 0, 0, 1])]);
  const clientData =
    options.client_data_text ??
    JSON.stringify({
      type: options.type ?? "webauthn.get",
      challenge: options.challenge ?? challengeFor(binding),
      origin: "https://localhost",
      crossOrigin: false
    });
  const clientDataBytes = Buffer.from(clientData, "utf8");
  const base = Buffer.concat([authenticatorData, sha256(clientDataBytes)]);
  const signer = options.signer ?? "p256";
  let signature;
  if (signer === "p256" || signer === "p384" || signer === "p521" || signer === "secp256k1") {
    signature = sign("SHA256", base, options.dsa === "p1363" ? { key: EC_KEYS[signer].privateKey, dsaEncoding: "ieee-p1363" } : EC_KEYS[signer].privateKey);
  } else {
    signature = sign(null, base, KEYS[signer].privateKey);
  }
  if (options.mutate_signature) {
    signature = options.mutate_signature(Buffer.from(signature));
  }
  return {
    credential_id: credentialId,
    authenticator_data: options.authenticator_data_text ?? base64url(authenticatorData),
    client_data_json: options.client_data_json_text ?? base64url(clientDataBytes),
    signature: options.signature_text ?? base64url(signature)
  };
}

// ECDSA (r, s) DER with s replaced by n - s: the same signature, high-S.
const P256_ORDER = BigInt("0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
function highS(der) {
  let offset = 2;
  const rLength = der[offset + 1];
  const r = der.subarray(offset + 2, offset + 2 + rLength);
  offset += 2 + rLength;
  const sLength = der[offset + 1];
  const s = BigInt(`0x${der.subarray(offset + 2, offset + 2 + sLength).toString("hex")}`);
  const flipped = P256_ORDER - s;
  let hex = flipped.toString(16);
  if (hex.length % 2) {
    hex = `0${hex}`;
  }
  let sBytes = Buffer.from(hex, "hex");
  if (sBytes[0] & 0x80) {
    sBytes = Buffer.concat([Buffer.from([0]), sBytes]);
  }
  const body = Buffer.concat([Buffer.from([0x02, r.length]), r, Buffer.from([0x02, sBytes.length]), sBytes]);
  return Buffer.concat([Buffer.from([0x30, body.length]), body]);
}

// ---------------------------------------------------------------------------
// Workspaces
// ---------------------------------------------------------------------------

const fixtureRoot = join(repositoryRoot, "tests/fixtures/workspaces/evidence-basic");

function extraRow(id, approvalPolicy) {
  return {
    id,
    title: `Row ${id}`,
    lifecycle: "active",
    value_tier: "critical",
    journey_role: "golden",
    usage_frequency: "common",
    actor: "agent",
    intent: "Exercise the showcase port.",
    preconditions: [],
    trigger: "The showcase runs.",
    scenarios: [{ id: `${id}.main`, kind: "steps", steps: [`Open ${id}`] }],
    observable_outcomes: [`${id} is shown`],
    host_applicability: [{ host_surface: "codex.cli", supported: true }],
    verification_policy: { mode: "none" },
    approval_policy: approvalPolicy
  };
}

const EXTRA_FEATURE = [
  "schema_version: 1",
  "feature:",
  "  id: showcase.extra",
  "  name: Extra showcase rows",
  "  summary: Rows the showcase corpus plans over.",
  "use_cases:",
  ...[
    extraRow("showcase.extra.plain", { mode: "none" }),
    extraRow("showcase.extra.webauthn", {
      mode: "predefined",
      minimum_assurance_tier: "webauthn_hardware",
      requirements: [{ approver_type: "user", minimum_count: 1 }],
      statement: "Hardware approval required."
    }),
    extraRow("showcase.extra.agent", {
      mode: "predefined",
      requirements: [{ approver_type: "agent", minimum_count: 1 }],
      statement: "An agent may approve."
    })
  ].map((item) => `  - ${JSON.stringify(item)}`)
].join("\n") + "\n";

function buildWorkspace() {
  const workspace = realpathSync(mkdtempSync(join(tmpdir(), "showcase-corpus-")));
  cpSync(fixtureRoot, workspace, { recursive: true });
  writeFileSync(join(workspace, "use-cases/showcase-extra.yml"), EXTRA_FEATURE);
  return workspace;
}

function baseTree() {
  const workspace = buildWorkspace();
  try {
    return listTree(workspace).filter((entry) => entry.text !== undefined);
  } finally {
    rmSync(workspace, { recursive: true, force: true });
  }
}

function listTree(root, current = root) {
  const out = [];
  for (const name of readdirSync(current).sort()) {
    const full = join(current, name);
    const stat = lstatSync(full);
    const path = relative(root, full);
    if (stat.isDirectory()) {
      out.push({ path: `${path}/` });
      out.push(...listTree(root, full));
    } else {
      out.push({ path, text: readFileSync(full, "utf8") });
    }
  }
  return out;
}

function tokenized(value, workspace) {
  if (value === undefined) {
    return undefined;
  }
  return JSON.parse(JSON.stringify(value).split(workspace).join("<workspace>"));
}

function thrown(error) {
  return { code: error.code ?? null, message: error.message, name: error.constructor.name };
}

function planFor(context, requestedUseCaseIds, maxItems) {
  const result = selectShowcasePlan({
    context,
    matrix: loadUseCaseMatrix({ context }),
    evidence: replayEvidence({ context }),
    request: {
      audience: "reviewer",
      timeboxSeconds: 3600,
      maxItems,
      hostSurface: "codex.cli",
      requestedUseCaseIds,
      generatedAt: "2026-06-25T12:00:00.000Z",
      freshnessEvaluatedAt: "2026-06-25T12:00:00.000Z"
    }
  });
  if (!result.plan) {
    throw new Error(`no plan for ${requestedUseCaseIds}`);
  }
  const selected = result.plan.selected_items.map((item) => item.use_case_id).sort();
  if (JSON.stringify(selected) !== JSON.stringify([...requestedUseCaseIds].sort())) {
    throw new Error(`plan for ${requestedUseCaseIds} selected ${selected}`);
  }
  return result.plan;
}

const rehashed = (plan, changes) => {
  const changed = { ...structuredClone(plan), ...changes };
  changed.plan_content_hash = computePresentationPlanHash(changed);
  return changed;
};

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------

const T0 = RealDate.parse("2026-06-25T12:00:00.000Z");
const DEFAULT_UUID = "00000000-0000-4000-8000-000000000000";

function actorArguments(args) {
  return {
    actorType: args.actor_type ?? "agent",
    hostSurface: args.host_surface ?? "codex.cli",
    idempotencyKey: args.idempotency_key,
    recordedAt: args.recorded_at
  };
}

function execute(op, args, session) {
  const context = session.context;
  switch (op) {
    case "load_plan_file":
      return loadPresentationPlanFile(join(session.workspace, args.path));
    case "start":
      return startShowcaseRun({
        context,
        plan: session.plans[args.plan],
        controlMode: args.control_mode ?? "agent_led",
        knownGapAcknowledgement: args.known_gap_acknowledgement,
        ...actorArguments(args)
      });
    case "observation":
      return appendShowcaseObservation({ context, runId: args.run_id, planItemId: args.plan_item_id, text: args.text, ...actorArguments(args) });
    case "action":
      return appendShowcaseAction({ context, runId: args.run_id, planItemId: args.plan_item_id, action: args.action, ...actorArguments(args) });
    case "verdict":
      return appendShowcaseVerdict({
        context,
        runId: args.run_id,
        planItemId: args.plan_item_id,
        verdict: args.verdict,
        observationEventIds: args.observation_event_ids,
        ...actorArguments(args)
      });
    case "failure_decision":
      return appendShowcaseFailureDecision({
        context,
        runId: args.run_id,
        verdictEventId: args.verdict_event_id,
        decision: args.decision,
        reason: args.reason,
        ...actorArguments(args)
      });
    case "pause":
      return pauseShowcaseRun({ context, runId: args.run_id, reason: args.reason, ...actorArguments(args) });
    case "resume":
      return resumeShowcaseRun({ context, runId: args.run_id, reason: args.reason, ...actorArguments(args) });
    case "epoch":
      return appendShowcaseEpoch({ context, runId: args.run_id, reason: args.reason, staleItemIds: args.stale_item_ids, ...actorArguments(args) });
    case "finish":
      return finishShowcaseRun({ context, runId: args.run_id, ...actorArguments(args) });
    case "correct":
      return correctShowcaseVerdict({
        context,
        runId: args.run_id,
        targetEventId: args.target_event_id,
        correctedVerdict: args.corrected_verdict,
        reason: args.reason,
        ...actorArguments(args)
      });
    case "approve":
    case "reject": {
      const common = {
        context,
        runId: args.run_id,
        statement: args.statement,
        approvalToken: args.token,
        nowMs: args.now_ms,
        ...resolversFor(args),
        ...actorArguments(args)
      };
      return op === "approve" ? appendShowcaseApproval({ ...common, decision: args.decision }) : rejectShowcaseApproval(common);
    }
    case "replay": {
      const resolvers = resolversFor(args);
      return replayShowcaseRun({
        context,
        runId: args.run_id,
        trustResolver: resolvers.resolver,
        trustTierResolver: resolvers.tierResolver,
        trustWebAuthnCredentialResolver: resolvers.webauthnCredentialResolver
      });
    }
    case "read":
      return readShowcaseEvents(context, args.run_id);
    case "binding":
      return computeRunApprovalBinding({ context, runId: args.run_id });
    case "write_raw": {
      const path = join(context.data_root, "showcase-runs", args.run_id, "events.jsonl");
      mkdirSync(dirname(path), { recursive: true });
      appendFileSync(path, args.text);
      return null;
    }
    default:
      throw new Error(`unknown op ${op}`);
  }
}

function runCase(name, script) {
  const workspace = buildWorkspace();
  const session = {
    workspace,
    context: resolveWorkspaceContext({ workspaceRoot: workspace }),
    plans: {},
    steps: [],
    results: []
  };
  const record = {
    name,
    plans: session.plans,
    steps: session.steps
  };
  const step = (op, args = {}, { clock = T0, uuid = DEFAULT_UUID } = {}) => {
    clockMilliseconds = clock;
    fixedUUID = uuid;
    const entry = { op, args: structuredClone(args), clock_ms: clock };
    let value;
    try {
      value = execute(op, args, session);
      entry.result = value === undefined ? null : structuredClone(value);
    } catch (error) {
      if (error instanceof Error && /unknown op/.test(error.message)) {
        throw error;
      }
      entry.throws = thrown(error);
      value = undefined;
    } finally {
      clockMilliseconds = null;
      fixedUUID = null;
    }
    session.steps.push(entry);
    return value;
  };
  const helpers = {
    step,
    context: session.context,
    plan: (planName, ids, maxItems = ids.length) => {
      clockMilliseconds = T0;
      session.plans[planName] = planFor(session.context, ids, maxItems);
      clockMilliseconds = null;
      return session.plans[planName];
    },
    setPlan: (planName, plan) => {
      session.plans[planName] = plan;
      return plan;
    },
    writePlanFile: (path, value) => {
      const target = join(workspace, path);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, typeof value === "string" ? value : JSON.stringify(value, null, 2));
      record.plan_files = [...(record.plan_files ?? []), { path, text: readFileSync(target, "utf8") }];
    },
    binding: (runId) => {
      clockMilliseconds = T0;
      const value = computeRunApprovalBinding({ context: session.context, runId });
      clockMilliseconds = null;
      return value;
    },
    events: (runId) => readShowcaseEvents(session.context, runId).events
  };
  try {
    script(helpers);
    const runsRoot = join(workspace, "showcase-runs");
    let files = [];
    try {
      files = listTree(runsRoot);
    } catch {
      files = [];
    }
    record.files_after = files;
    return tokenized(record, workspace);
  } finally {
    rmSync(workspace, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

function mint(binding, { nowMs = RealDate.parse("2026-06-25T12:04:00.000Z"), ttlMinutes = 60, jti = "approval.fixed-nonce" } = {}) {
  return mintApprovalRequest({ binding, nowMs, ttlMinutes, jti });
}

function ed25519Token(binding, { decision = "approved", key = "human", keyId = "human-key", method, request } = {}) {
  return signApprovalToken({
    request: request ?? mint(binding),
    decision,
    privateKey: KEYS[key].private_pem,
    keyId,
    assuranceMethod: method
  });
}

function forgedToken(binding, fields, { key = "human", keyId = "human-key" } = {}) {
  const request = mint(binding);
  const unsigned = {
    approval_token_schema: "ucase-approval-token-v1",
    binding: { ...request.binding },
    jti: request.jti,
    iat: request.iat,
    exp: request.exp,
    created_at: request.iat,
    decision: "approved",
    ...fields
  };
  for (const [field, value] of Object.entries(fields)) {
    if (value === undefined) {
      delete unsigned[field];
    }
  }
  return signEvent(unsigned, KEYS[key].private_pem, keyId);
}

function webauthnToken(binding, assertionOptions = {}, { decision = "approved", request, tokenFields = {} } = {}) {
  const token = buildWebAuthnApprovalToken({
    request: request ?? mint(binding),
    decision,
    assertion: assertion(binding, assertionOptions)
  });
  const changed = { ...token, ...tokenFields };
  for (const [field, value] of Object.entries(tokenFields)) {
    if (value === undefined) {
      delete changed[field];
    }
  }
  return changed;
}

// ---------------------------------------------------------------------------
// Run cases
// ---------------------------------------------------------------------------

const LIVE = "showcase.live.golden";
const LIVE_ITEM = "item.showcase.live.golden";
const PLAIN = "showcase.extra.plain";
const PLAIN_ITEM = "item.showcase.extra.plain";
const WEBAUTHN = "showcase.extra.webauthn";
const AGENT = "showcase.extra.agent";

const runCases = [];
const addRun = (name, script) => runCases.push(runCase(name, script));

// A started run with one observation and a pass verdict on every item, finished.
function finishedRun(h, planName, key, items, { recordedAt = "2026-06-25T12:01:00.000Z" } = {}) {
  const started = h.step("start", { plan: planName, idempotency_key: key, recorded_at: recordedAt });
  const runId = started.run_id;
  for (const item of items) {
    const observed = h.step("observation", { run_id: runId, plan_item_id: item, text: `Saw ${item}.`, idempotency_key: `${key}:obs:${item}`, recorded_at: recordedAt });
    h.step("verdict", {
      run_id: runId,
      plan_item_id: item,
      verdict: "pass",
      observation_event_ids: [observed.event.event_id],
      idempotency_key: `${key}:verdict:${item}`,
      recorded_at: recordedAt
    });
  }
  h.step("finish", { run_id: runId, idempotency_key: `${key}:finish`, recorded_at: recordedAt });
  return runId;
}

addRun("plan_file_lifecycle_with_trusted_approval", (h) => {
  const plan = h.plan("live", [LIVE]);
  h.writePlanFile("plans/live.json", plan);
  h.step("load_plan_file", { path: "plans/live.json" });
  const started = h.step("start", { plan: "live", idempotency_key: "cli:start-plan:live", recorded_at: "2026-06-25T12:00:00.000Z" });
  const runId = started.run_id;
  const observed = h.step("observation", {
    run_id: runId,
    plan_item_id: LIVE_ITEM,
    text: "Deployed with password=hunter2hunter2 and token: abc123def456 then sk-abcdefghijklmnop.",
    idempotency_key: "obs-1",
    recorded_at: "2026-06-25T12:00:10.000Z"
  });
  h.step("action", { run_id: runId, plan_item_id: LIVE_ITEM, action: { kind: "click", target: "Start", nested: { z: 1, a: [2, "b"] } }, idempotency_key: "act-1", recorded_at: "2026-06-25T12:00:11.000Z" });
  h.step("verdict", { run_id: runId, plan_item_id: LIVE_ITEM, verdict: "pass", observation_event_ids: ["evt.missing", observed.event.event_id], idempotency_key: "verdict-1", recorded_at: "2026-06-25T12:00:12.000Z" });
  h.step("finish", { run_id: runId, idempotency_key: "finish-1", recorded_at: "2026-06-25T12:00:13.000Z" });
  h.step("replay", { run_id: runId });
  h.step("binding", { run_id: runId });
  const token = ed25519Token(h.binding(runId));
  h.step("approve", { run_id: runId, decision: "approved", actor_type: "user", statement: "Looks right.", idempotency_key: "approve-1", recorded_at: "2026-06-25T12:05:00.000Z", token, keyring: "main", tier_resolver: true, now_ms: RealDate.parse("2026-06-25T12:30:00.000Z") });
  h.step("replay", { run_id: runId, keyring: "main", tier_resolver: true });
  h.step("replay", { run_id: runId, keyring: "main" });
  h.step("replay", { run_id: runId });
  h.step("approve", { run_id: runId, decision: "approved", actor_type: "user", statement: "Looks right.", idempotency_key: "approve-1", token, keyring: "main", tier_resolver: true });
  h.step("approve", { run_id: runId, decision: "approved", actor_type: "user", statement: "Again.", idempotency_key: "approve-2", recorded_at: "2026-06-25T12:06:00.000Z", token, keyring: "main", tier_resolver: true, now_ms: RealDate.parse("2026-06-25T12:30:00.000Z") });
  h.step("observation", { run_id: runId, plan_item_id: LIVE_ITEM, text: "One more look.", idempotency_key: "obs-after", recorded_at: "2026-06-25T12:07:00.000Z" });
  h.step("replay", { run_id: runId, keyring: "main", tier_resolver: true });
  h.step("read", { run_id: runId });
});

addRun("ad_hoc_plan_start_idempotency_and_run_ids", (h) => {
  h.plan("live", [LIVE]);
  const two = h.plan("two", [LIVE, PLAIN]);
  h.step("start", { plan: "live", idempotency_key: "cli:start:showcase.live.golden:1782388800000", recorded_at: "2026-06-25T12:00:00.000Z" });
  h.step("start", { plan: "live", idempotency_key: "cli:start:showcase.live.golden:1782388800000", recorded_at: "2026-06-25T12:09:00.000Z" });
  h.step("start", { plan: "live", idempotency_key: "cli:start:showcase.live.golden:1782388800000", control_mode: "user_led" });
  h.step("start", { plan: "two", idempotency_key: "cli:start:showcase.live.golden:1782388800000" });
  h.step("start", { plan: "live", idempotency_key: "CLI start showcase live golden 1782388800000!" });
  h.step("start", { plan: "live", idempotency_key: "", recorded_at: "2026-06-25T12:00:00.000Z" });
  h.step("start", { plan: "live", idempotency_key: "" }, { clock: RealDate.parse("2026-07-01T08:30:15.250Z") });
  h.step("start", { plan: "live", idempotency_key: "***" });
  h.step("start", { plan: "live", idempotency_key: "Ünïcode Key ✓", host_surface: "claude.cli", actor_type: "user" });
  h.step("observation", { run_id: "run.never_started", plan_item_id: LIVE_ITEM, text: "No start.", idempotency_key: "orphan" }, { clock: RealDate.parse("2026-06-26T00:00:00.001Z") });
  h.step("replay", { run_id: "run.never_started" });
  h.step("replay", { run_id: "run.missing" });
  h.step("read", { run_id: "run.missing" });
  void two;
});

addRun("plan_binding_and_plan_files", (h) => {
  const plan = h.plan("live", [LIVE]);
  h.setPlan("placeholder", { ...structuredClone(plan), plan_content_hash: `sha256:${"0".repeat(64)}` });
  h.setPlan("mismatch", { ...structuredClone(plan), audience: "someone else" });
  h.setPlan("partial_unacknowledged", rehashed(plan, { integrity_acknowledgement_required: true }));
  h.setPlan("partial_truthy_string", rehashed(plan, { integrity_acknowledgement_required: "yes" }));
  h.step("start", { plan: "placeholder", idempotency_key: "p" });
  h.step("start", { plan: "mismatch", idempotency_key: "m" });
  h.step("start", { plan: "partial_unacknowledged", idempotency_key: "u" });
  h.step("start", { plan: "partial_truthy_string", idempotency_key: "u2", known_gap_acknowledgement: { acknowledged: true, gaps: ["partial_due_to_integrity"] }, recorded_at: "2026-06-25T12:00:00.000Z" });
  h.step("start", { plan: "partial_unacknowledged", idempotency_key: "u3", known_gap_acknowledgement: { acknowledged: true, gaps: [] }, recorded_at: "2026-06-25T12:00:00.000Z" });
  h.writePlanFile("plans/good.json", plan);
  h.writePlanFile("plans/not-json.json", "{ nope");
  h.writePlanFile("plans/v2.json", { ...plan, schema_version: 2 });
  h.writePlanFile("plans/no-hash.json", { ...plan, plan_content_hash: 5 });
  h.writePlanFile("plans/array.json", "[1,2]");
  h.writePlanFile("plans/placeholder.json", { ...plan, plan_content_hash: `sha256:${"0".repeat(64)}` });
  h.writePlanFile("plans/mismatch.json", { ...plan, audience: "someone else" });
  h.step("load_plan_file", { path: "plans/good.json" });
  h.step("load_plan_file", { path: "plans/missing.json" });
  h.step("load_plan_file", { path: "plans/not-json.json" });
  h.step("load_plan_file", { path: "plans" });
  h.step("load_plan_file", { path: "plans/v2.json" });
  h.step("load_plan_file", { path: "plans/no-hash.json" });
  h.step("load_plan_file", { path: "plans/array.json" });
  h.step("load_plan_file", { path: "plans/placeholder.json" });
  h.step("load_plan_file", { path: "plans/mismatch.json" });
});

addRun("verdicts_failure_decisions_and_the_finish_gate", (h) => {
  h.plan("two", [LIVE, PLAIN]);
  const runId = h.step("start", { plan: "two", idempotency_key: "gate", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  const liveObservation = h.step("observation", { run_id: runId, plan_item_id: LIVE_ITEM, text: "Live seen.", idempotency_key: "o1", recorded_at: "2026-06-25T12:00:01.000Z" }).event.event_id;
  const plainObservation = h.step("observation", { run_id: runId, plan_item_id: PLAIN_ITEM, text: "Plain seen.", idempotency_key: "o2", recorded_at: "2026-06-25T12:00:02.000Z" }).event.event_id;
  h.step("verdict", { run_id: runId, plan_item_id: LIVE_ITEM, verdict: "fail", observation_event_ids: [plainObservation], idempotency_key: "v-wrong-item" });
  h.step("verdict", { run_id: runId, plan_item_id: LIVE_ITEM, verdict: "fail", observation_event_ids: [], idempotency_key: "v-none" });
  const failVerdict = h.step("verdict", { run_id: runId, plan_item_id: LIVE_ITEM, verdict: "fail", observation_event_ids: [liveObservation], idempotency_key: "v1", recorded_at: "2026-06-25T12:00:03.000Z" }).event.event_id;
  const blockedVerdict = h.step("verdict", { run_id: runId, plan_item_id: PLAIN_ITEM, verdict: "blocked", observation_event_ids: [plainObservation], idempotency_key: "v2", recorded_at: "2026-06-25T12:00:04.000Z" }).event.event_id;
  h.step("finish", { run_id: runId, idempotency_key: "finish-early" });
  h.step("failure_decision", { run_id: runId, verdict_event_id: liveObservation, decision: "continue", reason: "Not a verdict.", idempotency_key: "fd-bad-target" });
  h.step("failure_decision", { run_id: runId, verdict_event_id: "evt.nowhere", decision: "continue", reason: "Missing.", idempotency_key: "fd-missing" });
  h.step("failure_decision", { run_id: runId, verdict_event_id: failVerdict, decision: "continue", reason: "Known flake, api_key=abcdef123456 stays in the ledger.", idempotency_key: "fd1", recorded_at: "2026-06-25T12:00:05.000Z" });
  h.step("finish", { run_id: runId, idempotency_key: "finish-still-early" });
  h.step("failure_decision", { run_id: runId, verdict_event_id: blockedVerdict, decision: "waive_with_reason", reason: "Out of scope.", idempotency_key: "fd2", recorded_at: "2026-06-25T12:00:06.000Z" });
  h.step("replay", { run_id: runId });
  h.step("finish", { run_id: runId, idempotency_key: "finish-1", recorded_at: "2026-06-25T12:00:07.000Z" });
  h.step("finish", { run_id: runId, idempotency_key: "finish-1", recorded_at: "2026-06-25T12:00:07.000Z" });
  h.step("finish", { run_id: runId, idempotency_key: "finish-1", recorded_at: "2026-06-25T12:00:08.000Z" });
  h.step("finish", { run_id: runId, idempotency_key: "finish-1", recorded_at: "2026-06-25T12:00:07.000Z", actor_type: "user" });
  const passObservation = h.step("observation", { run_id: runId, plan_item_id: LIVE_ITEM, text: "Retry.", idempotency_key: "o3", recorded_at: "2026-06-25T12:00:09.000Z" }).event.event_id;
  const passVerdict = h.step("verdict", { run_id: runId, plan_item_id: LIVE_ITEM, verdict: "pass", observation_event_ids: [passObservation], idempotency_key: "v3", recorded_at: "2026-06-25T12:00:10.000Z" }).event.event_id;
  h.step("failure_decision", { run_id: runId, verdict_event_id: passVerdict, decision: "continue", reason: "A pass.", idempotency_key: "fd-pass" });
  h.step("replay", { run_id: runId });
});

addRun("verdict_kinds_and_outcomes", (h) => {
  h.plan("live", [LIVE]);
  h.plan("two", [LIVE, PLAIN]);
  const outcome = (key, plan, verdicts, decision) => {
    const runId = h.step("start", { plan, idempotency_key: key, recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
    const items = plan === "two" ? [LIVE_ITEM, PLAIN_ITEM] : [LIVE_ITEM];
    items.forEach((item, index) => {
      const verdict = verdicts[index];
      if (verdict === undefined) {
        return;
      }
      const observation = h.step("observation", { run_id: runId, plan_item_id: item, text: "Seen.", idempotency_key: `${key}-o${index}`, recorded_at: "2026-06-25T12:00:01.000Z" }).event.event_id;
      const verdictId = h.step("verdict", { run_id: runId, plan_item_id: item, verdict, observation_event_ids: [observation], idempotency_key: `${key}-v${index}`, recorded_at: "2026-06-25T12:00:02.000Z" }).event.event_id;
      if (decision && (verdict === "fail" || verdict === "blocked")) {
        h.step("failure_decision", { run_id: runId, verdict_event_id: verdictId, decision, reason: "Decided.", idempotency_key: `${key}-d${index}`, recorded_at: "2026-06-25T12:00:03.000Z" });
      }
    });
    h.step("finish", { run_id: runId, idempotency_key: `${key}-finish`, recorded_at: "2026-06-25T12:00:04.000Z" });
    h.step("replay", { run_id: runId });
  };
  outcome("all-pass", "two", ["pass", "pass"]);
  outcome("partial", "live", ["partial"]);
  outcome("waived-verdict", "live", ["waived"]);
  outcome("one-unjudged", "two", ["pass"]);
  outcome("fail-continue", "two", ["fail", "pass"], "continue");
  outcome("blocked-and-fail", "two", ["fail", "blocked"], "continue");
  outcome("pause-to-fix", "live", ["fail"], "pause_to_fix");
  outcome("abort", "live", ["blocked"], "abort");
  outcome("waive", "two", ["pass", "blocked"], "waive_with_reason");
  const unperformed = h.step("start", { plan: "live", idempotency_key: "only-action", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  h.step("replay", { run_id: unperformed });
  h.step("action", { run_id: unperformed, plan_item_id: "item.elsewhere", action: {}, idempotency_key: "only-action-a", recorded_at: "2026-06-25T12:00:01.000Z" });
  h.step("replay", { run_id: unperformed });
});

addRun("pause_resume_and_corrections", (h) => {
  h.plan("two", [LIVE, PLAIN]);
  const runId = h.step("start", { plan: "two", idempotency_key: "corrections", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  const observation = h.step("observation", { run_id: runId, plan_item_id: LIVE_ITEM, text: "Seen.", idempotency_key: "o1", recorded_at: "2026-06-25T12:00:01.000Z" }).event.event_id;
  h.step("pause", { run_id: runId, reason: "Coffee.", idempotency_key: "p1", recorded_at: "2026-06-25T12:00:02.000Z" });
  h.step("replay", { run_id: runId });
  h.step("resume", { run_id: runId, reason: "Back.", idempotency_key: "r1", recorded_at: "2026-06-25T12:00:03.000Z" });
  h.step("replay", { run_id: runId });
  const failed = h.step("verdict", { run_id: runId, plan_item_id: LIVE_ITEM, verdict: "fail", observation_event_ids: [observation], idempotency_key: "v1", recorded_at: "2026-06-25T12:00:04.000Z" }).event.event_id;
  h.step("correct", { run_id: runId, target_event_id: observation, corrected_verdict: "pass", reason: "Wrong target.", idempotency_key: "c-bad" });
  h.step("correct", { run_id: runId, target_event_id: "evt.none", corrected_verdict: "pass", reason: "Missing.", idempotency_key: "c-missing" });
  const corrected = h.step("correct", { run_id: runId, target_event_id: failed, corrected_verdict: "blocked", reason: "Actually blocked.", idempotency_key: "c1", recorded_at: "2026-06-25T12:00:05.000Z", actor_type: "user" }).event.event_id;
  h.step("replay", { run_id: runId });
  h.step("correct", { run_id: runId, target_event_id: corrected, corrected_verdict: "pass", reason: "Correcting a correction.", idempotency_key: "c-of-c" });
  h.step("failure_decision", { run_id: runId, verdict_event_id: failed, decision: "continue", reason: "Old verdict.", idempotency_key: "d-old", recorded_at: "2026-06-25T12:00:06.000Z" });
  h.step("replay", { run_id: runId });
  h.step("failure_decision", { run_id: runId, verdict_event_id: corrected, decision: "pause_to_fix", reason: "Fix it.", idempotency_key: "d1", recorded_at: "2026-06-25T12:00:07.000Z" });
  h.step("replay", { run_id: runId });
  h.step("resume", { run_id: runId, reason: "Fixed.", idempotency_key: "r2", recorded_at: "2026-06-25T12:00:08.000Z" });
  h.step("correct", { run_id: runId, target_event_id: failed, corrected_verdict: "pass", reason: "Passed after all.", idempotency_key: "c2", recorded_at: "2026-06-25T12:00:09.000Z" });
  h.step("finish", { run_id: runId, idempotency_key: "f1", recorded_at: "2026-06-25T12:00:10.000Z" });
  h.step("replay", { run_id: runId });
});

addRun("epochs_stale_items_and_literals", (h) => {
  h.plan("two", [LIVE, PLAIN]);
  const runId = finishedRun(h, "two", "epochs", [LIVE_ITEM, PLAIN_ITEM]);
  h.step("replay", { run_id: runId });
  h.step("epoch", { run_id: runId, reason: "workspace_changed", stale_item_ids: [LIVE_ITEM, "item.unknown"], idempotency_key: "e1", recorded_at: "2026-06-25T12:10:00.000Z" });
  h.step("replay", { run_id: runId });
  h.step("epoch", { run_id: runId, reason: "workspace_changed", stale_item_ids: [PLAIN_ITEM], idempotency_key: "e2", recorded_at: "2026-06-25T12:11:00.000Z" });
  h.step("epoch", { run_id: runId, reason: "workspace_changed", stale_item_ids: [PLAIN_ITEM], idempotency_key: "e2", recorded_at: "2026-06-25T12:11:00.000Z" });
  h.step("epoch", { run_id: runId, reason: "workspace_changed", stale_item_ids: [LIVE_ITEM], idempotency_key: "e2", recorded_at: "2026-06-25T12:11:00.000Z" });
  h.step("replay", { run_id: runId });
  const observation = h.step("observation", { run_id: runId, plan_item_id: LIVE_ITEM, text: "Seen again.", idempotency_key: "o-after", recorded_at: "2026-06-25T12:12:00.000Z" }).event.event_id;
  h.step("verdict", { run_id: runId, plan_item_id: LIVE_ITEM, verdict: "pass", observation_event_ids: [observation], idempotency_key: "v-after", recorded_at: "2026-06-25T12:13:00.000Z" });
  h.step("replay", { run_id: runId });
  h.step("epoch", { run_id: runId, reason: "workspace_changed", stale_item_ids: [], idempotency_key: "e3", recorded_at: "2026-06-25T12:14:00.000Z" });
  h.step("read", { run_id: runId });
});

addRun("damaged_ledgers", (h) => {
  h.plan("live", [LIVE]);
  const torn = finishedRun(h, "live", "torn", [LIVE_ITEM]);
  h.step("write_raw", { run_id: torn, text: '{"schema_version":1,"event_type":"observation_rec' });
  h.step("read", { run_id: torn });
  h.step("replay", { run_id: torn });
  h.step("observation", { run_id: torn, plan_item_id: LIVE_ITEM, text: "Refused.", idempotency_key: "refused" });
  h.step("finish", { run_id: torn, idempotency_key: "torn:finish" });
  h.step("start", { plan: "live", idempotency_key: "torn", recorded_at: "2026-06-25T12:01:00.000Z" });
  h.step("binding", { run_id: torn });

  const tornWithNewline = finishedRun(h, "live", "torn-newline", [LIVE_ITEM]);
  h.step("write_raw", { run_id: tornWithNewline, text: '{"schema_version":1,"event_type":"observation_rec\n' });
  h.step("read", { run_id: tornWithNewline });
  h.step("replay", { run_id: tornWithNewline });

  const middle = h.step("start", { plan: "live", idempotency_key: "middle", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  h.step("write_raw", { run_id: middle, text: "{not json\n" });
  h.step("observation", { run_id: middle, plan_item_id: LIVE_ITEM, text: "Refused.", idempotency_key: "middle-refused" });
  h.step("write_raw", { run_id: middle, text: `${JSON.stringify({ event_type: "observation_recorded", event_id: "evt.late", sequence: 9, payload: { plan_item_id: LIVE_ITEM } })}\n` });
  h.step("read", { run_id: middle });
  h.step("replay", { run_id: middle });
  h.step("start", { plan: "live", idempotency_key: "middle", recorded_at: "2026-06-25T12:00:00.000Z" });

  const blank = h.step("start", { plan: "live", idempotency_key: "blank", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  h.step("write_raw", { run_id: blank, text: "\n   \n\t\n" });
  h.step("observation", { run_id: blank, plan_item_id: LIVE_ITEM, text: "After blanks.", idempotency_key: "blank-o", recorded_at: "2026-06-25T12:00:01.000Z" });
  h.step("read", { run_id: blank });

  const crlf = h.step("start", { plan: "live", idempotency_key: "crlf", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  h.step("write_raw", { run_id: crlf, text: `${JSON.stringify({ event_type: "run_paused", event_id: "evt.crlf", sequence: 2, idempotency_key: "k" })}\r\n` });
  h.step("read", { run_id: crlf });
  h.step("replay", { run_id: crlf });

  const unterminatedValid = h.step("start", { plan: "live", idempotency_key: "unterminated", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  h.step("write_raw", { run_id: unterminatedValid, text: JSON.stringify({ event_type: "run_paused", event_id: "evt.u", sequence: 2 }) });
  h.step("read", { run_id: unterminatedValid });
  h.step("pause", { run_id: unterminatedValid, reason: "Joined onto the line.", idempotency_key: "u-p", recorded_at: "2026-06-25T12:00:01.000Z" });
  h.step("read", { run_id: unterminatedValid });
  h.step("replay", { run_id: unterminatedValid });

  h.step("write_raw", { run_id: "run.only_torn", text: "{" });
  h.step("read", { run_id: "run.only_torn" });
  h.step("start", { plan: "live", idempotency_key: "only torn", recorded_at: "2026-06-25T12:00:00.000Z" });
  h.step("write_raw", { run_id: "run.empty_file", text: "" });
  h.step("read", { run_id: "run.empty_file" });
  h.step("start", { plan: "live", idempotency_key: "empty file", recorded_at: "2026-06-25T12:00:00.000Z" });
});

addRun("foreign_json_lines", (h) => {
  h.plan("live", [LIVE]);
  h.plan("two", [LIVE, PLAIN]);
  const runId = h.step("start", { plan: "two", idempotency_key: "foreign", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  const lines = [
    { event_type: "observation_recorded", event_id: 42, sequence: "3", payload: { plan_item_id: LIVE_ITEM } },
    { event_type: "verdict_recorded", event_id: "evt.v", sequence: 2.5, payload: { plan_item_id: LIVE_ITEM, verdict: "fail" } },
    { event_type: "verdict_recorded", payload: { plan_item_id: PLAIN_ITEM, verdict: "blocked" }, sequence: 7 },
    { event_type: "verdict_recorded", payload: { plan_item_id: PLAIN_ITEM, verdict: "blocked" }, sequence: 8 },
    { event_type: "failure_decision_recorded", sequence: 9, payload: { verdict_event_id: 42 } },
    { event_type: "epoch_started", sequence: 10, payload: { stale_item_ids: "item" } },
    { event_type: "action_recorded", sequence: -1, payload: {} },
    { event_type: "approval_rejected", event_id: "evt.agent-reject", actor_type: "agent", sequence: 11, payload: {} },
    { event_type: "approval_recorded", event_id: "evt.user-approve", actor_type: "user", sequence: 12, payload: { approval_token: { approval_token_schema: "ucase-approval-token-v1" } } },
    { event_type: "approval_rejected", event_id: "evt.user-reject", actor_type: "user", sequence: 13, payload: {} },
    [1, 2],
    "a string line",
    7
  ];
  h.step("write_raw", { run_id: runId, text: lines.map((line) => JSON.stringify(line)).join("\n") + "\n" });
  h.step("read", { run_id: runId });
  h.step("replay", { run_id: runId });
  h.step("pause", { run_id: runId, reason: "Foreign lines are counted.", idempotency_key: "foreign-pause", recorded_at: "2026-06-25T12:00:01.000Z" });
  h.step("replay", { run_id: runId });

  const nullLine = h.step("start", { plan: "live", idempotency_key: "null line", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  h.step("write_raw", { run_id: nullLine, text: "null\n" });
  h.step("read", { run_id: nullLine });
  h.step("replay", { run_id: nullLine });
  h.step("pause", { run_id: nullLine, reason: "A null line.", idempotency_key: "null-pause" });
  h.step("start", { plan: "live", idempotency_key: "null line", recorded_at: "2026-06-25T12:00:00.000Z" });

  h.step("write_raw", { run_id: "run.lone_null", text: "null\n" });
  h.step("replay", { run_id: "run.lone_null" });

  const unordered = h.step("start", { plan: "live", idempotency_key: "unordered", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  h.step("write_raw", {
    run_id: unordered,
    text: [
      { event_type: "verdict_recorded", event_id: "evt.late-pass", sequence: 30, payload: { plan_item_id: LIVE_ITEM, verdict: "pass" } },
      { event_type: "verdict_recorded", event_id: "evt.early-fail", sequence: 20, payload: { plan_item_id: LIVE_ITEM, verdict: "fail" } },
      { event_type: "observation_recorded", event_id: "evt.obs-b", sequence: 20, payload: { plan_item_id: LIVE_ITEM } },
      { event_type: "run_finished", event_id: "evt.finish-a", sequence: 40, payload: {} },
      { event_type: "run_finished", event_id: "evt.finish-b", sequence: 40, payload: {} }
    ]
      .map((line) => JSON.stringify(line))
      .join("\n") + "\n"
  });
  h.step("replay", { run_id: unordered });
  h.step("binding", { run_id: unordered });
});

addRun("plan_shapes_in_replay", (h) => {
  const plan = h.plan("live", [LIVE]);
  const lines = (planValue, extra = []) =>
    [{ event_type: "run_started", event_id: "evt.s", sequence: 1, payload: { plan: planValue, plan_content_hash: "sha256:x" } }, ...extra].map((line) => JSON.stringify(line)).join("\n") + "\n";
  const performed = { event_type: "observation_recorded", event_id: "evt.o", sequence: 2, payload: { plan_item_id: LIVE_ITEM } };
  const variants = {
    "run.no_plan": lines(undefined),
    "run.null_plan": lines(null),
    "run.no_items": lines({ known_gaps: [{ code: "prepared_not_performed" }, { code: "other" }] }),
    "run.no_items_performed": lines({ known_gaps: [{ code: "prepared_not_performed" }, { code: "other" }] }, [performed]),
    "run.gaps_not_array": lines({ known_gaps: "gaps" }),
    "run.item_without_id": lines({ selected_items: [{ approval_policy_snapshot: { mode: "none" } }] }),
    "run.duplicate_item_ids": lines({ selected_items: [{ plan_item_id: LIVE_ITEM, approval_policy_snapshot: { mode: "none" } }, { plan_item_id: LIVE_ITEM, approval_policy_snapshot: { mode: "none" } }] }, [performed]),
    "run.floor_webauthn": lines({
      selected_items: [
        { plan_item_id: "a", approval_policy_snapshot: { mode: "predefined", requirements: [{ approver_type: "user" }], minimum_assurance_tier: "same_channel_operator_confirmation" } },
        { plan_item_id: "b", approval_policy_snapshot: { mode: "predefined", requirements: [null, { approver_type: "user" }], minimum_assurance_tier: "webauthn_hardware" } },
        { plan_item_id: "c", approval_policy_snapshot: { mode: "predefined", requirements: "user", minimum_assurance_tier: "bogus" } }
      ]
    }),
    "run.real_plan": lines(plan, [performed]),
    "run.gaps_not_array_performed": lines({ known_gaps: "gaps" }, [performed]),
    "run.gap_null_performed": lines({ known_gaps: [null] }, [performed]),
    "run.items_not_array": lines({ selected_items: "items" }),
    "run.item_null": lines({ selected_items: [null] }),
    "run.snapshot_missing": lines({ selected_items: [{ plan_item_id: "a" }] }),
    "run.requirement_null": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "predefined", requirements: [null] } }] }),
    "run.start_without_payload": [{ event_type: "run_started", event_id: "evt.s", sequence: 1 }].map((line) => JSON.stringify(line)).join("\n") + "\n",
    "run.stale_ids_number": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }] }, [{ event_type: "epoch_started", sequence: 2, payload: { stale_item_ids: 5 } }]),
    "run.stale_ids_null": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }] }, [{ event_type: "epoch_started", sequence: 2, payload: { stale_item_ids: null } }]),
    "run.stale_ids_string_matches_code_points": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }, { plan_item_id: "\u{1F600}", approval_policy_snapshot: { mode: "none" } }] }, [{ event_type: "epoch_started", sequence: 2, payload: { stale_item_ids: "a\u{1F600}" } }]),
    "run.event_without_payload": lines({ selected_items: [] }, [{ event_type: "observation_recorded", event_id: "evt.o", sequence: 2 }]),
    "run.sequences_mixed": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }] }, [
      { event_type: "verdict_recorded", event_id: "v-str", sequence: "10", payload: { plan_item_id: "a", verdict: "pass" } },
      { event_type: "verdict_recorded", event_id: "v-nine", sequence: 9, payload: { plan_item_id: "a", verdict: "fail" } },
      { event_type: "verdict_recorded", event_id: "v-null", sequence: null, payload: { plan_item_id: "a", verdict: "blocked" } },
      { event_type: "verdict_recorded", event_id: "v-arr", sequence: [11], payload: { plan_item_id: "a", verdict: "partial" } },
      { event_type: "verdict_recorded", event_id: "v-bool", sequence: true, payload: { plan_item_id: "a", verdict: "waived" } }
    ]),
    "run.sequences_nan": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }] }, [
      { event_type: "verdict_recorded", event_id: "v-5", sequence: 5, payload: { plan_item_id: "a", verdict: "pass" } },
      { event_type: "verdict_recorded", event_id: "v-x", sequence: "x", payload: { plan_item_id: "a", verdict: "fail" } },
      { event_type: "verdict_recorded", event_id: "v-3", sequence: 3, payload: { plan_item_id: "a", verdict: "blocked" } },
      { event_type: "verdict_recorded", event_id: "v-obj", sequence: {}, payload: { plan_item_id: "a", verdict: "partial" } },
      { event_type: "verdict_recorded", event_id: "v-4", sequence: 4, payload: { plan_item_id: "a", verdict: "waived" } }
    ]),
    "run.sequences_nan_descending_run": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }] },
      [9, 8, "x", 7, 6, {}, 12, 11, "y", 3, 2].map((sequence, index) => ({ event_type: "verdict_recorded", event_id: `v${index}`, sequence, payload: { plan_item_id: "a", verdict: ["pass", "fail", "blocked", "partial", "waived"][index % 5] } }))
    ).replace(/"sequence":1,/, '"sequence":99,'),
    "run.sequences_nan_ascending_run": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }] },
      [2, 3, "x", 4, 1, {}, 8, 7, null, "5", [6]].map((sequence, index) => ({ event_type: "verdict_recorded", event_id: `w${index}`, sequence, payload: { plan_item_id: "a", verdict: ["pass", "fail", "blocked", "partial", "waived"][index % 5] } }))
    ),
    "run.sequences_nan_seventy_events": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }] },
      Array.from({ length: 70 }, (_, index) => ({
        event_type: "verdict_recorded",
        event_id: `s${index}`,
        sequence: index % 9 === 4 ? "x" : index % 11 === 7 ? {} : (index * 37) % 71,
        payload: { plan_item_id: "a", verdict: ["pass", "fail", "blocked", "partial", "waived"][index % 5] }
      }))
    ),
    "run.approval_sequence_strings": lines({ selected_items: [{ plan_item_id: "a", approval_policy_snapshot: { mode: "none" } }] }, [
      { event_type: "approval_rejected", event_id: "r", actor_type: "agent", sequence: "9", payload: {} },
      { event_type: "observation_recorded", event_id: "o", sequence: "10", payload: { plan_item_id: "a" } }
    ])
  };
  for (const [runId, text] of Object.entries(variants)) {
    h.step("write_raw", { run_id: runId, text });
    h.step("replay", { run_id: runId });
  }
  h.step("approve", { run_id: "run.items_not_array", decision: "approved", actor_type: "agent", statement: "Crashes on the plan.", idempotency_key: "x" });
  h.step("approve", { run_id: "run.start_without_payload", decision: "approved", actor_type: "agent", statement: "Crashes on the payload.", idempotency_key: "x" });
  h.step("binding", { run_id: "run.start_without_payload" });
  h.step("write_raw", { run_id: "run.finished_null_plan", text: [{ event_type: "run_started", event_id: "s", sequence: 1, payload: { plan: "a string plan" } }, { event_type: "run_finished", event_id: 7, sequence: 2 }].map((line) => JSON.stringify(line)).join("\n") + "\n" });
  h.step("approve", { run_id: "run.finished_null_plan", decision: "approved", actor_type: "agent", statement: "String plan.", idempotency_key: "y", recorded_at: "2026-06-25T12:00:00.000Z" });
  h.step("binding", { run_id: "run.finished_null_plan" });
});

addRun("approval_gates_without_tokens", (h) => {
  h.plan("live", [LIVE]);
  h.plan("plain", [PLAIN]);
  h.plan("agent", [AGENT]);
  const unfinished = h.step("start", { plan: "plain", idempotency_key: "unfinished", recorded_at: "2026-06-25T12:00:00.000Z" }).run_id;
  h.step("approve", { run_id: unfinished, decision: "approved", actor_type: "agent", statement: "Too early.", idempotency_key: "a0" });
  h.step("binding", { run_id: unfinished });
  const live = finishedRun(h, "live", "live-gates", [LIVE_ITEM]);
  h.step("approve", { run_id: live, decision: "approved", actor_type: "agent", statement: "Agent tries.", idempotency_key: "a1" });
  h.step("reject", { run_id: live, actor_type: "script", statement: "Script tries.", idempotency_key: "a2" });
  h.step("approve", { run_id: live, decision: "approved", actor_type: "user", statement: "No token.", idempotency_key: "a3" });
  h.step("approve", { run_id: live, decision: "approved", actor_type: "user", statement: "Null token.", idempotency_key: "a3b", token: null });
  const plain = finishedRun(h, "plain", "plain-gates", [PLAIN_ITEM]);
  h.step("approve", { run_id: plain, decision: "approved_with_known_gaps", actor_type: "agent", statement: "Agent approves.", idempotency_key: "b1", recorded_at: "2026-06-25T12:02:00.000Z" });
  h.step("approve", { run_id: plain, decision: "approved", actor_type: "user", statement: "Same channel.", idempotency_key: "b2", recorded_at: "2026-06-25T12:03:00.000Z" });
  h.step("reject", { run_id: plain, actor_type: "user", statement: "Changed my mind.", idempotency_key: "b3", recorded_at: "2026-06-25T12:04:00.000Z" });
  h.step("reject", { run_id: plain, actor_type: "agent", statement: "Agent rejects.", idempotency_key: "b4" }, { clock: RealDate.parse("2026-06-25T12:05:06.789Z") });
  h.step("replay", { run_id: plain });
  const agent = finishedRun(h, "agent", "agent-gates", ["item.showcase.extra.agent"]);
  h.step("approve", { run_id: agent, decision: "approved", actor_type: "agent", statement: "Agent-approvable.", idempotency_key: "c1", recorded_at: "2026-06-25T12:02:00.000Z" });
  h.step("finish", { run_id: agent, idempotency_key: "agent-gates:finish-2", recorded_at: "2026-06-25T12:03:00.000Z" });
  h.step("approve", { run_id: agent, decision: "approved", actor_type: "system", statement: "Scope from the latest finish.", idempotency_key: "c2", recorded_at: "2026-06-25T12:04:00.000Z" });
  h.step("replay", { run_id: agent });
});

addRun("ed25519_token_rejections", (h) => {
  h.plan("live", [LIVE]);
  h.plan("plain", [PLAIN]);
  const runId = finishedRun(h, "live", "tokens", [LIVE_ITEM]);
  const other = finishedRun(h, "plain", "other-run", [PLAIN_ITEM]);
  const binding = h.binding(runId);
  const inWindow = RealDate.parse("2026-06-25T12:30:00.000Z");
  const attempt = (key, token, extra = {}) =>
    h.step("approve", { run_id: runId, decision: "approved", actor_type: "user", statement: `Attempt ${key}.`, idempotency_key: key, recorded_at: "2026-06-25T12:10:00.000Z", token, keyring: "main", tier_resolver: true, now_ms: inWindow, ...extra });
  attempt("unknown-key", ed25519Token(binding, { key: "stranger", keyId: "stranger-key" }));
  attempt("wrong-key", ed25519Token(binding, { key: "stranger", keyId: "human-key" }));
  attempt("expired-key-window", ed25519Token(binding, { key: "stranger", keyId: "expired-key" }));
  attempt("revoked-key", ed25519Token(binding, { key: "stranger", keyId: "revoked-key" }));
  attempt("expired", ed25519Token(binding), { now_ms: RealDate.parse("2026-06-25T13:04:00.001Z") });
  attempt("wrong-run", ed25519Token(h.binding(other)));
  attempt("wrong-binding", ed25519Token({ ...binding, ledger_head_hash: "sha256:stale" }));
  attempt("tampered-after-signing", { ...ed25519Token(binding), decision: "approved_with_known_gaps" });
  attempt("tier-mismatch", forgedToken(binding, { assurance_method: "os_presence", assurance_tier: "webauthn_hardware" }));
  attempt("tier-missing", forgedToken(binding, { assurance_method: "os_presence" }));
  attempt("method-unknown", forgedToken(binding, { assurance_method: "retina" }));
  attempt("method-webauthn-on-ed25519", forgedToken(binding, { assurance_method: "webauthn", assurance_tier: "webauthn_hardware" }));
  attempt("over-claim", ed25519Token(binding, { key: "automation", keyId: "automation-key", method: "os_presence" }));
  attempt("legacy-at-cap-too-low", ed25519Token(binding, { key: "same_channel", keyId: "same-channel-key" }));
  attempt("too-low", ed25519Token(binding, { method: "same_channel" }));
  attempt("no-tier-resolver", ed25519Token(binding), { tier_resolver: false });
  attempt("no-resolver", ed25519Token(binding), { keyring: undefined });
  attempt("rejected-token-cannot-approve", ed25519Token(binding, { decision: "rejected" }));
  h.step("reject", { run_id: runId, actor_type: "user", statement: "Approval token on reject.", idempotency_key: "approved-token-cannot-reject", token: ed25519Token(binding), keyring: "main", tier_resolver: true, now_ms: inWindow });
  attempt("malformed-no-schema", { ...ed25519Token(binding), approval_token_schema: "v0" });
  attempt("malformed-empty-jti", forgedToken(binding, { jti: "" }));
  attempt("malformed-no-binding", forgedToken(binding, { binding: undefined }));
  attempt("malformed-decision", forgedToken(binding, { decision: 1 }));
  attempt("unsigned", { ...ed25519Token(binding), signature: undefined });
  attempt("alg-unsupported", { ...ed25519Token(binding), signature: { ...ed25519Token(binding).signature, alg: "rsa" } });
  attempt("expiry-not-a-date", forgedToken(binding, { exp: "soon" }));
  attempt("expiry-exactly-now", ed25519Token(binding), { now_ms: RealDate.parse("2026-06-25T13:04:00.000Z"), idempotency_key: "exact" });
  h.step("replay", { run_id: runId, keyring: "main", tier_resolver: true });
  attempt("replayed-jti", ed25519Token(binding), { idempotency_key: "replayed" });
  const burned = ed25519Token(h.binding(runId), { request: mint(h.binding(runId), { jti: "approval.second" }) });
  attempt("replayed-jti-rebound", { ...burned, jti: "approval.fixed-nonce" });
  attempt("fresh-jti-after-approval", burned, { idempotency_key: "fresh" });
  h.step("read", { run_id: runId });
});

addRun("rejection_with_a_signed_token", (h) => {
  h.plan("live", [LIVE]);
  const runId = finishedRun(h, "live", "reject-signed", [LIVE_ITEM]);
  const token = ed25519Token(h.binding(runId), { decision: "rejected", method: "os_presence" });
  h.step("reject", { run_id: runId, actor_type: "user", statement: "No.", idempotency_key: "r1", recorded_at: "2026-06-25T12:10:00.000Z", token, keyring: "main", tier_resolver: true, now_ms: RealDate.parse("2026-06-25T12:30:00.000Z") });
  h.step("replay", { run_id: runId, keyring: "main", tier_resolver: true });
  h.step("replay", { run_id: runId, keyring: "main" });
  h.step("replay", { run_id: runId });
});

addRun("webauthn_approvals", (h) => {
  h.plan("webauthn", [WEBAUTHN]);
  const inWindow = RealDate.parse("2026-06-25T12:30:00.000Z");
  const p256 = finishedRun(h, "webauthn", "webauthn-p256", ["item.showcase.extra.webauthn"]);
  h.step("approve", {
    run_id: p256,
    decision: "approved",
    actor_type: "user",
    statement: "Touched the key.",
    idempotency_key: "w1",
    recorded_at: "2026-06-25T12:10:00.000Z",
    token: webauthnToken(h.binding(p256)),
    keyring: "main",
    tier_resolver: true,
    webauthn_resolver: true,
    now_ms: inWindow
  });
  h.step("replay", { run_id: p256, keyring: "main", tier_resolver: true, webauthn_resolver: true });
  h.step("replay", { run_id: p256, keyring: "main", tier_resolver: true });
  const ed = finishedRun(h, "webauthn", "webauthn-ed25519", ["item.showcase.extra.webauthn"]);
  h.step("approve", {
    run_id: ed,
    decision: "approved",
    actor_type: "user",
    statement: "Touched the other key.",
    idempotency_key: "w2",
    recorded_at: "2026-06-25T12:10:00.000Z",
    token: webauthnToken(h.binding(ed), { credential_id: "credential-ed25519", signer: "webauthn_ed25519" }),
    keyring: "main",
    webauthn_resolver: true,
    now_ms: inWindow
  });
  h.step("replay", { run_id: ed, keyring: "main", webauthn_resolver: true });
  const floor = finishedRun(h, "webauthn", "webauthn-floor", ["item.showcase.extra.webauthn"]);
  h.step("approve", {
    run_id: floor,
    decision: "approved",
    actor_type: "user",
    statement: "An ed25519 key below the hardware floor.",
    idempotency_key: "w3",
    token: ed25519Token(h.binding(floor), { method: "os_presence" }),
    keyring: "main",
    tier_resolver: true,
    now_ms: inWindow
  });
  h.step("approve", {
    run_id: floor,
    decision: "approved",
    actor_type: "user",
    statement: "No credential resolver.",
    idempotency_key: "w4",
    token: webauthnToken(h.binding(floor)),
    keyring: "main",
    tier_resolver: true,
    now_ms: inWindow
  });
});

// ---------------------------------------------------------------------------
// Direct token verification
// ---------------------------------------------------------------------------

const LIVE_BINDING = {
  run_id: "run.alpha",
  finish_event_id: "evt.run.alpha.7",
  plan_content_hash: "sha256:plan-alpha",
  ledger_head_hash: "sha256:head-alpha",
  evidence_digest: "sha256:evidence-alpha",
  git_commit: "0123456789abcdef0123456789abcdef01234567",
  ci_freshness_digest: "sha256:ci-alpha"
};

const verifyCases = [];
function addVerify(name, token, options = {}) {
  const args = {
    token,
    keyring: "main",
    tier_resolver: true,
    webauthn_resolver: true,
    live_binding: LIVE_BINDING,
    burned: [],
    now_ms: RealDate.parse("2026-06-25T12:30:00.000Z"),
    assurance_floor: "trusted_host_user_presence",
    ...options
  };
  if (options.credentials) {
    args.keyring = options.keyring ?? "main";
  }
  const resolvers = resolversFor(args);
  const credentials = args.credentials;
  const clock = args.clock_ms ?? RealDate.parse("2026-06-25T12:31:00.000Z");
  clockMilliseconds = clock;
  let entry;
  try {
    entry = {
      result: verifyApprovalToken({
        token: args.token,
        resolver: resolvers.resolver ?? (() => undefined),
        tierResolver: resolvers.tierResolver,
        webauthnCredentialResolver: credentials ? (id) => credentials[id] : resolvers.webauthnCredentialResolver,
        liveBinding: args.live_binding,
        isNonceBurned: (jti) => args.burned.includes(jti),
        nowMs: args.now_ms,
        assuranceFloor: args.assurance_floor
      })
    };
  } catch (error) {
    entry = { throws: thrown(error) };
  } finally {
    clockMilliseconds = null;
  }
  verifyCases.push({ name, args, clock_ms: clock, ...entry });
}

const B = LIVE_BINDING;
addVerify("ed25519_valid_legacy_token_claims_the_key_cap", ed25519Token(B));
addVerify("ed25519_valid_os_presence", ed25519Token(B, { method: "os_presence" }));
addVerify("ed25519_now_from_the_clock_when_absent", ed25519Token(B), { now_ms: undefined });
addVerify("ed25519_now_from_a_clock_past_expiry", ed25519Token(B), { now_ms: undefined, clock_ms: RealDate.parse("2026-06-25T13:04:00.001Z") });
addVerify("ed25519_burned_nonce", ed25519Token(B), { burned: ["approval.fixed-nonce"] });
addVerify("ed25519_floor_untrusted_accepts_automation", ed25519Token(B, { key: "automation", keyId: "automation-key", method: "automation" }), { assurance_floor: "untrusted_automation" });
addVerify("ed25519_floor_webauthn_refuses_os_presence", ed25519Token(B, { method: "os_presence" }), { assurance_floor: "webauthn_hardware" });
addVerify("ed25519_binding_field_missing_on_live", ed25519Token(B), { live_binding: { ...B, ci_freshness_digest: undefined } });
addVerify("ed25519_binding_extra_field_ignored", ed25519Token({ ...B, extra: "x" }));
addVerify("ed25519_binding_is_a_string", forgedToken(B, { binding: "run.alpha" }));
addVerify("ed25519_signature_null", { ...ed25519Token(B), signature: null });
addVerify("ed25519_signature_value_not_string", { ...ed25519Token(B), signature: { alg: "ed25519", key_id: "human-key", value: 5 } });
addVerify("ed25519_created_at_before_the_key", forgedToken(B, { created_at: "2025-12-31T23:59:59.999Z" }));
addVerify("ed25519_created_at_not_a_string", forgedToken(B, { created_at: 20260625 }));
addVerify("token_null", null);
addVerify("token_string", "token");
addVerify("token_empty_object", {});
addVerify("token_jti_number", forgedToken(B, { jti: 7 }));
addVerify("token_exp_number", forgedToken(B, { exp: RealDate.parse("2026-06-25T13:00:00.000Z") }));
addVerify("token_exp_date_only", forgedToken(B, { exp: "2026-06-26" }));

const W = (options, extra) => webauthnToken(B, options, extra);
addVerify("webauthn_p256_valid", W());
addVerify("webauthn_ed25519_valid", W({ credential_id: "credential-ed25519", signer: "webauthn_ed25519" }));
addVerify("webauthn_p256_high_s_signature", W({ mutate_signature: highS }));
addVerify("webauthn_p256_declared_eddsa_still_verifies", W({ credential_id: "credential-p256-declared-eddsa" }));
addVerify("webauthn_ed25519_declared_es256_is_refused", W({ credential_id: "credential-ed25519-declared-es256", signer: "webauthn_ed25519" }));
addVerify("webauthn_p384_valid", W({ credential_id: "credential-p384", signer: "p384" }));
addVerify("webauthn_p521_declared_eddsa_valid", W({ credential_id: "credential-p521", signer: "p521" }));
addVerify("webauthn_p256_ieee_p1363_signature_is_refused", W({ dsa: "p1363" }));
addVerify("webauthn_bad_spki", W({ credential_id: "credential-bad-spki" }));
addVerify("webauthn_wrong_challenge", W({ challenge: challengeFor({ ...B, run_id: "run.beta" }) }));
addVerify("webauthn_challenge_not_a_string", W({ client_data_text: JSON.stringify({ type: "webauthn.get", challenge: 5 }) }));
addVerify("webauthn_challenge_with_padding", W({ challenge: `${challengeFor(B)}=` }));
addVerify("webauthn_wrong_binding_in_token", W({}, { request: mint({ ...B, git_commit: "other" }) }));
addVerify("webauthn_missing_user_present", W({ flags: 0x04 }));
addVerify("webauthn_missing_user_verified", W({ flags: 0x01 }));
addVerify("webauthn_extra_flags_accepted", W({ flags: 0xff }));
addVerify("webauthn_no_flags", W({ flags: 0x00 }));
addVerify("webauthn_wrong_type", W({ type: "webauthn.create" }));
addVerify("webauthn_client_data_not_json", W({ client_data_text: "not json" }));
addVerify("webauthn_client_data_null", W({ client_data_text: "null" }));
addVerify("webauthn_client_data_array", W({ client_data_text: "[]" }));
addVerify("webauthn_client_data_with_bom", W({ client_data_text: `﻿${JSON.stringify({ type: "webauthn.get", challenge: challengeFor(B) })}` }));
addVerify("webauthn_client_data_invalid_utf8", W({ client_data_json_text: base64url(Buffer.from([0x7b, 0xff, 0x7d])) }));
addVerify("webauthn_authenticator_data_too_short", W({ authenticator_data: Buffer.alloc(36, 5) }));
addVerify("webauthn_authenticator_data_exactly_37", W({ authenticator_data: Buffer.concat([Buffer.alloc(32, 1), Buffer.from([5]), Buffer.alloc(4)]) }));
addVerify("webauthn_bad_base64url_trailing_bits", W({ authenticator_data_text: "YR" }));
addVerify("webauthn_bad_base64url_padding", W({ signature_text: "YQ==" }));
addVerify("webauthn_bad_base64url_standard_alphabet", W({ client_data_json_text: "ab+/" }));
addVerify("webauthn_bad_base64url_empty", W({ signature_text: "" }));
addVerify("webauthn_bad_base64url_single_character", W({ signature_text: "Y" }));
addVerify("webauthn_bad_signature", W({ mutate_signature: (der) => { der[der.length - 1] ^= 0x01; return der; } }));
addVerify("webauthn_signature_by_another_key", W({ signer: "p384" }));
addVerify("webauthn_signature_with_trailing_byte", W({ mutate_signature: (der) => Buffer.concat([der, Buffer.from([0])]) }));
addVerify("webauthn_unknown_credential", W({ credential_id: "credential-nowhere" }));
addVerify("webauthn_revoked_credential", W({ credential_id: "credential-revoked" }));
addVerify("webauthn_no_credential_resolver", W(), { webauthn_resolver: false });
addVerify("webauthn_created_at_outside_window", W({}, { tokenFields: { created_at: "2025-01-01T00:00:00.000Z" } }));
addVerify("webauthn_created_at_number", W({}, { tokenFields: { created_at: 2026 } }));
addVerify("webauthn_created_at_missing", W({}, { tokenFields: { created_at: undefined } }));
addVerify("webauthn_signature_block_incomplete", W({}, { tokenFields: { signature: { alg: "webauthn", credential_id: "credential-es256" } } }));
addVerify("webauthn_no_assurance_claim_defaults_to_hardware", W({}, { tokenFields: { assurance_method: undefined, assurance_tier: undefined } }));
addVerify("webauthn_tier_only_is_malformed", W({}, { tokenFields: { assurance_method: undefined } }));
addVerify("webauthn_method_mismatch", W({}, { tokenFields: { assurance_method: "os_presence" } }));
addVerify("webauthn_tier_mismatch", W({}, { tokenFields: { assurance_tier: "trusted_host_user_presence" } }));
addVerify("webauthn_expired", W(), { now_ms: RealDate.parse("2026-06-25T14:00:00.000Z") });
addVerify("webauthn_burned", W(), { burned: ["approval.fixed-nonce"] });
addVerify("webauthn_credential_cap_below_hardware", W(), {
  credentials: {
    "credential-es256": { credential_id: "credential-es256", credential_public_key_alg: -7, credential_public_key_spki: EC_KEYS.p256.spki, max_assurance_tier: "trusted_host_user_presence" }
  }
});
addVerify("webauthn_credential_cap_unknown", W(), {
  credentials: {
    "credential-es256": { credential_id: "credential-es256", credential_public_key_alg: -7, credential_public_key_spki: EC_KEYS.p256.spki, max_assurance_tier: "bogus" }
  }
});
addVerify("webauthn_resolver_ignores_declared_alg_minus_257", W(), {
  credentials: {
    "credential-es256": { credential_id: "credential-es256", credential_public_key_alg: -257, credential_public_key_spki: EC_KEYS.p256.spki, max_assurance_tier: "webauthn_hardware" }
  }
});
addVerify("webauthn_ed25519_valid_under_alg_minus_257", W({ credential_id: "credential-ed25519", signer: "webauthn_ed25519" }), {
  credentials: {
    "credential-ed25519": { credential_id: "credential-ed25519", credential_public_key_alg: -257, credential_public_key_spki: KEYS.webauthn_ed25519.spki, max_assurance_tier: "webauthn_hardware" }
  }
});
addVerify("webauthn_decision_is_carried", W({}, { decision: "rejected" }));

// Key types node verifies and swift-crypto cannot: recorded so the Swift side
// pins its refusal against node's acceptance, not so it matches.
const divergenceCases = [];
function addDivergence(name, token, credential) {
  const before = verifyCases.length;
  addVerify(name, token, { credentials: { [credential.credential_id]: credential } });
  divergenceCases.push(verifyCases.splice(before, 1)[0]);
}
addDivergence("webauthn_secp256k1_es256", W({ credential_id: "credential-secp256k1", signer: "secp256k1" }), {
  credential_id: "credential-secp256k1",
  credential_public_key_alg: -7,
  credential_public_key_spki: EC_KEYS.secp256k1.spki,
  max_assurance_tier: "webauthn_hardware"
});
addDivergence("webauthn_ed448_eddsa", W({ credential_id: "credential-ed448", signer: "webauthn_ed448" }), {
  credential_id: "credential-ed448",
  credential_public_key_alg: -8,
  credential_public_key_spki: ED448_KEY.spki,
  max_assurance_tier: "webauthn_hardware"
});

// ---------------------------------------------------------------------------
// Requests, signing and building
// ---------------------------------------------------------------------------

const requestCases = [];
function addRequest(name, op, args, { clock = T0, uuid = DEFAULT_UUID } = {}) {
  clockMilliseconds = clock;
  fixedUUID = uuid;
  let entry;
  try {
    let value;
    if (op === "mint") {
      value = mintApprovalRequest({ binding: args.binding, nowMs: args.now_ms, ttlMinutes: args.ttl_minutes, jti: args.jti });
    } else if (op === "sign") {
      value = signApprovalToken({ request: args.request, decision: args.decision, privateKey: KEYS[args.key].private_pem, keyId: args.key_id, assuranceMethod: args.assurance_method });
    } else {
      value = buildWebAuthnApprovalToken({ request: args.request, decision: args.decision, assertion: args.assertion });
    }
    entry = { result: value };
  } catch (error) {
    entry = { throws: thrown(error) };
  } finally {
    clockMilliseconds = null;
    fixedUUID = null;
  }
  requestCases.push({ name, op, args, clock_ms: clock, uuid, ...entry });
}

addRequest("mint_defaults_read_the_clock_and_uuid", "mint", { binding: B }, { clock: RealDate.parse("2026-06-25T12:04:00.123Z"), uuid: "0b7c5b0e-7e0a-4c55-9a3f-0f3b8f5a1c2d" });
addRequest("mint_explicit_now_ttl_and_jti", "mint", { binding: B, now_ms: RealDate.parse("2026-06-25T12:04:00.000Z"), ttl_minutes: 60, jti: "approval.fixed-nonce" });
addRequest("mint_fractional_ttl", "mint", { binding: B, now_ms: 0, ttl_minutes: 0.5 });
addRequest("mint_zero_ttl_is_not_defaulted", "mint", { binding: B, now_ms: 1000, ttl_minutes: 0 });
addRequest("mint_negative_ttl", "mint", { binding: B, now_ms: 1000, ttl_minutes: -1 });
addRequest("mint_empty_jti_is_kept", "mint", { binding: B, now_ms: 1000, jti: "" });
addRequest("mint_binding_order_is_kept", "mint", { binding: { z: "last", run_id: "r", a: "first" }, now_ms: 1000 });
addRequest("mint_time_value_out_of_range", "mint", { binding: B, now_ms: 8.64e15, ttl_minutes: 1 });
const REQUEST = mint(B);
addRequest("sign_legacy", "sign", { request: REQUEST, decision: "approved", key: "human", key_id: "human-key" });
addRequest("sign_os_presence", "sign", { request: REQUEST, decision: "approved_with_known_gaps", key: "human", key_id: "human-key", assurance_method: "os_presence" });
addRequest("sign_automation", "sign", { request: REQUEST, decision: "rejected", key: "automation", key_id: "automation-key", assurance_method: "automation" });
addRequest("sign_same_channel", "sign", { request: REQUEST, decision: "approved", key: "same_channel", key_id: "same-channel-key", assurance_method: "same_channel" });
addRequest("sign_refuses_webauthn_method", "sign", { request: REQUEST, decision: "approved", key: "human", key_id: "human-key", assurance_method: "webauthn" });
addRequest("sign_request_with_extra_members", "sign", { request: { ...REQUEST, extra: true, binding: { ...REQUEST.binding, extra: 1 } }, decision: "approved", key: "human", key_id: "human-key" });
addRequest("build_webauthn", "build_webauthn", { request: REQUEST, decision: "approved", assertion: assertion(B) });
addRequest("build_webauthn_extra_assertion_members_dropped", "build_webauthn", { request: REQUEST, decision: "rejected", assertion: { ...assertion(B), alg: "none", extra: 1 } });

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const floorCases = [
  undefined,
  {},
  { selected_items: [] },
  { selected_items: [{ approval_policy_snapshot: { mode: "none", minimum_assurance_tier: "webauthn_hardware" } }] },
  { selected_items: [{ approval_policy_snapshot: { mode: "predefined", requirements: [{ approver_type: "agent" }], minimum_assurance_tier: "webauthn_hardware" } }] },
  { selected_items: [{ approval_policy_snapshot: { mode: "predefined", requirements: [{ approver_type: "user" }] } }] },
  { selected_items: [{ approval_policy_snapshot: { mode: "predefined", requirements: [{ approver_type: "user" }], minimum_assurance_tier: "untrusted_automation" } }] },
  {
    selected_items: [
      { approval_policy_snapshot: { mode: "predefined", requirements: [{ approver_type: "user" }], minimum_assurance_tier: "same_channel_operator_confirmation" } },
      { approval_policy_snapshot: { mode: "predefined", requirements: [[], "user", { approver_type: "user" }], minimum_assurance_tier: "untrusted_automation" } }
    ]
  },
  {
    selected_items: [
      { approval_policy_snapshot: { mode: "predefined", requirements: [{ approver_type: "user" }], minimum_assurance_tier: "webauthn_hardware" } },
      { approval_policy_snapshot: { mode: "predefined", requirements: [{ approver_type: "user" }], minimum_assurance_tier: "same_channel_operator_confirmation" } }
    ]
  }
].map((plan) => ({ plan, floor: approvalAssuranceFloorForPlan(plan) }));

const bindingCases = [
  { name: "no_finish", events: [{ event_type: "run_started", event_id: "evt.1", sequence: 1, payload: {} }] },
  {
    name: "latest_finish_by_sequence_and_start_facts",
    events: [
      { event_type: "run_finished", event_id: "evt.9", sequence: 9 },
      { event_type: "run_started", event_id: "evt.1", sequence: 1, payload: { plan_content_hash: "sha256:p", git_commit: "abc", ci_freshness_digest: "sha256:ci" } },
      { event_type: "observation_recorded", event_id: "evt.b", sequence: 3 },
      { event_type: "verdict_recorded", event_id: "evt.B", sequence: 4 },
      { event_type: "observation_recorded", event_id: "evt.10", sequence: 2 },
      { event_type: "run_finished", event_id: "evt.5", sequence: 5 }
    ]
  },
  {
    name: "empty_freshness_and_non_string_facts",
    events: [
      { event_type: "run_started", event_id: "evt.1", sequence: 1, payload: { plan_content_hash: 12, git_commit: null, ci_freshness_digest: "" } },
      { event_type: "run_finished", event_id: "evt.2", sequence: 2 }
    ]
  },
  { name: "no_start", events: [{ event_type: "run_finished", event_id: "evt.2", sequence: 2 }] },
  {
    name: "missing_event_id_cannot_be_canonicalised",
    events: [
      { event_type: "run_started", sequence: 1, payload: {} },
      { event_type: "run_finished", event_id: "evt.2", sequence: 2 }
    ]
  },
  {
    name: "missing_evidence_ids_sort_last",
    events: [
      { event_type: "run_started", event_id: "evt.1", sequence: 1, payload: {} },
      { event_type: "observation_recorded", event_id: 3, sequence: 2 },
      { event_type: "observation_recorded", event_id: "evt.a", sequence: 3 },
      { event_type: "run_finished", event_id: "evt.4", sequence: 4 }
    ]
  }
].map((testCase) => {
  try {
    return { ...testCase, result: computeApprovalBindingFromEvents("run.binding", testCase.events) };
  } catch (error) {
    return { ...testCase, throws: thrown(error) };
  }
});

// ---------------------------------------------------------------------------
// Emission
// ---------------------------------------------------------------------------

function asciiJson(value) {
  return JSON.stringify(value).replace(/[-￿]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`);
}

function nameList(propertyName, names) {
  return `  static let ${propertyName}: [String] = [\n${names.map((name) => `    ${asciiJson(name)},`).join("\n")}\n  ]\n\n`;
}

const golden = {
  keys: Object.fromEntries(Object.entries(KEYS).filter(([name]) => name !== "webauthn_ed448").map(([name, key]) => [name, { private_pem: key.private_pem, public_pem: key.public_pem, spki: key.spki }])),
  ec_keys: Object.fromEntries(Object.entries(EC_KEYS).map(([name, key]) => [name, { spki: key.spki }])),
  keyrings: KEYRINGS,
  base_tree: baseTree(),
  runs: runCases,
  verify: verifyCases,
  divergences: divergenceCases,
  requests: requestCases,
  floors: floorCases,
  bindings: bindingCases
};

const json = asciiJson(golden);
let pounds = "#";
while (json.includes(`\\${pounds}`) || json.includes(`"""${pounds}`) || json.includes(`"${pounds}`)) {
  pounds += "#";
}
const contents = `// swiftlint:disable line_length single_line_closure_body
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript showcase run ledger and approval code. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/showcase returned, threw or
// wrote for the workspace, clock, uuid, keys and options beside it.
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-showcase-corpus.mjs
enum ShowcaseGoldenCorpus {
${nameList("runCaseNames", golden.runs.map((item) => item.name))}${nameList("verifyCaseNames", golden.verify.map((item) => item.name))}${nameList("requestCaseNames", golden.requests.map((item) => item.name))}${nameList("bindingCaseNames", golden.bindings.map((item) => item.name))}  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable line_length single_line_closure_body
`;
mkdirSync(testsDirectory, { recursive: true });
const targetPath = join(testsDirectory, "ShowcaseGoldenCorpus.swift");
writeFileSync(targetPath, contents);
if (!/^[\x00-\x7f]*$/.test(readFileSync(targetPath, "utf8"))) {
  throw new Error("ShowcaseGoldenCorpus.swift is not ASCII");
}
console.log(
  `wrote ${targetPath}: ${golden.runs.length} run cases (${golden.runs.reduce((sum, item) => sum + item.steps.length, 0)} steps), ` +
    `${golden.verify.length} verify, ${golden.requests.length} request, ${golden.floors.length} floor, ${golden.bindings.length} binding cases`
);
