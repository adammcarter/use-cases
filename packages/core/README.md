# @adammcarter/use-cases-core

Core domain library for **use-case-matrix** — a repo-local, agent-facing
assurance system for keeping product claims, code spans, demonstrations,
evidence, and release decisions aligned.

This package ships the schemas, types, and engine used by the `cli` and `mcp`
workspaces. All three are **internal** and ship bundled inside the
[`use-case-matrix`](https://www.npmjs.com/package/use-case-matrix) package rather
than published separately. The bundled JSON Schemas (under `dist/schemas/v1/`)
use the stable `https://use-cases.dev/schemas/v1/...` `$id` namespace.

## Install

Internal — not published separately. Install the umbrella package:

```bash
npm i -g use-case-matrix
```

## Usage

```ts
import { getVersionInfo } from "@adammcarter/use-cases-core";

getVersionInfo(); // { name: "use-case-matrix", version: "1.0.0" }
```

## Stability

Only the **documented** TypeScript exports are part of the public, SemVer-governed
surface. See the
[stability & versioning policy](https://github.com/adammcarter/use-case-matrix/blob/main/docs/reference/stability.md).

## License

[MIT](https://github.com/adammcarter/use-case-matrix/blob/main/LICENSE)
