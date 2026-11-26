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
          include-hidden-files: true            # upload-artifact skips hidden paths (.use-cases) without this
```

## Release branches

```yaml
      - run: use-cases status --gate --strict
        if: startsWith(github.ref, 'refs/heads/release/')
      - run: use-cases status --gate
        if: ${{ !startsWith(github.ref, 'refs/heads/release/') }}
```

## Your own test step

The test step fails the job as usual, so a failing test that no use case claims fails CI. The finish and gate steps run even then (not when the job is cancelled, and only when the start step succeeded), so the run is still sealed and judged.

The report path is read with `sed`: the JSON of `verify --start --json` has one key to a line, and the official Swift Linux image has neither `jq` nor Python, so nothing needs installing. (A repository that has uv can read it with Python instead, as `UseCases/scripts/ci-verify-start` does.)

```yaml
      - id: start
        run: |
          json=$(use-cases verify --start --json)
          echo "report=$(printf '%s' "$json" | sed -n 's/.*"unit-tests": *"\([^"]*\)".*/\1/p')" >> "$GITHUB_OUTPUT"
      - run: python -m pytest --junitxml="${{ steps.start.outputs.report }}"
      - if: ${{ !cancelled() && steps.start.outcome == 'success' }}
        run: use-cases verify --finish
      - if: ${{ !cancelled() && steps.start.outcome == 'success' }}
        run: use-cases status --gate
```

- Between the start and finish steps, write no files that hold marker text into the checkout outside `discovery.exclude` (a second build folder that copies docs, for instance): finish refuses the workspace. Put build output outside the checkout (`$RUNNER_TEMP`) or exclude it.
- For Swift, `swift test --experimental-event-stream-output "$REPORT" --experimental-event-stream-version 0` writes the report; a wrapper that already passes the output flag is pointed at `$REPORT`, because `swift test` takes the flag only once (`../transformers/swift-testing.md`).
- To keep the run for people to read, add `actions/upload-artifact@v4` of `.use-cases/runs` with `include-hidden-files: true` and the same `if:`.

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
        run: |
          json=$(use-cases verify --start --json)
          echo "run_id=$(printf '%s' "$json" | sed -n 's/.*"run_id": *"\([^"]*\)".*/\1/p')" >> "$GITHUB_OUTPUT"
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
      - if: ${{ !cancelled() }}              # the report is kept even when the shard's tests failed
        uses: actions/upload-artifact@v4
        with:
          name: shard-${{ matrix.shard }}
          path: shard-${{ matrix.shard }}.xml

  finish:
    needs: [start, shard]
    # Runs after the shards whether or not their tests passed, so every report is collected and the run is
    # sealed; a shard with failing tests still fails its own job, and so the pipeline.
    if: ${{ !cancelled() && needs.start.result == 'success' }}
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
      - if: ${{ !cancelled() }}
        run: use-cases status --gate
```
