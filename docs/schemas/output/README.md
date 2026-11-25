# Command-line output schemas

Draft 2020-12 schemas for every `use-cases --json` document (chapter 16 §5). The human output is not a contract; these are.

Every `pattern` that ends a value ends `$(?!\n)`, not `$`: some regex engines let `$` match before a final line break, and a name ending in one must be refused by every engine.

| Schema | Describes |
|---|---|
| `cli-common.schema.json` | shared parts: `output_version`, statuses, counts |
| `cli-error.schema.json` | any refused request: `error.kind` (`usage`, `invalid`, `refused`, `storage`) and `error.message` |
| `cli-version.schema.json` | `use-cases --version` |
| `cli-validate.schema.json` | `use-cases validate` |
| `cli-status.schema.json` | `use-cases status`, including `--group` and `--gate` |
| `cli-verify.schema.json` | `use-cases verify --start`, `--finish`, `--run`, `--abort` |
| `cli-record.schema.json` | `use-cases record` |
| `cli-links.schema.json` | `use-cases links` |
| `cli-search.schema.json` | `use-cases search`, one page |
| `cli-render.schema.json` | `use-cases render`: a canonical layout's model and text |
| `cli-docs.schema.json` | `use-cases docs`: the list, one guide, or one page of sections |
| `cli-show.schema.json` | `use-cases show` |
| `cli-save.schema.json` | `use-cases save` |
| `cli-remove.schema.json` | `use-cases remove` |
| `cli-apply.schema.json` | `use-cases apply`, a batch |
| `cli-approve.schema.json` | `use-cases approve` |
| `cli-init.schema.json` | `use-cases init` |
| `cli-hooks.schema.json` | `use-cases hooks` |
| `cli-prune.schema.json` | `use-cases prune`, including `--dry-run` |

They reuse the engine schemas in `../engine/` for runs, results and links, and grow only by optional fields (ADR 015, ADR 022).

`../engine/validate.py` checks them with positive and negative samples and checks chapter 16's published examples. The acceptance suite also checks every `--json` document the build prints (`UseCases/Acceptance/conftest.py`).
