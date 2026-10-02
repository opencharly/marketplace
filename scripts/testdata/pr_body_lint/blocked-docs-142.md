## Summary

Rewrites `start/install.md`, a hand-written page, so the install path matches what charly ships today.

- **Before:**
  - The page led with "a source build with Go + go-task".
  - That build cloned `opencharly/charly` directly and ran `scripts/bootstrap-charly.sh --install`.
  - The signed native package repositories were never mentioned.
  - go-task is no longer part of the toolchain: the repo's maintenance surface is `charly task`.
- **After:**
  1. **The package repositories come first.** There are copy-paste steps for Fedora, Debian/Ubuntu, Arch/CachyOS and Alpine, taken from each `charly-<distro>` repo's README. The Arch steps are the corrected ones merged in opencharly/charly-arch#10.
  2. **The variants table** (`charly`, `charly-full`, `charly-minimal`), with the plugin sets from charly's `packaging/charly.yml`. The OpenWrt feed and the JetKVM build each get one line.
  3. **`charly version` + `charly doctor`** as the "it works" check.
  4. **The mise section**, unchanged apart from its final sentence. A release binary brings no runtime dependencies, unlike the packages.
  5. **"Developing charly"** now routes contributors to the `opencharly/opencharly` umbrella: clone with `--recurse-submodules`, run `./charly/scripts/bootstrap-charly.sh`, and work in per-session worktrees under `.worktrees/<slug>/<repo>/` with PR-only landing. This matches the umbrella `AGENTS.md` "The development model". It replaces the clone-charly-directly section.

Part of opencharly/charly#747 (README and docs truth audit).

## How tested

Head `041625863684b7dfa7306f4ea1f1147aeeef6542`, based on `origin/main` `b36cc88`:

```
 src/content/docs/start/install.md | 125 +++++++++++++++++++++++++++-----------
 1 file changed, 92 insertions(+), 33 deletions(-)
```

The repo's own build gate (`AGENTS.md` "Build / validate / test"), on this tree:

```
$ npm ci && npm run build
00:11:31 [build] 1476 page(s) built in 1m 25s
00:11:31 [build] Complete!
exit=0
$ grep -c -i warn build.log
0
```

Every URL the page uses was checked live (HTTP status, then URL):

```
200 https://opencharly.github.io/charly-fedora/RPM-GPG-KEY-charly
200 https://opencharly.github.io/charly-debian/charly.gpg
200 https://opencharly.github.io/charly-ubuntu/charly.gpg
200 https://opencharly.github.io/charly-ubuntu/dists/stable/Release
200 https://opencharly.github.io/charly-arch/charly.gpg
200 https://opencharly.github.io/charly-arch/amd64/charly.db
200 https://opencharly.github.io/charly-alpine/charly.rsa.pub
200 https://opencharly.github.io/charly-alpine/amd64/x86_64/APKINDEX.tar.gz    # apk appends its arch to the repo URL
200 https://opencharly.github.io/charly-alpine/arm64/aarch64/APKINDEX.tar.gz
200 https://github.com/opencharly/charly-openwrt
200 https://github.com/opencharly/charly-jetkvm
200 https://github.com/opencharly/opencharly/blob/main/AGENTS.md
```

The Arch key fingerprint `978DFF11A951A830F7ADA2D4062B073E9D1BAE2E` is the one of the published `charly.gpg`, verified in opencharly/charly-arch#10 against the `check-arch-repo` bed's own key derivation. The variant plugin lists match `packaging/charly.yml` `variants.{default,full,minimal}.plugins` on charly `main`.

No page links into the removed headings:

```
$ grep -rn -E 'start/install/?#|install#' src/content/docs --include='*.md' --include='*.mdx' | grep -v -E 'reference/|recipes/'
$
```

**Not re-run here:**
- The mise commands; mise is not installed on the test host. That section's commands are unchanged; its pinned example `v2026.234.1727` exists as a GitHub release.
- The package installs themselves; the repos' own install-test beds prove those.

## Rulebook compliance

- **R0:** `/charly-internals:git-workflow` and `/charly-build:docs` were loaded.
- **R4a:** the page leads with the native package, per the "one exception is the INSTALL page" clause; working on charly is scoped to the umbrella.
- **R5:** the go-task / clone-charly path is removed.
- **R6:** a feat branch, a single push, no force push.
- **Rule 9:** no other session's PR touches `start/` (the open docs PRs were checked); the work is coordinated on #747.
- **R10:** no runtime path changed.

## Change classification

- **Change class:** documentation only (a hand-written page; no generated page touched).
- **Verification gate:** `npm ci && npm run build` passed with zero warnings, and every URL was checked live (above).
- **Attribution tier:** documentation reviewed.

*Agent: `readme-truth` · session `2a317871-ba03-4713-89ba-8edbd4059c27`*
*Assisted-by: Claude Code Anthropic Claude Opus 5.5 (documentation reviewed)*
