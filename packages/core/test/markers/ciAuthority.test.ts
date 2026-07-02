// CI-neutral provenance authority detection (public-v1, Phase 2).
//
// detectCiAuthority is PURE (env passed in). These tests pin the recognition of
// GitHub Actions, GitLab CI, and CircleCI from representative env maps, the
// local/generic fallback when no CI env is present, the protected_ref tri-state,
// the protectedRef override option, and the schema-validity of every emitted
// record (it must satisfy the public authority.schema.json).
import Ajv2020Module, { type ValidateFunction } from "ajv/dist/2020.js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import { detectCiAuthority, type CiAuthority } from "../../src/markers/ciAuthority.js";

const AUTHORITY_SCHEMA = fileURLToPath(
  new URL("../../../../schemas/v1/authority.schema.json", import.meta.url)
);

function authorityValidator(): ValidateFunction {
  const Ajv2020 = Ajv2020Module.default;
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  const schema = JSON.parse(readFileSync(AUTHORITY_SCHEMA, "utf8")) as Record<string, unknown>;
  return ajv.compile(schema);
}

const validate = authorityValidator();

function expectSchemaValid(authority: CiAuthority): void {
  const ok = validate(authority);
  if (!ok) {
    throw new Error(`authority not schema-valid: ${JSON.stringify(validate.errors)}`);
  }
  expect(ok).toBe(true);
}

describe("detectCiAuthority", () => {
  test("recognises GitHub Actions from its env vars", () => {
    const authority = detectCiAuthority({
      GITHUB_ACTIONS: "true",
      GITHUB_REPOSITORY: "use-case-matrix/use-case-matrix",
      GITHUB_REF: "refs/heads/main",
      GITHUB_SHA: "0123456789abcdef0123456789abcdef01234567",
      GITHUB_RUN_ID: "1234567890",
      GITHUB_ACTOR: "octocat",
      GITHUB_EVENT_NAME: "push"
    });
    expect(authority).toEqual({
      type: "ci",
      provider: "github-actions",
      repository: "use-case-matrix/use-case-matrix",
      ref: "refs/heads/main",
      commit: "0123456789abcdef0123456789abcdef01234567",
      run_id: "1234567890",
      actor: "octocat",
      // protected_ref is unknowable from the runner env.
      protected_ref: null,
      event: "push"
    });
    expectSchemaValid(authority);
  });

  test("recognises GitLab CI, including its explicit protected-ref signal", () => {
    const authority = detectCiAuthority({
      GITLAB_CI: "true",
      CI_PROJECT_PATH: "group/project",
      CI_COMMIT_REF_NAME: "main",
      CI_COMMIT_SHA: "abcabcabcabcabcabcabcabcabcabcabcabcabca",
      CI_PIPELINE_ID: "99887766",
      GITLAB_USER_LOGIN: "gitlab-user",
      CI_COMMIT_REF_PROTECTED: "true",
      CI_PIPELINE_SOURCE: "merge_request_event"
    });
    expect(authority).toEqual({
      type: "ci",
      provider: "gitlab-ci",
      repository: "group/project",
      ref: "main",
      commit: "abcabcabcabcabcabcabcabcabcabcabcabcabca",
      run_id: "99887766",
      actor: "gitlab-user",
      protected_ref: true,
      event: "merge_request_event"
    });
    expectSchemaValid(authority);
  });

  test("GitLab protected_ref is false when the signal says so", () => {
    const authority = detectCiAuthority({
      GITLAB_CI: "true",
      CI_PROJECT_PATH: "group/project",
      CI_COMMIT_REF_PROTECTED: "false"
    });
    expect(authority.protected_ref).toBe(false);
    expectSchemaValid(authority);
  });

  test("recognises CircleCI and composes owner/repo", () => {
    const authority = detectCiAuthority({
      CIRCLECI: "true",
      CIRCLE_PROJECT_USERNAME: "acme",
      CIRCLE_PROJECT_REPONAME: "widgets",
      CIRCLE_BRANCH: "main",
      CIRCLE_SHA1: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
      CIRCLE_BUILD_NUM: "4242",
      CIRCLE_USERNAME: "circle-user"
    });
    expect(authority).toEqual({
      type: "ci",
      provider: "circleci",
      repository: "acme/widgets",
      ref: "main",
      commit: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
      run_id: "4242",
      actor: "circle-user",
      protected_ref: null
    });
    expectSchemaValid(authority);
  });

  test("falls back to local/generic when no CI env is present", () => {
    const authority = detectCiAuthority({});
    expect(authority).toEqual({ type: "local", provider: "generic" });
    expectSchemaValid(authority);
  });

  test("falls back to local/generic for an unrecognised CI", () => {
    const authority = detectCiAuthority({ CI: "true", TRAVIS: "true" });
    expect(authority).toEqual({ type: "local", provider: "generic" });
    expectSchemaValid(authority);
  });

  test("omits optional fields whose env vars are absent", () => {
    const authority = detectCiAuthority({ GITHUB_ACTIONS: "true" });
    expect(authority).toEqual({
      type: "ci",
      provider: "github-actions",
      protected_ref: null
    });
    expect(authority).not.toHaveProperty("repository");
    expect(authority).not.toHaveProperty("event");
    expectSchemaValid(authority);
  });

  test("protectedRef option overrides the detected tri-state across providers", () => {
    const github = detectCiAuthority({ GITHUB_ACTIONS: "true" }, { protectedRef: true });
    expect(github.protected_ref).toBe(true);

    const gitlab = detectCiAuthority(
      { GITLAB_CI: "true", CI_COMMIT_REF_PROTECTED: "true" },
      { protectedRef: false }
    );
    expect(gitlab.protected_ref).toBe(false);

    const local = detectCiAuthority({}, { protectedRef: null });
    expect(local).toEqual({ type: "local", provider: "generic", protected_ref: null });
    expectSchemaValid(local);
  });
});
