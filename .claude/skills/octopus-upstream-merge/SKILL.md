---
name: octopus-upstream-merge
description: >-
  Merge a new upstream Chatwoot release into this fork's customizations and open the PR
  against alphnology/chatwoot. Use when the user says "merge v4.10.1-dev-merge with
  v4.16.2-dev", "merge <old>-dev-merge into <new>-dev", "upgrade the fork to v4.16.2",
  "bring our customizations up to the new Chatwoot", "sync with upstream chatwoot",
  "create the v4.16.2-dev-merge branch", or asks to resolve or verify an in-progress
  upstream merge, or to check whether a fork customization got lost. Encodes this repo's
  schema.rb, migration-swap and inline-image landmines plus the gh --repo gotcha.
---

# Octopus ⇄ upstream Chatwoot merge

This repo is a fork of `chatwoot/chatwoot`, rebranded **Octopus**. `origin` = alphnology,
`upstream` = chatwoot. Each upstream release has to carry the fork's customizations forward.

| Branch shape | Meaning |
|---|---|
| `vX.Y.Z-dev` | *intended* to be a clean upstream release point |
| `vX.Y.Z-dev-merge` | that release **with** the fork's customizations merged in |

The one rule that governs everything: **`ours` = fork customizations, `theirs` = new
Chatwoot. Never blanket-take either side.**

The customization inventory and per-category strategies live in
`.claude/skills/octopus-upstream-merge/references/customizations.md`. Read it before
resolving anything.

---

## The five traps

**1. `gh` resolves to upstream, not this fork.** `gh pr list` with no `--repo` returns
`chatwoot/chatwoot` PRs (#15xxx). This fork's own PRs are single digits. **Every `gh` call
carries `--repo alphnology/chatwoot`.** Sanity check: `gh pr list --repo alphnology/chatwoot
--limit 5` must return small numbers.

**2. `-dev` branches lie.** They are *not* reliably clean upstream release points. Measured:

| ref | vs its tag |
|---|---|
| `v4.16.2-dev` | `0 0` — clean |
| `v4.13.0-dev` | **21 commits ahead** — already carries a partial fork merge |
| `v4.10.1-dev` | **identical to `v4.10.1-dev-merge`** — a stale pointer, not the 4.10.1 base |

Verify before starting (Step 0), and always derive the fork's customization surface from
the **tag** (`v4.10.1`), never from the `-dev` branch.

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

---

## Step 0 — Preflight

All read-only. Every check must pass before a branch is created.

```bash
git status --porcelain                     # MUST be empty — never stash silently
git fetch origin && git fetch upstream --tags
gh pr list --repo alphnology/chatwoot --limit 5    # trap 1 sanity check
```

Resolve the arguments. If the user names only one branch, infer OLD as the newest existing
`*-dev-merge` and confirm before proceeding.

```bash
OLD=v4.10.1-dev-merge ; NEW=v4.16.2-dev
OLD_VER=4.10.1        ; NEW_VER=4.16.2
BASE=v$OLD_VER        ; TARGET=v${NEW_VER}-dev-merge   # BASE is the TAG (trap 2)
```

Then run the forecast, which performs the remaining preflight checks and refuses to pass on
a drifted branch:

```bash
.claude/skills/octopus-upstream-merge/scripts/forecast.sh "$OLD_VER" "$NEW_VER" "$OLD" "$NEW"
```

If it exits non-zero, **stop** and report what drifted. Do not pick a different base for the
user.

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
git checkout -b "$TARGET" "$OLD"
git -c rerere.enabled=true -c merge.conflictStyle=zdiff3 merge --no-commit --no-ff "$NEW"
git diff --name-only --diff-filter=U | sort
```

- `--no-commit` is mandatory — nothing lands before the audit passes.
- `zdiff3` shows the merge base in a `|||||||` section, which is what makes "did the fork add
  this, or did upstream remove it?" answerable. Set via `-c` so the user's global config is
  never mutated.
- `rerere` makes a re-run cheap.

Compare the real conflict set to the forecast. Investigate any file that conflicted but was
**not** forecast — it means a branch assumption is wrong.

## Step 3 — Resolve, category by category

Work `references/customizations.md` top to bottom: mechanical categories first, judgement
calls last, so the list shrinks before the hard thinking starts.

For every conflicted file, before touching it:

```bash
git log --oneline "$BASE..v$NEW_VER" -- <file>   # WHY upstream changed it
git diff "$BASE..$OLD" -- <file>                 # WHY the fork changed it
```

**Never `git add` a file whose upstream log you have not read.**

Any conflicted file with no matching category is a gap in the inventory — say so and classify
it with the user rather than improvising.

## Step 4 — Cruft and migrations

```bash
git rm -f --ignore-unmatch repro_threading.rb        # accidental debug script at repo root
ls db/migrate | grep -E '20250416182131|20250421082927'
ls db/migrate | wc -l                                # expect 158 for 4.16.2
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
.claude/skills/octopus-upstream-merge/scripts/audit.sh "$NEW_VER" "$BASE" "$OLD"
```

Three directions. **Any FAIL blocks the commit.**

- **A — nothing of ours lost.** Every invariant in `references/customizations.md`.
- **B — nothing of theirs reverted.** Files identical to `$OLD` that upstream changed in
  `$BASE..v$NEW_VER` are suspected bad `--ours`; plus the fork-untouched set must be
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
git commit -m "fix(octopus): merge with v$NEW_VER from chatwoot"
```

Matches the existing convention on `v4.13.0-dev`. **No AI attribution, ever.**

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
   The in-container `db:migrate` is the only real proof the 52 new upstream migrations apply
   on top of the fork's swapped pair.
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
  --base "$NEW" --head "$TARGET" \
  --title "Merge Chatwoot $NEW_VER into Octopus customizations" \
  --body-file <body>
```

Body sections: ① summary + `git diff --stat "v$NEW_VER..$TARGET"` ② upstream commits absorbed
③ **the Step 5 audit table verbatim** ④ conflict ledger — each conflicted file, strategy
applied, one-line why ⑤ landmines and decisions (schema.rb taken wholesale; the migration
swap kept, with the "no `schema_migrations` change needed" reasoning; the #14516
consolidation) ⑥ verification results + screenshots ⑦ deployer actions required
⑧ follow-ups (e.g. `'Opciones'` → i18n). No AI attribution anywhere.

## Step 8 — Refresh the inventory

After the PR is filed, reconcile `references/customizations.md` against the merge just
completed: bucket `git diff --name-only "v$NEW_VER..$TARGET"` into the categories and report
**UNCATEGORIZED** (new customization landed since last merge), **VANISHED** (upstreamed or
dropped — propose deleting the row) and **MOVED** (invariant grep fails but the string exists
at a new path). Update the reference **only with the user's approval**, then append a row to
its merge-history table.

This skill lives in the repo, so the update rides along on the same branch and PR as the
merge it describes — which is the point: the inventory can never be one release out of date.

---

## Hard rules

1. Never `git merge` without `--no-commit`.
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
8. Never proceed when the target `-dev` branch is not byte-identical to its upstream tag.
9. Every `gh` call carries `--repo alphnology/chatwoot`.
10. Never mutate the user's global git config — use `git -c` for `rerere`/`conflictStyle`.
11. Never run `bundle install`/`pnpm install` on the host as the build check; the build check
    is docker.
12. Never download a browser. Browser verification is `claude-in-chrome` on the user's Chrome.
13. No AI attribution in commit messages or the PR body.
14. A conflict in `package.json`, lockfiles, `Gemfile*`, `docker/Dockerfile`, `.github/**` or
    `config/routes.rb` is a red flag, not a routine resolution — investigate before accepting.
15. This repo's `CLAUDE.md` overrides this skill on any conflict (Tailwind-only, Composition
    API, `en.yml`/`en.json` only, `enterprise/` overlay checks).
