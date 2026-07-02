# @use-case-matrix/cli

Command-line interface for **Use Cases Plugin** — a repo-local, agent-facing
assurance system for keeping product claims, code spans, demonstrations,
evidence, and release decisions aligned.

## Install

```bash
npm install -D @use-case-matrix/cli
```

This installs two binaries:

- `ucm` — primary binary.
- `use-case-matrix` — long-form alias.

## Usage

```bash
npx ucm --version --json
npx ucm matrix validate --repo . --json
```

The `--json` envelope and every command's `data` shape, the command/flag names,
and the exit codes are versioned public contracts. Human-readable (non-`--json`)
output is **not** part of the contract.

See the
[CLI reference](https://github.com/adammcarter/use-case-matrix/blob/main/docs/cli.md)
and the
[stability & versioning policy](https://github.com/adammcarter/use-case-matrix/blob/main/docs/reference/stability.md).

## License

[MIT](https://github.com/adammcarter/use-case-matrix/blob/main/LICENSE)
