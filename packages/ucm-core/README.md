# @use-case-matrix/core

Core domain library for **Use Case Matrix (UCM)** — a repo-local, agent-facing
assurance system for keeping product claims, code spans, demonstrations,
evidence, and release decisions aligned.

This package ships the schemas, types, and engine used by the
[`@use-case-matrix/cli`](https://www.npmjs.com/package/@use-case-matrix/cli) and
[`@use-case-matrix/mcp`](https://www.npmjs.com/package/@use-case-matrix/mcp)
packages. The bundled JSON Schemas (under `dist/schemas/v1/`) are published with
the stable `https://use-case-matrix.dev/schemas/v1/...` `$id` namespace.

## Install

```bash
npm install @use-case-matrix/core
```

## Usage

```ts
import { getVersionInfo } from "@use-case-matrix/core";

getVersionInfo(); // { name: "use-case-matrix", version: "1.0.0" }
```

## Stability

Only the **documented** TypeScript exports are part of the public, SemVer-governed
surface. See the
[stability & versioning policy](https://github.com/adammcarter/presentation-skills/blob/main/docs/reference/stability.md).

## License

[MIT](./LICENSE)
