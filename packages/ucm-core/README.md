# @use-cases-plugin/core

Core domain library for **Use Cases Plugin (UCM)** — a repo-local, agent-facing
assurance system for keeping product claims, code spans, demonstrations,
evidence, and release decisions aligned.

This package ships the schemas, types, and engine used by the
[`@use-cases-plugin/cli`](https://www.npmjs.com/package/@use-cases-plugin/cli) and
[`@use-cases-plugin/mcp`](https://www.npmjs.com/package/@use-cases-plugin/mcp)
packages. The bundled JSON Schemas (under `dist/schemas/v1/`) are published with
the stable `https://use-cases-plugin.dev/schemas/v1/...` `$id` namespace.

## Install

```bash
npm install @use-cases-plugin/core
```

## Usage

```ts
import { getVersionInfo } from "@use-cases-plugin/core";

getVersionInfo(); // { name: "use-cases-plugin", version: "1.0.0" }
```

## Stability

Only the **documented** TypeScript exports are part of the public, SemVer-governed
surface. See the
[stability & versioning policy](https://github.com/adammcarter/use-cases-plugin/blob/main/docs/reference/stability.md).

## License

[MIT](./LICENSE)
