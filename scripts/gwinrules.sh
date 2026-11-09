#!/usr/bin/env sh
# Supports: Claude Code (macOS / Linux / WSL / Git Bash)
#
# Installs the Gwin shared rules into a project repo so every session (local or cloud) can read them.
# Run it inside a project (or pass --project). It:
#   1. Copies Gwin_Shared/instructions/*.md (except README.md) into <project>/.claude/gwin-shared/,
#      each stamped with its source file, the Gwin_Shared commit and a content hash.
#   2. Adds one marked block to <project>/CLAUDE.md importing .claude/gwin-shared/RULES.md
#      (creating CLAUDE.md if there is none). Nothing else in CLAUDE.md is touched.
# If the folder is not a git repo, or the repo has no GitHub remote, it warns that the rules will work
# only on this computer: Claude cloud sessions read the project from GitHub.
# It only previews by default; pass --apply to write. It never commits or pushes.
# Hand-edited copies and files it didn't create are left alone unless --force is given.
# --check writes nothing. It reports whether every rule can fire (rules loaded and committed, staging
# branch, HANDOFF.md, secrets setup, release notes, gh, model pins) as PASS, FIX, BLOCKED or ASK, and
# exits 1 if anything is not PASS. --staging NAME sets the staging branch name (default: staging).
#
# Usage: gwinrules.sh [--project DIR] [--apply] [--force] [--uninstall] [--check] [--staging NAME]
set -eu

DEST_REL=.claude/gwin-shared
START_MARK='<!-- gwin-shared:start -->'
END_MARK='<!-- gwin-shared:end -->'
STAMP_RE='^<!-- gwin-shared: file=[^ ]+ source=[^ ]+ sha256=[0-9a-f]{12} '

PROJECT=. APPLY=0 FORCE=0 UNINSTALL=0 CHECK=0 STAGING=staging
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT=$2; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --check) CHECK=1; shift ;;
    --staging) STAGING=$2; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

warn() { echo "WARNING: $*" >&2; }
hash12() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-12; }
stamp_of() { head -n 1 "$1" | tr -d '\r'; }
body_hash() { tail -n +2 "$1" | tr -d '\r' | hash12; }
stamp_hash() { stamp_of "$1" | sed -n 's/.* sha256=\([0-9a-f]\{12\}\) .*/\1/p'; }
is_stamped() { stamp_of "$1" | grep -Eq "$STAMP_RE"; }

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
SRC="$REPO/instructions"
[ -d "$PROJECT" ] || { echo "Folder not found: $PROJECT" >&2; exit 1; }
IS_GIT=1
ROOT=$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null) || { IS_GIT=0; ROOT=$PROJECT; }
ROOT=$(cd "$ROOT" && pwd -P)
[ "$ROOT" != "$REPO" ] || { echo "That is the Gwin_Shared repo itself; run this inside a project." >&2; exit 1; }
if [ "$IS_GIT" = 0 ] && { [ "$ROOT" = "$(cd ~ && pwd -P)" ] || [ "$ROOT" = / ] || [ "$(dirname "$ROOT")" = "$ROOT" ]; }; then
  echo "Refusing to install into $ROOT (your home folder or a drive root). Run this inside a project folder." >&2; exit 1
fi

HAS_GITHUB=0
[ "$IS_GIT" = 1 ] && git -C "$ROOT" remote -v 2>/dev/null | grep -Eq 'github\.com[:/]' && HAS_GITHUB=1
LOCAL_ONLY=""
if [ "$IS_GIT" = 0 ]; then
  LOCAL_ONLY='This folder is not a git repository.
  The rules will work only in this folder, on this computer.
  Claude cloud sessions and other computers will not see them.
  To share them: make the folder a git repo, add a GitHub remote, then commit and push.'
elif [ "$HAS_GITHUB" = 0 ]; then
  LOCAL_ONLY='This repo has no GitHub remote.
  The rules will work only in copies of this repo on computers you set up yourself.
  Claude cloud sessions need the project on GitHub, so they will not see the rules.
  To share them: add a GitHub remote (git remote add origin <url>), then commit and push.'
fi
local_only_warning() { [ -z "$LOCAL_ONLY" ] || printf 'WARNING: LOCAL ONLY\n  %s\n' "$LOCAL_ONLY" >&2; }
local_only_warning

# --- --check: can every rule fire? (read-only) -------------------------------------------------
if [ "$CHECK" = 1 ]; then
  BAD=0
  res() { # status name [detail]
    printf '  %-8s %s\n' "$1" "$2"
    [ -z "${3:-}" ] || printf '           %s\n' "$3"
    case "$1" in PASS|INFO) ;; *) BAD=$((BAD + 1)) ;; esac
  }
  CD="$ROOT/$DEST_REL"
  PROD=main
  if [ "$IS_GIT" = 1 ]; then
    d=$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || d=""
    [ -z "$d" ] || PROD=$d
  fi
  echo "Rule checks for $ROOT (staging branch: $STAGING, production branch: $PROD)"
  echo

  # Loaded (all rules)
  missing="" stale="" ignored="" untracked=""
  for src in "$SRC"/*.md; do
    name=$(basename "$src"); [ "$name" = README.md ] && continue
    f="$CD/$name"
    if [ ! -f "$f" ]; then missing="$missing $name"; continue; fi
    h=$(tr -d '\r' < "$src" | hash12)
    if [ "$(stamp_hash "$f")" != "$h" ] || [ "$(body_hash "$f")" != "$h" ]; then stale="$stale $name"; fi
    if [ "$IS_GIT" = 1 ]; then
      if git -C "$ROOT" check-ignore -q "$DEST_REL/$name"; then ignored="$ignored $name"; fi
      if ! git -C "$ROOT" ls-files --error-unmatch "$DEST_REL/$name" >/dev/null 2>&1; then untracked="$untracked $name"; fi
    fi
  done
  if [ -n "$missing" ]; then res FIX "rules: all rule files are in $DEST_REL" "missing:$missing. Run gwinrules --apply."
  elif [ -n "$stale" ]; then res FIX "rules: copies match Gwin_Shared" "stale or edited:$stale. Run gwinrules --apply."
  else res PASS "rules: all rule files are in $DEST_REL and match Gwin_Shared"; fi
  if [ -n "$ignored" ]; then res FIX "rules: not ignored by git" "ignored:$ignored. Remove or negate the .gitignore line."
  elif [ "$IS_GIT" = 1 ] && [ -z "$missing" ]; then res PASS "rules: not ignored by git"; fi
  if [ "$IS_GIT" = 0 ]; then res BLOCKED "rules: committed so cloud sessions can read them" "Not a git repo."
  elif [ -n "$untracked" ] && [ -z "$missing" ]; then res FIX "rules: committed" "not tracked by git:$untracked. Commit and push them."
  elif [ -z "$missing" ]; then res PASS "rules: committed"; fi
  if [ "$HAS_GITHUB" = 0 ]; then res BLOCKED "rules: project has a GitHub remote" "Cloud sessions read the project from GitHub."
  else res PASS "rules: project has a GitHub remote"; fi
  CM="$ROOT/CLAUDE.md"
  if [ -f "$CM" ] && grep -Fq "$START_MARK" "$CM" && grep -Fq "@$DEST_REL/RULES.md" "$CM"; then res PASS "rules: CLAUDE.md imports RULES.md"
  else res FIX "rules: CLAUDE.md imports RULES.md" "Run gwinrules --apply."; fi
  res INFO "rules: loaded in a session" "Start a new session and run /memory. All 12 rule files must show."

  # Staging and protection (rules 02, 07)
  if [ "$IS_GIT" = 1 ]; then
    if git -C "$ROOT" show-ref --verify -q "refs/remotes/origin/$STAGING"; then res PASS "branches: $STAGING exists on origin (rules 02, 07)"
    elif git -C "$ROOT" show-ref --verify -q "refs/heads/$STAGING"; then res BLOCKED "branches: $STAGING exists on origin (rules 02, 07)" "It exists only on this computer. Push it."
    else res BLOCKED "branches: $STAGING exists on origin (rules 02, 07)" "Create it from $PROD, push it, protect it. If you just created it, run git fetch."; fi
  fi
  prot_msg="Cannot confirm. Check in GitHub settings: $STAGING and $PROD protected against deletion and force-push; Automatically delete head branches on."
  if [ "$HAS_GITHUB" = 1 ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    for b in "$STAGING" "$PROD"; do
      if (cd "$ROOT" && gh api "repos/{owner}/{repo}/branches/$b/protection" >/dev/null 2>&1); then res PASS "branches: $b is protected (rules 02, 07)"
      else res BLOCKED "branches: $b is protected (rules 02, 07)" "No branch protection rule found. Rulesets are not visible here; confirm in GitHub settings."; fi
    done
    dob=$(cd "$ROOT" && gh repo view --json deleteBranchOnMerge -q .deleteBranchOnMerge 2>/dev/null || echo unknown)
    if [ "$dob" = true ]; then res PASS "branches: Automatically delete head branches is on (rule 07)"
    else res BLOCKED "branches: Automatically delete head branches is on (rule 07)" "Turn it on in GitHub settings (value: $dob). Protect $STAGING and $PROD first."; fi
  else
    res BLOCKED "branches: protection and auto-delete (rules 02, 07)" "$prot_msg"
  fi

  # Handoff (rules 03, 08)
  H="$ROOT/HANDOFF.md"
  if [ ! -f "$H" ]; then res FIX "handoff: HANDOFF.md exists (rules 03, 08)" "Install the pipeline kit, or create a minimal HANDOFF.md."
  else
    if grep -Eiq 'last updated[*_: ]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$H"; then res PASS "handoff: has a Last updated date"
    else res FIX "handoff: has a Last updated date" "Add: **Last updated:** YYYY-MM-DD"; fi
    if grep -Eiq 'divergence:' "$H"; then res PASS "handoff: has a Divergence line"
    else res FIX "handoff: has a Divergence line" "Add: **Divergence:** <branch state>"; fi
  fi

  # Secrets (rule 04). Never reads .env files.
  if [ -f "$ROOT/.gitignore" ] && grep -Eq '^/?\.env(\*|\.local)?[[:space:]]*$|^/?\.env\.\*[[:space:]]*$' "$ROOT/.gitignore"; then res PASS "secrets: .env is in .gitignore (rule 04)"
  else res FIX "secrets: .env is in .gitignore (rule 04)" "Add .env and .env.local to .gitignore."; fi
  if [ -f "$ROOT/.env.example" ]; then res PASS "secrets: .env.example exists"
  else res FIX "secrets: .env.example exists" "Create it with placeholder values only."; fi
  SJ="$ROOT/.claude/settings.json"
  if [ -f "$SJ" ] && command -v python3 >/dev/null 2>&1 && python3 -c "import json,sys; d=json.load(open(sys.argv[1])).get('permissions',{}).get('deny',[]); sys.exit(0 if any(r.startswith('Read(') and '.env' in r for r in d) else 1)" "$SJ" 2>/dev/null; then res PASS "secrets: settings.json denies reading .env"
  else res FIX "secrets: settings.json denies reading .env" "Add Read(./.env) and Read(./.env.*) to permissions.deny in .claude/settings.json."; fi

  # Release notes and PR checklist files (rule 05)
  if ls "$ROOT"/CHANGELOG* >/dev/null 2>&1; then res PASS "release notes: CHANGELOG exists (rule 05)"
  else res FIX "release notes: CHANGELOG exists (rule 05)" "Create CHANGELOG.md, or name another file in CLAUDE.md."; fi
  ver=""
  for v in package.json pyproject.toml Cargo.toml VERSION version.txt setup.py .claude-plugin/plugin.json; do [ -f "$ROOT/$v" ] && ver="$ver $v"; done
  if [ -n "$ver" ]; then res PASS "release notes: version source found" "found:$ver"
  else res ASK "release notes: version source found" "Tell me where the version lives."; fi
  if [ -f "$ROOT/claude/design-doc-index.md" ]; then res PASS "pr checklist: design-doc index exists"
  else res FIX "pr checklist: design-doc index exists" "Create claude/design-doc-index.md (the pipeline kit does this)."; fi
  if [ -n "$(find "$ROOT" -maxdepth 3 \( -path "$ROOT/.git" -o -path "$ROOT/node_modules" \) -prune -o -iname '*architecture*' -print 2>/dev/null | head -n 1)" ]; then res PASS "pr checklist: architecture diagram found"
  else res ASK "pr checklist: architecture diagram found" "Name the diagram file, or say there is none."; fi
  if [ -n "$(find "$ROOT" -maxdepth 3 \( -path "$ROOT/.git" -o -path "$ROOT/node_modules" \) -prune -o -iname '*regression*' -print 2>/dev/null | head -n 1)" ]; then res PASS "pr checklist: regression list found"
  else res ASK "pr checklist: regression list found" "Name the regression list, or say there is none."; fi

  # Tools (rules 01, 11) and model tiers (rule 06)
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then res PASS "tools: gh installed and signed in"
    else res FIX "tools: gh installed and signed in" "Run gh auth login yourself. Never paste a token into chat."; fi
  else res FIX "tools: gh installed and signed in" "Install gh. Without it, read CI on the PR's Checks tab."; fi
  command -v python3 >/dev/null 2>&1 && res PASS "tools: python3 available" || res FIX "tools: python3 available" "The pipeline kit's tools need Python 3."
  if ls "$ROOT"/.claude/agents/*.md >/dev/null 2>&1 && grep -lq '^model: ' "$ROOT"/.claude/agents/*.md 2>/dev/null; then res PASS "model tiers: agent files pin a model (rule 06)"
  else res ASK "model tiers: agent files pin a model (rule 06)" "Install the kit, or say which model fills each tier."; fi
  res INFO "test command" "Rules 01 and 05 need one. Set TEST_COMMAND in the kit interview, or say there is none."
  res INFO "rule 10" "Applies only if test suites share live data or accounts."
  echo
  echo "Checks do not enforce rules. Only settings.json permissions and hooks enforce."
  if [ "$BAD" = 0 ]; then echo "All rule checks passed."; exit 0; fi
  echo "$BAD check(s) not PASS. Fix them, then re-run with --check."; exit 1
fi

COMMIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)
SOURCE="gwincode/Gwin_Shared@$COMMIT"
if [ -n "$(git -C "$REPO" status --porcelain -- instructions 2>/dev/null)" ]; then
  SOURCE="$SOURCE+local"
  warn 'Gwin_Shared/instructions has uncommitted changes; copies will be stamped "+local".'
fi

DEST="$ROOT/$DEST_REL"
CLAUDE_MD="$ROOT/CLAUDE.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ACTIONS="$TMP/actions"   # lines: kind<TAB>target<TAB>staged-file
: > "$ACTIONS"
N=0

action() { # kind target note staged
  printf '%s\t%s\t%s\n' "$1" "$2" "$4" >> "$ACTIONS"; N=$((N + 1))
  rel=${2#"$ROOT"/}
  if [ -n "$3" ]; then printf '  %-8s %s  (%s)\n' "$1" "$rel" "$3"; else printf '  %-8s %s\n' "$1" "$rel"; fi
}

echo "Gwin_Shared: $REPO ($SOURCE)"
echo "Project:     $ROOT"
echo

# --- Rule copies -------------------------------------------------------------------------------
echo "$DEST_REL/"
names=""
for src in "$SRC"/*.md; do
  name=$(basename "$src")
  [ "$name" = README.md ] && continue
  names="$names $name "
  [ "$UNINSTALL" = 1 ] && continue
  h=$(tr -d '\r' < "$src" | hash12)
  staged="$TMP/$name"
  { printf '<!-- gwin-shared: file=%s source=%s sha256=%s | Managed by gwinrules: edit in Gwin_Shared and re-run, not here. -->\n' "$name" "$SOURCE" "$h"
    tr -d '\r' < "$src"; } > "$staged"
  dst="$DEST/$name"
  if [ ! -e "$dst" ]; then action add "$dst" "" "$staged"; continue; fi
  if ! is_stamped "$dst"; then
    if [ "$FORCE" = 1 ]; then action replace "$dst" "not created by gwinrules; --force" "$staged"
    else warn "skip $name: exists but wasn't created by gwinrules (use --force to replace)"; fi
    continue
  fi
  cur=$(body_hash "$dst"); edited=0
  [ "$cur" = "$(stamp_hash "$dst")" ] || edited=1
  if [ "$cur" = "$h" ] && [ "$edited" = 0 ]; then printf '  %-8s %s\n' same "$DEST_REL/$name"; continue; fi
  if [ "$edited" = 1 ] && [ "$FORCE" = 0 ]; then warn "skip $name: edited by hand since it was installed (use --force to overwrite)"; continue; fi
  if [ "$edited" = 1 ]; then action update "$dst" "overwriting local edits" "$staged"; else action update "$dst" "" "$staged"; fi
done
[ -n "$names" ] || { echo "No rule files found in $SRC" >&2; exit 1; }

if [ -d "$DEST" ]; then
  for f in "$DEST"/* "$DEST"/.[!.]*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if [ "$UNINSTALL" = 0 ]; then case "$names" in *" $name "*) continue ;; esac; fi
    if ! is_stamped "$f"; then
      if [ "$FORCE" = 1 ]; then action remove "$f" "not created by gwinrules; --force" ""; else warn "keep $name: not created by gwinrules"; fi
      continue
    fi
    if [ "$(body_hash "$f")" != "$(stamp_hash "$f")" ] && [ "$FORCE" = 0 ]; then warn "keep $name: edited by hand (use --force to remove)"; continue; fi
    if [ "$UNINSTALL" = 1 ]; then action remove "$f" "" ""; else action remove "$f" "no longer in Gwin_Shared" ""; fi
  done
fi

# --- CLAUDE.md block ---------------------------------------------------------------------------
echo "CLAUDE.md"
BLOCK="$TMP/block"
{ echo "$START_MARK"
  echo '## Shared rules'
  echo
  echo 'This project follows the Gwin shared rules, installed by `gwinrules` from Gwin_Shared. Edit them in'
  echo 'Gwin_Shared and re-run `gwinrules`, not here. A rule in this file overrides a shared rule only where it'
  echo 'says so explicitly.'
  echo
  echo "@$DEST_REL/RULES.md"
  echo "$END_MARK"; } > "$BLOCK"

NORM="$TMP/claude.norm"; NEW="$TMP/claude.new"; crlf=0; exists=0
if [ -f "$CLAUDE_MD" ]; then
  exists=1
  tr -d '\r' < "$CLAUDE_MD" > "$NORM"
  cmp -s "$NORM" "$CLAUDE_MD" || crlf=1
else
  : > "$NORM"
fi
s=$(grep -n -x -F "$START_MARK" "$NORM" | head -n 1 | cut -d: -f1)
e=$(grep -n -x -F "$END_MARK" "$NORM" | head -n 1 | cut -d: -f1)
ok=1; kind=""
if { [ -n "$s" ] && [ -z "$e" ]; } || { [ -z "$s" ] && [ -n "$e" ]; } || { [ -n "$s" ] && [ "$e" -lt "$s" ]; }; then
  warn 'CLAUDE.md has a broken gwin-shared block (one marker missing or out of order); fix it by hand. CLAUDE.md left unchanged.'
  ok=0
elif [ "$UNINSTALL" = 1 ]; then
  if [ -n "$s" ]; then
    awk -v s="$START_MARK" -v e="$END_MARK" '
      inb { if ($0 == e) { inb = 0; after = 1 } ; next }
      $0 == s { inb = 1; pend = ""; next }
      /^$/ { if (after && !printed_after) next; pend = pend "\n"; next }
      { if (after && !printed_after && printed) printf "\n"; if (after) printed_after = 1
        printf "%s", pend; pend = ""; print; printed = 1 }' "$NORM" > "$NEW"
    kind=edit
  else
    echo '  none     (no block to remove)'; ok=0
  fi
elif [ -n "$s" ]; then
  awk -v s="$START_MARK" -v e="$END_MARK" -v bf="$BLOCK" '
    inb { if ($0 == e) inb = 0; next }
    $0 == s { while ((getline l < bf) > 0) print l; inb = 1; next }
    { print }' "$NORM" > "$NEW"
  kind=update
elif [ "$exists" = 1 ] && [ -s "$NORM" ]; then
  { printf '%s\n\n' "$(cat "$NORM")"; cat "$BLOCK"; } > "$NEW"
  kind=append
else
  cp "$BLOCK" "$NEW"
  if [ "$exists" = 1 ]; then kind=append; else kind=create; fi
fi

if [ "$ok" = 1 ]; then
  if [ "$crlf" = 1 ]; then awk '{ printf "%s\r\n", $0 }' "$NEW" > "$NEW.crlf" && mv "$NEW.crlf" "$NEW"; fi
  if [ "$exists" = 1 ] && cmp -s "$NEW" "$CLAUDE_MD"; then
    printf '  %-8s %s\n' same CLAUDE.md
  elif [ "$UNINSTALL" = 1 ] && ! grep -q '[^[:space:]]' "$NEW"; then action remove "$CLAUDE_MD" "only held the shared-rules block" ""
  elif [ "$UNINSTALL" = 1 ]; then action "$kind" "$CLAUDE_MD" "remove the shared-rules block" "$NEW"
  else action "$kind" "$CLAUDE_MD" "shared-rules import block" "$NEW"; fi
fi

# --- Apply -------------------------------------------------------------------------------------
echo
local_only_warning
if [ "$N" = 0 ]; then echo "Nothing to change."; exit 0; fi
if [ "$APPLY" = 0 ]; then echo "Preview only: $N change(s). Re-run with --apply to write them."; exit 0; fi

[ "$UNINSTALL" = 1 ] || mkdir -p "$DEST"
tab=$(printf '\t')
while IFS="$tab" read -r kind target staged; do
  if [ "$kind" = remove ]; then rm -f "$target"; else cp "$staged" "$target"; fi
done < "$ACTIONS"
[ "$UNINSTALL" = 0 ] || rmdir "$DEST" 2>/dev/null || true
echo "Wrote $N change(s). Nothing was committed."
if [ "$IS_GIT" = 1 ]; then
  echo "Review with: git -C \"$ROOT\" status"
  [ "$HAS_GITHUB" = 0 ] || echo "Commit and push the changes so that cloud sessions and other computers get them."
fi
