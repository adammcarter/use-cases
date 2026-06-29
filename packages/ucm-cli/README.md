# @use-cases-plugin/cli

Command-line interface for **Use Cases Plugin (UCM)** — a repo-local, agent-facing
assurance system for keeping product claims, code spans, demonstrations,
evidence, and release decisions aligned.

## Install

```bash
npm install -D @use-cases-plugin/cli
```

This installs two binaries:

- `ucp` — primary binary.
- `use-cases-plugin` — long-form alias.

## Usage

```bash
npx ucp --version --json
npx ucp matrix validate --repo . --json
```

The `--json` envelope and every command's `data` shape, the command/flag names,
and the exit codes are versioned public contracts. Human-readable (non-`--json`)
output is **not** part of the contract.

See the
[CLI reference](https://github.com/adammcarter/use-cases-plugin/blob/main/docs/cli.md)
and the
[stability & versioning policy](https://github.com/adammcarter/use-cases-plugin/blob/main/docs/reference/stability.md).

## License

[MIT](./LICENSE)
