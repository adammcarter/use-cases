# GitLab CI

An example of chapter 19's recipe on GitLab CI. The hidden `.install-use-cases` job installs `use-cases` (chapter 19, install first) and every job extends it; replace the setup script with whatever your project needs to run its tests.

## The simple run

```yaml
# .gitlab-ci.yml
.install-use-cases:
  variables:
    USE_CASES_VERSION: "0.1.0"             # pinned: change it on purpose
    USE_CASES_RELEASE_URL: https://github.com/adammcarter/use-cases/releases/download   # where the release is published
  before_script:
    - |
      case "$(uname -s)-$(uname -m)" in
        Darwin-*) platform=macos-universal ;;
        Linux-aarch64) platform=linux-arm64 ;;
        *) platform=linux-x86_64 ;;
      esac
      name="use-cases-$USE_CASES_VERSION-$platform.tar.gz"
      base="$USE_CASES_RELEASE_URL/v$USE_CASES_VERSION"
      curl -fsSL -O "$base/$name" -O "$base/$name.sha256"
      shasum -a 256 -c "$name.sha256"
      mkdir -p "$HOME/use-cases-release" "$HOME/bin"
      tar -xzf "$name" -C "$HOME/use-cases-release" --strip-components=1
      ln -sf "$HOME/use-cases-release/use-cases" "$HOME/bin/use-cases"
      export PATH="$HOME/bin:$PATH"

use-cases:
  extends: .install-use-cases
  script:
    - ./scripts/setup-ci.sh                # your language and your test tool
    - use-cases verify --run
    - use-cases status --gate
  artifacts:                               # optional: keep the evidence for people to inspect
    when: always
    paths:
      - .use-cases/runs
```

## Release branches

```yaml
use-cases-release:
  extends: .install-use-cases
  rules:
    - if: $CI_COMMIT_BRANCH =~ /^release\//
  script:
    - ./scripts/setup-ci.sh
    - use-cases verify --run
    - use-cases status --gate --strict
```

## Your own test step

```yaml
use-cases:
  extends: .install-use-cases
  script:
    - ./scripts/setup-ci.sh
    - REPORT=$(use-cases verify --start --json | jq -r '.reports["unit-tests"]')
    - python -m pytest --junitxml="$REPORT" || true    # a failing test is a verdict: --finish still reads it
    - use-cases verify --finish
    - use-cases status --gate
```

## Sharded tests

The validation (`unit-tests` here) has no `report` name, so its `{report}` is a folder that holds every shard's file.

```yaml
stages: [start, test, finish]

use-cases-start:
  extends: .install-use-cases
  stage: start
  script:
    - ./scripts/setup-ci.sh
    - RUN_ID=$(use-cases verify --start --json | jq -r '.run_id')
    - echo "RUN_ID=$RUN_ID" > run.env
  artifacts:
    reports:
      dotenv: run.env
    paths:
      - .use-cases/runs

shard:
  stage: test
  parallel: 3
  needs: []
  script:
    - ./scripts/setup-ci.sh
    - python -m pytest $(./scripts/tests-for-shard.sh $CI_NODE_INDEX $CI_NODE_TOTAL) --junitxml=shard-$CI_NODE_INDEX.xml || true
  artifacts:
    paths:
      - shard-*.xml

use-cases-finish:
  extends: .install-use-cases
  stage: finish
  needs: [use-cases-start, shard]
  script:
    - ./scripts/setup-ci.sh
    - mkdir -p ".use-cases/runs/$RUN_ID/reports/unit-tests"
    - mv shard-*.xml ".use-cases/runs/$RUN_ID/reports/unit-tests/"
    - use-cases verify --finish --run-id "$RUN_ID"
    - use-cases status --gate
```
