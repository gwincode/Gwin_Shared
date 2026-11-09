#!/usr/bin/env sh
# Supports: any terminal (bash, zsh, dash; macOS / Linux / WSL). Tool-agnostic.
#
# A lo-fi ASCII progress loader for install-style work. It shows a little face, a bouncing
# bar for the running step, and a permanent checklist of finished steps. Failures stop the run
# and print the tail of that step's log.
#
# Steps file: one step per line, "Label | command". Lines starting with # are ignored.
#
# Usage:
#   scripts/ascii-loader.sh --demo          simulated install (changes nothing)
#   scripts/ascii-loader.sh --demo-fail     simulated install where step 3 fails
#   scripts/ascii-loader.sh STEPS_FILE      run the steps for real
#
# Windows: use scripts/ascii-loader.ps1 (same behaviour, same steps-file format).
set -u

# ---- colours (only when stdout is a terminal, so logs stay clean) ------------------------
if [ -t 1 ]; then
  G=$(printf '\033[32m'); R=$(printf '\033[31m'); Y=$(printf '\033[33m')
  C=$(printf '\033[36m'); D=$(printf '\033[2m');  B=$(printf '\033[1m'); N=$(printf '\033[0m')
  ANIM=1
else
  G=''; R=''; Y=''; C=''; D=''; B=''; N=''
  ANIM=0
fi

LIVE_LINES=5      # height of the redrawn block (see draw_live)
LIVE_DRAWN=0
BAR_W=24          # width of the bouncing bar
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ascii-loader.XXXXXX")

cleanup() { [ "$ANIM" = 1 ] && printf '\033[?25h'; }   # always restore the cursor
trap cleanup EXIT INT TERM

# ---- drawing helpers ----------------------------------------------------------------------
# Move the cursor back to the top of the live block and wipe it, so we can redraw in place.
clear_live() {
  if [ "$ANIM" = 1 ] && [ "$LIVE_DRAWN" = 1 ]; then
    # \r first: "cursor up" keeps the column, so go back to column 0 before moving up.
    printf '\r\033[%dA\033[J' "$LIVE_LINES"
  fi
}

# $1 face  $2 headline  $3 bar  $4 footer
draw_live() {
  printf '   .-----.   %s\n' "$2"
  printf '   | %s |   %s\n' "$1" "$3"
  printf "   |  ~  |   %s\n" "$4"
  printf "   '-----'\n"
  printf '\n'
  LIVE_DRAWN=1
}

# A bar of width BAR_W with a 4-char block at position $1.
bounce_bar() {
  pos=$1; out=''; i=0
  while [ "$i" -lt "$BAR_W" ]; do
    if [ "$i" -ge "$pos" ] && [ "$i" -lt $((pos + 4)) ]; then out="${out}="; else out="${out}."; fi
    i=$((i + 1))
  done
  printf '[%s]' "$out"
}

# A full bar for a finished fraction: $1 done, $2 total.
full_bar() {
  done_n=$1; total=$2; filled=$((done_n * BAR_W / total)); out=''; i=0
  while [ "$i" -lt "$BAR_W" ]; do
    if [ "$i" -lt "$filled" ]; then out="${out}#"; else out="${out}."; fi
    i=$((i + 1))
  done
  printf '[%s]' "$out"
}

# Print a permanent line above the live block.
say() { printf '%s\n' "$1"; }

# ---- run one step -------------------------------------------------------------------------
# $1 index  $2 total  $3 label  $4 command.  Sets STEP_RC.
run_step() {
  idx=$1; total=$2; label=$3; cmd=$4
  log="$LOG_DIR/step$idx.log"
  start=$(date +%s)

  # Run the command in a background subshell; its output goes to a log file, not the screen.
  ( eval "$cmd" ) >"$log" 2>&1 &
  pid=$!

  spin='|/-\'; tick=0; pos=0; dir=1
  if [ "$ANIM" = 1 ]; then
    printf '\033[?25l'                       # hide cursor while animating
    while kill -0 "$pid" 2>/dev/null; do
      clear_live
      frame=$(printf '%s' "$spin" | cut -c$((tick % 4 + 1)))
      draw_live "o_o" "${C}${B}Installing${N} $label" "$(bounce_bar $pos)" \
                "${D}step $idx of $total  $frame  working...${N}"
      pos=$((pos + dir))
      if [ "$pos" -ge $((BAR_W - 4)) ]; then dir=-1; fi
      if [ "$pos" -le 0 ]; then dir=1; fi
      tick=$((tick + 1))
      sleep 0.12
    done
    printf '\033[?25h'
  fi
  wait "$pid"; STEP_RC=$?

  elapsed=$(( $(date +%s) - start ))
  clear_live
  LIVE_DRAWN=0
  if [ "$STEP_RC" -eq 0 ]; then
    say "   ${G}[ OK ]${N} $label ${D}(${elapsed}s)${N}"
  else
    say "   ${R}[FAIL]${N} $label ${D}(exit $STEP_RC)${N}"
    say "   ${D}last lines of $log:${N}"
    tail -n 5 "$log" | sed 's/^/      | /'
  fi
}

# ---- main ---------------------------------------------------------------------------------
STEPS_FILE=$(mktemp "$LOG_DIR/steps.XXXXXX")

make_demo() {
  cat >"$STEPS_FILE" <<'EOF'
# Simulated install: nothing on this machine changes.
Checking prerequisites | sleep 1
Downloading packages | sleep 2
Unpacking files | sleep 1.5
Linking config | sleep 0.8
Verifying checksums | sleep 1
EOF
  if [ "${1:-}" = "fail" ]; then
    cat >"$STEPS_FILE" <<'EOF'
Checking prerequisites | sleep 1
Downloading packages | sleep 2
Unpacking files | echo "tar: unexpected end of file"; echo "checksum mismatch on pkg-2.3.tgz" >&2; sleep 1; exit 2
Linking config | sleep 0.8
EOF
  fi
}

case "${1:-}" in
  --demo)      make_demo ok ;;
  --demo-fail) make_demo fail ;;
  -h|--help|'') sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)           [ -f "$1" ] || { echo "no such steps file: $1" >&2; exit 1; }
               cp "$1" "$STEPS_FILE" ;;
esac

# Count runnable steps (skip blank and # lines).
TOTAL=$(grep -c -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$STEPS_FILE")
[ "$TOTAL" -gt 0 ] || { echo "no steps to run" >&2; exit 1; }

say ""
say "   ${B}ascii-loader${N}  ${D}$TOTAL step(s)${N}"
say ""

DONE=0; IDX=0; FAILED=0
START_ALL=$(date +%s)
[ "$ANIM" = 1 ] && draw_live "-_-" "${D}Getting ready...${N}" "$(full_bar 0 "$TOTAL")" "${D}0 of $TOTAL done${N}"

while IFS= read -r line || [ -n "$line" ]; do
  # Skip comments and blank lines (including whitespace-only ones).
  case "$line" in \#*) continue ;; esac
  [ -z "$(printf '%s' "$line" | tr -d ' \t')" ] && continue
  label=${line%% | *}
  cmd=${line#* | }
  IDX=$((IDX + 1))
  run_step "$IDX" "$TOTAL" "$label" "$cmd"
  if [ "$STEP_RC" -ne 0 ]; then FAILED=1; break; fi
  DONE=$((DONE + 1))
  if [ "$ANIM" = 1 ] && [ "$DONE" -lt "$TOTAL" ]; then
    draw_live "^_^" "${G}Step done${N}" "$(full_bar "$DONE" "$TOTAL")" "${D}$DONE of $TOTAL done${N}"
  fi
done <"$STEPS_FILE"

clear_live
LIVE_DRAWN=0
ELAPSED_ALL=$(( $(date +%s) - START_ALL ))
say ""
if [ "$FAILED" -eq 0 ]; then
  draw_live "^_^" "${G}${B}All done${N}" "$(full_bar "$DONE" "$TOTAL")" \
            "${G}$DONE of $TOTAL installed in ${ELAPSED_ALL}s${N}"
  say "   ${G}${B}SUCCESS${N}  nothing left to install."
  exit 0
else
  draw_live "x_x" "${R}${B}Stopped${N}" "$(full_bar "$DONE" "$TOTAL")" \
            "${R}$DONE of $TOTAL installed, step $IDX failed${N}"
  say "   ${R}${B}FAILED${N}  fix the step above and run again."
  say "   ${D}logs kept in $LOG_DIR${N}"
  exit 1
fi
