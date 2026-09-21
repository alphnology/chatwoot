# Octopus fork — customization inventory

Generated from `v4.10.1` (tag) → `v4.10.1-dev-merge`: **26 commits, 75 files, +2879/−308**.

Since the 4.16.2 merge, all customizations live on the long-lived `octopus` branch.
Regenerate the file list at runtime — never trust a stored one:

```bash
BASE=$(git tag --merged octopus --sort=-v:refname --list 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
git diff --stat "$BASE..octopus" | tail -1
git diff --name-only "$BASE..octopus" | sort
```

What is stored here is only what git cannot tell you: **why** a file differs, **which
strategy** resolves it, and **what must remain true** afterwards. The `ASSERT` blocks are
executed by `scripts/audit.sh`.

---

## Never-conflicts — the fork does not customize these

`package.json` · `pnpm-lock.yaml` · `Gemfile` · `Gemfile.lock` · `docker/Dockerfile` ·
`.github/**` · `config/routes.rb` · `config/features.yml`

A conflict or post-merge difference in any of them means an unexpected fork edit exists.
Investigate; do not resolve routinely.

---

## Known landmines

**L1 — `db/schema.rb` is dump drift, not intent.** The fork shows ±90 lines (re-adding
`precision: nil`) while its schema **version is unchanged from `v4.10.1`**
(`2026_01_14_201315`) — proof of zero intent. Upstream moves to `2026_07_18_000000` and adds
52 migrations (106 → 158). Take `--theirs` wholesale; never hand-merge.

**L2 — the migration timestamp swap is silent.** The fork swapped the timestamps on a pair:

| ref | filenames |
|---|---|
| upstream `v4.10.1` and `v4.16.2` | `20250416182131_flip_chatwoot_v4_default_feature_flag_installation_config.rb`, `20250421082927_add_settings_column_to_account.rb` |
| fork | `20250416182131_add_settings_column_to_account.rb`, `20250421082927_flip_chatwoot_v4_default_feature_flag_installation_config.rb` |

**Verified by trial merge:** git applies the fork's rename unopposed → **2** files under the
fork's names, **no duplicate class names**, no conflict. Because it is silent it must be
asserted. Default: keep the fork's swap (deployed instances already recorded those
timestamps; both namings use the same two timestamp values, so `schema_migrations` needs no
edit). Say so explicitly in the PR — it is not the intuitive conclusion.

**L3 — upstream PR #14516 collides with inline images.** Landed in v4.15.0: renames
`cw_image_height` → `cw_image_width` and swaps `@chatwoot/prosemirror-schema`. The fork's own
`[ALPHNOLOGY]` notes at `MessageFormatter.js:5,26,46` and `base_markdown_renderer.rb:1,27,44`
are the map. Consolidate — if upstream now implements this natively, prefer upstream, delete
the fork's copy, and record that in the PR.

---

## Cruft — resolve during the merge

- `repro_threading.rb` — accidental debug script at repo root. **Delete.**
- `docker-compose.yaml` hardcodes `POSTGRES_PASSWORD=p0stgr3s`. **Flag, do not change.**
- `app/services/whatsapp/providers/base_service.rb` hardcodes Spanish `'Opciones'` over
  `I18n.t('conversations.messages.whatsapp.list_button_label')`. **Flag as a follow-up.**

---

## Categories

Work top to bottom: mechanical first, judgement last.

**Every new customization registers itself here as part of its own PR** (Flow F): a row in
an existing category or a new category, plus an invariant `chk` line in `scripts/audit.sh`.
A change that is not listed here is not protected in the next upstream sync.

### 1. `db/schema.rb`
**Strategy:** `--theirs` wholesale, then regenerate if migrations were touched. See L1.
```sh
git diff --quiet "$NEW_TAG" -- db/schema.rb   # must be byte-identical to upstream
```

### 2. Migration timestamp swap
**Strategy:** assert, don't wait for a conflict. See L2.
```sh
test "$(ls db/migrate | grep -cE '20250416182131|20250421082927')" -eq 2
test "$(grep -h '^class ' db/migrate/20250416182131_* db/migrate/20250421082927_* | sort -u | wc -l)" -eq 2
```

### 3. `Caching` migration fix — silent, high risk
`db/migrate/20231211010807_add_cached_labels_list.rb`: fork changed
`ActsAsTaggableOn::Taggable::Cache` → `Caching`. **Upstream still ships the broken `Cache` at
4.16.2.** Only one side changed it, so it auto-merges — and a directory-wide `--theirs` on
`db/` reverts it silently.
**Strategy:** keep ours; verify, never assume.
```sh
grep -q 'Taggable::Caching' db/migrate/20231211010807_add_cached_labels_list.rb
```

### A. Branding assets (7)
`public/brand-assets/logo.svg` · `logo_dark.svg` · `logo_thumbnail.svg` · `public/manifest.json` ·
`app/javascript/dashboard/assets/images/bubble-logo.svg` ·
`app/javascript/design-system/images/logo-thumbnail.svg` ·
`app/javascript/widget/assets/images/logo.svg`
**Strategy:** `--ours`. Pure identity; upstream logo changes are irrelevant.
```sh
grep -qi octopus public/manifest.json
```

### B. Branding strings — the regression magnet
15 files under `app/javascript/dashboard/i18n/locale/en/` plus `widget/i18n/locale/en.json`
and `survey/i18n/locale/en.json`. Substitutions: `Chatwoot`→`Octopus`,
`window.chatwootSettings`→`window.octopusSettings`, `*.chatwoot.dev`→`*.octopus.app`.

**Strategy:** hunk-by-hunk, ours-biased. **Never whole-file `--ours`** — upstream adds new
keys to these files every release and whole-file ours drops them.

**Measured on 4.10.1→4.16.2:** fork had **1** en file containing `Chatwoot` before the merge,
**5** after — upstream introduced new user-facing strings (`signup.json` GET_STARTED,
`conversation.json` NATIVE_APP_ADVISORY, `integrations.json` AVAILABLE_ON, `inboxMgmt.json`
VERIFY_NOTICE + DESCRIPTION). **Re-sweep after merging** and re-brand the new arrivals.
```sh
# only generalSettings.json may legitimately match, via the {latestChatwootVersion} variable
test "$(grep -rl 'Chatwoot' app/javascript/dashboard/i18n/locale/en/ | wc -l)" -le 1
```
Also assert upstream key parity — every key present in upstream's copy exists in ours.

### C. Inline image paste — consolidate only
`app/javascript/dashboard/components/widgets/WootWriter/Editor.vue` (+109) ·
`app/javascript/shared/helpers/MessageFormatter.js` · `lib/base_markdown_renderer.rb` ·
`INLINE_IMAGE.*` keys in `en/conversation.json`
**Strategy:** the one category where neither side may be taken. See L3.
```sh
grep -q cw_image_width  app/javascript/shared/helpers/MessageFormatter.js
grep -q cw_image_width  lib/base_markdown_renderer.rb
grep -q INLINE_IMAGE    app/javascript/dashboard/i18n/locale/en/conversation.json
grep -q '\[ALPHNOLOGY\]' app/javascript/dashboard/components/widgets/WootWriter/Editor.vue
```

### D. Delete-action gating
`app/javascript/dashboard/constants/deleteActions.js` (new, 3 hardcoded `false` flags) plus
6 consumers: `conversation/contextMenu/Index.vue` · `MessageContextMenu.vue` ·
`ContactsCard/ContactDeleteSection.vue` · `Contacts/Pages/ContactDetails.vue` ·
`ContactsBulkActionBar.vue` · `conversation/contact/ContactInfo.vue`

**Strategy:** `--ours` per hunk; if upstream restructured a component, take upstream's
version and re-apply the guard onto the new delete affordance. Note
`ContactDeleteSection.vue` and `ContactDetails.vue` **auto-merge** — the count invariant is
what catches a silent loss there.
```sh
test "$(grep -rl deleteActions app/javascript | wc -l)" -eq 6   # 6 consumers; the def file doesn't self-reference
test "$(grep -c 'false' app/javascript/dashboard/constants/deleteActions.js)" -ge 3
```

### E. Sidebar nav
`app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — the fork *comments out* the
SLA Reports and Agent Bots entries. Upstream touched this file 23× in v4.10.1..v4.16.2.
**Strategy:** `--theirs`, then re-apply the comment-out. The fork's contribution is two
commented entries — worthless to hand-merge, trivial to re-apply, and `--ours` would discard
every new upstream nav entry.
Verify: diff vs upstream shows *only* the two commented entries; confirm by screenshot.

### F. WhatsApp Flows
`whatsapp/providers/base_service.rb` (`create_flow_payload`) · `incoming_message_base_service.rb` ·
`incoming_message_service_helpers.rb` · `app/models/message.rb` (`store_accessor`) ·
`concerns/content_attribute_validator.rb` · `builders/messages/message_builder.rb` ·
`services/messages/in_reply_to_message_builder.rb`
**Strategy:** consolidate, ours-biased. `store_accessor` conflicts are single-line — the union
of both key lists is almost always right.
```sh
grep -q 'in_reply_to_interactive_id' app/models/message.rb
grep -q 'flow_data'                  app/models/message.rb
grep -q "'Opciones'" app/services/whatsapp/providers/base_service.rb   # present, but flag as follow-up
```

### G. Microsoft Graph mail
New: `app/services/microsoft/send_mail_service.rb` · `graph_token_service.rb`.
Modified: `email/send_on_email_service.rb` (SMTP-vs-Graph branch) ·
`microsoft/refresh_oauth_token_service.rb` · `concerns/microsoft_concern.rb`
(`Mail.Send`/`Mail.ReadWrite` scopes) · `microsoft/callbacks_controller.rb` ·
`oauth_callback_controller.rb` · `lib/microsoft_graph_auth.rb`
**Strategy:** ours for the new files; consolidate `send_on_email_service.rb` — the Graph
branch is a fork insertion inside a method upstream keeps editing.
```sh
test -f app/services/microsoft/send_mail_service.rb
test -f app/services/microsoft/graph_token_service.rb
grep -q 'Mail.Send' app/controllers/concerns/microsoft_concern.rb
```

### H. Silent behavioral tweaks — top silent-loss risk
One-liners with no marker, mostly auto-merging:
```sh
grep -q '10.minutes.ago' app/models/conversation.rb                     # unattended scope
grep -q "self.primary_key = 'id'" app/models/installation_config.rb
grep -qE '1809|1829' app/javascript/shared/constants/countries.js       # DR phone prefixes
grep -q "return ' '" app/presenters/reports/time_format_presenter.rb    # CSV encoding fix, not 'N/A'
grep -q 'MESSAGE_PATTERN' app/mailboxes/imap/imap_mailbox.rb            # conversation-UUID threading
```
**Strategy:** ours, verified individually. Add `[ALPHNOLOGY]` markers to each during Step 5.

### I. SuperAdmin restyle
`app/javascript/entrypoints/superadmin.js` is **modified, not new** (it exists upstream at
both 4.10.1 and 4.16.2) — consolidate it. `superadmin.css` is new. Plus 6 ERB views:
`layouts/vueapp.html.erb` · `layouts/super_admin/application.html.erb` ·
`super_admin/application/_navigation.html.erb` · `super_admin/devise/sessions/new.html.erb` ·
`super_admin/settings/show.html.erb` · `installation/onboarding/index.html.erb`
**Strategy:** consolidate `superadmin.js`; `--ours` for the css and ERB unless upstream
restructured them. Verify by screenshot.

### J. Config
`config/installation_config.yml` · `config/locales/en.yml` — branding values.
**Strategy:** hunk-by-hunk, ours-biased. Same shape as B: upstream adds new keys here every
release, so whole-file `--ours` loses them.

### K. Deployment
`Makefile` (`docker-amd64` target) · `Procfile.dev` (dropped `dotenv`) ·
`docker-compose.yaml` / `.production.yaml` / `.test.yaml` (removed the `version:` key) ·
`deployment/setup_debian-12.sh` (new, +1335) · `MIGRATION_STEPS.md`
**Strategy:** `--ours` — the fork owns its deployment.
```sh
grep -q 'docker-amd64' Makefile
! grep -qE '^version:' docker-compose.yaml
```

### L. Cruft
```sh
test ! -f repro_threading.rb
```

### M. This skill
`.claude/skills/octopus/**` — the branch workflow (named `octopus-upstream-merge` before), this inventory, and the two
scripts. Tracked in the repo (`.gitignore` excludes only `.claude/settings.local.json`), so
it is itself part of the fork's customization surface.

**Strategy:** ours-only by construction — upstream has no `.claude/skills/`, so it never
conflicts. Expect it in the ours-only forecast list; it is **not** an UNCATEGORIZED finding.
Step 8's inventory refresh rides along on the same branch and PR as the merge it describes.
```sh
test -f .claude/skills/octopus/SKILL.md
test -x .claude/skills/octopus/scripts/audit.sh
```

---

## Merge history

| date | range | branch | conflicts | fork files auto-merged | PR |
|---|---|---|---|---|---|
| 2026-08-08 | 4.10.1 → 4.16.2 | `v4.16.2-dev-merge` (became the root of `octopus`) | 18 (forecast 38) | 57 | — |
