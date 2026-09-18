# @adammcarter/use-cases-cli

Command-line interface for **use-cases** — a repo-local, agent-facing
assurance system for keeping product claims, code spans, demonstrations,
evidence, and release decisions aligned.

## Install

This is an internal workspace package — it is **not published separately**. It
ships bundled inside the
[`use-cases`](https://www.npmjs.com/package/use-cases) package:

```bash
npm i -g use-cases
```

That provides the `use-cases` binary.

## Usage

```bash
npx use-cases --version --json
npx use-cases matrix validate --repo . --json
```

The `--json` envelope and every command's `data` shape, the command/flag names,
and the exit codes are versioned public contracts. Human-readable (non-`--json`)
output is **not** part of the contract.

See the
[CLI reference](https://github.com/adammcarter/use-cases/blob/main/docs/cli.md)
and the
[stability & versioning policy](https://github.com/adammcarter/use-cases/blob/main/docs/reference/stability.md).

## License

[MIT](https://github.com/adammcarter/use-cases/blob/main/LICENSE)
