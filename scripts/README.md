# scripts

See the root [README](../README.md) for what belongs here.

| Script | Use |
| --- | --- |
| `gwinrules.sh` / `.ps1` | Copy the shared rules into a project (steps 3 and 5 of `INSTALL-PROMPT.md`). With `--check` / `-Check`: report whether every rule can fire (step 6b). |
| `install.sh` / `.ps1` | Link personal skills, agents and commands into `~/.claude`. Not part of a project install. |
| `test-sandbox-install.sh` | Test the scripted part of the one-shot install in a throwaway repo. |
| `ascii-loader.sh` / `.ps1` | Lo-fi ASCII progress loader for install-style steps: animated bar, OK/FAIL checklist, and a stop-on-failure summary. `--demo` / `-Demo` simulates an install and changes nothing; `STEPS_FILE` / `-StepsFile` runs `Label \| command` lines. Tool-agnostic. |
