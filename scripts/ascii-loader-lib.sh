#!/usr/bin/env sh
# Supports: any terminal (bash, zsh, dash; macOS / Linux / WSL). Tool-agnostic.
# This is a library: source it, do not run it. For a command line, use ascii-loader.sh.
#
# Lo-fi ASCII progress loader. A step's output goes to a log, not the screen. The screen shows a
# small face, a bouncing bar for the running step, and a permanent checklist of finished steps.
#
# API
#   loader_init TITLE TOTAL [VERB]
#       Call once, before any step. TOTAL is the number of loader_step calls to come. VERB is the word
#       shown while a step runs (default "Installing").
#   loader_step LABEL CMD [ARG...]
#       Run CMD (a command or a shell function) as one step, in a subshell. Exit 0 is [ OK ], exit 10
#       is [SKIP] (counts as success), anything else is [FAIL]. After a failure, later loader_step
#       calls do nothing and return 1. The last line the step printed is shown as a short note.
#   loader_done
#       Print the summary. Returns 0 if every step passed, 1 otherwise.
#
# Behaviour
#   - Safe under `set -e` and `set -u` in the caller. All names start with ld_ / LD_ to stay clear of the
#     caller's variables. The library owns the INT, TERM and EXIT traps once loader_init has run; to
#     run your own cleanup on exit, set LD_EXIT_HOOK to the name of a function before loader_init.
#   - Animation only on a terminal that is not TERM=dumb. NO_COLOR turns colours off. Elsewhere the
#     output is plain lines, so logs stay clean.
#   - Ctrl-C or SIGTERM stops the running step and the processes it started (needs pgrep; without it
#     only the step itself is stopped), restores the cursor, and exits 130.
#   - Logs are removed on exit unless a step failed, in which case their folder is kept and named.

LD_SKIP_RC=10

ld_setup_terminal() {
  LD_ANIM=0
  LD_G=''; LD_R=''; LD_Y=''; LD_C=''; LD_D=''; LD_B=''; LD_N=''
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then
    LD_ANIM=1
    if [ -z "${NO_COLOR:-}" ]; then
      LD_G=$(printf '\033[32m'); LD_R=$(printf '\033[31m'); LD_Y=$(printf '\033[33m')
      LD_C=$(printf '\033[36m'); LD_D=$(printf '\033[2m');  LD_B=$(printf '\033[1m')
      LD_N=$(printf '\033[0m')
    fi
  fi
  LD_ESC=$(printf '\033')
  # Width matters: a label that wraps makes the live block taller than the cursor-up count, and every
  # frame then leaves residue behind. Everything drawn is cut to fit this.
  LD_COLS=''
  if [ "$LD_ANIM" = 1 ]; then LD_COLS=$(tput cols 2>/dev/null || echo ''); fi
  case $LD_COLS in ''|*[!0-9]*) LD_COLS=${COLUMNS:-80} ;; esac
  case $LD_COLS in ''|*[!0-9]*) LD_COLS=80 ;; esac
  if [ "$LD_COLS" -lt 40 ]; then LD_COLS=40; fi
}

# Print TEXT cut to MAX characters, with "..." when something was cut.
ld_trunc() {
  if [ "${#1}" -le "$2" ]; then
    printf '%s' "$1"
  else
    ld_tn=$(($2 - 3))
    if [ "$ld_tn" -lt 1 ]; then ld_tn=1; fi
    printf '%s...' "$(printf '%s' "$1" | cut -c1-"$ld_tn")"
  fi
}

ld_bounce_bar() { # POS: a 4-char block at POS inside a bar
  ld_s=''; ld_i=0
  while [ "$ld_i" -lt "$LD_BAR_W" ]; do
    if [ "$ld_i" -ge "$1" ] && [ "$ld_i" -lt $(($1 + 4)) ]; then ld_s="${ld_s}="; else ld_s="${ld_s}."; fi
    ld_i=$((ld_i + 1))
  done
  printf '[%s]' "$ld_s"
}

ld_full_bar() { # DONE: a bar filled DONE/TOTAL of the way
  if [ "$LD_TOTAL" -gt 0 ]; then ld_f=$(($1 * LD_BAR_W / LD_TOTAL)); else ld_f=0; fi
  ld_s=''; ld_i=0
  while [ "$ld_i" -lt "$LD_BAR_W" ]; do
    if [ "$ld_i" -lt "$ld_f" ]; then ld_s="${ld_s}#"; else ld_s="${ld_s}."; fi
    ld_i=$((ld_i + 1))
  done
  printf '[%s]' "$ld_s"
}

# Move back to the top of the live block and wipe it, so it can be redrawn in place.
ld_clear_live() {
  if [ "$LD_ANIM" = 1 ] && [ "$LD_LIVE" = 1 ]; then
    # \r first: "cursor up" keeps the column, so return to column 0 before moving up.
    printf '\r\033[%dA\033[J' "$LD_LIVE_LINES"
  fi
  LD_LIVE=0
}

# 1 face, 2 verb, 3 verb colour, 4 label, 5 bar, 6 footer, 7 footer colour
ld_draw_live() {
  ld_max=$((LD_COLS - 15 - ${#2}))
  if [ "$ld_max" -lt 8 ]; then ld_max=8; fi
  ld_lab=$(ld_trunc "$4" "$ld_max")
  ld_foot=$(ld_trunc "$6" $((LD_COLS - 15)))
  printf '   .-----.   %s%s%s %s\n' "$3" "$2" "$LD_N" "$ld_lab"
  printf '   | %s |   %s\n' "$1" "$5"
  printf '   |  ~  |   %s%s%s\n' "$7" "$ld_foot" "$LD_N"
  printf "   '-----'\n"
  printf '\n'
  LD_LIVE=1
}

# The last non-blank line of a log, without colour codes or surrounding space.
ld_last_line() {
  sed "s/${LD_ESC}\[[0-9;?]*[A-Za-z]//g" "$1" 2>/dev/null \
    | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' | grep -v '^$' | tail -n 1
}

# 1 tag, 2 label, 3 seconds, 4 note
ld_print_result() {
  # Budget: "   [ OK ] " is 10 columns, plus one spare so a full line never wraps. The time tail is
  # measured first, the label gets what is left, and the note only gets room the label did not use.
  ld_tail=''
  if [ "$3" -ge 1 ]; then ld_tail=" ($3s)"; fi
  ld_l=$(ld_trunc "$2" $((LD_COLS - 11 - ${#ld_tail})))
  ld_room=$((LD_COLS - 11 - ${#ld_l} - ${#ld_tail} - 4))   # 4 = the "  - " before the note
  ld_n=''
  if [ -n "$4" ] && [ "$ld_room" -ge 8 ]; then
    ld_n="  ${LD_D}- $(ld_trunc "$4" "$ld_room")${LD_N}"
  fi
  if [ -n "$ld_tail" ]; then ld_tail="${LD_D}${ld_tail}${LD_N}"; fi
  printf '   %s %s%s%s\n' "$1" "$ld_l" "$ld_tail" "$ld_n"
}

# Stop PID and everything it started, children first. Killing only the step's subshell would leave
# whatever it was running (a download, a build) alive. Needs pgrep; without it only PID is stopped.
ld_kill_tree() {
  if command -v pgrep >/dev/null 2>&1; then
    for ld_kc in $(pgrep -P "$1" 2>/dev/null); do ld_kill_tree "$ld_kc"; done
  fi
  kill "$1" 2>/dev/null || :
}

ld_on_signal() {
  if [ -n "$LD_PID" ]; then ld_kill_tree "$LD_PID"; fi
  ld_clear_live
  printf '   %sInterrupted%s  stopped before finishing.\n' "$LD_R" "$LD_N"
  exit 130
}

ld_on_exit() {
  if [ "$LD_ANIM" = 1 ]; then printf '\033[?25h'; fi   # always give the cursor back
  if [ "$LD_FAILED" = 0 ]; then
    case $LD_DIR in */ascii-loader.*) rm -rf "$LD_DIR" ;; esac
  fi
  if [ -n "${LD_EXIT_HOOK:-}" ]; then "$LD_EXIT_HOOK" || :; fi   # caller's own cleanup, if any
}

loader_init() {
  LD_TITLE=$1; LD_TOTAL=$2; LD_VERB=${3:-Installing}
  LD_IDX=0; LD_DONE=0; LD_SKIPPED=0; LD_FAILED=0; LD_PID=''
  LD_LIVE=0; LD_LIVE_LINES=5; LD_BAR_W=24
  LD_START=$(date +%s)
  LD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ascii-loader.XXXXXX") || {
    echo "loader: cannot create a temp folder" >&2; return 1
  }
  ld_setup_terminal
  trap ld_on_signal INT TERM
  trap ld_on_exit EXIT
  ld_t=$(ld_trunc "$LD_TITLE" $((LD_COLS - 20)))
  printf '\n   %s%s%s  %s%s step(s)%s\n\n' "$LD_B" "$ld_t" "$LD_N" "$LD_D" "$LD_TOTAL" "$LD_N"
  if [ "$LD_ANIM" = 1 ]; then
    ld_draw_live '-_-' 'Getting ready' "$LD_D" '' "$(ld_full_bar 0)" "0 of $LD_TOTAL done" "$LD_D"
  fi
}

loader_step() {
  ld_label=$1; shift
  if [ "$LD_FAILED" = 1 ]; then return 1; fi
  LD_IDX=$((LD_IDX + 1))
  ld_log="$LD_DIR/step$LD_IDX.log"
  ld_t0=$(date +%s)

  # Background subshell: its output goes to the log, and stdin is closed so a step cannot eat the
  # caller's input. A shell function works here too, because a subshell inherits functions.
  ( "$@" ) >"$ld_log" 2>&1 </dev/null &
  LD_PID=$!

  ld_pos=0; ld_dir=1; ld_tick=0
  if [ "$LD_ANIM" = 1 ]; then
    printf '\033[?25l'                                  # hide the cursor while animating
    while kill -0 "$LD_PID" 2>/dev/null; do
      ld_clear_live
      case $((ld_tick % 4)) in 0) ld_sp='|' ;; 1) ld_sp='/' ;; 2) ld_sp='-' ;; *) ld_sp='\' ;; esac
      ld_draw_live 'o_o' "$LD_VERB" "$LD_C$LD_B" "$ld_label" "$(ld_bounce_bar "$ld_pos")" \
                   "step $LD_IDX of $LD_TOTAL  $ld_sp  working..." "$LD_D"
      ld_pos=$((ld_pos + ld_dir))
      if [ "$ld_pos" -ge $((LD_BAR_W - 4)) ]; then ld_dir=-1; fi
      if [ "$ld_pos" -le 0 ]; then ld_dir=1; fi
      ld_tick=$((ld_tick + 1))
      sleep 0.12 2>/dev/null || sleep 1                 # fractional sleep is not in POSIX
    done
    printf '\033[?25h'
  fi
  ld_rc=0
  wait "$LD_PID" || ld_rc=$?
  LD_PID=''

  ld_secs=$(( $(date +%s) - ld_t0 ))
  ld_clear_live
  # Tidy the note so the useful part survives truncation: squeeze padding, and show $HOME as ~.
  ld_note=$(ld_last_line "$ld_log" | tr -s ' ')
  case $ld_note in *"$HOME"*) ld_note="${ld_note%%"$HOME"*}~${ld_note#*"$HOME"}" ;; esac

  if [ "$ld_rc" -eq 0 ]; then
    ld_print_result "${LD_G}[ OK ]${LD_N}" "$ld_label" "$ld_secs" "$ld_note"
  elif [ "$ld_rc" -eq "$LD_SKIP_RC" ]; then
    ld_print_result "${LD_Y}[SKIP]${LD_N}" "$ld_label" "$ld_secs" "$ld_note"
    LD_SKIPPED=$((LD_SKIPPED + 1))
  else
    ld_print_result "${LD_R}[FAIL]${LD_N}" "$ld_label" "$ld_secs" "exit $ld_rc"
    printf '   %slast lines of its log:%s\n' "$LD_D" "$LD_N"
    sed "s/${LD_ESC}\[[0-9;?]*[A-Za-z]//g" "$ld_log" | grep -v '^[[:space:]]*$' | tail -n 5 \
      | while IFS= read -r ld_ln; do printf '      | %s\n' "$(ld_trunc "$ld_ln" $((LD_COLS - 10)))"; done
    LD_FAILED=1
    return 1
  fi

  LD_DONE=$((LD_DONE + 1))
  if [ "$LD_ANIM" = 1 ] && [ "$LD_IDX" -lt "$LD_TOTAL" ]; then
    ld_draw_live '^_^' 'Step done' "$LD_G" '' "$(ld_full_bar "$LD_DONE")" \
                 "$LD_DONE of $LD_TOTAL done" "$LD_D"
  fi
  return 0
}

loader_done() {
  ld_clear_live
  ld_secs=$(( $(date +%s) - LD_START ))
  printf '\n'
  if [ "$LD_FAILED" = 0 ]; then
    ld_msg="$LD_DONE of $LD_TOTAL done in ${ld_secs}s"
    if [ "$LD_SKIPPED" -gt 0 ]; then ld_msg="$ld_msg ($LD_SKIPPED skipped)"; fi
    ld_draw_live '^_^' 'All done' "$LD_G$LD_B" '' "$(ld_full_bar "$LD_DONE")" "$ld_msg" "$LD_G"
    printf '   %sSUCCESS%s\n' "$LD_G$LD_B" "$LD_N"
    return 0
  fi
  ld_draw_live 'x_x' 'Stopped' "$LD_R$LD_B" '' "$(ld_full_bar "$LD_DONE")" \
               "$LD_DONE of $LD_TOTAL done, step $LD_IDX failed" "$LD_R"
  printf '   %sFAILED%s  fix the step above and run again.\n' "$LD_R$LD_B" "$LD_N"
  printf '   %slogs kept in %s%s\n' "$LD_D" "$LD_DIR" "$LD_N"
  return 1
}
