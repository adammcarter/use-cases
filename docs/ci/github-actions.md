# GitHub Actions

An example of chapter 19's recipe on GitHub Actions. The first step installs `use-cases` (chapter 19, install first); replace the setup step with whatever your project needs to run its tests. The other recipes below start with the same install step and leave it out for brevity.

## The simple run

```yaml
# .github/workflows/use-cases.yml
name: use cases
on: [push, pull_request]
jobs:
  use-cases:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install use-cases
        env:
          USE_CASES_VERSION: "0.1.0"          # pinned: change it on purpose
          USE_CASES_REPOSITORY: adammcarter/use-cases    # where the release is published
        run: |
          case "$RUNNER_OS-$RUNNER_ARCH" in
            macOS-*) platform=macos-universal ;;
            Linux-ARM64) platform=linux-arm64 ;;
            *) platform=linux-x86_64 ;;
          esac
          name="use-cases-$USE_CASES_VERSION-$platform.tar.gz"
          base="https://github.com/$USE_CASES_REPOSITORY/releases/download/v$USE_CASES_VERSION"
          curl -fsSL -O "$base/$name" -O "$base/$name.sha256"
          shasum -a 256 -c "$name.sha256"
          mkdir -p "$HOME/use-cases-release" "$HOME/bin"
          tar -xzf "$name" -C "$HOME/use-cases-release" --strip-components=1
          ln -s "$HOME/use-cases-release/use-cases" "$HOME/bin/use-cases"
          echo "$HOME/bin" >> "$GITHUB_PATH"
      - run: ./scripts/setup-ci.sh          # your language and your test tool
      - run: use-cases verify --run
      - run: use-cases status --gate
      - if: always()                        # optional: keep the evidence for people to inspect
        uses: actions/upload-artifact@v4
        with:
          name: use-cases-runs
          path: .use-cases/runs
```

## Release branches

```yaml
      - run: use-cases status --gate --strict
        if: startsWith(github.ref, 'refs/heads/release/')
      - run: use-cases status --gate
        if: ${{ !startsWith(github.ref, 'refs/heads/release/') }}
```

## Your own test step

```yaml
      - id: start
        run: echo "report=$(use-cases verify --start --json | jq -r '.reports["unit-tests"]')" >> "$GITHUB_OUTPUT"
      - run: python -m pytest --junitxml="${{ steps.start.outputs.report }}"
        continue-on-error: true                # a failing test is a verdict: --finish still reads it
      - run: use-cases verify --finish
      - run: use-cases status --gate
```

## Sharded tests

The validation (`unit-tests` here) has no `report` name, so its `{report}` is a folder that holds every shard's file.

```yaml
jobs:
  start:
    runs-on: ubuntu-latest
    outputs:
      run_id: ${{ steps.start.outputs.run_id }}
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/setup-ci.sh          # after the Install use-cases step
      - id: start
        run: echo "run_id=$(use-cases verify --start --json | jq -r '.run_id')" >> "$GITHUB_OUTPUT"
      - uses: actions/upload-artifact@v4
        with:
          name: use-cases-run
          path: .use-cases/runs/${{ steps.start.outputs.run_id }}
          include-hidden-files: true

  shard:
    needs: start
    runs-on: ubuntu-latest
    strategy:
      matrix:
        shard: [1, 2, 3]
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/setup-ci.sh          # after the Install use-cases step
      - run: python -m pytest $(./scripts/tests-for-shard.sh ${{ matrix.shard }} 3) --junitxml=shard-${{ matrix.shard }}.xml
        continue-on-error: true
      - uses: actions/upload-artifact@v4
        with:
          name: shard-${{ matrix.shard }}
          path: shard-${{ matrix.shard }}.xml

  finish:
    needs: [start, shard]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/setup-ci.sh          # after the Install use-cases step
      - uses: actions/download-artifact@v4
        with:
          name: use-cases-run
          path: .use-cases/runs/${{ needs.start.outputs.run_id }}
      - uses: actions/download-artifact@v4
        with:
          pattern: shard-*
          merge-multiple: true
          path: .use-cases/runs/${{ needs.start.outputs.run_id }}/reports/unit-tests
      - run: use-cases verify --finish --run-id ${{ needs.start.outputs.run_id }}
      - run: use-cases status --gate
```
