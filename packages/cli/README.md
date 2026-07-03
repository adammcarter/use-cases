# @adammcarter/use-cases-cli

Command-line interface for **use-case-matrix** — a repo-local, agent-facing
assurance system for keeping product claims, code spans, demonstrations,
evidence, and release decisions aligned.

## Install

This is an internal workspace package — it is **not published separately**. It
ships bundled inside the
[`use-case-matrix`](https://www.npmjs.com/package/use-case-matrix) package:

```bash
npm i -g use-case-matrix
```

That provides the `uc` binary (and its `use-case-matrix` long-form alias).

## Usage

```bash
npx uc --version --json
npx uc matrix validate --repo . --json
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
