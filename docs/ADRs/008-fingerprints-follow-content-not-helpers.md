# ADR 008: Fingerprints follow content, never helpers

## Status

Accepted - 2026-09-25

## Context

Freshness answers whether an old result still applies. If the fingerprint included the command, toolchain or file locations, harmless changes would make evidence stale. Changing `swift test --filter X` to `swift test`, or moving a function, are examples. If it left out real inputs, stale evidence would still look verified.

## Decision

A route fingerprint covers:
- the use case's intent
- the covered scenarios
- the route definition
- the content of its implementation links, its validation links and its resources
- the freshness policy

It never includes:
- bridge settings, commands, transformers or report names
- the title, description or out-of-scope list
- locators, in the default `content` mode

The strict `content-and-locator` mode adds locators. Encoding is exact: canonical JSON, domain-separated SHA-256 and published test vectors.

## Consequences

- Good: changing how tests run never makes anything stale.
- Good: moving unchanged code stays verified.
- Good: two independent implementations produce identical fingerprints.
- Cost: toolchain or dependency changes don't make anything stale unless a pin file (a lockfile, say) is declared as a resource.
- Cost: changing the freshness policy makes every route stale, by design.

## Considered Options

- **Fingerprint commands and environments:** catches toolchain drift, but creates constant irrelevant staleness and captures machine noise.
- **Fingerprint file locations by default:** simple, but every refactor makes verified evidence stale.

## Confirmation

- Chapter 11's three route vectors match the reference script and `openssl`, checked by `validate.py`.
- Acceptance tests show moving code and editing a title keep verification, while editing linked code, a test, a resource or the intent makes it stale.

## Related Links

- `docs/design/11-fingerprints-and-freshness.md`
