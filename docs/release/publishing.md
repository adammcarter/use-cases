# Publishing to npm (Trusted Publishing + provenance)

How `@use-cases-plugin/core`, `@use-cases-plugin/cli`, and `@use-cases-plugin/mcp`
are released to npm. All three packages are **published together at the same
version** (see the [stability policy](../reference/stability.md)).

Releases are **tokenless**: the
[`release` workflow](../../.github/workflows/release.yml) uses
[npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers) (OIDC) and
attaches [build provenance](https://docs.npmjs.com/generating-provenance-statements).
There is no `NPM_TOKEN` secret. npm mints a short-lived, workflow-scoped
credential from the GitHub Actions `id-token`, so the credential cannot leak or
be reused.

---

## Owner one-time setup (human only — an agent cannot do this)

These steps require a logged-in npm account with publish rights to the
`@use-cases-plugin` scope and must be done **once** on npmjs.com / GitHub before
the first publish. CI cannot bootstrap them.

1. **Create the npm scope/org.** Create the `@use-cases-plugin` scope (an npm org
   or a user scope) on npmjs.com. Confirm the account that owns it has publish
   rights.

2. **Create each package as public, or let the first publish create it.**
   Trusted Publishing can create a brand-new package on first publish, but the
   trusted-publisher link (next step) is configured **per package**, so each of
   the three package names must exist (or be created in the same flow). The
   packages are scoped, so they must be published with **public** access — this
   repo already sets `"publishConfig": { "access": "public", "provenance": true }`
   in every package manifest.

3. **Configure the Trusted Publisher on each package.** On npmjs.com, open each
   package → **Settings → Trusted Publishing → Add a trusted publisher** and set:
   - **Publisher:** GitHub Actions
   - **Organization / user:** `adammcarter`
   - **Repository:** `presentation-skills`
   - **Workflow filename:** `release.yml`
   - **Environment:** leave blank (the workflow does not use a GitHub
     environment).

   Do this for **all three** packages: `@use-cases-plugin/core`,
   `@use-cases-plugin/cli`, `@use-cases-plugin/mcp`.

4. **Provenance / 2FA.** Provenance is generated automatically by Trusted
   Publishing — no extra npm setting is needed beyond the trusted-publisher link.
   If the account/org enforces 2FA "for write" actions, confirm the org's
   publishing-access setting permits **automation/OIDC** publishes (Trusted
   Publishing satisfies the 2FA requirement without an automation token).

5. **Version floors required by Trusted Publishing.** The publishing runner needs
   **npm `>= 11.5.1`** and **Node `>= 22.14.0`**. The release workflow pins Node
   22 (whose bundled npm meets the floor). Self-hosted runners are **not**
   supported by npm Trusted Publishing — keep the job on GitHub-hosted runners.

> After this is configured, no human action is needed per release beyond pushing
> the tag (below). There is no token to rotate.

---

## Cutting a release

Everything below is normal repo work an agent or maintainer can do.

1. **Land all release work on `main`** and make sure the
   [release gate](../release.md) is green:

   ```bash
   node scripts/release-gate.mjs
   ```

2. **Set the version on all three packages** (and the root) to the target
   version. They must match. For example, for `1.0.0`:

   ```bash
   # from the repo root
   npm version 1.0.0 --no-git-tag-version --workspaces --include-workspace-root
   ```

   (Or edit each `packages/ucp-*/package.json` + root `package.json` by hand.)
   Do **not** change package names.

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

6. **The workflow does the rest:** install → build → test → `pnpm -r publish`
   with `--provenance`. Watch the `release` workflow run. On success, all three
   packages are live with provenance.

7. **Post-publish smoke** (optional but recommended):

   ```bash
   npx @use-cases-plugin/cli --version --json
   npx -y @use-cases-plugin/mcp   # should start the stdio server
   ```

   Confirm the provenance badge appears on each package page on npmjs.com.

---

## Release-candidate → stable flow

Publish a release candidate first, dogfood it from npm, then promote to stable.
npm dist-tags keep `latest` pointing at the stable line while RCs install only
when asked for explicitly.

1. **RC:** set the version to a prerelease and tag it. pnpm publishes prerelease
   versions under the `next` dist-tag automatically (a `1.0.0-rc.1` version is
   not tagged `latest`), so `npm install @use-cases-plugin/cli` keeps resolving
   the last stable release:

   ```bash
   npm version 1.0.0-rc.1 --no-git-tag-version --workspaces --include-workspace-root
   git commit -am "release: v1.0.0-rc.1"
   git tag v1.0.0-rc.1
   git push origin main --tags
   ```

   Install and exercise the RC explicitly:

   ```bash
   npm install @use-cases-plugin/cli@next       # or @1.0.0-rc.1
   ```

2. **More RCs if needed:** `1.0.0-rc.2`, … repeat.

3. **Stable:** when the RC is proven, cut the stable version. This publishes
   under the `latest` dist-tag:

   ```bash
   npm version 1.0.0 --no-git-tag-version --workspaces --include-workspace-root
   git commit -am "release: v1.0.0"
   git tag v1.0.0
   git push origin main --tags
   ```

---

## What provenance does (and does not) prove

npm provenance attests **where and how the package tarball was built** (this
repo, this workflow, this commit). It is independent of UCM's own
proof/evidence ledger: npm provenance proves package build origin, **not**
row-level use-case freshness. Keep the two mental models separate.

The tarball contents themselves are guarded by
[`tests/release/pack-contents.test.ts`](../../tests/release/pack-contents.test.ts),
which runs in the release workflow's `test` step and fails the publish if any
package would ship source, tests, build config, local state, or secrets.
