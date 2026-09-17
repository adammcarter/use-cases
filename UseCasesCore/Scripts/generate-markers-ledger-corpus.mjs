// Regenerates `Tests/UseCasesCoreTests/Markers/MarkersLedgerGoldenCorpus.swift`
// by running every case below through the REAL TypeScript marker code in
// `packages/core/dist/markers` and recording exactly what it returns.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-markers-ledger-corpus.mjs
//
// This is the oracle for the registry, the ledgers, the hashes and the
// signatures (row 3d2). Every hash here is written into a ledger that already
// exists, so the Swift port is asserted against these bytes (ADR 0007
// decision 8). The script refuses to run against a `dist` older than its `src`.
//
// Inputs that could be merged by canonical equivalence are carried as JSON
// TEXT, and the corpus is emitted ASCII-only, so neither the Swift compiler nor
// the Swift `String` type gets a chance to normalize an input before the code
// under test parses it.
import { execFileSync } from "node:child_process";
import { createPrivateKey, createPublicKey } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const sourceDirectory = join(repositoryRoot, "packages/core/src/markers");
const distDirectory = join(repositoryRoot, "packages/core/dist/markers");
const targetPath = join(
  packageRoot,
  "Tests/UseCasesCoreTests/Markers/MarkersLedgerGoldenCorpus.swift"
);

const PORTED = [
  "validators",
  "appendOnly",
  "registry",
  "reconcile",
  "bindingSetHash",
  "policyHash",
  "rowHash",
  "proofSignature",
  "keyring",
  "keygen",
  "runAttestation",
  "ciAuthority",
  "evidenceLedger",
  "gitDiff",
  "canonicalJson",
  "scanner"
];

for (const name of PORTED) {
  const source = statSync(join(sourceDirectory, `${name}.ts`)).mtimeMs;
  const built = statSync(join(distDirectory, `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/markers/${name}.js is older than src; rebuild packages/core first`);
  }
}

const markers = await import(join(distDirectory, "index.js"));
const {
  canonicalJson,
  canonicalJsonSha256,
  computeBindingSetHash,
  buildBindingSetMaterial,
  computePolicyHash,
  computeVerificationPolicyHash,
  computeApprovalPolicyHash,
  computeRowHash,
  proofSigningPayload,
  signEvent,
  verifyEvent,
  parseKeyring,
  loadKeyring,
  keyringResolver,
  keyringMaxAssuranceTierResolver,
  keyringWebAuthnCredentialResolver,
  generateSigningKeypair,
  computeRunAttestation,
  verifyRunAttestation,
  detectCiAuthority,
  readEvidenceJsonl,
  validateEvidenceLedger,
  verifyLedgerChain,
  computeLedgerEntryHash,
  evidenceErrorsAreKeyResolutionOnly,
  GENESIS_ENTRY_HASH,
  appendOnly,
  splitJsonlLines,
  readBaseRefFile,
  readBindingsJsonl,
  validateBindingsJsonl,
  materializeRegistry,
  reconcileRegistryWithScan,
  scanFiles,
  parseNameStatusZ,
  parseUnifiedZeroHunks,
  rangesOverlap,
  collectChangedFiles,
  validateMarkerSchema
} = markers;
const { join: pathJoin } = await import("node:path");

// A marker line, built at runtime so this file never carries one literally.
const markerToken = (prefix) => `${prefix}: @use-` + "case:";
const lines = (...parts) => parts.join("\n");

// Every JavaScript value the corpus records goes through this, so `undefined`
// members disappear exactly as JSON.stringify drops them.
const plain = (value) => (value === undefined ? null : JSON.parse(JSON.stringify(value)));

const captureThrow = (thunk) => {
  try {
    return { value: plain(thunk()) };
  } catch (error) {
    return { throws: error.message };
  }
};

// ---------------------------------------------------------------------------
// keys: deterministic ed25519 keypairs from fixed seeds
// ---------------------------------------------------------------------------

const PKCS8_ED25519_PREFIX = Buffer.from("302e020100300506032b657004220420", "hex");

function keypairFromSeed(byte) {
  const privateKey = createPrivateKey({
    key: Buffer.concat([PKCS8_ED25519_PREFIX, Buffer.alloc(32, byte)]),
    format: "der",
    type: "pkcs8"
  });
  const publicKey = createPublicKey(privateKey);
  return {
    private_pem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
    public_pem: publicKey.export({ type: "spki", format: "pem" }).toString()
  };
}

const keys = {
  primary: keypairFromSeed(7),
  other: keypairFromSeed(9)
};

const hash = (digit) => `sha256:${digit.repeat(64)}`;

// ---------------------------------------------------------------------------
// JSON parsing: key identity is by code unit, never by canonical equivalence
// ---------------------------------------------------------------------------

const keyIdentityInputs = {
  precomposed_and_decomposed_e_acute:
    '{"\\u00e9":1,"e\\u0301":2}',
  decomposed_first: '{"e\\u0301":"decomposed","\\u00e9":"precomposed"}',
  three_spellings_of_angstrom: '{"\\u212b":1,"\\u00c5":2,"A\\u030a":3}',
  kelvin_sign_and_capital_k: '{"\\u212a":1,"K":2}',
  hangul_syllable_and_jamo: '{"\\uac00":1,"\\u1100\\u1161":2}',
  reordered_combining_marks: '{"a\\u0301\\u0327":1,"a\\u0327\\u0301":2}',
  exact_duplicate_keeps_first_position_last_value:
    '{"\\u00e9":1,"e\\u0301":2,"\\u00e9":3}',
  nested_both_spellings: '{"outer":{"\\u00e9":[{"e\\u0301":true,"\\u00e9":false}]}}',
  equivalent_values_stay_distinct: '{"a":"\\u00e9","b":"e\\u0301"}'
};

const keyIdentityCases = Object.entries(keyIdentityInputs).map(([name, text]) => {
  const parsed = JSON.parse(text);
  return {
    name,
    text,
    keys: Object.keys(parsed),
    wire: JSON.stringify(parsed),
    canonical: canonicalJson(parsed),
    sha256: canonicalJsonSha256(parsed)
  };
});

// ---------------------------------------------------------------------------
// binding-set hash
// ---------------------------------------------------------------------------

const binding = (slug, overrides = {}) => ({
  binding_slug: slug,
  row_id: slug.split("#")[0],
  file_path: "Sources/Checkout/Tax.swift",
  extent_kind: "explicit",
  recognizer_id: "explicit-span-v1",
  span_canon_id: "ucase-span-lines-v2",
  span_sha256: hash("a"),
  ...overrides
});

const bindingSetInputs = {
  empty: { row_id: "checkout.apply_coupon", bindings: [] },
  single: { row_id: "checkout.apply_coupon", bindings: [binding("checkout.apply_coupon#tax")] },
  sorted_by_slug: {
    row_id: "checkout.apply_coupon",
    bindings: [
      binding("checkout.apply_coupon#z"),
      binding("checkout.apply_coupon"),
      binding("checkout.apply_coupon#a")
    ]
  },
  extra_diagnostic_fields_excluded: {
    row_id: "checkout.apply_coupon",
    bindings: [
      binding("checkout.apply_coupon#tax", {
        span_start_line: 3,
        span_end_line: 9,
        start_marker: { line: 2, column: 1 },
        proof_status: "FRESH"
      })
    ]
  },
  slug_order_is_code_unit_not_locale: {
    row_id: "r",
    bindings: [binding("r#b"), binding("r#B"), binding("r#a-b"), binding("r#a_b"), binding("r#\u00e9")]
  },
  equal_slugs_keep_input_order: {
    row_id: "r",
    bindings: [
      binding("r#same", { file_path: "second.swift" }),
      binding("r#same", { file_path: "first.swift" }),
      binding("r#aaa", { file_path: "third.swift" })
    ]
  },
  surrogate_pair_slug_sorts_below_last_basic_plane_unit: {
    row_id: "r",
    bindings: [binding("r#\uffff"), binding("r#\ud83d\ude00")]
  },
  canonically_equivalent_slugs_stay_distinct: {
    row_id: "r",
    bindings: [binding("r#\u00e9"), binding("r#e\u0301")]
  },
  equivalent_extra_keys_are_excluded: {
    row_id: "r",
    bindings: [{ ...binding("r#x"), "\u00e9": 1, "e\u0301": 2 }]
  },
  non_ascii_paths_and_row_mismatch: {
    row_id: "checkout.other",
    bindings: [binding("checkout.apply_coupon#caf\u00e9", { file_path: "Sources/Caf\u00e9/\ud83d\ude00.swift" })]
  }
};

const bindingSetCases = Object.entries(bindingSetInputs).map(([name, input]) => {
  // The bindings travel as JSON text so the Swift side parses the same bytes.
  const text = JSON.stringify(input.bindings);
  const parsed = JSON.parse(text);
  return {
    name,
    row_id: input.row_id,
    bindings_text: text,
    material: canonicalJson(buildBindingSetMaterial(input.row_id, parsed)),
    hash: computeBindingSetHash(input.row_id, parsed)
  };
});

// ---------------------------------------------------------------------------
// policy hash and row hash
// ---------------------------------------------------------------------------

const objectHashInputs = {
  empty_object: "{}",
  null_policy: "null",
  simple_policy: '{"required_for_release":true,"verifiers":["unit","ui"]}',
  key_order_irrelevant: '{"verifiers":["unit","ui"],"required_for_release":true}',
  code_unit_versus_locale_order: '{"b":1,"B":2,"a-b":3,"a_b":4}',
  nested: '{"approval":{"mode":"human","quorum":2},"notes":null}',
  both_spellings_as_keys: '{"\\u00e9":1,"e\\u0301":2}',
  both_spellings_nested: '{"policy":{"e\\u0301":"x","\\u00e9":"y"},"z":[{"\\u212b":1,"\\u00c5":2}]}',
  numbers: '{"a":1.5,"b":-0,"c":1e21,"d":0.1}',
  row_shaped:
    '{"id":"checkout.apply_coupon","title":"Apply a coupon","value_tier":"core","observable_outcomes":["total drops"]}'
};

const policyHashCases = Object.entries(objectHashInputs).map(([name, text]) => {
  const parsed = JSON.parse(text);
  return {
    name,
    text,
    policy_hash: computePolicyHash(parsed),
    verification_policy_hash: computeVerificationPolicyHash(parsed),
    approval_policy_hash: computeApprovalPolicyHash(parsed)
  };
});

const rowHashCases = Object.entries(objectHashInputs).map(([name, text]) => ({
  name,
  text,
  row_hash: computeRowHash(JSON.parse(text))
}));

// ---------------------------------------------------------------------------
// proof signatures
// ---------------------------------------------------------------------------

const baseItems = [
  {
    binding_slug: "checkout.apply_coupon#tax",
    row_id: "checkout.apply_coupon",
    file_path: "Sources/Checkout/Tax.swift",
    extent_kind: "explicit",
    recognizer_id: "explicit-span-v1",
    span_canon_id: "ucase-span-lines-v2",
    span_sha256: hash("a"),
    span_start_line: 3,
    span_end_line: 9
  }
];

function unsignedEvent(overrides = {}) {
  const rowId = overrides.row_id ?? "checkout.apply_coupon";
  const items = overrides.items ?? baseItems;
  const event = {
    schema: "ucase-proof-event-v1",
    event_type: "row_proof_passed",
    event_id: overrides.event_id ?? "evt_0001",
    created_at: overrides.created_at ?? "2026-06-01T12:00:00Z",
    producer: {
      kind: "trusted-ci-prover",
      id: "ucm-ci",
      version: "1.0.0",
      ci_run_id: "run-1",
      repo: "example/app",
      commit: "abc123"
    },
    row: {
      row_id: rowId,
      row_hash_id: "existing-semantic-row-hash",
      row_hash: hash("0"),
      verification_policy_hash: hash("1"),
      approval_policy_hash: hash("2")
    },
    bindings: {
      binding_set_hash_id: "ucase-binding-set-v1",
      binding_set_hash: overrides.binding_set_hash ?? computeBindingSetHash(rowId, items),
      span_canon_id: "ucase-span-lines-v2",
      items
    },
    verification: {
      command_id: "swift-test",
      result: "pass",
      started_at: "2026-06-01T11:59:00Z",
      completed_at: "2026-06-01T12:00:00Z",
      artifacts: [],
      context_hash_id: "ucase-verification-context-hash-v1",
      context_hash: hash("3")
    }
  };
  return event;
}

const signWith = (event, keyName = "primary", keyId = "ci-key-1") =>
  signEvent(event, keys[keyName].private_pem, keyId);

// ed25519's group order. A signature whose S is not reduced below it is
// malleable, and OpenSSL rejects it.
const ED25519_ORDER = (1n << 252n) + 27742317777372353535851937790883648493n;

function nonCanonicalSignature(base64) {
  const bytes = Buffer.from(base64, "base64");
  let s = 0n;
  for (let index = 63; index >= 32; index -= 1) {
    s = (s << 8n) | BigInt(bytes[index]);
  }
  s += ED25519_ORDER;
  const out = Buffer.from(bytes);
  for (let index = 32; index < 64; index += 1) {
    out[index] = Number(s & 0xffn);
    s >>= 8n;
  }
  return out.toString("base64");
}

const signedBase = signWith(unsignedEvent());
const withSignatureValue = (event, value) => ({
  ...event,
  signature: { ...event.signature, value }
});

const pem = keys.primary.public_pem;
const pemBody = pem.split("\n")[1];

// The resolver a case uses, as data the Swift side rebuilds.
//   none:   every key id is unknown
//   single: every key id resolves to `pem` (the single-key CLI path)
//   keyring: a keyring's fail-closed resolver
const signatureInputs = [
  { name: "valid", event: signedBase, resolver: { kind: "single", pem } },
  { name: "unknown_key_id", event: signedBase, resolver: { kind: "none" } },
  { name: "wrong_public_key", event: signedBase, resolver: { kind: "single", pem: keys.other.public_pem } },
  { name: "private_key_pem_resolves_as_public", event: signedBase, resolver: { kind: "single", pem: keys.primary.private_pem } },
  {
    name: "tampered_after_signing",
    event: { ...signedBase, event_id: "evt_tampered" },
    resolver: { kind: "single", pem }
  },
  { name: "unsigned", event: unsignedEvent(), resolver: { kind: "single", pem } },
  {
    name: "signature_without_value",
    event: { ...signedBase, signature: { alg: "ed25519", key_id: "ci-key-1" } },
    resolver: { kind: "single", pem }
  },
  {
    name: "signature_key_id_not_a_string",
    event: { ...signedBase, signature: { ...signedBase.signature, key_id: 7 } },
    resolver: { kind: "single", pem }
  },
  { name: "signature_is_an_array", event: { ...signedBase, signature: [1, 2] }, resolver: { kind: "single", pem } },
  { name: "signature_is_a_string", event: { ...signedBase, signature: "sig" }, resolver: { kind: "single", pem } },
  { name: "signature_is_null", event: { ...signedBase, signature: null }, resolver: { kind: "single", pem } },
  {
    name: "unsupported_alg",
    event: { ...signedBase, signature: { ...signedBase.signature, alg: "rsa" } },
    resolver: { kind: "single", pem }
  },
  {
    name: "missing_alg_reads_undefined",
    event: { ...signedBase, signature: { key_id: "ci-key-1", value: signedBase.signature.value } },
    resolver: { kind: "single", pem }
  },
  {
    name: "alg_is_an_object",
    event: { ...signedBase, signature: { ...signedBase.signature, alg: { a: 1 } } },
    resolver: { kind: "single", pem }
  },
  {
    name: "alg_is_an_array_with_null",
    event: { ...signedBase, signature: { ...signedBase.signature, alg: [null, "x", [1, null]] } },
    resolver: { kind: "single", pem }
  },
  {
    name: "base64_without_padding",
    event: withSignatureValue(signedBase, signedBase.signature.value.replace(/=+$/, "")),
    resolver: { kind: "single", pem }
  },
  {
    name: "base64_url_alphabet",
    event: withSignatureValue(signedBase, signedBase.signature.value.replace(/\+/g, "-").replace(/\//g, "_")),
    resolver: { kind: "single", pem }
  },
  {
    name: "base64_with_whitespace_and_junk",
    event: withSignatureValue(
      signedBase,
      `${signedBase.signature.value.slice(0, 10)} \n*${signedBase.signature.value.slice(10)}`
    ),
    resolver: { kind: "single", pem }
  },
  {
    name: "base64_trailing_data_after_padding",
    event: withSignatureValue(signedBase, `${signedBase.signature.value}QUJD`),
    resolver: { kind: "single", pem }
  },
  {
    name: "signature_truncated",
    event: withSignatureValue(signedBase, signedBase.signature.value.slice(0, 40)),
    resolver: { kind: "single", pem }
  },
  {
    name: "signature_not_reduced_modulo_group_order",
    event: withSignatureValue(signedBase, nonCanonicalSignature(signedBase.signature.value)),
    resolver: { kind: "single", pem }
  },
  { name: "resolver_pem_is_empty", event: signedBase, resolver: { kind: "single", pem: "" } },
  { name: "resolver_pem_is_garbage", event: signedBase, resolver: { kind: "single", pem: "not a key" } },
  { name: "pem_with_crlf", event: signedBase, resolver: { kind: "single", pem: pem.replace(/\n/g, "\r\n") } },
  { name: "pem_without_trailing_newline", event: signedBase, resolver: { kind: "single", pem: pem.trimEnd() } },
  { name: "pem_with_leading_text", event: signedBase, resolver: { kind: "single", pem: `a comment\n${pem}` } },
  {
    name: "pem_with_space_inside_body",
    event: signedBase,
    resolver: { kind: "single", pem: pem.replace(pemBody, `${pemBody.slice(0, 8)} ${pemBody.slice(8)}`) }
  },
  {
    name: "pem_body_split_over_lines",
    event: signedBase,
    resolver: { kind: "single", pem: pem.replace(pemBody, `${pemBody.slice(0, 30)}\n${pemBody.slice(30)}`) }
  },
  {
    name: "pem_body_on_the_begin_line",
    event: signedBase,
    resolver: { kind: "single", pem: pem.replace("-----\n", "-----") }
  },
  {
    name: "pem_wrong_label",
    event: signedBase,
    resolver: { kind: "single", pem: pem.replace(/PUBLIC KEY/g, "CERTIFICATE") }
  },
  {
    name: "raw_base64_der_without_armour",
    event: signedBase,
    resolver: { kind: "single", pem: pemBody }
  },
  {
    name: "equivalent_keys_are_distinct_payload_members",
    event: signWith({ ...unsignedEvent(), "\u00e9": 1, "e\u0301": 2 }),
    resolver: { kind: "single", pem }
  },
  {
    name: "created_at_threads_into_a_keyring",
    event: signWith(unsignedEvent({ created_at: "2025-06-01T00:00:00Z" })),
    resolver: {
      kind: "keyring",
      keyring: {
        keyring_schema_id: "ucase-public-key-registry-v1",
        keys: [
          {
            key_id: "ci-key-1",
            algorithm: "ed25519",
            public_key: pem,
            valid_from: "2026-01-01T00:00:00Z",
            valid_until: null,
            status: "active"
          }
        ]
      }
    }
  },
  {
    name: "signed_authority_block",
    event: signWith({
      ...unsignedEvent(),
      authority: detectCiAuthority({ GITLAB_CI: "true", CI_COMMIT_REF_PROTECTED: "true" })
    }),
    resolver: { kind: "single", pem }
  },
  {
    name: "non_ascii_values",
    event: signWith(unsignedEvent({ event_id: "evt_caf\u00e9_\ud83d\ude00\u2028" })),
    resolver: { kind: "single", pem }
  }
];

function resolverFor(spec) {
  if (spec.kind === "none") {
    return () => undefined;
  }
  if (spec.kind === "single") {
    return () => spec.pem;
  }
  return keyringResolver(parseKeyring(spec.keyring));
}

const signatureCases = signatureInputs.map((entry) => {
  const text = JSON.stringify(entry.event);
  const parsed = JSON.parse(text);
  return {
    name: entry.name,
    event_text: text,
    resolver: entry.resolver,
    payload: captureThrow(() => proofSigningPayload(parsed)),
    verify: plain(verifyEvent(parsed, resolverFor(entry.resolver)))
  };
});

// Signing is deterministic in node (RFC 8032), so the signed event is pinned.
const signingInputs = {
  plain_event: unsignedEvent(),
  replaces_an_existing_signature: { ...unsignedEvent(), signature: { alg: "x", key_id: "y", value: "z" } },
  signature_key_first_in_input: { signature: 1, ...unsignedEvent() },
  equivalent_keys: { "\u00e9": 1, ...unsignedEvent(), "e\u0301": 2 },
  empty_object: {}
};

const signingCases = Object.entries(signingInputs).map(([name, event]) => {
  const text = JSON.stringify(event);
  const signed = signEvent(JSON.parse(text), keys.primary.private_pem, "ci-key-1");
  return {
    name,
    event_text: text,
    payload: proofSigningPayload(JSON.parse(text)),
    signed_wire: JSON.stringify(signed)
  };
});

// ---------------------------------------------------------------------------
// keyring
// ---------------------------------------------------------------------------

const edKey = (overrides) => ({
  key_id: "ci-key-1",
  algorithm: "ed25519",
  public_key: keys.primary.public_pem,
  valid_from: "2026-01-01T00:00:00Z",
  valid_until: null,
  status: "active",
  ...overrides
});

const webauthnKey = (overrides) => ({
  algorithm: "webauthn",
  credential_id: "cred_A-1",
  credential_public_key_alg: -8,
  credential_public_key_spki: "MCowBQYDK2VwAyEA",
  valid_from: "2026-01-01T00:00:00Z",
  valid_until: "2027-01-01T00:00:00.000Z",
  status: "active",
  max_assurance_tier: "webauthn_hardware",
  ...overrides
});

const richKeyring = {
  keyring_schema_id: "ucase-public-key-registry-v1",
  keys: [
    edKey({}),
    edKey({ key_id: "ci-key-1", public_key: keys.other.public_pem }),
    edKey({ key_id: "revoked", status: "revoked" }),
    edKey({
      key_id: "windowed",
      public_key: keys.other.public_pem,
      valid_from: "2026-03-01T00:00:00Z",
      valid_until: "2026-04-01T00:00:00.500Z",
      max_assurance_tier: "trusted_host_user_presence"
    }),
    edKey({ key_id: "legacy-tier", assurance_tier: "same_channel_operator_confirmation" }),
    edKey({
      key_id: "both-tiers",
      assurance_tier: "same_channel_operator_confirmation",
      max_assurance_tier: "trusted_host_user_presence"
    }),
    edKey({ key_id: "\u00e9" }),
    webauthnKey({}),
    webauthnKey({ credential_id: "cred_B", credential_public_key_alg: -7, status: "revoked" })
  ]
};

const keyringParseInputs = {
  rich: richKeyring,
  minimal: { keyring_schema_id: "ucase-public-key-registry-v1", keys: [edKey({})] },
  wrong_schema_id: { keyring_schema_id: "nope", keys: [edKey({})] },
  empty_keys: { keyring_schema_id: "ucase-public-key-registry-v1", keys: [] },
  ed25519_missing_public_key: {
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys: [{ ...edKey({}), public_key: undefined }]
  },
  bad_timestamp: {
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys: [edKey({ valid_from: "2026-01-01" })]
  },
  not_an_object: [1, 2],
  extra_property: { keyring_schema_id: "ucase-public-key-registry-v1", keys: [edKey({})], extra: true }
};

const keyringParseCases = Object.entries(keyringParseInputs).map(([name, value]) => {
  const text = JSON.stringify(value);
  return {
    name,
    text,
    result: (() => {
      try {
        parseKeyring(JSON.parse(text), "keyring.json");
        return { ok: true };
      } catch (error) {
        return { ok: false, code: error.code, message: error.message };
      }
    })()
  };
});

const keyringLoadPaths = {
  missing_file: "/nonexistent-use-cases-keyring/keyring.json",
  directory: "/"
};

const keyringLoadCases = Object.entries(keyringLoadPaths).map(([name, path]) => {
  try {
    loadKeyring(path);
    return { name, path, ok: true };
  } catch (error) {
    return { name, path, ok: false, code: error.code, message: error.message };
  }
});

const resolverQueries = [
  ["ci-key-1", "2026-06-01T00:00:00Z"],
  ["ci-key-1", null],
  ["ci-key-1", "not a date"],
  ["ci-key-1", "2025-12-31T23:59:59.999Z"],
  ["ci-key-1", "2026-01-01T00:00:00Z"],
  ["ci-key-1", "2026-01-01T00:00:00+01:00"],
  ["revoked", "2026-06-01T00:00:00Z"],
  ["windowed", "2026-03-15T00:00:00Z"],
  ["windowed", "2026-04-01T00:00:00.500Z"],
  ["windowed", "2026-04-01T00:00:00.501Z"],
  ["windowed", "2026-02-28T23:59:59Z"],
  ["legacy-tier", "2026-06-01T00:00:00Z"],
  ["both-tiers", "2026-06-01T00:00:00Z"],
  ["\u00e9", "2026-06-01T00:00:00Z"],
  ["e\u0301", "2026-06-01T00:00:00Z"],
  ["missing", "2026-06-01T00:00:00Z"],
  ["cred_A-1", "2026-06-01T00:00:00Z"],
  ["cred_A-1", "2027-01-01T00:00:00.001Z"],
  ["cred_B", "2026-06-01T00:00:00Z"]
];

const parsedRichKeyring = parseKeyring(JSON.parse(JSON.stringify(richKeyring)));
const publicKeyResolver = keyringResolver(parsedRichKeyring);
const tierResolver = keyringMaxAssuranceTierResolver(parsedRichKeyring);
const credentialResolver = keyringWebAuthnCredentialResolver(parsedRichKeyring);

const keyringResolverCases = resolverQueries.map(([keyId, createdAt], index) => {
  const at = createdAt === null ? undefined : createdAt;
  return {
    name: `query_${index}`,
    key_id: keyId,
    created_at: createdAt,
    public_key: plain(publicKeyResolver(keyId, at)),
    max_assurance_tier: plain(tierResolver(keyId, at)),
    webauthn_credential: plain(credentialResolver(keyId, at))
  };
});

// Date.parse, which the keyring's validity windows run through.
const dateInputs = [
  "2026-01-01T00:00:00Z",
  "2026-01-01T00:00:00.000Z",
  "2026-01-01T00:00:00.1Z",
  "2026-01-01T00:00:00.12345Z",
  "2026-01-01T00:00:00.000000000000000000001Z",
  "2026-02-30T00:00:00Z",
  "2026-04-31T00:00:00Z",
  "2024-02-29T00:00:00Z",
  "2026-13-01T00:00:00Z",
  "2026-00-01T00:00:00Z",
  "2026-01-00T00:00:00Z",
  "2026-01-32T00:00:00Z",
  "2026-01-01T24:00:00Z",
  "2026-01-01T24:00:00.000Z",
  "2026-01-01T24:00Z",
  "2026-01-01T24:00:01Z",
  "2026-01-01T25:00:00Z",
  "2026-01-01T00:60:00Z",
  "2026-01-01T23:59:60Z",
  "2026-01-01",
  "2026-01",
  "2026",
  "+002026-01-01T00:00:00Z",
  "-000001-01-01T00:00:00Z",
  "-000000-01-01T00:00:00Z",
  "+275760-09-13T00:00:00Z",
  "+275760-09-13T00:00:00.001Z",
  "0000-01-01T00:00:00Z",
  "2026-01-01T00:00Z",
  "2026-01-01T00:00:00+01:00",
  "2026-01-01T00:00:00-00:00",
  "2026-01-01T00:00:00+23:59",
  "2026-01-01T00:00:00+24:00",
  "2026-01-01T00:00:00.5+01:00",
  "2026-01-01t00:00:00z",
  "2026-01-01T00:00:00+0100",
  "2026-01-01T00:00:00-2360",
  "2026-01-01T00:00:00+01",
  "2026-1-1T00:00:00Z",
  "2026-01-01T00:00:00.Z",
  "2026-01-01T00Z",
  "2026-01-01T00:00:00 Z",
  "2026-01-01T00:00:00Zjunk",
  "2026-01-01T00:00:00Z ",
  " 2026-01-01T00:00:00Z",
  "20260101",
  "",
  "not a date",
  "\uff12\uff10\uff12\uff16-01-01T00:00:00Z"
];

// Forms V8 reads through its LEGACY date parser. They are pinned here so the
// Swift port's refusal of them is a recorded, visible difference.
const legacyDateInputs = [
  "2026-01-01 00:00:00Z",
  "2026-01-01Z",
  "Jan 1 2026",
  "2026/01/01"
];

const dateParseCases = dateInputs.map((input, index) => ({
  name: `date_${index}`,
  input,
  milliseconds: Number.isNaN(Date.parse(input)) ? null : Date.parse(input)
}));

const legacyDateParseCases = legacyDateInputs.map((input, index) => ({
  name: `legacy_date_${index}`,
  input,
  milliseconds: Number.isNaN(Date.parse(input)) ? null : Date.parse(input)
}));

// ---------------------------------------------------------------------------
// node's lenient decoders
// ---------------------------------------------------------------------------

const base64Inputs = [
  "YWJj", "YW Jj", "YWJ", "YW=Jj", "YW*Jj", "-_-_", "+/+/", "YWJj\n", "Y", "YQ", "YQ=", "YQ==YQ==",
  "=YWJj", "YWJjZA=x", "", "====", "\u00e9YWJj", "YWJj\ud83d\ude00ZA", "Y\u0000W\u0000J\u0000j", "YQ=\n=",
  // A code unit above U+00FF is read by its LOW byte: U+0141 is "A", and the
  // high surrogate D83D is "=".
  "YWJj\u0141ZA", "YWJj\u0100ZA", "\u0159WJj", "YWJj\u017aA", "YWJj\u4e00ZA",
  "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-P0BBQkNERUZH"
];

const base64Cases = base64Inputs.map((input, index) => ({
  name: `base64_${index}`,
  input,
  hex: Buffer.from(input, "base64").toString("hex")
}));

const hexInputs = ["00ff", "0", "00f", "0g11", "g011", "00 11", "AbCd", "0011zz22", "", "\u00e9\u00e9", "0\u00e9", "0\u0130", "\u0130\u0131", "ab\u0163d", "\u0100\u0100"];

const hexCases = hexInputs.map((input, index) => ({
  name: `hex_${index}`,
  input,
  hex: Buffer.from(input, "hex").toString("hex")
}));

// ---------------------------------------------------------------------------
// keygen: the SHAPE node's output has (values are random by design)
// ---------------------------------------------------------------------------

const sampleKeypair = generateSigningKeypair();
const keygenShape = {
  private_pem_lines: sampleKeypair.privatePem.split("\n").map((line, index, all) =>
    index === 0 || index === all.length - 2 || line === "" ? line : `<base64:${line.length}>`
  ),
  public_pem_lines: sampleKeypair.publicPem.split("\n").map((line, index, all) =>
    index === 0 || index === all.length - 2 || line === "" ? line : `<base64:${line.length}>`
  ),
  private_der_prefix_hex: Buffer.from(sampleKeypair.privatePem.split("\n")[1], "base64")
    .subarray(0, 16)
    .toString("hex"),
  public_der_prefix_hex: Buffer.from(sampleKeypair.publicPem.split("\n")[1], "base64")
    .subarray(0, 12)
    .toString("hex")
};

// ---------------------------------------------------------------------------
// run attestation
// ---------------------------------------------------------------------------

const RUN_KEY_A = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
const RUN_KEY_B = "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100";

const recordTexts = {
  simple: '{"row_id":"checkout.apply_coupon","result":"pass","span_sha256":"sha256:aa"}',
  reordered: '{"span_sha256":"sha256:aa","result":"pass","row_id":"checkout.apply_coupon"}',
  with_existing_attestation:
    '{"row_id":"checkout.apply_coupon","run_attestation":"hmac-sha256:00","result":"pass"}',
  equivalent_keys: '{"\\u00e9":1,"e\\u0301":2}',
  nested_and_unicode: '{"a":[1,{"z":null,"\\ud83d\\ude00":"caf\\u00e9"}],"b":0.1}',
  empty: "{}"
};

const attestationKeys = {
  key_a: RUN_KEY_A,
  key_b: RUN_KEY_B,
  uppercase: RUN_KEY_A.toUpperCase(),
  odd_length: "abc",
  invalid_hex_midway: "0011zz22",
  empty: ""
};

const computeAttestationCases = [];
for (const [recordName, text] of Object.entries(recordTexts)) {
  for (const [keyName, key] of Object.entries(attestationKeys)) {
    computeAttestationCases.push({
      name: `${recordName}_${keyName}`,
      record_text: text,
      key,
      attestation: computeRunAttestation(JSON.parse(text), key)
    });
  }
}

const attested = (text, key = RUN_KEY_A) => {
  const record = JSON.parse(text);
  record.run_attestation = computeRunAttestation(record, key);
  return JSON.stringify(record);
};

const verifyAttestationInputs = [
  { name: "honest", text: attested(recordTexts.simple), key: RUN_KEY_A },
  { name: "honest_after_reordering", text: attested(recordTexts.reordered), key: RUN_KEY_A },
  { name: "equivalent_keys_honest", text: attested(recordTexts.equivalent_keys), key: RUN_KEY_A },
  { name: "other_machine_key", text: attested(recordTexts.simple), key: RUN_KEY_B },
  { name: "no_key", text: attested(recordTexts.simple), key: null },
  { name: "uppercase_key_fails_closed", text: attested(recordTexts.simple, RUN_KEY_A.toUpperCase()), key: RUN_KEY_A.toUpperCase() },
  { name: "short_key", text: attested(recordTexts.simple, "abcd"), key: "abcd" },
  { name: "key_with_trailing_newline", text: attested(recordTexts.simple), key: `${RUN_KEY_A}\n` },
  { name: "no_attestation", text: recordTexts.simple, key: RUN_KEY_A },
  { name: "empty_attestation", text: '{"row_id":"r","run_attestation":""}', key: RUN_KEY_A },
  { name: "attestation_not_a_string", text: '{"row_id":"r","run_attestation":5}', key: RUN_KEY_A },
  { name: "wrong_length", text: '{"row_id":"r","run_attestation":"hmac-sha256:00"}', key: RUN_KEY_A },
  {
    name: "tampered",
    text: attested(recordTexts.simple).replace('"pass"', '"fail"'),
    key: RUN_KEY_A
  },
  {
    name: "equivalent_key_swapped",
    text: attested(recordTexts.equivalent_keys).replace('"e\\u0301":2', '"e\\u0301":3'),
    key: RUN_KEY_A
  }
];

const verifyAttestationCases = verifyAttestationInputs.map((entry) => ({
  name: entry.name,
  record_text: entry.text,
  key: entry.key,
  verified: verifyRunAttestation(JSON.parse(entry.text), entry.key)
}));

const runKeyPathInputs = [
  { name: "default_under_home", env: {}, home: "/Users/someone" },
  { name: "home_with_trailing_slash", env: {}, home: "/Users/someone/" },
  { name: "empty_home", env: {}, home: "" },
  { name: "root_home", env: {}, home: "/" },
  { name: "home_with_dot_dot", env: {}, home: "/a/../b" },
  { name: "override_trimmed", env: { UC_RUN_KEY_FILE: "  /mnt/keys/run-key \n" }, home: "/Users/someone" },
  { name: "blank_override_ignored", env: { UC_RUN_KEY_FILE: " \t\u00a0" }, home: "/Users/someone" },
  { name: "empty_override_ignored", env: { UC_RUN_KEY_FILE: "" }, home: "/Users/someone" },
  { name: "relative_override_kept", env: { UC_RUN_KEY_FILE: "keys//run-key" }, home: "/Users/someone" }
];

// `defaultRunKeyPath` reads the real home directory, so the home-directory
// branch is recorded through the same `path.join` it calls.
const { defaultRunKeyPath } = markers;
const runKeyPathCases = runKeyPathInputs.map((entry) => {
  const override = entry.env.UC_RUN_KEY_FILE;
  const usesOverride = typeof override === "string" && override.trim() !== "";
  return {
    name: entry.name,
    environment: entry.env,
    home_directory: entry.home,
    path: usesOverride ? defaultRunKeyPath(entry.env) : pathJoin(entry.home, ".use-cases", "run-key")
  };
});

// ---------------------------------------------------------------------------
// CI authority
// ---------------------------------------------------------------------------

const ciInputs = {
  local_no_env: { env: {} },
  local_with_override_true: { env: {}, override: "true" },
  local_with_override_null: { env: {}, override: "null" },
  local_with_override_undefined: { env: {}, override: "undefined" },
  github_full: {
    env: {
      GITHUB_ACTIONS: "true",
      GITHUB_REPOSITORY: "octo/app",
      GITHUB_REF: "refs/heads/main",
      GITHUB_SHA: "abc123",
      GITHUB_RUN_ID: "42",
      GITHUB_ACTOR: "octocat",
      GITHUB_EVENT_NAME: "push"
    }
  },
  github_blank_fields_omitted: { env: { GITHUB_ACTIONS: "1", GITHUB_REPOSITORY: "  ", GITHUB_SHA: " abc \n" } },
  github_empty_flag_is_not_github: { env: { GITHUB_ACTIONS: "", GITLAB_CI: "true" } },
  github_override_false: { env: { GITHUB_ACTIONS: "true" }, override: "false" },
  github_override_undefined: { env: { GITHUB_ACTIONS: "true" }, override: "undefined" },
  gitlab_protected: {
    env: {
      GITLAB_CI: "true",
      CI_PROJECT_PATH: "group/app",
      CI_COMMIT_REF_NAME: "main",
      CI_COMMIT_SHA: "def456",
      CI_PIPELINE_ID: "7",
      GITLAB_USER_LOGIN: "dev",
      CI_PIPELINE_SOURCE: "merge_request_event",
      CI_COMMIT_REF_PROTECTED: "true"
    }
  },
  gitlab_unprotected: { env: { GITLAB_CI: "true", CI_COMMIT_REF_PROTECTED: "false" } },
  gitlab_protected_signal_not_exact: { env: { GITLAB_CI: "true", CI_COMMIT_REF_PROTECTED: "TRUE" } },
  gitlab_override_null: { env: { GITLAB_CI: "true", CI_COMMIT_REF_PROTECTED: "true" }, override: "null" },
  circleci_owner_and_repo: {
    env: {
      CIRCLECI: "true",
      CIRCLE_PROJECT_USERNAME: "owner",
      CIRCLE_PROJECT_REPONAME: "repo",
      CIRCLE_BRANCH: "main",
      CIRCLE_SHA1: "789",
      CIRCLE_BUILD_NUM: "12",
      CIRCLE_USERNAME: "builder"
    }
  },
  circleci_repo_only: { env: { CIRCLECI: "true", CIRCLE_PROJECT_REPONAME: "repo" } },
  circleci_owner_only: { env: { CIRCLECI: "true", CIRCLE_PROJECT_USERNAME: "owner" } },
  github_wins_over_others: { env: { CIRCLECI: "true", GITLAB_CI: "true", GITHUB_ACTIONS: "true" } },
  unicode_whitespace_trimmed: { env: { GITHUB_ACTIONS: "true", GITHUB_ACTOR: "\u00a0\ufeffdev\u2028" } }
};

const overrideOptions = (override) => {
  switch (override) {
    case undefined:
      return {};
    case "undefined":
      return { protectedRef: undefined };
    case "null":
      return { protectedRef: null };
    default:
      return { protectedRef: override === "true" };
  }
};

const ciAuthorityCases = Object.entries(ciInputs).map(([name, entry]) => ({
  name,
  environment: entry.env,
  override: entry.override ?? "absent",
  wire: JSON.stringify(detectCiAuthority(entry.env, overrideOptions(entry.override)))
}));

// ---------------------------------------------------------------------------
// append-only
// ---------------------------------------------------------------------------

const appendOnlyInputs = {
  pure_append: [["a", "b"], ["a", "b", "c"]],
  identical: [["a", "b"], ["a", "b"]],
  edited: [["a", "b", "c"], ["a", "X", "c", "d"]],
  deleted: [["a", "b", "c"], ["a", "b"]],
  reordered: [["a", "b", "c"], ["a", "c", "b"]],
  empty_old: [[], ["a"]],
  both_empty: [[], []],
  canonically_equivalent_line_is_an_edit: [["\u00e9"], ["e\u0301"]],
  trailing_whitespace_is_an_edit: [["a"], ["a "]]
};

const appendOnlyCases = Object.entries(appendOnlyInputs).map(([name, [oldLines, newLines]]) => ({
  name,
  old_lines: oldLines,
  new_lines: newLines,
  result: plain(appendOnly(oldLines, newLines))
}));

const splitInputs = ["", "a", "a\n", "a\nb", "a\nb\n", "\n", "\n\n", "a\n\nb\n", "a\r\nb\r\n", "a\n\n"];

const splitCases = splitInputs.map((text, index) => ({
  name: `split_${index}`,
  text,
  lines: splitJsonlLines(text)
}));

// ---------------------------------------------------------------------------
// binding registry and reconciliation
// ---------------------------------------------------------------------------

const registryEvent = (overrides = {}) => ({
  schema: "ucase-binding-registry-event-v1",
  event_type: "binding_registered",
  event_id: overrides.event_id ?? "reg_1",
  created_at: "2026-06-01T00:00:00Z",
  created_by: { tool: "uc", command: "bind", version: "0.7.0" },
  row_id: "checkout.apply_coupon",
  binding_slug: "checkout.apply_coupon#tax",
  reason: "initial binding",
  ...overrides
});

const released = (overrides = {}) =>
  registryEvent({ event_type: "binding_released", reason: "retired", ...overrides });

const jsonl = (...values) => `${values.map((value) => (typeof value === "string" ? value : JSON.stringify(value))).join("\n")}\n`;

const registryInputs = {
  empty: { text: "", rows: [] },
  one_registration: { text: jsonl(registryEvent()), rows: ["checkout.apply_coupon"] },
  parse_error_and_blank_lines: {
    text: `\n${JSON.stringify(registryEvent())}\n{ not json\n \t\u00a0\n`,
    rows: ["checkout.apply_coupon"]
  },
  schema_invalid: {
    text: jsonl({ ...registryEvent(), reason: "", extra: 1 }, { schema: "x" }, "null", "[1]", "\"s\""),
    rows: ["checkout.apply_coupon"]
  },
  slug_prefix_mismatch: {
    text: jsonl(registryEvent({ binding_slug: "checkout.other#tax" })),
    rows: ["checkout.apply_coupon"]
  },
  duplicate_registration: {
    text: jsonl(registryEvent(), registryEvent({ event_id: "reg_2" })),
    rows: ["checkout.apply_coupon"]
  },
  slug_row_conflict: {
    text: jsonl(
      registryEvent({ binding_slug: "checkout.apply_coupon" }),
      registryEvent({ event_id: "reg_2", row_id: "checkout", binding_slug: "checkout.apply_coupon" })
    ),
    rows: ["checkout.apply_coupon", "checkout"]
  },
  release_then_rebind: {
    text: jsonl(
      registryEvent(),
      released({ event_id: "rel_1" }),
      registryEvent({ event_id: "reg_2", reason: "rebound" })
    ),
    rows: ["checkout.apply_coupon"]
  },
  release_without_registration: {
    text: jsonl(released({ event_id: "rel_1" })),
    rows: ["checkout.apply_coupon"]
  },
  retired_row_can_leave_the_matrix: {
    text: jsonl(registryEvent(), released({ event_id: "rel_1" })),
    rows: []
  },
  dangling_rows_reported_in_registration_order: {
    text: jsonl(
      registryEvent({ row_id: "b.row", binding_slug: "b.row#x" }),
      registryEvent({ event_id: "reg_2", row_id: "a.row", binding_slug: "a.row" }),
      registryEvent({ event_id: "reg_3", row_id: "b.row", binding_slug: "b.row" }),
      released({ event_id: "rel_1", row_id: "b.row", binding_slug: "b.row#x" }),
      registryEvent({ event_id: "reg_4", row_id: "b.row", binding_slug: "b.row#x" })
    ),
    rows: []
  },
  many_slugs_per_row: {
    text: jsonl(
      registryEvent({ binding_slug: "checkout.apply_coupon#b" }),
      registryEvent({ event_id: "reg_2", binding_slug: "checkout.apply_coupon#a" }),
      registryEvent({ event_id: "reg_3", binding_slug: "checkout.apply_coupon" }),
      released({ event_id: "rel_1", binding_slug: "checkout.apply_coupon#b" })
    ),
    rows: ["checkout.apply_coupon"]
  },
  crlf_lines: {
    text: `${JSON.stringify(registryEvent())}\r\n`,
    rows: ["checkout.apply_coupon"]
  }
};

const materializedWire = (registry) => ({
  row_to_slugs: [...registry.rowToSlugs].map(([row, slugs]) => [row, [...slugs]]),
  slug_to_row: [...registry.slugToRow]
});

const registryCases = Object.entries(registryInputs).map(([name, entry]) => {
  const read = readBindingsJsonl(entry.text);
  const result = validateBindingsJsonl(entry.text, new Set(entry.rows));
  return {
    name,
    text: entry.text,
    rows: entry.rows,
    read: plain({ lines: read.lines, errors: read.errors }),
    ok: result.ok,
    errors: plain(result.errors),
    events: plain(result.events),
    registry: materializedWire(result.registry),
    rematerialized: materializedWire(materializeRegistry(result.events))
  };
});

const explicitBlock = (prefix, slug, body) =>
  lines(`${markerToken(prefix)}${slug}`, body, `${markerToken(prefix)}end ${slug}`);

const reconcileInputs = {
  in_sync: {
    registry: jsonl(registryEvent()),
    files: [{ file_path: "Tax.py", contents: explicitBlock("#", "checkout.apply_coupon#tax", "x = 1") }]
  },
  marker_removed_is_missing: {
    registry: jsonl(registryEvent(), registryEvent({ event_id: "reg_2", binding_slug: "checkout.apply_coupon#b" })),
    files: [{ file_path: "Tax.py", contents: explicitBlock("#", "checkout.apply_coupon#tax", "x = 1") }]
  },
  unregistered_marker: {
    registry: "",
    files: [
      { file_path: "b.py", contents: explicitBlock("#", "zeta.row#b", "y = 2") },
      { file_path: "a.py", contents: explicitBlock("#", "alpha.row", "x = 1") }
    ]
  },
  registered_row_matches_its_marker: {
    registry: jsonl(registryEvent({ row_id: "alpha.row", binding_slug: "alpha.row" })),
    files: [{ file_path: "a.py", contents: explicitBlock("#", "alpha.row", "x = 1") }]
  },
  rows_sorted_by_code_unit: {
    registry: jsonl(
      registryEvent({ row_id: "b_row", binding_slug: "b_row" }),
      registryEvent({ event_id: "reg_2", row_id: "b.row", binding_slug: "b.row#z" }),
      registryEvent({ event_id: "reg_3", row_id: "b.row", binding_slug: "b.row#a-b" }),
      registryEvent({ event_id: "reg_4", row_id: "b.row", binding_slug: "b.row#a_b" })
    ),
    files: []
  }
};

// A registry built by hand rather than folded from events: validation forces a
// slug's row to be its own prefix, so only a hand-built registry can bind a slug
// to ANOTHER row, which is the branch that makes a marker unregistered.
const handBuiltReconcileInputs = {
  slug_bound_to_another_row: {
    registry: [["beta.row", ["alpha.row"]]],
    files: [{ file_path: "a.py", contents: explicitBlock("#", "alpha.row", "x = 1") }]
  }
};

const handBuiltReconcileCases = Object.entries(handBuiltReconcileInputs).map(([name, entry]) => {
  const rowToSlugs = new Map(entry.registry.map(([row, slugs]) => [row, new Set(slugs)]));
  const slugToRow = new Map(entry.registry.flatMap(([row, slugs]) => slugs.map((slug) => [slug, row])));
  return {
    name,
    registry: entry.registry,
    files: entry.files,
    result: plain(reconcileRegistryWithScan({ rowToSlugs, slugToRow }, scanFiles(entry.files)))
  };
});

const reconcileCases = Object.entries(reconcileInputs).map(([name, entry]) => {
  const registry = validateBindingsJsonl(entry.registry, new Set()).registry;
  return {
    name,
    registry_text: entry.registry,
    files: entry.files,
    result: plain(reconcileRegistryWithScan(registry, scanFiles(entry.files)))
  };
});

// ---------------------------------------------------------------------------
// evidence ledger
// ---------------------------------------------------------------------------

const keyringSpec = {
  keyring_schema_id: "ucase-public-key-registry-v1",
  keys: [
    edKey({ valid_from: "2026-01-01T00:00:00Z" }),
    edKey({ key_id: "old-key", public_key: keys.other.public_pem, status: "revoked" })
  ]
};

function chained(events) {
  const out = [];
  for (const [index, event] of events.entries()) {
    const previous = index === 0 ? GENESIS_ENTRY_HASH : computeLedgerEntryHash(out[index - 1]);
    const unsigned = { ...event, entry_index: index, previous_entry_hash: previous };
    delete unsigned.signature;
    out.push(signWith(unsigned));
  }
  return out;
}

const eventA = unsignedEvent({ event_id: "evt_a" });
const eventB = unsignedEvent({ event_id: "evt_b" });
const eventC = unsignedEvent({ event_id: "evt_c" });
const [chainA, chainB, chainC] = chained([eventA, eventB, eventC]);
const single = { kind: "single", pem };

const equivalentKeysEntry = signWith({ ...unsignedEvent({ event_id: "evt_eq" }), "\u00e9": 1, "e\u0301": 2 });
const afterEquivalentEntry = signWith({
  ...unsignedEvent({ event_id: "evt_after" }),
  entry_index: 1,
  previous_entry_hash: computeLedgerEntryHash(
    JSON.parse(JSON.stringify({ ...equivalentKeysEntry, entry_index: 0, previous_entry_hash: GENESIS_ENTRY_HASH }))
  )
});
const equivalentChainHead = signWith({
  ...unsignedEvent({ event_id: "evt_eq" }),
  "\u00e9": 1,
  "e\u0301": 2,
  entry_index: 0,
  previous_entry_hash: GENESIS_ENTRY_HASH
});
const equivalentChainNext = signWith({
  ...unsignedEvent({ event_id: "evt_after" }),
  entry_index: 1,
  previous_entry_hash: computeLedgerEntryHash(equivalentChainHead)
});

const ledgerInputs = {
  empty: { text: "", resolver: single },
  one_valid_event: { text: jsonl(signWith(eventA)), resolver: single },
  no_key_supplied: { text: jsonl(signWith(eventA)), resolver: { kind: "none" } },
  unsigned_event: { text: jsonl(eventA), resolver: single },
  tampered_event: { text: jsonl({ ...signWith(eventA), event_id: "evt_x" }), resolver: single },
  producer_not_trusted: {
    text: jsonl(signWith({ ...eventA, producer: { ...eventA.producer, kind: "laptop" } })),
    resolver: single
  },
  producer_kind_not_a_string: {
    text: jsonl(signWith({ ...eventA, producer: { ...eventA.producer, kind: [null, 1] } })),
    resolver: single
  },
  verification_not_pass: {
    text: jsonl(signWith({ ...eventA, verification: { ...eventA.verification, result: "fail" } })),
    resolver: single
  },
  binding_set_hash_mismatch: {
    text: jsonl(signWith(unsignedEvent({ binding_set_hash: hash("9") }))),
    resolver: single
  },
  row_missing: { text: jsonl(signWith(eventA)), resolver: single, rows: ["other.row"] },
  row_present: { text: jsonl(signWith(eventA)), resolver: single, rows: ["checkout.apply_coupon"] },
  parse_errors_and_blank_lines: {
    text: `\n${JSON.stringify(signWith(eventA))}\n{ nope\n\u00a0\u2028\n\n`,
    resolver: single
  },
  non_object_lines: { text: jsonl("5", "[1]", "\"s\"", "true"), resolver: single },
  null_line_throws: { text: jsonl("null"), resolver: single },
  non_finite_number_throws: {
    text: `${JSON.stringify(signWith(eventA)).slice(0, -1)},"huge":1e400}\n`,
    resolver: single
  },
  append_only_holds: {
    text: jsonl(signWith(eventA), signWith(eventB)),
    base: jsonl(signWith(eventA)),
    resolver: single
  },
  append_only_edit: {
    text: jsonl(signWith(eventB)),
    base: jsonl(signWith(eventA)),
    resolver: single
  },
  append_only_delete: {
    text: jsonl(signWith(eventA)),
    base: jsonl(signWith(eventA), signWith(eventB)),
    resolver: single
  },
  append_only_empty_base: { text: jsonl(signWith(eventA)), base: "", resolver: single },
  keyring_in_window: { text: jsonl(signWith(eventA)), resolver: { kind: "keyring", keyring: keyringSpec } },
  keyring_before_window: {
    text: jsonl(signWith(unsignedEvent({ created_at: "2025-01-01T00:00:00Z" }))),
    resolver: { kind: "keyring", keyring: keyringSpec }
  },
  keyring_revoked_key: {
    text: jsonl(signWith(eventA, "other", "old-key")),
    resolver: { kind: "keyring", keyring: keyringSpec }
  },
  chained_valid: { text: jsonl(chainA, chainB, chainC), resolver: single },
  chain_broken_by_edit: {
    text: jsonl(chainA, { ...chainB, event_id: "evt_edited" }, chainC),
    resolver: single
  },
  chain_truncated_at_head: { text: jsonl(chainB, chainC), resolver: single },
  chain_reordered: { text: jsonl(chainA, chainC, chainB), resolver: single },
  chain_duplicate_index: { text: jsonl(chainA, chainB, chainB), resolver: single },
  legacy_prefix_then_chain: {
    text: jsonl(
      signWith(eventA),
      signWith({ ...eventB, entry_index: 1, previous_entry_hash: computeLedgerEntryHash(signWith(eventA)) })
    ),
    resolver: single
  },
  half_present_chain_fields: {
    text: jsonl(signWith({ ...eventA, entry_index: 0 })),
    resolver: single
  },
  fractional_entry_index: {
    text: jsonl(signWith({ ...eventA, entry_index: 0.5, previous_entry_hash: GENESIS_ENTRY_HASH })),
    resolver: single
  },
  chain_entry_hash_over_equivalent_keys: {
    text: jsonl(equivalentChainHead, equivalentChainNext),
    resolver: single
  },
  equivalent_keys_entry_unchained: {
    text: jsonl(equivalentKeysEntry, afterEquivalentEntry),
    resolver: single
  },
  lenient_signature_base64: {
    text: jsonl(withSignatureValue(signWith(eventA), signWith(eventA).signature.value.replace(/=+$/, "").replace(/\+/g, "-"))),
    resolver: single
  }
};

const ledgerResolver = (spec) => resolverFor(spec);

const ledgerCases = Object.entries(ledgerInputs).map(([name, entry]) => {
  const options = { publicKeyResolver: ledgerResolver(entry.resolver) };
  if (entry.base !== undefined) {
    options.baseRefOldText = entry.base;
  }
  if (entry.rows !== undefined) {
    options.yamlRowIds = new Set(entry.rows);
  }
  const outcome = captureThrow(() => {
    const result = validateEvidenceLedger(entry.text, options);
    return {
      ok: result.ok,
      errors: result.errors,
      event_ids: result.events.map((event) => event.event_id),
      append_only: result.append_only,
      summary: result.summary,
      key_resolution_only: evidenceErrorsAreKeyResolutionOnly(result.errors)
    };
  });
  const read = readEvidenceJsonl(entry.text);
  return {
    name,
    text: entry.text,
    resolver: entry.resolver,
    base: entry.base ?? null,
    rows: entry.rows ?? null,
    outcome,
    chain: captureThrow(() => verifyLedgerChain(read.lines)),
    entry_hashes: read.lines.map((line) => captureThrow(() => computeLedgerEntryHash(line.value)))
  };
});

// ---------------------------------------------------------------------------
// marker schema validators
// ---------------------------------------------------------------------------

const schemaValidationInputs = [
  { name: "registry_valid", schema: "ucase-binding-registry-event-v1", value: registryEvent() },
  {
    name: "registry_many_errors",
    schema: "ucase-binding-registry-event-v1",
    value: { ...registryEvent(), event_type: "x", row_id: "Bad", created_by: { tool: "" }, extra: 1 }
  },
  { name: "proof_valid", schema: "ucase-proof-event-v1", value: signWith(eventA) },
  {
    name: "proof_nested_errors",
    schema: "ucase-proof-event-v1",
    value: {
      ...signWith(eventA),
      bindings: { ...eventA.bindings, items: [{ ...baseItems[0], span_start_line: 0, span_sha256: "nope" }] },
      authority: { type: "ci", provider: "jenkins", protected_ref: "yes" },
      entry_index: -1
    }
  },
  { name: "status_empty_object", schema: "ucase-freshness-status-v1", value: {} },
  { name: "unknown_schema", schema: "ucase-nothing-v1", value: {} },
  { name: "registry_not_an_object", schema: "ucase-binding-registry-event-v1", value: [1] }
];

const schemaValidationCases = schemaValidationInputs.map((entry) => ({
  name: entry.name,
  schema: entry.schema,
  value_text: JSON.stringify(entry.value),
  result: plain(validateMarkerSchema(entry.schema, JSON.parse(JSON.stringify(entry.value))))
}));

// ---------------------------------------------------------------------------
// git diff parsing
// ---------------------------------------------------------------------------

const nameStatusInputs = {
  empty: "",
  modify_add_delete: "M\0a.swift\0A\0b.swift\0D\0c.swift\0",
  rename_with_score: "R087\0old.swift\0new.swift\0",
  copy_is_an_add: "C100\0src.swift\0copy.swift\0",
  type_change_reads_as_modified: "T\0link\0",
  malformed_rename_tail: "M\0a.swift\0R100\0only-old.swift\0",
  malformed_modify_tail: "M\0a.swift\0D",
  paths_with_spaces_and_unicode: "M\0dir with space/caf\u00e9.swift\0A\0\ud83d\ude00.txt\0",
  no_trailing_nul: "M\0a.swift"
};

const nameStatusCases = Object.entries(nameStatusInputs).map(([name, text]) => ({
  name,
  text,
  changes: plain(parseNameStatusZ(text))
}));

const hunkInputs = {
  empty: "",
  single_line_default_count: "@@ -1 +2 @@\n+x",
  counted: "@@ -3,2 +10,4 @@ func f() {\n+a\n+b",
  pure_deletion: "@@ -5,3 +4,0 @@\n-x",
  many: "diff --git a/x b/x\n@@ -1,0 +1,2 @@\n+a\n+b\n@@ -10 +12 @@\n-c\n+d",
  not_at_line_start: " @@ -1 +1 @@",
  missing_space: "@@ -1 +1@@",
  crlf_line_ending: "@@ -1,2 +3,4 @@\r\n",
  non_ascii_digits_rejected: "@@ -1 +\u0661 @@",
  leading_zeros: "@@ -01 +007,003 @@"
};

const hunkCases = Object.entries(hunkInputs).map(([name, text]) => ({
  name,
  text,
  ranges: plain(parseUnifiedZeroHunks(text))
}));

const overlapInputs = [
  [[1, 5], [5, 9]],
  [[1, 4], [5, 9]],
  [[5, 9], [1, 4]],
  [[3, 3], [3, 3]],
  [[1, 10], [4, 5]]
];

const overlapCases = overlapInputs.map(([a, b], index) => ({
  name: `overlap_${index}`,
  a,
  b,
  overlaps: rangesOverlap({ start_line: a[0], end_line: a[1] }, { start_line: b[0], end_line: b[1] })
}));

// ---------------------------------------------------------------------------
// git: a real repository, replayed step for step on the Swift side
// ---------------------------------------------------------------------------

// Steps are argv lists run with `git` (file writes are `write`), so the Swift
// test can replay exactly the same history into its own temporary directory.
const identity = ["-c", "user.name=Use Cases", "-c", "user.email=use-cases@example.com", "-c", "commit.gpgsign=false"];
const gitSteps = [
  ["git", "init", "-q", "-b", "main"],
  ["write", "keep.swift", "line 1\nline 2\nline 3\nline 4\nline 5\n"],
  ["write", "gone.swift", "bye\n"],
  ["write", "moved.swift", "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\n"],
  ["write", ".use-cases/proofs.jsonl", '{"a":1}\n'],
  ["git", "add", "-A"],
  ["git", ...identity, "commit", "-q", "-m", "base"],
  ["git", "tag", "base"],
  ["write", "keep.swift", "line 1\nchanged 2\nline 3\nline 4\nadded\nline 5\n"],
  ["git", "rm", "-q", "gone.swift"],
  ["git", "mv", "moved.swift", "renamed.swift"],
  ["write", "fresh.swift", "new\n"],
  ["git", "add", "fresh.swift"],
  ["git", ...identity, "commit", "-q", "-m", "second"],
  ["write", "keep.swift", "line 1\nchanged 2\nline 3\nline 4\nadded\nline 5\nstaged\n"],
  ["git", "add", "keep.swift"],
  ["write", "keep.swift", "worktree\nline 1\nchanged 2\nline 3\nline 4\nadded\nline 5\nstaged\n"],
  ["write", "caf\u00e9.swift", "untracked is invisible to git diff\n"]
];

const repository = mkdtempSync(join(tmpdir(), "uc-ledger-corpus-"));
try {
  for (const step of gitSteps) {
    if (step[0] === "write") {
      mkdirSync(dirname(join(repository, step[1])), { recursive: true });
      writeFileSync(join(repository, step[1]), step[2]);
    } else {
      execFileSync(step[0], step.slice(1), { cwd: repository, stdio: "pipe" });
    }
  }
} catch (error) {
  rmSync(repository, { recursive: true, force: true });
  throw error;
}

const quietRunner = (args, cwd) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: "pipe" });

const collectCases = [
  { name: "working_tree_against_head", options: {} },
  { name: "staged_against_head", options: { staged: true } },
  { name: "working_tree_against_base_tag", options: { base: "base" } },
  { name: "staged_wins_over_base", options: { staged: true, base: "base" } }
].map((entry) => ({
  name: entry.name,
  base: entry.options.base ?? null,
  staged: entry.options.staged ?? false,
  result: plain(collectChangedFiles({ ...entry.options, cwd: repository, runner: quietRunner }))
}));

const baseRefCases = [
  { name: "present_at_head", ref: "HEAD", path: "keep.swift" },
  { name: "present_at_tag", ref: "base", path: ".use-cases/proofs.jsonl" },
  { name: "deleted_since_tag", ref: "HEAD", path: "gone.swift" },
  { name: "added_after_tag", ref: "base", path: "fresh.swift" },
  { name: "exists_on_disk_not_at_ref", ref: "HEAD", path: "caf\u00e9.swift" },
  { name: "unknown_ref", ref: "no-such-ref", path: "keep.swift" }
].map((entry) => ({
  ...entry,
  result: captureThrow(() => readBaseRefFile(entry.ref, entry.path, { cwd: repository, runner: quietRunner }))
}));

rmSync(repository, { recursive: true, force: true });

// ---------------------------------------------------------------------------
// emit
// ---------------------------------------------------------------------------

const corpus = {
  keys,
  genesis_entry_hash: GENESIS_ENTRY_HASH,
  json_key_identity: keyIdentityCases,
  binding_set_hash: bindingSetCases,
  policy_hash: policyHashCases,
  row_hash: rowHashCases,
  proof_signature: signatureCases,
  signing: signingCases,
  keyring_parse: keyringParseCases,
  keyring_load: keyringLoadCases,
  keyring_resolver: keyringResolverCases,
  date_parse: dateParseCases,
  legacy_date_parse: legacyDateParseCases,
  base64_decode: base64Cases,
  hex_decode: hexCases,
  keygen_shape: keygenShape,
  compute_attestation: computeAttestationCases,
  verify_attestation: verifyAttestationCases,
  run_key_path: runKeyPathCases,
  ci_authority: ciAuthorityCases,
  append_only: appendOnlyCases,
  split_jsonl: splitCases,
  registry: registryCases,
  reconcile: reconcileCases,
  reconcile_hand_built: handBuiltReconcileCases,
  evidence_ledger: ledgerCases,
  schema_validation: schemaValidationCases,
  name_status: nameStatusCases,
  hunks: hunkCases,
  overlaps: overlapCases,
  git_steps: gitSteps,
  collect_changed_files: collectCases,
  read_base_ref: baseRefCases
};

// Every non-ASCII code unit (including each half of a surrogate pair) becomes
// a \uXXXX escape, so the emitted Swift file is pure ASCII.
const asciiJson = JSON.stringify(corpus).replace(
  /[\u007f-\uffff]/g,
  (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`
);

let pounds = "#";
while (asciiJson.includes(`\\${pounds}`) || asciiJson.includes(`"""${pounds}`)) {
  pounds += "#";
}

const names = (cases) => cases.map((entry) => `    ${JSON.stringify(entry.name)},`).join("\n");
const nameList = (label, cases) => `  static let ${label}: [String] = [\n${names(cases)}\n  ]\n`;

const swift = `// swiftlint:disable single_line_closure_body line_length
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript marker code. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/markers returned for the input
// beside it. Registry events, proof events, their hashes and signatures land in
// ledgers, so these bytes are frozen contract (ADR 0007 decision 8).
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-markers-ledger-corpus.mjs
enum MarkersLedgerGoldenCorpus {
${nameList("jsonKeyIdentityCaseNames", keyIdentityCases)}
${nameList("bindingSetHashCaseNames", bindingSetCases)}
${nameList("policyHashCaseNames", policyHashCases)}
${nameList("proofSignatureCaseNames", signatureCases)}
${nameList("signingCaseNames", signingCases)}
${nameList("computeAttestationCaseNames", computeAttestationCases)}
${nameList("verifyAttestationCaseNames", verifyAttestationCases)}
${nameList("ciAuthorityCaseNames", ciAuthorityCases)}
${nameList("registryCaseNames", registryCases)}
${nameList("reconcileCaseNames", reconcileCases)}
${nameList("evidenceLedgerCaseNames", ledgerCases)}
${nameList("keyringResolverCaseNames", keyringResolverCases)}
${nameList("dateParseCaseNames", dateParseCases)}
  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${asciiJson}
  """${pounds}
}

// swiftlint:enable single_line_closure_body line_length
`;

writeFileSync(targetPath, swift);
const written = readFileSync(targetPath, "utf8");
if (!/^[\x00-\x7f]*$/.test(written)) {
  throw new Error("corpus file is not ASCII");
}
console.log(
  `wrote ${targetPath}: ${signatureCases.length} signature, ${ledgerCases.length} ledger, ` +
    `${registryCases.length} registry, ${bindingSetCases.length} binding-set, ` +
    `${policyHashCases.length} policy, ${rowHashCases.length} row-hash, ` +
    `${computeAttestationCases.length} attestation cases`
);
