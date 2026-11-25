# Swift Use Cases Example

A small illustrative Swift repository showing:

- root + child `use-cases.yml` scopes
- explicit namespace composition
- root `use-case-groups.yml`
- automated and procedural validation routes
- gating and non-gating routes
- markers in sources and tests
- one manual binding (a file and line range, written in the use case YAML)
- one validation resource (`Packages/Auth/Fixtures/users.json`)
- root-only freshness policy
- optional helpers in `use-cases-bridge.yml`
- one generated `.use-cases/` location (not included; it is runtime output)

Resolved use cases:

```text
shop.checkout.complete
shop.auth.login.authenticate
```

## The three rings in this repo

```text
 core      use-cases.yml, use-cases/*.yml, Packages/Auth/use-cases/*.yml
 links     @use-case: markers in Sources/ and Tests/, plus one manual binding
 helpers   use-cases-bridge.yml: two swift test runs read by the swift-testing transformer
```

The use case files name no commands or tools. The manual binding in `Packages/Auth/use-cases/login.yml` points at lines 37–40 of `Packages/Auth/Sources/Auth/LoginService.swift`, which carry no marker.

## Validating

```text
use-cases verify --run    runs both swift test commands, then reads their reports
use-cases verify --start  notes the code; then you run swift test yourself
use-cases verify --finish reads the reports those runs wrote
```

Each `run` writes Swift Testing's structured report to `{report}`, inside the run's own reports folder. A plain `swift test` writes no report, so runs you start yourself need the same `--experimental-event-stream-output` flag.

`real-app-acceptance` and `manual-login-check` are procedures. They receive verdicts through `use-cases record`, not from a transformer.

This repo is intentionally small and illustrative rather than a complete buildable app. The YAML and marker relationships are the focus.
