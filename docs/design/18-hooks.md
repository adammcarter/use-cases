# 18 — Hooks

**Phase:** 3 — Core Experience  
**Status:** Specification (locked)

## 1. Purpose

Hooks run a Use Cases check automatically at a git moment, so nobody has to remember it. They are **opt-in**: nothing is ever added unless someone asks, with `use-cases hooks add` or by answering yes in `init`'s wizard (chapter 17).

```text
use-cases hooks                    which hooks are installed
use-cases hooks add commit push    add one or both
use-cases hooks remove commit      take one out
use-cases hooks add push --dry-run what it would change; writes nothing (chapter 16 §17)
```

## 2. The two hooks

| Hook | Git moment | Runs | Stops the commit or push when |
|---|---|---|---|
| `commit` | pre-commit | `use-cases validate` | the workspace is INVALID: a use case file, groups, bridge settings or a link (chapter 09) |
| `push` | pre-push | `use-cases status --gate` | something blocks (chapter 16 §10) |

`commit` is fast and runs no test. `push` runs no test either: it reads the verdicts already stored, so it blocks a push whose use cases are stale until they are verified again. CI remains where the tests run and the gate decides for everyone (chapter 19).

`git commit --no-verify` and `git push --no-verify` skip a hook once, as for any git hook.

## 3. Per clone, never shared

A hook is a small script written into this clone's git hooks folder (`git rev-parse --git-path hooks`). It is not committed, and it changes no git configuration: each person adds the hooks they want on their own clone.

```sh
#!/bin/sh
# Added by `use-cases hooks add commit`; `use-cases hooks remove commit` takes it out.
# `git commit --no-verify` skips it once.
if command -v use-cases >/dev/null 2>&1; then
  exec use-cases --workspace "." validate --quiet
fi
if [ -e /opt/use-cases/bin/use-cases ]; then
  exec /opt/use-cases/bin/use-cases --workspace "." validate --quiet
fi
echo "use-cases isn't installed here, so this hook can't check your use cases." >&2
echo "Install it, re-run 'use-cases hooks add commit', or skip it once: git commit --no-verify" >&2
exit 1
```

A hook never passes without checking:

- **`use-cases` on the PATH** runs the check.
- **Otherwise, the `use-cases` that added the hook,** whose full path the hook remembers (`/opt/use-cases/bin/use-cases` above): agents' shells often have no `use-cases` on their PATH. The path remembered is the one `use-cases` was run by, made absolute, with any links in it kept, so an upgrade that moves the real program does not break the hook.
- **Otherwise it stops the commit or push and says why,** with the two ways on: install it or add the hook again, or skip it once with `--no-verify`.
- Use Cases recognises its own hook whichever `use-cases` added it: only that remembered path may differ.

The hook names the workspace relative to the top of the git work tree, where git runs hooks, so a workspace in a subfolder of a repository is checked correctly. It checks the files as they are in the work tree, not only what is staged or pushed. `hooks` needs only the workspace root, never the model, so it works on a workspace that does not load.

## 4. It never overwrites

- **A hook file already there** that is not exactly the one Use Cases writes (another tool's, or one edited by hand) is left alone. `hooks add` reports it and prints the one line to add to that hook yourself, and exits 1 (done, but something needs you).
- **`core.hooksPath` is set** (a hook manager such as husky or lefthook owns the hooks): Use Cases writes nothing there and prints the line to add to that manager's configuration, exit 1.
- **`hooks remove`** removes a hook only when it is exactly the file Use Cases wrote for this workspace (its remembered path aside). Anything else is left alone and reported.
- **Not a git repository:** `hooks` refuses with exit 2.

## 5. `use-cases hooks`

```text
$ use-cases hooks
commit   installed      use-cases validate
push     not installed  use-cases status --gate
→ use-cases hooks add push
```

| State | Meaning |
|---|---|
| `installed` | the hook is exactly the one Use Cases writes for this workspace |
| `not installed` | no hook file for that moment |
| `other` | a different hook file is there; Use Cases leaves it alone |
| `managed` | `core.hooksPath` is set; the hook manager owns every hook |
| `would install` | with `--dry-run`: `add` would write this hook; nothing is written |
| `would remove` | with `--dry-run`: `remove` would take this hook out; it is still there |

```text
$ use-cases hooks add commit push --dry-run
would add the commit hook
would add the push hook
commit   would install  use-cases validate
push     would install  use-cases status --gate
```

With `--json` (chapter 16 §5):

```json
{
  "output_version": 1,
  "command": "hooks",
  "hooks_dir": ".git/hooks",
  "managed": false,
  "hooks": [
    {"name": "commit", "event": "pre-commit", "state": "installed", "runs": "use-cases validate"},
    {"name": "push", "event": "pre-push", "state": "absent", "runs": "use-cases status --gate"}
  ],
  "changed": [],
  "notes": [],
  "dry_run": false
}
```

`changed` lists the hooks this request added or removed, or with `--dry-run` would add or remove. `hooks_dir` is relative to the workspace root.

## 6. Exit codes

```text
0   done
1   done, and something needs you: a hook was left alone (another file, or a hook manager)
2   refused: not a git repository, an unknown hook name, or no workspace
```

## 7. Final model

```text
use-cases hooks add commit|push
        |
git repository?  ── no ──▶ refused (exit 2)
        |
core.hooksPath set?  ── yes ──▶ write nothing; print the line for the hook manager (exit 1)
        |
a different hook file there?  ── yes ──▶ leave it; print the line to add (exit 1)
        |
write the hook script into this clone's hooks folder (not committed)
        |
commit: use-cases validate        push: use-cases status --gate
```
