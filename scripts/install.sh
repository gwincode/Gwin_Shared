#!/usr/bin/env sh
# Supports: Claude Code (macOS / Linux / WSL)
#
# Links shared skills, agents and commands from this repo into a Claude Code config folder.
#   skills/<name>/      -> $TARGET/skills/<name>
#   agents/<name>.md    -> $TARGET/agents/<name>.md
#   commands/<name>.md  -> $TARGET/commands/<name>.md
# README.md files are ignored. Existing items that are not links into this repo are left alone
# unless --force is given. Copies (--copy) do not update on `git pull`; refresh them with --force.
#
# Also installs the token status line (plugins/cc-token-statusline, MIT, Alfafis) into the personal
# ~/.claude only. It backs up settings.json and chains onto any status line already set. Skip it with
# --no-statusline. With --target it is skipped, because a status line is a personal setting.
#
# --loader shows progress with the ASCII loader (scripts/ascii-loader-lib.sh): one animated step per
# item, [ OK ] / [SKIP] / [FAIL] per line, and a stop on the first failure. Each step's own output goes
# to a log and its last line is shown as a note. Without it, the output is the plain list, which is
# what you want in CI and logs. Off a terminal, --loader prints plain lines too.
#
# Usage: scripts/install.sh [--target DIR] [--copy] [--force] [--uninstall] [--dry-run]
#                           [--no-statusline] [--loader]
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
TARGET="$HOME/.claude"
COPY=0 FORCE=0 UNINSTALL=0 DRY=0 STATUSLINE=1 LOADER=0
SKIP_RC=0   # exit code that means "skipped". 0 normally; 10 under --loader so it shows as [SKIP]

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET=$2; shift 2 ;;
    --copy) COPY=1; shift ;;
    --force) FORCE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --no-statusline) STATUSLINE=0; shift ;;
    --loader) LOADER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

run() { if [ "$DRY" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

points_into_repo() {
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in "$REPO"/*) return 0 ;; *) return 1 ;; esac
}

install_item() { # src dest
  src=$1 dest=$2
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if points_into_repo "$dest"; then
      [ "$COPY" = 0 ] && { echo "  ok       $dest"; return; }
    elif [ "$FORCE" = 0 ]; then
      echo "  skip     $dest (exists and is not a link into this repo; use --force to replace)" >&2
      return "$SKIP_RC"
    fi
    run rm -rf "$dest"
  fi
  if [ "$COPY" = 1 ]; then run cp -R "$src" "$dest"; echo "  copied   $dest"
  else run ln -s "$src" "$dest"; echo "  linked   $dest"; fi
}

uninstall_item() { # dest
  dest=$1
  [ -e "$dest" ] || [ -L "$dest" ] || return 0
  if points_into_repo "$dest" || [ "$FORCE" = 1 ]; then
    run rm -rf "$dest"; echo "  removed  $dest"
  else
    echo "  keep     $dest (not a link into this repo; use --force to remove copies)" >&2
    return "$SKIP_RC"
  fi
}

# Is $2 an item this repo ships in set $1? Skills are folders with a SKILL.md; agents and commands
# are .md files other than README.md.
is_item() { # set src
  if [ "$1" = skills ]; then [ -f "$2/SKILL.md" ]; return; fi
  [ -f "$2" ] || return 1
  case "$(basename "$2")" in README.md) return 1 ;; *.md) return 0 ;; *) return 1 ;; esac
}

# One loader step: make sure the folder exists, then link (or remove) the item.
do_item() { # set src
  [ "$UNINSTALL" = 1 ] || [ -d "$TARGET/$1" ] || run mkdir -p "$TARGET/$1"
  if [ "$UNINSTALL" = 1 ]; then uninstall_item "$TARGET/$1/$(basename "$2")"
  else install_item "$2" "$TARGET/$1/$(basename "$2")"; fi
}

# Token status line: the plugin's own installer does the work (copy, backup, chain, uninstall).
# Returns 0 on success, $SKIP_RC when skipped, and non-zero when the installer fails.
run_statusline() {
  if [ "$STATUSLINE" = 0 ]; then echo "statusline: skipped (--no-statusline)"; return "$SKIP_RC"; fi
  if [ "$TARGET" != "$HOME/.claude" ]; then
    echo "statusline: skipped (only the personal ~/.claude gets a status line, not --target)"
    return "$SKIP_RC"
  fi
  py=""
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then py=$candidate; break; fi
  done
  if [ -z "$py" ]; then
    echo "statusline: skipped (python3 not found; the badge needs it)" >&2; return "$SKIP_RC"
  fi
  echo "statusline:"
  # The plugin's installer reads CLAUDE_CONFIG_DIR, so point it at the same folder as the links.
  if [ "$DRY" = 1 ]; then flag=--dry-run
  elif [ "$UNINSTALL" = 1 ]; then flag=--uninstall
  else flag=; fi
  CLAUDE_CONFIG_DIR="$TARGET" "$py" "$REPO/plugins/cc-token-statusline/scripts/install.py" ${flag:+"$flag"}
}

# ---- --loader: one step per item, plus one for the status line ----------------------------------
if [ "$LOADER" = 1 ]; then
  . "$REPO/scripts/ascii-loader-lib.sh"
  SKIP_RC=$LD_SKIP_RC

  LIST=$(mktemp "${TMPDIR:-/tmp}/gwin-items.XXXXXX")
  for set in skills agents commands; do
    [ -d "$REPO/$set" ] || continue
    for src in "$REPO/$set"/*; do
      [ -e "$src" ] || continue
      if is_item "$set" "$src"; then printf '%s\t%s\n' "$set" "$src" >>"$LIST"; fi
    done
  done
  total=$(( $(wc -l <"$LIST") + 1 ))   # +1 for the status line step, which may itself be skipped

  if [ "$UNINSTALL" = 1 ]; then verb=Removing; else verb=Installing; fi
  title="Gwin_Shared -> $TARGET"
  if [ "$DRY" = 1 ]; then title="$title (dry run: nothing is changed)"; fi
  loader_init "$title" "$total" "$verb"

  TAB=$(printf '\t')
  while IFS=$TAB read -r set src; do
    case $set in skills) kind=skill ;; agents) kind=agent ;; *) kind=command ;; esac
    loader_step "$kind: $(basename "$src" .md)" do_item "$set" "$src" || break
  done <"$LIST"
  rm -f "$LIST"
  loader_step "token status line" run_statusline || true

  if loader_done; then exit 0; else exit 1; fi
fi

# ---- default: the plain list --------------------------------------------------------------------
echo "Repo:   $REPO"
echo "Target: $TARGET"

for set in skills agents commands; do
  [ -d "$REPO/$set" ] || continue
  found=0
  for src in "$REPO/$set"/*; do
    [ -e "$src" ] || continue
    is_item "$set" "$src" || continue
    name=$(basename "$src")
    if [ "$found" = 0 ]; then
      echo "$set:"; found=1
      [ "$UNINSTALL" = 1 ] || [ -d "$TARGET/$set" ] || run mkdir -p "$TARGET/$set"
    fi
    if [ "$UNINSTALL" = 1 ]; then uninstall_item "$TARGET/$set/$name"
    else install_item "$src" "$TARGET/$set/$name"; fi
  done
  [ "$found" = 1 ] || echo "$set: nothing to do"
done

run_statusline || echo "statusline: installer failed (links above are unaffected)" >&2
