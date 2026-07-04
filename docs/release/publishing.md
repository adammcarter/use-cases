# Publishing to npm (Trusted Publishing + provenance)

How the **`use-cases`** package is released to npm. This is a single,
self-contained package: the `uc` and `uc-mcp` binaries plus the plugin bundle
(skills, hooks, bootstrap, docs, schemas) ship together in one tarball. The
`packages/core`, `packages/cli`, and `packages/mcp` workspaces are **private**
and are bundled inside this package — they are **not** published separately. The
CLI resolves the bundled core through a relative fallback (`coreLoader.ts`), so
the published package runs standalone with no scoped dependencies.

Releases are **tokenless**: the
[`release` workflow](../../.github/workflows/release.yml) uses
[npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers) (OIDC) and
attaches [build provenance](https://docs.npmjs.com/generating-provenance-statements).
There is no `NPM_TOKEN` secret. npm mints a short-lived, workflow-scoped
credential from the GitHub Actions `id-token`, so the credential cannot leak or
be reused.

---

## Owner one-time setup (human only — an agent cannot do this)

These steps require a logged-in npm account and must be done **once** on
npmjs.com / GitHub before the first publish. CI cannot bootstrap them.

1. **Make sure the name `use-cases` is free — and not an npm _org_.** On
   npm, org names and unscoped package names share one namespace: if an
   organization named `use-cases` exists, you **cannot** publish a package
   of the same name. If you created such an org, delete it first (npmjs.com →
   your org → **Settings → Delete organization**; an org with no published
   packages can be deleted directly). Then `use-cases` is available to
   publish as a package.

2. **Do the first publish manually (token-based).** npm Trusted Publishing
   **cannot create a brand-new package** — a trusted publisher can only be added
   to a package that already exists on the registry. So the very first publish
   must go out with an ordinary credential (a local `npm login`, or a short-lived
   automation token). From the repo root:

   ```bash
   npm login                 # your npm account
   corepack pnpm -s build    # builds the workspace; the root packs the dist
   npm publish --access public
   ```

   Only `use-cases` publishes — the three workspace packages are private
   and are skipped. This local publish carries **no provenance** (provenance
   needs the OIDC/CI context), so it arrives on the next release from CI. If you
   want provenance on the headline `1.0.0`, publish a throwaway prerelease here
   (`1.0.0-rc.0`, see the RC flow below) and cut the real `1.0.0` from CI once
   step 3 is in place. Delete any temporary token afterward.

3. **Configure the Trusted Publisher on the package** (now that it exists). On
   npmjs.com, open the `use-cases` package → **Settings → Trusted
   Publishing → Add a trusted publisher** and set:
   - **Publisher:** GitHub Actions
   - **Organization / user:** `adammcarter`
   - **Repository:** `use-cases`
   - **Workflow filename:** `release.yml`
   - **Environment:** leave blank (the workflow does not use a GitHub
     environment).
   - **Allowed actions:** tick **npm publish** — trusted publishers created after
     2026-05-20 must select at least one allowed action (older ones defaulted to
     publish-only).

   Fields are **case-sensitive** and are **not** validated on save — a typo
   surfaces only as a failed publish.

4. **Provenance / 2FA.** Provenance is generated automatically by Trusted
   Publishing — no extra npm setting is needed beyond the trusted-publisher link.
   If the account enforces 2FA "for write" actions, confirm the publishing-access
   setting permits **automation/OIDC** publishes (Trusted Publishing satisfies
   the 2FA requirement without an automation token).

5. **Version floors required by Trusted Publishing.** The publishing runner needs
   **npm `>= 11.5.1`** and **Node `>= 22.14.0`**. The release workflow pins Node
   24 and upgrades npm to latest, which clears both floors. The publish step uses
   the **npm CLI**, not `pnpm publish` — pnpm 11 has an open OIDC regression
   ([pnpm/pnpm#11513](https://github.com/pnpm/pnpm/issues/11513)) that 404s on
   trusted publish. Self-hosted runners are **not** supported by npm Trusted
   Publishing — keep the job on GitHub-hosted runners.

> After the first manual publish and the trusted-publisher link are in place, no
> human action is needed per release beyond pushing the tag (below). There is no
> long-lived token to rotate — revoke the temporary first-publish token once the
> OIDC path is proven.

---

## Cutting a release

Everything below is normal repo work an agent or maintainer can do.

1. **Land all release work on `main`** and make sure the
   [release gate](../release.md) is green:

   ```bash
   node scripts/release-gate.mjs
   ```

2. **Set the version** to the target. The `use-cases` package version is
   the source of truth, but the version-parity test also checks the workspace
   package manifests, the plugin manifests, and `packages/core/src/version.ts` —
   bump them together. The quickest way for the manifests:

   ```bash
   # from the repo root
   npm version 1.0.0 --no-git-tag-version --workspaces --include-workspace-root
   ```

   Then update `packages/core/src/version.ts` (`UCM_VERSION`) and the
   `plugin.json` / `.claude-plugin/plugin.json` / `.codex-plugin/plugin.json`
   versions to match. Do **not** change package names.

3. **Update the changelog.** Add the release section to `CHANGELOG.md`.

4. **Commit** the version bump + changelog:

   ```bash
   git commit -am "release: v1.0.0"
   ```

5. **Tag and push.** The workflow triggers on a pushed `v*` tag (and on a
   published GitHub Release):

   ```bash
   git tag v1.0.0
   git push origin main --tags
   ```

6. **The workflow does the rest:** install → build → test → `npm publish` with
   `--provenance`. Watch the `release` workflow run. On success, `use-cases`
   is live with provenance.

7. **Post-publish smoke** (optional but recommended):

   ```bash
   npx use-cases --version --json           # runs the uc CLI
   npx -p use-cases use-cases-mcp      # should start the stdio server
   ```

   Confirm the provenance badge appears on the package page on npmjs.com.

---

## Release-candidate → stable flow

Publish a release candidate first, dogfood it from npm, then promote to stable.
npm dist-tags keep `latest` pointing at the stable line while RCs install only
when asked for explicitly.

1. **RC:** set the version to a prerelease and tag it. A prerelease version
   (`1.0.0-rc.1`) is not tagged `latest`, so `npm install use-cases` keeps
   resolving the last stable release:

   ```bash
   npm version 1.0.0-rc.1 --no-git-tag-version --workspaces --include-workspace-root
   # bump version.ts + plugin manifests to match, then:
   git commit -am "release: v1.0.0-rc.1"
   git tag v1.0.0-rc.1
   git push origin main --tags
   ```

   Install and exercise the RC explicitly:

   ```bash
   npm install -g use-cases@next       # or @1.0.0-rc.1
   ```

2. **More RCs if needed:** `1.0.0-rc.2`, … repeat.

3. **Stable:** when the RC is proven, cut the stable version. This publishes
   under the `latest` dist-tag:

   ```bash
   npm version 1.0.0 --no-git-tag-version --workspaces --include-workspace-root
   # bump version.ts + plugin manifests to match, then:
   git commit -am "release: v1.0.0"
   git tag v1.0.0
   git push origin main --tags
   ```

---

## What provenance does (and does not) prove

npm provenance attests **where and how the package tarball was built** (this
repo, this workflow, this commit). It is independent of the tool's own
proof/evidence ledger: npm provenance proves package build origin, **not**
row-level use-case freshness. Keep the two mental models separate.

The tarball contents themselves are guarded by
[`tests/release/pack-contents.test.ts`](../../tests/release/pack-contents.test.ts),
which runs in the release workflow's `test` step and fails the publish if the
package would ship source, tests, build config, local state, or secrets.
