# scripts

See the root [README](../README.md) for what belongs here.

| Script | Use |
| --- | --- |
| `gwinrules.sh` / `.ps1` | Copy the shared rules into a project (steps 3 and 5 of `INSTALL-PROMPT.md`). With `--check` / `-Check`: report whether every rule can fire (step 6b). |
| `install.sh` / `.ps1` | Link personal skills, agents and commands into `~/.claude`, and install the token status line from `plugins/cc-token-statusline` (skip with `--no-statusline` / `-NoStatusline`). `--loader` / `-Loader` shows progress with the ASCII loader instead of the plain list. Not part of a project install. |
| `test-sandbox-install.sh` | Test the scripted part of the one-shot install in a throwaway repo. |
| `ascii-loader.sh` / `.ps1` | Lo-fi ASCII progress loader for install-style steps: animated bar, OK/SKIP/FAIL checklist, and a stop-on-failure summary. `--demo` / `-Demo` simulates an install and changes nothing; `STEPS_FILE` / `-StepsFile` runs `Label \| command` lines (a line without ` \| ` is rejected before anything runs). Tool-agnostic. |
| `ascii-loader-lib.sh` / `.ps1` | The loader as a library, sourced by `ascii-loader` and `install --loader`. API: `loader_init` / `loader_step` / `loader_done` (shell) and `Initialize-Loader` / `Invoke-LoaderStep` / `Invoke-LoaderBlock` / `Complete-Loader` (PowerShell). Not run directly. |
