# CI recipes

The recipe of chapter 19 (`../design/19-ci.md`) for particular CI providers. They are examples: the core and its commands name no provider, and any CI that can run commands works the same way.

| Recipe | Covers |
|---|---|
| [GitHub Actions](github-actions.md) | the simple run, release branches, your own test step, sharded tests |
| [GitLab CI](gitlab-ci.md) | the simple run, release branches, your own test step, sharded tests |

Each recipe installs `use-cases` the way chapter 19 says: one pinned download of the release tarball for the runner's platform, with its checksum checked. Every `use-cases` command line in these files is read by the real command line (`CiRecipeCommandTests`), and every YAML block is checked to parse (`UseCases/Acceptance/test_ci.py`).

Adding a provider: one file here with the same four parts, labelled with the provider it is for.
