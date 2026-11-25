# Engine schemas

Draft 2020-12 schemas for what the core stores, what it exchanges with transformers, and what it fingerprints.

Every `pattern` that ends a value ends `$(?!\n)`, not `$`: some regex engines let `$` match before a final line break, and a name ending in one must be refused by every engine.

| Schema | Describes | Chapter |
|---|---|---|
| `common.schema.json` | shared definitions: ids, paths, link keys, links, verdicts, fingerprints, timestamps | — |
| `run.schema.json` | `.use-cases/runs/<run-id>/run.json` | 12 |
| `start.schema.json` | `start.json`, the code at a verify run's start point | 12, 13 |
| `result.schema.json` | one line of `results.jsonl` (one route's verdict) | 12 |
| `completion.schema.json` | `completion.json`, the sealing marker | 12 |
| `run-order.schema.json` | the run allocation high-water mark | 12 |
| `transformer-links-request.schema.json` / `-response` | the links job | 10 |
| `transformer-results-request.schema.json` / `-response` | the results job | 10 |
| `route-fingerprint.schema.json` | the route fingerprint payload | 11 |
| `workspace-fingerprint.schema.json` | the workspace fingerprint payload | 11 |

```text
 core ──request.json──▶ transformer ──response.json──▶ core ──▶ run.json · start.json · results.jsonl · completion.json
          (10)                          (10)                          (12)
```

Other files here:
- `fingerprint_vectors.py`: the reference computation of chapter 11's conformance vectors, using the standard library only.
- `validate.py`: meta-validates every schema and checks positive and negative samples for every schema, all example YAML files, and the JSON and YAML examples published in chapters 02, 06, 10 and 12. It confirms that chapter 11's published vector bytes and digests match `fingerprint_vectors.py`, and it cross-checks the route digests with `openssl`.

These schemas are the contract (ADR 011). Beyond `validate.py`, the acceptance suite checks every file the build stores and every transformer request and response against them (`UseCases/Acceptance/conftest.py`).

What stays a core check:
- run integrity: completion hashes, and results matching the manifest
- a result's link keys existing in the current workspace
- transformer determinism
- fingerprint recomputation from real content
