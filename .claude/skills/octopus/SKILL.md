---
name: octopus
description: >-
  Development workflow for the Octopus fork of Chatwoot (alphnology/chatwoot), built around
  the long-lived `octopus` branch. Use when the user wants to bring a new upstream Chatwoot
  release in ("merge v4.18.0 into octopus", "sync with upstream chatwoot", "upgrade the fork
  to v4.18", "bring our customizations up to the new Chatwoot"), to land our own change
  ("start a feature/fix on octopus", "land this change in octopus", "open a PR to octopus"),
  to resolve or verify an in-progress sync, to check whether a fork customization got lost,
  or to ask which upstream version octopus is on. Encodes this repo's schema.rb,
  migration-swap and inline-image landmines, the merge-commit rule and the gh --repo gotcha.
---

# Octopus development workflow

This repo is a fork of `chatwoot/chatwoot`, rebranded **Octopus**. `origin` = alphnology,
`upstream` = chatwoot.

| Branch | Meaning |
|---|---|
| `octopus` | **the development branch.** Upstream releases and our changes both land here, always via PR |
| `sync/vX.Y.Z` | carries one upstream release tag into `octopus` (Flow U) |
| `feat/<name>`, `fix/<name>` | our own changes, branched from `octopus` (Flow F) |
| `develop`, `vX.Y.Z-dev`, `vX.Y.Z-dev-merge` | history of the old per-release model — read only, never a base |

`octopus` started as `v4.16.2-dev-merge`. Which upstream release it is on is derived, never
stored:

```bash
BASE=$(git tag --merged octopus --sort=-v:refname --list 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
```

The one rule that governs every sync: **`ours` = fork customizations, `theirs` = new
Chatwoot. Never blanket-take either side.**

The customization inventory and per-category strategies live in
`.claude/skills/octopus/references/customizations.md`. Read it before resolving anything,
and add to it whenever a change of ours lands (Flow F).

---

## The six traps

**1. `gh` resolves to upstream, not this fork.** `gh pr list` with no `--repo` returns
`chatwoot/chatwoot` PRs (#15xxx). This fork's own PRs are single digits. **Every `gh` call
carries `--repo alphnology/chatwoot`.** Sanity check: `gh pr list --repo alphnology/chatwoot
--limit 5` must return small numbers.

**2. Only merge upstream release tags.** `vX.Y.Z` — never `upstream/develop`,
`upstream/master` or an old `-dev` branch (they drifted: `v4.13.0-dev` was 21 commits ahead
of its tag, `v4.10.1-dev` was a stale copy of `-dev-merge`). `BASE` detection and every diff
in this skill assume `octopus` contains exactly released tags.

**3. The conflict list is the small problem.** On the 4.10.1 → 4.16.2 merge, measured by
actually running it: **18 conflicts, but 57 fork-owned files auto-merged silently.** Files
only this fork touched merge with no marker and never enter the resolution loop — they are
where customizations die. Direction C of the audit exists for exactly this.

**4. Upstream re-introduces "Chatwoot" strings.** Measured on the same merge: this fork had
**1** en-i18n file containing `Chatwoot` before the merge, **5** after — upstream added new
user-facing strings. A merge that "succeeds" still ships branding regressions. This is why
category B is never resolved whole-file `--ours` *and* is re-swept after merging.

**5. Auto-merged ≠ preserved.** `db/migrate/20231211010807_add_cached_labels_list.rb` holds
a fork fix (`ActsAsTaggableOn::Taggable::Cache` → `Caching`) that upstream **still ships
broken at 4.16.2**. Only one side changed it, so it merges silently — and a careless
directory-wide `--theirs` on `db/` reverts it without a word.

**6. A `sync/*` PR must be merged with "Create a merge commit".** Squash or rebase rewrites
upstream's commits and drops the release tag from `octopus`'s ancestry: `BASE` detection then
returns the *previous* release, and the next sync replays hundreds of already-absorbed
upstream commits as conflicts. State this in every sync PR body. `feat/*`/`fix/*` PRs may be
squashed.

---

# Flow U — upstream sync

## Step 0 — Preflight

All read-only. Every check must pass before a branch is created.

```bash
git status --porcelain                     # MUST be empty — never stash silently
git fetch origin && git fetch upstream --tags
gh pr list --repo alphnology/chatwoot --limit 5    # trap 1 sanity check
```

Resolve the target. If the user names none, default to the newest upstream release tag and
confirm before proceeding:

```bash
NEW_TAG=$(git tag --sort=-v:refname --list 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
TARGET=sync/$NEW_TAG
```

If `origin/octopus` exists and differs from local `octopus`, fast-forward local first
(`git checkout octopus && git merge --ff-only origin/octopus`) — never sync from a stale tip.

Then run the forecast, which detects `BASE` and performs the remaining checks (tag format,
not already merged, newer than `BASE`, `octopus` in step with `origin/octopus`):

```bash
.claude/skills/octopus/scripts/forecast.sh "$NEW_TAG"
BASE=$(git tag --merged octopus --sort=-v:refname --list 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
```

If it exits non-zero, **stop** and report why. Do not pick a different base for the user.

Jumping several releases in one sync (e.g. 4.16.2 → 4.18.0) is fine — the forecast shows the
scale. If it is very large, offer to go one minor at a time; each step is its own
`sync/*` PR.

If `$TARGET` already exists, warn that re-running means a force-push and wait for a
go-ahead — check for an open PR on it first (`gh pr list --repo alphnology/chatwoot --head
"$TARGET"`).

## Step 1 — Read the forecast

`forecast.sh` prints two lists:

- **both sides touched** — likely conflicts. This **over-predicts** (38 predicted vs 18 real
  on 4.10.1→4.16.2); git merges many overlapping files cleanly. Treat it as an upper bound.
- **ours only** — the silent-loss risk (trap 3). This is the list that matters most.

Group both by the categories in `references/customizations.md`, print a work plan, and **get
a go-ahead before creating the branch.**

## Step 2 — Branch and merge

```bash
git checkout -b "$TARGET" octopus
git -c rerere.enabled=true -c merge.conflictStyle=zdiff3 merge --no-commit --no-ff "$NEW_TAG"
git diff --name-only --diff-filter=U | sort
```

- `--no-commit` is mandatory — nothing lands before the audit passes.
- `zdiff3` shows the merge base in a `|||||||` section, which is what makes "did the fork add
  this, or did upstream remove it?" answerable. Set via `-c` so the user's global config is
  never mutated.
- `rerere` makes a re-run cheap.

Compare the real conflict set to the forecast. Investigate any file that conflicted but was
**not** forecast — it means an assumption about `octopus` or `BASE` is wrong.

## Step 3 — Resolve, category by category

Work `references/customizations.md` top to bottom: mechanical categories first, judgement
calls last, so the list shrinks before the hard thinking starts.

For every conflicted file, before touching it:

```bash
git log --oneline "$BASE..$NEW_TAG" -- <file>   # WHY upstream changed it
git diff "$BASE..octopus" -- <file>             # WHY the fork changed it
```

**Never `git add` a file whose upstream log you have not read.**

Any conflicted file with no matching category is a gap in the inventory — say so and classify
it with the user rather than improvising.

## Step 4 — Cruft and migrations

```bash
git rm -f --ignore-unmatch repro_threading.rb        # accidental debug script at repo root
ls db/migrate | grep -E '20250416182131|20250421082927'
ls db/migrate | wc -l                                # must equal the next line
git ls-tree --name-only "$NEW_TAG" db/migrate/ | wc -l   # upstream's count (158 at v4.16.2)
```

**The migration swap does not conflict.** Verified by trial merge: git applies the fork's
rename unopposed, producing **2** files under the fork's swapped names with **no duplicate
class names**. It is silent, so it must be asserted rather than waited for. Default decision:
**keep the fork's swap** — deployed instances already recorded those timestamps in
`schema_migrations`, and both namings use the same two timestamp values, so no
`schema_migrations` edit is needed. State this explicitly in the PR body; it is not the
intuitive answer.

Flag but do not unilaterally change: the hardcoded `POSTGRES_PASSWORD=p0stgr3s` in
`docker-compose.yaml`, and the hardcoded Spanish `'Opciones'` in
`app/services/whatsapp/providers/base_service.rb` (a regression over
`I18n.t('conversations.messages.whatsapp.list_button_label')`).

## Step 5 — Audit (the gate)

```bash
.claude/skills/octopus/scripts/audit.sh "$NEW_TAG"     # sync mode: a merge is in progress
```

Three directions. **Any FAIL blocks the commit.**

- **A — nothing of ours lost.** Every invariant in `references/customizations.md`.
- **B — nothing of theirs reverted.** Files identical to `octopus` that upstream changed in
  `$BASE..$NEW_TAG` are suspected bad `--ours`; plus the fork-untouched set must be
  byte-identical to upstream. A difference there is a red flag — this fork does not customize
  `package.json`, lockfiles, `Gemfile*`, `docker/Dockerfile`, `.github/**`, `config/routes.rb`
  or `config/features.yml`.
- **C — the silent losses.** The ours-only set from the forecast, asserted by name. This is
  the direction that catches traps 3 and 5.

Then close the loop: **add an `[ALPHNOLOGY]` marker comment to every customization hunk that
lacks one.** The convention already exists in `Editor.vue`, `MessageFormatter.js` and
`lib/base_markdown_renderer.rb`; extending it makes the next release's Direction C a single
`git grep`.

Only once the table is all-PASS:

```bash
git commit -m "chore(upstream): merge chatwoot $NEW_TAG into octopus"
```
 **No AI attribution, ever.**

## Step 6 — Verify

Cheapest first; stop and report on the first failure.

1. **Conflict-marker sweep** — `git grep -nE '^(<{7}|={7}|>{7})'` must be empty.
2. **Lint the resolved files only** (`eval "$(rbenv init -)"` first, per `CLAUDE.md`):
   `pnpm eslint <changed .js/.vue>` and `bundle exec rubocop <changed .rb>`.
3. **Build via docker** — the user's explicit choice over bare `pnpm`/`bundle`. Service names
   verified identical between this fork and 4.16.2 (`rails`, `sidekiq`, `vite`, `postgres`,
   `redis`, `mailhog`; the compose files differ only by the removed `version:` key).
   ```bash
   make docker-amd64
   docker compose -f docker-compose.yaml build
   docker compose -f docker-compose.yaml up -d
   docker compose exec rails bundle exec rails db:migrate
   docker compose logs rails | grep -i 'Multiple migrations have the class name'   # must be empty
   ```
   The in-container `db:migrate` is the only real proof the new upstream migrations apply
   on top of the fork's swapped pair. Re-check the service names against `$NEW_TAG`'s
   `docker-compose.yaml` if the compose file conflicted.
4. **Tests** — `pnpm test`, plus rspec targeted at the categories actually touched:
   ```bash
   bundle exec rspec spec/models/conversation_spec.rb spec/models/message_spec.rb \
     spec/services/whatsapp spec/services/microsoft spec/mailboxes spec/presenters
   ```
5. **Browser verification with screenshots.** Invoke the **`claude-in-chrome` skill**, which
   drives the user's already-installed Chrome against the compose stack. **Never download a
   browser** — no Playwright, no Puppeteer, no `npx`. Playwright is not installed here and
   the user asked explicitly for the installed browser. If the extension is not connected,
   stop and ask them to connect it rather than falling back.

   | Shot | Proves |
   |---|---|
   | Login page + favicon | A — branding assets and strings |
   | Sidebar expanded | E — SLA Reports & Agent Bots hidden, new upstream entries present |
   | Composer, Shift+Cmd/Ctrl+V an image | C — inline paste survived upstream #14516 |
   | Message context menu | D — no Delete |
   | Contact detail panel | D — no Delete |
   | SuperAdmin dashboard | I |
   | Any feature upstream added in this range | nothing upstream got reverted |

   Present the screenshots inline in the summary — this is the image proof the user asked
   for — and attach them to the PR.

## Step 7 — Push and open the PR

**Only after explicit approval.**

```bash
git push -u origin "$TARGET"
gh pr create --repo alphnology/chatwoot \
  --base octopus --head "$TARGET" \
  --title "chore(upstream): merge chatwoot $NEW_TAG into octopus" \
  --body-file <body>
```

Body sections: ① summary + `git diff --stat "$NEW_TAG..$TARGET"` ② upstream commits absorbed
(`$BASE..$NEW_TAG`) ③ **the Step 5 audit table verbatim** ④ conflict ledger — each
conflicted file, strategy applied, one-line why ⑤ landmines and decisions (schema.rb taken
wholesale; the migration swap kept, with the "no `schema_migrations` change needed"
reasoning) ⑥ verification results + screenshots ⑦ deployer actions required ⑧ follow-ups
(e.g. `'Opciones'` → i18n) ⑨ **"Merge with *Create a merge commit* — never squash or rebase
(trap 6)."** No AI attribution anywhere.

After it is merged, confirm the tag landed: `git fetch origin && git tag --merged
origin/octopus | grep -x "$NEW_TAG"` must print it. If it does not, the PR was squashed —
stop and tell the user before anything else lands on `octopus`.

## Step 8 — Refresh the inventory

Before the PR is merged, reconcile `references/customizations.md` against the sync: bucket
`git diff --name-only "$NEW_TAG..$TARGET"` into the categories and report
**UNCATEGORIZED** (a customization nobody registered), **VANISHED** (upstreamed or dropped —
propose deleting the row) and **MOVED** (invariant grep fails but the string exists at a new
path). Update the reference **only with the user's approval**, then append a row to its
merge-history table.

This skill lives in the repo, so the update rides along on the same `sync/*` branch and PR
as the merge it describes — the inventory can never be one release out of date.

---

# Flow F — our own changes

Every fork change lands on `octopus` through a `feat/*` or `fix/*` PR. Nothing is committed
directly on `octopus`.

1. **Branch from a fresh tip.**
   ```bash
   git status --porcelain                  # MUST be empty
   git fetch origin
   git checkout octopus && git merge --ff-only origin/octopus   # skip if octopus is not on origin yet
   git checkout -b feat/<name> octopus     # or fix/<name>
   ```
2. **Build it per `CLAUDE.md`** — Tailwind only, Composition API, `en.yml`/`en.json` only,
   `enterprise/` overlay checks, `replaceInstallationName` for anything that says Chatwoot.
3. **Mark it.** Put an `[ALPHNOLOGY]` comment on every hunk that diverges from upstream
   behavior. Direction C of the next sync starts from `git grep '\[ALPHNOLOGY\]'`.
4. **Register it.** Add the change to `references/customizations.md` (a row in an existing
   category, or a new lettered category with *Strategy* and an `ASSERT` block) and a
   matching `chk` line in `scripts/audit.sh`. This is what protects it in the next sync — an
   unregistered change is the next silent loss (trap 3). A pure bug fix that leaves no
   fork-specific behavior (e.g. a lint fix) does not need a row; say so explicitly.
5. **Audit in feature mode** — no merge is in progress, so only Direction A runs:
   ```bash
   .claude/skills/octopus/scripts/audit.sh
   ```
   All PASS, including the new invariant.
6. **Verify** — lint the changed files, run the targeted specs/tests, and for UI changes take
   `claude-in-chrome` screenshots (never download a browser).
7. **Commit** with a Conventional Commit (`feat(scope): subject`), no AI attribution.
8. **Push and open the PR — only after explicit approval.**
   ```bash
   git push -u origin feat/<name>
   gh pr create --repo alphnology/chatwoot --base octopus --head feat/<name> --body-file <body>
   ```
   Body per `CLAUDE.md`'s PR format, plus a line naming the customizations.md category it
   registered under.

If a `sync/*` PR is open when a feature lands, the sync branch must merge `octopus` again
(`git merge octopus` on the sync branch, then re-run the audit) before it is merged.

---

## Hard rules

1. Never `git merge` an upstream release without `--no-commit`.
2. Never hand-merge `db/schema.rb` — `--theirs` wholesale, then assert it equals the upstream
   tag byte for byte.
3. Never resolve the inline-image files (category C) by taking a side. Consolidate against
   upstream PR #14516, or stop and ask.
4. Never whole-file `--ours` on i18n JSON, `config/locales/en.yml` or `Sidebar.vue` — it
   silently drops upstream's new keys and nav entries.
5. Never `git checkout --ours/--theirs` on a directory or glob. File by file, after reading
   both logs.
6. Never commit while any audit row is FAIL.
7. Never push or open a PR without explicit approval.
8. Only upstream release tags (`vX.Y.Z`) are merged into `octopus` — never an upstream branch
   or an old `-dev` branch.
9. `sync/*` PRs are merged with a merge commit only — never squash, never rebase.
10. Nothing is committed directly on `octopus`; every change arrives through a PR.
11. Every `gh` call carries `--repo alphnology/chatwoot`.
12. Never mutate the user's global git config — use `git -c` for `rerere`/`conflictStyle`.
13. Never run `bundle install`/`pnpm install` on the host as the build check; the build check
    is docker.
14. Never download a browser. Browser verification is `claude-in-chrome` on the user's Chrome.
15. No AI attribution in commit messages or the PR body.
16. A conflict in `package.json`, lockfiles, `Gemfile*`, `docker/Dockerfile`, `.github/**` or
    `config/routes.rb` is a red flag, not a routine resolution — investigate before accepting.
17. This repo's `CLAUDE.md` overrides this skill on any conflict (Tailwind-only, Composition
    API, `en.yml`/`en.json` only, `enterprise/` overlay checks).
