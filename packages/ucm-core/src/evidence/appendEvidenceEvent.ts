import { createHash, randomBytes } from "node:crypto";
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, rmSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import { PresentationSkillsError } from "../errors.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import type { EvidenceAppendResultData, EvidenceEvent, EvidenceKind, EvidenceResult, EvidenceTarget } from "./types.js";
import { evidenceRelativePath, evidenceRoot } from "./jsonlLedger.js";
import { replayEvidence } from "./replayEvidence.js";

export type AppendEvidenceEventOptions = {
  context: ResolvedWorkspaceContext;
  idempotencyKey: string;
  target: EvidenceTarget;
  kind: EvidenceKind;
  result: EvidenceResult;
  summary: string;
  actorType: "user" | "agent" | "script" | "system";
  hostSurface: EvidenceEvent["host_surface"];
};

export type VoidEvidenceEventOptions = {
  context: ResolvedWorkspaceContext;
  evidenceId: string;
  expectedHeadEventId: string;
  reason: string;
  idempotencyKey: string;
  actorType: "user" | "agent" | "script" | "system";
  hostSurface: EvidenceEvent["host_surface"];
};

export type AppendEvidenceEventResult = EvidenceAppendResultData & {
  ledgerPath: string;
};

export function appendEvidenceEvent(options: AppendEvidenceEventOptions): AppendEvidenceEventResult {
  return withEvidenceAppendLock(options.context, () => appendUnderLock(options));
}

export function appendEvidenceVoidEvent(options: VoidEvidenceEventOptions): AppendEvidenceEventResult {
  return withEvidenceAppendLock(options.context, () => voidUnderLock(options));
}

function appendUnderLock(options: AppendEvidenceEventOptions): AppendEvidenceEventResult {
  const snapshot = replayEvidence({ context: options.context });
  if (!snapshot.complete) {
    throw new PresentationSkillsError("Refusing to append to damaged evidence history.", "evidence_ledger_damaged");
  }
  const intentDigest = digestIntent(options);
  const existing = snapshot.events.find((event) => event.idempotency_key === options.idempotencyKey);
  if (existing) {
    if (existing.intent_digest === intentDigest) {
      const ledgerPath = ledgerPathFor(options.context, existing.aggregate_id);
      return {
        schema_version: 1,
        appended: false,
        event: existing,
        ledger_path: evidenceRelativePath(options.context, ledgerPath),
        durability: "file_synced",
        ledgerPath
      };
    }
    throw new PresentationSkillsError("Idempotency key was reused with different intent.", "evidence_idempotency_conflict");
  }

  const eventId = uuidv7();
  const event = recordedEventFromOptions(options, eventId, intentDigest);
  const ledgerPath = ledgerPathFor(options.context, event.aggregate_id);
  mkdirSync(dirname(ledgerPath), { recursive: true });
  const fd = openSync(ledgerPath, "a");
  try {
    writeSync(fd, `${JSON.stringify(event)}\n`);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }

  return {
    schema_version: 1,
    appended: true,
    event,
    ledger_path: evidenceRelativePath(options.context, ledgerPath),
    durability: "file_synced",
    ledgerPath
  };
}

function voidUnderLock(options: VoidEvidenceEventOptions): AppendEvidenceEventResult {
  const snapshot = replayEvidence({ context: options.context });
  if (!snapshot.complete) {
    throw new PresentationSkillsError("Refusing to append to damaged evidence history.", "evidence_ledger_damaged");
  }
  const aggregate = snapshot.aggregates.find((item) => item.evidenceId === options.evidenceId);
  if (!aggregate || aggregate.status !== "active") {
    throw new PresentationSkillsError("Evidence aggregate is not active.", "evidence_invalid_transition");
  }
  const currentHead = aggregate.eventIds.at(-1);
  if (currentHead !== options.expectedHeadEventId) {
    throw new PresentationSkillsError("Expected head event does not match current head.", "evidence_expected_head_mismatch");
  }
  const intentDigest = digestIntent({
    context: options.context,
    idempotencyKey: options.idempotencyKey,
    target: {
      use_case_id: options.evidenceId,
      use_case_semantic_hash: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    },
    kind: "manual_observation",
    result: "observed",
    summary: options.reason,
    actorType: options.actorType,
    hostSurface: options.hostSurface
  });
  const existing = snapshot.events.find((event) => event.idempotency_key === options.idempotencyKey);
  if (existing) {
    if (existing.intent_digest === intentDigest) {
      const ledgerPath = ledgerPathFor(options.context, existing.aggregate_id);
      return {
        schema_version: 1,
        appended: false,
        event: existing,
        ledger_path: evidenceRelativePath(options.context, ledgerPath),
        durability: "file_synced",
        ledgerPath
      };
    }
    throw new PresentationSkillsError("Idempotency key was reused with different intent.", "evidence_idempotency_conflict");
  }

  const eventId = uuidv7();
  const event: EvidenceEvent = {
    schema_version: 1,
    event_type: "evidence_voided",
    event_id: eventId,
    aggregate_id: options.evidenceId,
    sequence: aggregate.eventIds.length + 1,
    recorded_at: new Date().toISOString(),
    actor_type: options.actorType,
    host_surface: options.hostSurface,
    idempotency_key: options.idempotencyKey,
    intent_digest: intentDigest,
    target_event_id: options.expectedHeadEventId,
    reason: options.reason
  };
  const ledgerPath = ledgerPathFor(options.context, options.evidenceId);
  const fd = openSync(ledgerPath, "a");
  try {
    writeSync(fd, `${JSON.stringify(event)}\n`);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  return {
    schema_version: 1,
    appended: true,
    event,
    ledger_path: evidenceRelativePath(options.context, ledgerPath),
    durability: "file_synced",
    ledgerPath
  };
}

function recordedEventFromOptions(
  options: AppendEvidenceEventOptions,
  eventId: string,
  intentDigest: string
): EvidenceEvent {
  const now = new Date().toISOString();
  return {
    schema_version: 1,
    event_type: "evidence_recorded",
    event_id: eventId,
    aggregate_id: eventId,
    sequence: 1,
    recorded_at: now,
    actor_type: options.actorType,
    host_surface: options.hostSurface,
    idempotency_key: options.idempotencyKey,
    intent_digest: intentDigest,
    payload: {
      targets: [options.target],
      kind: options.kind,
      captured_at: now,
      result: options.result,
      summary: options.summary,
      producer: { type: options.actorType },
      method: { type: options.actorType === "script" ? "structured_command" : "reported" },
      evidence_kind: options.kind,
      use_case_ids: [options.target.use_case_id],
      verifier: { type: options.actorType === "system" ? "agent" : options.actorType },
      verdict: options.result === "inconclusive" || options.result === "observed" ? "partial" : options.result
    }
  };
}

function ledgerPathFor(context: ResolvedWorkspaceContext, evidenceId: string): string {
  const prefix = evidenceId.slice(0, 2);
  return join(evidenceRoot(context), "by-id", prefix, `${evidenceId}.jsonl`);
}

function withEvidenceAppendLock<T>(context: ResolvedWorkspaceContext, work: () => T): T {
  const lockDir = join(evidenceRoot(context), ".locks/append.lock");
  mkdirSync(dirname(lockDir), { recursive: true });
  const deadline = Date.now() + 30_000;
  while (true) {
    try {
      mkdirSync(lockDir);
      break;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST" || Date.now() > deadline) {
        throw new PresentationSkillsError("Timed out acquiring evidence append lock.", "evidence_lock_timeout");
      }
      sleep(25);
    }
  }
  try {
    return work();
  } finally {
    rmSync(lockDir, { recursive: true, force: true });
  }
}

function digestIntent(options: AppendEvidenceEventOptions): string {
  return `sha256:${createHash("sha256").update(canonicalJson({
    target: options.target,
    kind: options.kind,
    result: options.result,
    summary: options.summary,
    actorType: options.actorType,
    hostSurface: options.hostSurface
  })).digest("hex")}`;
}

function uuidv7(): string {
  const timestamp = Date.now().toString(16).padStart(12, "0");
  const random = randomBytes(10).toString("hex");
  return [
    timestamp.slice(0, 8),
    timestamp.slice(8, 12),
    `7${random.slice(0, 3)}`,
    `8${random.slice(3, 6)}`,
    random.slice(6, 18)
  ].join("-");
}

function sleep(milliseconds: number): void {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
}

function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, item]) => item !== undefined)
    .sort(([left], [right]) => left.localeCompare(right));
  return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonicalJson(item)}`).join(",")}}`;
}
