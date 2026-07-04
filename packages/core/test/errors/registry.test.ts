import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { EvidenceErrorCode } from "../../src/markers/evidenceLedger.js";
import { MarkerErrorCode } from "../../src/markers/markerLine.js";
import { SignatureFailureCode } from "../../src/markers/proofSignature.js";
import { RegistryErrorCode } from "../../src/markers/registry.js";
import { SwiftFuncErrorCode } from "../../src/markers/swiftFuncRecognizer.js";
import {
  LEGACY_ENUM_CODE_MAP,
  LEGACY_STRING_CODE_MAP,
  mapEnumCode,
  mapStringCode,
  UCM_ERROR_CODES,
  UCM_ERROR_REGISTRY,
  type UcmErrorCode
} from "../../src/errors/registry.js";
import { renderErrorCodesMarkdown } from "../../src/errors/render.js";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../../..");

const ENUM_FAMILIES = {
  marker: MarkerErrorCode,
  registry: RegistryErrorCode,
  evidence: EvidenceErrorCode,
  swiftFunc: SwiftFuncErrorCode,
  signature: SignatureFailureCode
} as const;

const VALID_SEVERITIES = new Set(["error", "warning", "info"]);

describe("Use Cases error-code registry", () => {
  it("has no duplicate codes and every entry is well-formed", () => {
    const codes = Object.keys(UCM_ERROR_REGISTRY);
    expect(new Set(codes).size).toBe(codes.length);

    for (const [code, entry] of Object.entries(UCM_ERROR_REGISTRY)) {
      expect(code, `${code} must start with UCM_`).toMatch(/^UCM_[A-Z0-9_]+$/);
      expect(entry.message.length, `${code} message`).toBeGreaterThan(0);
      expect(VALID_SEVERITIES.has(entry.severity), `${code} severity`).toBe(true);
      expect(entry.surface.length, `${code} surface`).toBeGreaterThan(0);
      expect(entry.docs, `${code} docs`).toBe(`errors/${code}`);
    }
  });

  it("exposes UCM_ERROR_CODES sorted and consistent with the registry", () => {
    expect([...UCM_ERROR_CODES].sort()).toEqual(UCM_ERROR_CODES);
    expect(new Set(UCM_ERROR_CODES)).toEqual(new Set(Object.keys(UCM_ERROR_REGISTRY)));
  });

  describe("legacy enum mapping", () => {
    for (const [family, enumObject] of Object.entries(ENUM_FAMILIES)) {
      it(`is exhaustive over ${family} and maps each value to exactly one valid UCM_* code`, () => {
        const enumValues = Object.values(enumObject);
        const familyMap = LEGACY_ENUM_CODE_MAP[family as keyof typeof LEGACY_ENUM_CODE_MAP] as Record<
          string,
          UcmErrorCode
        >;

        // Exhaustive: every enum value is mapped.
        for (const value of enumValues) {
          const mapped = familyMap[value];
          expect(mapped, `${family}.${value} must be mapped`).toBeDefined();
          // Maps to exactly one valid registry code.
          expect(UCM_ERROR_REGISTRY[mapped]).toBeDefined();
          // The runtime helper agrees with the table.
          expect(mapEnumCode(family as never, value as never)).toBe(mapped);
        }

        // No extra keys in the map beyond the enum's own values.
        expect(new Set(Object.keys(familyMap))).toEqual(new Set(enumValues));
      });
    }

    it("throws for an unknown enum code", () => {
      expect(() => mapEnumCode("marker" as never, "NOPE" as never)).toThrow(/No UCM_\* code/);
    });
  });

  describe("legacy string-literal mapping", () => {
    it("maps every known string code to a valid registry code", () => {
      for (const [legacy, uc] of Object.entries(LEGACY_STRING_CODE_MAP)) {
        expect(UCM_ERROR_REGISTRY[uc], `${legacy} -> ${uc}`).toBeDefined();
        expect(mapStringCode(legacy)).toBe(uc);
      }
    });

    it("returns undefined for an unknown string code", () => {
      expect(mapStringCode("definitely.not.a.code")).toBeUndefined();
    });
  });

  it("docs/reference/error-codes.md is in sync with the registry", () => {
    const onDisk = readFileSync(resolve(repoRoot, "docs/reference/error-codes.md"), "utf8");
    expect(onDisk).toBe(renderErrorCodesMarkdown());
  });
});
