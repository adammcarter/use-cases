# 8 · What a use case holds

**What a use case holds.**

Behaviour, and how it's proved. Links to code are optional. Every file reads one way in every tool.

```text
┌─ use-cases/login.yml ───────────────────────────────┐   ┌─ ALSO ON A ROUTE, IF YOU WANT THEM ──────┐
│ - id: authenticate                                  │   │ bindings  [optional link]                │
│   title: Authenticate user                          │   │   Manual file/line bindings point at     │
│   value_tier: core                                  │   │   code without touching it. Markers in   │
│   intent: Let a user with valid credentials         │   │   the code need no entry.                │
│     sign in, and reject anyone without them.        │   │ resources  [optional link]               │
│   scenarios:                                        │   │   Fixtures and golden files, such as     │
│     - id: valid-credentials                         │   │   fixtures/users.json. Freshness only;   │
│       when: [The user submits valid credentials.]   │   │   they never expect a result.            │
│       then: [The user is signed in.]                │   └──────────────────────────────────────────┘
│     - id: invalid-password                          │   ┌─ READ ONE WAY, EVERYWHERE ───────────────┐
│       when: [The user submits a wrong password.]    │   │ The root says so                         │
│       then: [The user is not signed in.]            │   │   The root use-cases.yml has root: true, │
│   validation:                                       │   │   so ids are the same from any folder.   │
│     - id: unit-tests                                │   │ Quote what YAML could misread            │
│       type: { kind: unit }                          │   │   title: "No", not No. Unquoted on, 1:30 │
│       covers: [valid-credentials, invalid-password] │   │   or a date is refused.                  │
│     - id: manual-login-check                        │   │ Ids are unique where used                │
│       type: { kind: acceptance }                    │   │   Scenario and route ids once per use    │
│       covers: [valid-credentials]                   │   │   case; paths spelled exactly as on      │
│       gates_verification: false                     │   │   disk.                                  │
│       procedure:                                    │   └──────────────────────────────────────────┘
│         steps: [Enter valid credentials., Submit.]  │   ┌─ OR THE GLUE, IN A TEST (OPTIONAL) ──────┐
└─────────────────────────────────────────────────────┘   │ // @use-case:shop.login.authenticate#    │
                                                          │ //   unit-tests.valid-credentials        │
                                                          │ @Test func validCredentials() …          │
                                                          │ // @use-case:end …valid-credentials      │
                                                          └──────────────────────────────────────────┘
```

The marker snippet is an example from a Swift project; markers work the same in any language's comments.

*Proven · 506 checks on macOS + Linux · 438 on Windows*

---

Source: slide 8 of the [Use Cases Bridge Contract canvas](https://claude.ai/artifact/TLbJK1GoogFUgZTCLX6YW6) (private until you share it from its Share menu).
