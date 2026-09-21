#!/usr/bin/env bash
# Customization audit for the Octopus fork. Two modes, picked automatically:
#
#   sync mode    — a merge is in progress (MERGE_HEAD exists): run it with the upstream merge
#                  staged but NOT committed. Directions A, B and C.
#   feature mode — no merge in progress: the pre-PR check for feat/* and fix/* branches.
#                  Direction A invariants only, against the working tree.
#
#   audit.sh [NEW_TAG]          # NEW_TAG defaults to the tag MERGE_HEAD points at
#   audit.sh v4.18.0
#
# Any FAIL blocks the commit. Invariants mirror references/customizations.md.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1   # runnable from anywhere in the repo

TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
if git rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
  MODE=sync
  NEW_TAG=${1:-$(git tag --points-at MERGE_HEAD | grep -E "$TAG_RE" | head -1)}
  [ -n "$NEW_TAG" ] || { echo "MERGE_HEAD is not an upstream release tag — pass NEW_TAG"; exit 1; }
  OLD=HEAD   # mid-merge, HEAD is still the pre-merge tip of sync/* (= octopus)
else
  MODE=feature
  NEW_TAG=
  OLD=HEAD
fi
# The upstream release the pre-merge tip is built on (tags only — see the merge-commit trap).
BASE=$(git tag --merged "$OLD" --sort=-v:refname --list 'v[0-9]*' | grep -E "$TAG_RE" | head -1)
echo "mode: $MODE   base: ${BASE:-?}   target: ${NEW_TAG:-n/a}"

pass=0; fail=0
chk() { # chk <CAT> <description> <command...>
  local cat=$1 desc=$2; shift 2
  if "$@" >/dev/null 2>&1; then
    printf '%-4s %-52s PASS\n' "$cat" "$desc"; pass=$((pass+1))
  else
    printf '%-4s %-52s FAIL\n' "$cat" "$desc"; fail=$((fail+1))
  fi
}
hr() { printf '%s\n' "──────────────────────────────────────────────────────────────"; }

hr; echo "DIRECTION A — nothing of ours was lost"; hr

if [ "$MODE" = sync ]; then
  chk 1 "schema.rb byte-identical to $NEW_TAG" \
      git diff --quiet "$NEW_TAG" -- db/schema.rb
fi
chk 2 "migration swap: exactly 2 files at those timestamps" \
    bash -c "[ \$(ls db/migrate | grep -cE '20250416182131|20250421082927') -eq 2 ]"
chk 2 "migration swap: no duplicate class names" \
    bash -c "[ \$(grep -h '^class ' db/migrate/20250416182131_* db/migrate/20250421082927_* | sort -u | wc -l) -eq 2 ]"
chk 3 "Taggable::Caching fix preserved (upstream ships Cache)" \
    grep -q 'Taggable::Caching' db/migrate/20231211010807_add_cached_labels_list.rb

chk A "manifest.json branded Octopus" \
    grep -qi octopus public/manifest.json
# Category B is NOT "zero Chatwoot strings". Upstream deliberately authors copy containing
# "Chatwoot" and re-brands it at render time via replaceInstallationName (useBranding), which
# reads INSTALLATION_NAME (= 'Octopus'). Hardcoding the brand into those strings is redundant
# and fights upstream. What must hold is that every remaining occurrence is either rendered
# through the helper or is a non-user-facing token. Assert the render sites, not the strings.
chk B "widget SDK global is octopusSettings" \
    grep -q 'window.octopusSettings' app/javascript/dashboard/i18n/locale/en/inboxMgmt.json
chk B "paywall copy rendered via replaceInstallationName" \
    grep -q 'replaceInstallationName' app/javascript/dashboard/routes/dashboard/settings/components/BasePaywallModal.vue
chk B "INSTALLATION_NAME still set to Octopus" \
    grep -q "value: 'Octopus'" config/installation_config.yml
# Category C (inline image paste) was UPSTREAMED in PR #14516 — upstream v4.16.2 ships
# pasteInlineImageFromClipboard + the $mod+Shift+KeyV keymap and a hardened cw_image_width
# renderer. The fork's copy is deleted, so its old invariants are retired. What remains is
# that upstream's sizing support is present and the fork's try/catch guard survives.
chk C "upstream image sizing present (MessageFormatter)" \
    grep -q cw_image_width app/javascript/shared/helpers/MessageFormatter.js
chk C "upstream image sizing present (renderer)" \
    grep -q cw_image_width lib/base_markdown_renderer.rb
chk C "fork's relative-URL guard kept in MessageFormatter" \
    grep -q 'catch' app/javascript/shared/helpers/MessageFormatter.js
chk C "upstream inline paste keymap wired" \
    grep -q 'pasteInlineImageFromClipboard' app/javascript/dashboard/components/widgets/WootWriter/Editor.vue
chk D "deleteActions: 6 consumers still guarded" \
    bash -c "[ \$(grep -rl deleteActions app/javascript | wc -l) -eq 6 ]"
chk D "deleteActions: 3 flags still false" \
    bash -c "[ \$(grep -c false app/javascript/dashboard/constants/deleteActions.js) -ge 3 ]"
chk F "message.rb store_accessor: in_reply_to_interactive_id" \
    grep -q in_reply_to_interactive_id app/models/message.rb
chk F "message.rb store_accessor: flow_data" \
    grep -q flow_data app/models/message.rb
chk G "microsoft/send_mail_service.rb present" \
    test -f app/services/microsoft/send_mail_service.rb
chk G "microsoft/graph_token_service.rb present" \
    test -f app/services/microsoft/graph_token_service.rb
chk G "Mail.Send scope preserved" \
    grep -q 'Mail.Send' app/controllers/concerns/microsoft_concern.rb
chk H "conversation.rb unattended: 10.minutes.ago" \
    grep -q '10.minutes.ago' app/models/conversation.rb
chk H "installation_config.rb primary_key" \
    grep -q "self.primary_key = 'id'" app/models/installation_config.rb
chk H "countries.js DR prefixes 1809/1829" \
    grep -qE '1809|1829' app/javascript/shared/constants/countries.js
chk H "time_format_presenter returns ' ' not 'N/A'" \
    grep -q "return ' '" app/presenters/reports/time_format_presenter.rb
chk H "imap_mailbox MESSAGE_PATTERN" \
    grep -q MESSAGE_PATTERN app/mailboxes/imap/imap_mailbox.rb
chk I "superadmin.css present" \
    test -f app/javascript/entrypoints/superadmin.css
chk K "Makefile docker-amd64 target" \
    grep -q 'docker-amd64' Makefile
chk K "docker-compose.yaml has no version: key" \
    bash -c "! grep -qE '^version:' docker-compose.yaml"
chk L "repro_threading.rb removed" \
    test ! -f repro_threading.rb
chk M "this skill survived the merge" \
    test -f .claude/skills/octopus/SKILL.md
chk M "audit.sh still executable" \
    test -x .claude/skills/octopus/scripts/audit.sh

if [ "$MODE" = sync ]; then
hr; echo "DIRECTION B — nothing of theirs was reverted"; hr

# NB: compare the TAG to the WORKING TREE (no ..HEAD). The audit runs mid-merge, before the
# commit, so HEAD is still the pre-merge tip — "$NEW_TAG..HEAD" would compare upstream against
# the old fork tip and report all of upstream's own changes as failures.
chk B2 "fork-untouched files identical to upstream" \
    git diff --quiet "$NEW_TAG" -- package.json pnpm-lock.yaml Gemfile Gemfile.lock \
        docker/Dockerfile .github config/routes.rb config/features.yml
chk B2 "no conflict markers anywhere" \
    bash -c "! git grep -qnE '^(<{7}|={7}|>{7})'"

if [ -n "$BASE" ]; then
  echo
  echo "Suspected bad --ours (identical to $OLD, but upstream changed them in $BASE..$NEW_TAG):"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  git diff --name-only "$BASE..$NEW_TAG" | sort > "$tmp/upstream_touched"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if git diff --quiet "$OLD" -- "$f" 2>/dev/null; then echo "  $f"; fi
  done < "$tmp/upstream_touched"
  echo "  (each is a file upstream changed that came through unchanged from the fork — review)"
fi
else
  chk B2 "no conflict markers anywhere" \
      bash -c "! git grep -qnE '^(<{7}|={7}|>{7})'"
fi

hr; echo "DIRECTION C — silent losses (auto-merged, never conflicted)"; hr
echo "[ALPHNOLOGY] marker census (grow this every merge):"
git grep -l '\[ALPHNOLOGY\]' | sed 's/^/  /'

hr
printf 'RESULT: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && echo "AUDIT CLEAN ($MODE mode) — safe to commit" || echo "AUDIT FAILED — DO NOT COMMIT"
exit $(( fail > 0 ? 1 : 0 ))
