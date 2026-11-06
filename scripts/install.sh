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
# Usage: scripts/install.sh [--target DIR] [--copy] [--force] [--uninstall] [--dry-run]
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
TARGET="$HOME/.claude"
COPY=0 FORCE=0 UNINSTALL=0 DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET=$2; shift 2 ;;
    --copy) COPY=1; shift ;;
    --force) FORCE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
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
      return
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
  fi
}

echo "Repo:   $REPO"
echo "Target: $TARGET"

for set in skills agents commands; do
  [ -d "$REPO/$set" ] || continue
  found=0
  for src in "$REPO/$set"/*; do
    [ -e "$src" ] || continue
    name=$(basename "$src")
    if [ "$set" = skills ]; then
      [ -f "$src/SKILL.md" ] || continue
    else
      [ -f "$src" ] || continue
      case "$name" in README.md) continue ;; *.md) ;; *) continue ;; esac
    fi
    if [ "$found" = 0 ]; then
      echo "$set:"; found=1
      [ "$UNINSTALL" = 1 ] || [ -d "$TARGET/$set" ] || run mkdir -p "$TARGET/$set"
    fi
    if [ "$UNINSTALL" = 1 ]; then uninstall_item "$TARGET/$set/$name"
    else install_item "$src" "$TARGET/$set/$name"; fi
  done
  [ "$found" = 1 ] || echo "$set: nothing to do"
done
