#!/usr/bin/env sh
# Supports: any terminal (bash, zsh, dash; macOS / Linux / WSL). Tool-agnostic.
#
# A lo-fi ASCII progress loader for install-style work. It shows a little face, a bouncing bar for the
# running step, and a permanent checklist of finished steps. A failing step stops the run and prints
# the tail of that step's log. The drawing code lives in ascii-loader-lib.sh, which other scripts
# (such as install.sh --loader) source directly.
#
# Steps file: one step per line, "Label | command". Lines starting with # are ignored. Each command
# runs through `sh -c`. A line without " | " is rejected before anything runs.
#
# Usage:
#   scripts/ascii-loader.sh --demo          simulated install (changes nothing)
#   scripts/ascii-loader.sh --demo-fail     simulated install where step 3 fails
#   scripts/ascii-loader.sh STEPS_FILE      run the steps for real
#
# Windows: use scripts/ascii-loader.ps1 (same behaviour, same steps-file format).
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

TMP_STEPS=''
cleanup_steps() { if [ -n "$TMP_STEPS" ]; then rm -f "$TMP_STEPS"; fi; }
trap cleanup_steps EXIT   # until loader_init runs; after that the library calls it through LD_EXIT_HOOK
LD_EXIT_HOOK=cleanup_steps

case "${1:-}" in
  --demo|--demo-fail)
    TMP_STEPS=$(mktemp "${TMPDIR:-/tmp}/ascii-loader-steps.XXXXXX")
    STEPS_FILE=$TMP_STEPS
    if [ "$1" = "--demo" ]; then
      cat >"$STEPS_FILE" <<'EOF'
# Simulated install: nothing on this machine changes.
Checking prerequisites | sleep 1
Downloading packages | sleep 2
Unpacking files | sleep 1.5
Linking config | sleep 0.8
Verifying checksums | sleep 1
EOF
    else
      cat >"$STEPS_FILE" <<'EOF'
Checking prerequisites | sleep 1
Downloading packages | sleep 2
Unpacking files | echo "tar: unexpected end of file"; echo "checksum mismatch on pkg-2.3.tgz" >&2; sleep 1; exit 2
Linking config | sleep 0.8
EOF
    fi ;;
  -h|--help|'') usage; exit 0 ;;
  *) STEPS_FILE=$1
     [ -f "$STEPS_FILE" ] || { echo "no such steps file: $STEPS_FILE" >&2; exit 1; } ;;
esac

# Check every line before running anything: a typo must not turn into a command.
TOTAL=0; LINENO_=0
while IFS= read -r line || [ -n "$line" ]; do
  LINENO_=$((LINENO_ + 1))
  case $line in \#*) continue ;; esac
  if [ -z "$(printf '%s' "$line" | tr -d ' \t')" ]; then continue; fi
  case $line in
    *' | '*) ;;
    *) echo "$STEPS_FILE line $LINENO_: expected 'Label | command', got: $line" >&2; exit 2 ;;
  esac
  if [ -z "${line%% | *}" ] || [ -z "${line#* | }" ]; then
    echo "$STEPS_FILE line $LINENO_: label and command must both be non-empty" >&2; exit 2
  fi
  TOTAL=$((TOTAL + 1))
done <"$STEPS_FILE"
[ "$TOTAL" -gt 0 ] || { echo "no steps to run" >&2; exit 1; }

. "$HERE/ascii-loader-lib.sh"
loader_init "ascii-loader" "$TOTAL"

while IFS= read -r line || [ -n "$line" ]; do
  case $line in \#*) continue ;; esac
  if [ -z "$(printf '%s' "$line" | tr -d ' \t')" ]; then continue; fi
  loader_step "${line%% | *}" sh -c "${line#* | }" || break
done <"$STEPS_FILE"

cleanup_steps
if loader_done; then exit 0; else exit 1; fi
