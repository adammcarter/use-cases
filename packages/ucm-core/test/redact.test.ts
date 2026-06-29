import { describe, expect, test } from "vitest";
import { redactSecrets } from "../src/redact.js";

describe("redactSecrets shared util", () => {
  test("redacts labelled secret/token/password/api_key assignments, preserving the label and its case", () => {
    expect(redactSecrets("api_key=SECRETVALUE")).toBe("api_key=[redacted]");
    expect(redactSecrets("API-KEY: hunter2hunter2")).toBe("API-KEY=[redacted]");
    expect(redactSecrets("token: abc123def456")).toBe("token=[redacted]");
    expect(redactSecrets("password = p@ssw0rd!")).toBe("password=[redacted]");
    expect(redactSecrets("Secret=topsecretvalue")).toBe("Secret=[redacted]");
  });

  test("redacts OpenAI-style sk- tokens", () => {
    expect(redactSecrets("key is sk-ABCD1234efgh5678 here")).toBe("key is sk-[redacted] here");
  });

  test("redacts GitHub ghp_/gho_ tokens", () => {
    expect(redactSecrets("ghp_0123456789abcdefABCDEF0123456789abcdef")).toBe("ghp_[redacted]");
    expect(redactSecrets("gho_0123456789abcdefABCDEF0123456789abcdef")).toBe("gho_[redacted]");
  });

  test("redacts AWS access key ids", () => {
    expect(redactSecrets("AKIAIOSFODNN7EXAMPLE")).toBe("AKIA[redacted]");
  });

  test("leaves legitimate prose with no secret pattern unchanged", () => {
    const prose = "The api documentation explains how tokens and secrets work in general.";
    expect(redactSecrets(prose)).toBe(prose);
    // Short / non-matching look-alikes must survive verbatim.
    expect(redactSecrets("skiing on the slopes")).toBe("skiing on the slopes");
    expect(redactSecrets("sk-short")).toBe("sk-short");
    expect(redactSecrets("AKIASHORT")).toBe("AKIASHORT");
  });

  test("redacts multiple distinct secrets in one string", () => {
    const input = "use api_key=AAA and sk-ZZZZ1111YYYY2222 together";
    expect(redactSecrets(input)).toBe("use api_key=[redacted] and sk-[redacted] together");
  });
});
