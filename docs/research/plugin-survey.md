# Survey: sessions using today's plugin (2026-09-30)

Input for chapter 21. Four Claude sessions working in real repos were sent the high-level flow and six questions (what worked, friction, when the owner stepped in, sign-off in practice, the flow, the one change). All four answered; one had not used the plugin beyond a commit hook.

| Session | Repo | Use |
|---|---|---|
| goal-6 | a plugin and kit rebuild | a commit hook only |
| sidecar | a macOS app, CLI | every change, ~109 rows |
| imagecap | a macOS app, Swift, parallel worker agents | daily, ~45 rows |
| imagediff-site | an Astro site and a Worker, planner/builder/reviewer agents | daily, ~35 rows |

## What they agree on

```text
                                     goal-6  sidecar  imagecap  imagediff
status in a fresh checkout is noise             ●        ●         ●       ← "one change" for 2 of 3
"done" ≠ tests passed; seen/performed           ●        ●         ●       ← "one change" for imagecap
owners never read rows; they approve by looking  ○        ●        ●         ●
a fast path for small changes and tuning                 ●        ●
the owner changes it after seeing a build                ●        ●         ●
the proposal: plain words first, ids last        ●                 ●         ●
not sure the agent may touch use cases           ●                           ●
```

## Already handled by the new design

| Complaint | In the new design |
|---|---|
| a global start-up text in every session | step 0: asked once per repo, a small AGENTS.md block |
| one append-only ledger conflicts on every merge | no ledger: links are markers and YAML; each run is its own folder, never committed |
| removed rows linger as tombstones | `remove` deletes the lines; nothing lingers |
| a gate that can never fail | the gate blocks failed, error and stale (ADR 023) |
| the agent tools were read-only; YAML hand-edited | `save` / `remove`, never INVALID (ADR 028) |
| a writer that reformats the whole file | `save` changes only that use case's lines |
| hyphens rejected in ids | ids allow hyphens (chapter 05) |
| no markers in CSS or .astro | markers have no comment-syntax model: any text file (chapter 08) |
| a marker inside another's span refused | different markers nest (chapter 08) |
| a verifier killed past 1 MiB of output | the first and last 512 KiB are kept; nothing is killed (chapter 14) |

## Gaps the survey found in the new design

- **A YAML `#` that silently cuts text.** A step like `Check medal #4` is read as `Check medal`: YAML treats ` #` as a comment. Nothing in the reader catches it.
- **A hook when `use-cases` is not installed.** Chapter 18 does not say what happens; it must fail loudly, never pass silently.
- **Code moved out of its markers during a refactor** is no longer tracked, and nothing says so.
- **Where the CLI lives** (not on PATH for agents): a packaging question for the real build.

## For chapter 21

- **A fast path.** A papercut or a tuning change ("4 s, not 40 s") edits the use case and its test without a full brief.
- **Explore before pinning.** For visual or interaction work, try variants, then write the use case for the winner.
- **The feedback loop is the normal case.** The owner tries a build and says "change X": the use case changes, red, green again. Say which earlier decisions it replaces.
- **Can these tests fail?** Between red and green, plant a defect and check the tests catch it.
- **What an agent may do.** When its code change touches marked code or adds a behaviour: say so, and either update the use case (with sign-off) or flag it.
- **The proposal.** Plain words, "what you'll see", choices with previews where taste matters, ids last, short.
- **Seen, not just passed.** User-visible behaviour needs evidence that it was performed and seen (a recording, a measurement, a person trying it), attached to its verdict.

## Decisions for the owner

1. **Verification state in a fresh checkout.** Every heavy user ignores it because a new worktree shows everything unverified.
2. **What "done" means for user-visible behaviour**, and how the gate knows it was performed and seen.
3. **When sign-off happens:** before the code (the proposal), after seeing it (the build), or both; recorded per use case, and invalidated when its behaviour changes later.

## The replies


### goal-6 (port plugin + kit rebuild; mostly not using it)

1. Implicit use via Game Shelf's pre-commit hook (`uc matrix validate`, `uc validate-ledger`): never blocked, never said anything. Fine as a silent guard.
2. Friction: a subagent edited marked code (PackageContentLoader, row package.loading.a_package_plays_in_the_modes_it_declares) and added a new behaviour (malformed `container` falls back to the previous build). It noted the evidence "probably needs re-checking" and no row covers the new behaviour, but didn't know whether it was allowed to touch rows, so left them. Wants: a commit touching marked code says loudly, without blocking: "row X is now stale; recover it, or add a row for the new case".
3. Noise: the global session-start "EXTREMELY_IMPORTANT Use Cases Activation" lands in every session. Step 0 (ask once per repo, small AGENTS.md block) fixes it; drop the global injection.
- Flow: step 5 sign-off always matches the owner; plain language, not command names; approves one at a time.
- One change: the proposal leads with a small diagram/table of new / changed / untouched cases in plain words; row ids underneath, not up front.

→ design: ch21 must state what an agent may do to use cases when it changes marked code; a loud, non-blocking "now stale / uncovered" signal on commit; templates: plain words first, ids second.

### sidecar (repo sidecar; ~8 small features/fixes today, CLI only; uses it on every change)

1. Worked: the matrix as the place to record behaviour changes (every change); `uc matrix validate` fast and trusted; `//: @use-case:` markers greppable from a row id; `uc scan --gate` never blocked wrongly.
2. Friction:
   a. fresh worktree: all 109 rows UNVERIFIED_LOCAL, main too; gate passes anyway → the number means nothing, stopped looking.
   b. `uc verify` kills a verifier printing > 1 MiB; worked around with lockf + `verify --row` within 30 s.
   c. hand-written markers rejected in favour of `uc bind`; refactored code into new types without rebinding and nothing said the marker regions drifted.
   d. MCP server failed to connect (uc-mcp not on PATH) → edited YAML by hand; nothing checks beyond the schema.
   e. a planned row still says NOT BUILT for grouping shipped long ago; nothing flags stale rows.
   f. never used showcase or evidence.
3. Owner corrections: product calls from looking at the running app, never about the matrix.
4. Sign-off: the owner never looked at rows; sign-off = install the branch build, try it, say "approved"/"merge". Owner's rule: no per-row approval on verified rows for small UI changes. Wants: approval against a plain-English behaviour summary next to the running build, rows updated from that approval — not approval of YAML/proposal before code exists.
5. Flow:
   a. BRIEF + SIGN-OFF before TDD too heavy for papercuts (label rename) → needs a fast path that records the change and moves on.
   b. PROVE lacks real-system evidence: a VM measurement rig (panel close 1.0–2.4 s → 0.3 s, main measured red first) was the key proof; attach e.g. a rig's summary.json to the row.
   c. "sign-off always, before TDD" doesn't match this owner: he reacts to running builds; a second sign-off after the demo matters more than the one before.
   d. DISCOVER through use cases then links: good.
6. One change: make verification status real and shared (survives worktrees, reads VERIFIED on main after merge) — or drop it. Today it's noise every session learns to ignore.

→ design: proportional flow (fast path for papercuts); sign-off before AND/OR after (demo sign-off may matter more); local status in a fresh checkout is noise → shared verified state question; real-system evidence attaches (record --attach exists); marker drift after refactors; output size limits in verify runs (check ch14/the proof).

### imagecap (macOS app, Swift, ~45 rows, many parallel worker agents on sibling worktrees; owner is a non-engineer who approves by looking; used bind/rebind/unbind/verify/scan --gate/matrix validate daily)

1. Worked: rows as the brief (golden/bad/edge → one test each), a great spine for delegating to sub-agents; markers + verify = fast "code and test still agree"; run.sh failing on "No matching test cases" caught a real empty suite; rename via unbind→bind --register-existing clean; matrix validate in pre-commit catches typos early.
2. Friction:
   a. .use-cases/bindings.jsonl, one append-only file → every merge of parallel branches conflicts; `merge=union`; a hand-resolve once left conflict markers in the ledger (caught only at commit). Wants per-row/per-file ledger.
   b. `matrix remove` leaves a tombstone that scans UNBOUND forever → permanent noise.
   c. `scan --gate`: "0 required behaviours meet VERIFIED_LOCAL" — nothing required by default, so the gate can never fail; agents quoted it as if it meant something.
   d. results per checkout → after every merge to main, re-run verify --all.
   e. `bind --mode swift-func` orphaned doc comments (marker between /// and func) → rebind --mode explicit.
   f. MCP server read-only in practice → rows hand-edited via CLI/yq.
   g. lint limits forced splitting suites into +Topic.swift files mid-row; markers with #suffix per file worked but felt fragile.
3. Owner corrections: almost all VISUAL/INTERACTION behaviour that rows + unit tests + verify called green (hover jumping, card flashing on drop, blur "looks like it vanishes", peek order, hit areas). VERIFIED_LOCAL repeatedly mistaken for "done". Nothing ties a scenario to evidence that a human-visible result was seen. Acceptance always NOT_SUPPORTED; built their own process outside the plugin (Debug build in a VM, HID-driven, 60 fps frame recording → contact sheets → independent reviewer agent).
4. Sign-off: owner never reads YAML. Rows → short tables/ASCII + choices in chat; owner approved the table, then rows written. Problems: approval not recorded on the row; rows edited many times AFTER approval (mid-build tweaks) with no "changed since approval" marker. Wants: a fixed one-screen proposal (what changes, golden path, edges, out of scope, decisions as choices); approval stored per row (who / when / version); a later edit to a row's behaviour wording flips it to "needs re-approval", with a diff.
5. Flow: 0–7 read right. Missing: (i) a live-evidence step between TDD and PROVE for anything user-visible (run it the way the user will, record frames, independent reviewer) — where all their defects were; (ii) an explicit feedback loop after sign-off/prove: owner tries it, "change X" → row edit → re-red → re-green; the normal case, not the exception; (iii) parallel workers: rows and ledger must merge cleanly across branches, and a "who owns this row" notion; (iv) a cheap path for tuning requests ("4 s not 40 s"): a changed-value row edit + test bump. Overkill: signed tiers/keys, showcase ceremony, one test per scenario when a parameterised test does it.
6. One change: a scenario/row declares its required EVIDENCE KIND (unit, snapshot, recorded frames + review...) and the gate/status fails until that evidence exists for user-visible rows: "done" = "performed and seen", not "a test passed". Runner-up: per-row ledger files so parallel branches merge.

→ design: evidence kind per route (validation type already exists: unit/acceptance...) + gate on user-visible routes; approval recorded per use case, invalidated by later edits (ties to tier sign-off); feedback loop in the flow; live evidence step; parallel-branch merges (our store: per-run folders, no single ledger — check); tuning fast path.

### imagediff-site (Astro site + a Cloudflare Worker; ~35 rows; planner → builder → reviewer agents, every branch in a sibling worktree; owner approves by looking)

1. Worked: row ids as a shared handle between planner, builder, verifier and owner; row id in test titles + verify-row.sh ("no test names this row" fails rather than passing on nothing); markers around code; matrix validate; the planner→red→builder→green split. Mutation runs (plant a defect, run the row's tests) were the most valuable check: across ~10 rows they found tests that can't fail.
2. Friction:
   a. results file gitignored → every fresh worktree scans ALL rows UNPROVEN; agents kept reporting that as meaningful; only verify in that checkout clears it.
   b. UNPROVEN / "NOT_SUPPORTED — do NOT claim acceptance" stays on rows whose tests pass; lifecycle stays `planned`; nobody knows who flips it.
   c. row ids with hyphens rejected by the marker tool (found by error).
   d. markers can't go in .astro or CSS → no CSS marked → impact won't flag an edit to the very rule a row describes.
   e. NESTED_SPAN: a marker inside another row's span is refused → helpers hoisted just to bind them.
   f. YAML: a step containing " #N" read as a comment and silently truncated (four steps, unnoticed for weeks). `matrix upsert` rewrites formatting → agents edit rows by script.
   g. pre-commit hook exits 0 silently when `use-cases` isn't on PATH (it isn't, for agents) → validation skipped.
   h. pre-commit scan walked a gitignored folder with a built .app and refused every commit (another repo's markers inside).
   i. the CLI lives at a versioned plugin-cache path, not on PATH.
   j. a verifier started a dev server on a fixed port and silently failed all rows when a daemon already ran.
3. Corrections: the owner changed requirements AFTER seeing a build, about every second row. Builders were forbidden to edit rows/tests, so re-brief as planners each time. Wants a "requirement changed: supersede these pins" path naming the changed pins.
4. Sign-off: the owner NEVER read a row; approved by looking (screenshots in Preview, live branch build in Safari: "dont show me videos i want to feel it in safari", multiple-choice questions with ASCII previews); rows approved implicitly via a plain-English summary. Wants one fixed proposal layout in plain words (what changes / what you'll see / out of scope), options with previews when taste is involved, then build. Short: the owner is overwhelmed by text.
5. Flow: DISCOVER and BRIEF right. Missing: a DESIGN/EXPLORE step before rows for visual/interaction work (variants first, then pin the winner); a "can these tests fail?" gate between red and green (planted defect). PROVE for them = "owner tries it live", not status --gate. Overkill for a solo site: signed proofs/FRESH; per-scenario out_of_scope lists (10+ exclusions per row: useful once, noisy after).
6. One change: make verification results repo-level (shared across worktrees, or derivable from the tests' last run) so any worktree tells the truth. Second: separate "tests green locally" from "signed proof" in the wording, so UNPROVEN stops reading as failure.
