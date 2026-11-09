#!/usr/bin/env sh
# Supports: Claude Code (macOS / Linux / WSL / Git Bash); run in CI on ubuntu.
#
# Tests the scripted part of the one-shot install (INSTALL-PROMPT.md) in a throwaway sandbox repo:
#   1. Creates a sandbox git repo with a fake GitHub remote (nothing is pushed).
#   2. Runs gwinrules --apply into it.
#   3. Clones the public pipeline kit and copies pipeline-kit/ in.
#   4. Copies agents, commands, settings and the CLAUDE block, as steps 5 and 6 of the install do.
#   5. Fills the placeholders with fill-placeholders.py (preview, then --write).
#   6. Asserts the expected files exist and no placeholder is left.
# It does NOT test the Claude-driven steps (interview, merges, permission prompts, /agents, /status).
# Exit code is non-zero if any assertion fails.
#
# Usage: scripts/test-sandbox-install.sh [--keep]   (--keep leaves the sandbox folder for inspection)
set -eu

KIT_URL=${KIT_URL:-https://github.com/gwincode/gwin-claude-agent-pipeline-kit.git}
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t sandboxinstall)
SANDBOX="$WORK/sandbox"
KITSRC="$WORK/kit"
cleanup() { [ "$KEEP" = 1 ] && { echo "Kept: $WORK"; return; }; rm -rf "$WORK"; }
trap cleanup EXIT

fail=0
check() { # check <description> <command...>
  desc=$1; shift
  if "$@" >/dev/null 2>&1; then echo "PASS  $desc"; else echo "FAIL  $desc"; fail=1; fi
}

echo "== 1. Sandbox repo"
mkdir -p "$SANDBOX"
git -C "$SANDBOX" init -q -b main
git -C "$SANDBOX" config user.email sandbox@example.invalid
git -C "$SANDBOX" config user.name sandbox
echo "# Sandbox" > "$SANDBOX/README.md"
git -C "$SANDBOX" add README.md
git -C "$SANDBOX" commit -qm init
git -C "$SANDBOX" remote add origin https://github.com/example/sandbox.git

echo "== 2. gwinrules --apply"
sh "$ROOT/scripts/gwinrules.sh" --project "$SANDBOX" --apply

echo "== 3. Clone public kit"
git clone -q --depth 1 "$KIT_URL" "$KITSRC"
cp -R "$KITSRC/pipeline-kit" "$SANDBOX/pipeline-kit"
K="$SANDBOX/pipeline-kit"

echo "== 4. Copy agents, commands, settings, CLAUDE block, handoff"
mkdir -p "$SANDBOX/.claude/agents" "$SANDBOX/.claude/commands"
cp "$K"/agents/*.md "$SANDBOX/.claude/agents/"
cp "$K"/commands/*.md "$SANDBOX/.claude/commands/"
cp "$K/settings.json" "$SANDBOX/.claude/settings.json"
cat "$K/CLAUDE-pipeline-block.md" >> "$SANDBOX/CLAUDE.md"
cp "$K/handoff-template.md" "$SANDBOX/HANDOFF.md"

echo "== 5. Fill placeholders"
cp "$K/tools/values.example.json" "$WORK/values.json"
python3 - "$WORK/values.json" <<'PY'
import json, sys
p = sys.argv[1]
v = json.load(open(p))
v.update({'PROJECT_NAME': 'Sandbox', 'REPO': 'example/sandbox', 'HANDOFF_FILE': 'HANDOFF.md',
          'DEPLOY_HOST': 'none', 'SMOKE_URL': 'none', 'TEST_COMMAND': 'none',
          'HOUSEKEEPING_NOTE': None})
json.dump(v, open(p, 'w'), indent=2)
PY
cd "$SANDBOX"
python3 pipeline-kit/tools/fill-placeholders.py "$WORK/values.json" .claude CLAUDE.md HANDOFF.md
python3 pipeline-kit/tools/fill-placeholders.py "$WORK/values.json" .claude CLAUDE.md HANDOFF.md --write

echo "== 6. Assertions"
check "rules copied (12 files + RULES.md)" test "$(ls .claude/gwin-shared | wc -l)" -eq 13
check "RULES.md present" test -f .claude/gwin-shared/RULES.md
check "CLAUDE.md imports RULES.md" grep -q '@.claude/gwin-shared/RULES.md' CLAUDE.md
check "4 agents installed" test "$(ls .claude/agents/*.md | wc -l)" -eq 4
check "4 commands installed" test "$(ls .claude/commands/*.md | wc -l)" -eq 4
check "settings.json parses" python3 -c "import json; json.load(open('.claude/settings.json'))"
check "settings.json mentions the production branch 'main'" grep -q 'main' .claude/settings.json
check "no blanket allow in settings.json" sh -c "! python3 -c \"import json,sys; a=json.load(open('.claude/settings.json')).get('permissions',{}).get('allow',[]); sys.exit(0 if any(r in ('Bash(*)','PowerShell(*)') or r.endswith(':*)') for r in a) else 1)\""
check "no placeholder left in .claude, CLAUDE.md, HANDOFF.md" sh -c "! grep -rn '{{' .claude CLAUDE.md HANDOFF.md | grep -v '\${{' | grep -q ."
check "fill tool reports no placeholders left" sh -c "python3 pipeline-kit/tools/fill-placeholders.py $WORK/values.json .claude CLAUDE.md HANDOFF.md | grep -q 'No placeholders left'"

echo
if [ "$fail" = 0 ]; then echo "All sandbox install checks passed."; else echo "Sandbox install checks FAILED."; fi
exit "$fail"
