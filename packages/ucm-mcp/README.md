# @use-case-matrix/mcp

Local stdio [Model Context Protocol](https://modelcontextprotocol.io) server for
**Use Case Matrix (UCM)** — exposing the full UCM workflow (matrix, freshness,
evidence, showcase, host applicability, and more) to coding agents without a GUI.

## Install

```bash
npm install @use-case-matrix/mcp
```

This installs two binaries:

- `ucm-mcp` — primary binary.
- `use-case-matrix-mcp` — long-form alias.

## Usage

Configure your MCP client to launch the server over stdio:

```json
{
  "mcpServers": {
    "use-case-matrix": {
      "command": "npx",
      "args": ["-y", "@use-case-matrix/mcp"]
    }
  }
}
```

## Security model

The server ships a conservative default safety policy: mutations are gated, there
is no generic shell tool, signing/`prove` is not exposed, and the workspace root
is locked. MCP **tool names** and their input/output schemas are versioned public
contracts.

See the
[MCP reference](https://github.com/adammcarter/presentation-skills/blob/main/docs/mcp.md)
and the
[stability & versioning policy](https://github.com/adammcarter/presentation-skills/blob/main/docs/reference/stability.md).

## License

[MIT](./LICENSE)
