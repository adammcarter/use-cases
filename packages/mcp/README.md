# @adammcarter/use-cases-mcp

Local stdio [Model Context Protocol](https://modelcontextprotocol.io) server for
**use-cases** — exposing the full workflow (matrix, freshness,
evidence, showcase, host applicability, and more) to coding agents without a GUI.

## Install

This is an internal workspace package — it is **not published separately**. It
ships bundled inside the
[`use-cases`](https://www.npmjs.com/package/use-cases) package:

```bash
npm i -g use-cases
```

That provides the `uc-mcp` binary (and its `use-cases-mcp` long-form alias).

## Usage

Configure your MCP client to launch the server over stdio:

```json
{
  "mcpServers": {
    "use-cases": {
      "command": "npx",
      "args": ["-y", "@adammcarter/use-cases-mcp"]
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
[MCP reference](https://github.com/adammcarter/use-cases/blob/main/docs/mcp.md)
and the
[stability & versioning policy](https://github.com/adammcarter/use-cases/blob/main/docs/reference/stability.md).

## License

[MIT](https://github.com/adammcarter/use-cases/blob/main/LICENSE)
