#!/usr/bin/env sh
# Supports: Claude Code (macOS / Linux / WSL / Git Bash)
#
# Installs the Gwin shared rules into a project repo so every session (local or cloud) can read them.
# Run it inside a project (or pass --project). It:
#   1. Copies Gwin_Shared/instructions/*.md (except README.md) into <project>/.claude/gwin-shared/,
#      each stamped with its source file, the Gwin_Shared commit and a content hash.
#   2. Adds one marked block to <project>/CLAUDE.md importing .claude/gwin-shared/RULES.md
#      (creating CLAUDE.md if there is none). Nothing else in CLAUDE.md is touched.
# It only previews by default; pass --apply to write. It never commits or pushes.
# Hand-edited copies and files it didn't create are left alone unless --force is given.
#
# Usage: gwinrules.sh [--project DIR] [--apply] [--force] [--uninstall]
set -eu

DEST_REL=.claude/gwin-shared
START_MARK='<!-- gwin-shared:start -->'
END_MARK='<!-- gwin-shared:end -->'
STAMP_RE='^<!-- gwin-shared: file=[^ ]+ source=[^ ]+ sha256=[0-9a-f]{12} '

PROJECT=. APPLY=0 FORCE=0 UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT=$2; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
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
ROOT=$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null) || { echo "Not inside a git repository: $PROJECT" >&2; exit 1; }
ROOT=$(cd "$ROOT" && pwd -P)
[ "$ROOT" != "$REPO" ] || { echo "That is the Gwin_Shared repo itself; run this inside a project." >&2; exit 1; }

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
if [ "$N" = 0 ]; then echo "Nothing to change."; exit 0; fi
if [ "$APPLY" = 0 ]; then echo "Preview only: $N change(s). Re-run with --apply to write them."; exit 0; fi

[ "$UNINSTALL" = 1 ] || mkdir -p "$DEST"
tab=$(printf '\t')
while IFS="$tab" read -r kind target staged; do
  if [ "$kind" = remove ]; then rm -f "$target"; else cp "$staged" "$target"; fi
done < "$ACTIONS"
[ "$UNINSTALL" = 0 ] || rmdir "$DEST" 2>/dev/null || true
echo "Wrote $N change(s). Nothing was committed."
echo "Review with: git -C \"$ROOT\" status"
