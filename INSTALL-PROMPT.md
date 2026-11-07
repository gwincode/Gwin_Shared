# One-shot install: Gwin shared rules + agent pipeline

Supports: Claude Code (Desktop Code tab or CLI), Windows, macOS or Linux.

**You need:** git; Python 3; a GitHub account with read access to
`gwincode/gwin-claude-agent-pipeline-kit` (that repo is private: ask the owner to add you; `gwincode/Gwin_Shared`
is public); and a project folder that is a git repo with a GitHub remote.

**How to use:** open Claude Code in your project's root folder, start a new session, and paste everything
between the two lines below. Claude asks you one set of questions, shows every change before it writes it,
and commits nothing until you say so. When it finishes, start a new session so the new settings load.

---

Install the Gwin shared rules and the agent pipeline kit in this repository, in one pass.
Write every reply in ASD-STE100 Simplified Technical English: short sentences, simple words, one
instruction per sentence, active voice. Keep code, commands and file names exact.

**Ground rules for this whole install**
- Show me each change before you write it. Never overwrite or delete anything I did not approve.
- Never write a secret, token, password or API key into any file, and never ask me for one.
- Do not commit or push until step 7, and then only if I say yes.
- Do not run `/feature`, `/discover`, `/promote` or any subagent. Installing is copying files.
- Keep `Gwin_Shared` and the kit outside this repo's tracked files, except where a step says otherwise.

**1. Check the repo.** Confirm this folder is the root of a git repo (`git rev-parse --show-toplevel`) and
that it has a GitHub remote (`git remote -v`). If it is not a git repo, or it has no GitHub remote, stop and
tell me: the rules and agents will then work only on this computer, because Claude cloud sessions and other
computers get them from GitHub. Ask whether to continue anyway. Run `git status`. If there are uncommitted
changes, list them and ask whether to continue. Note the branches (`git branch -r`).

**2. Get the sources.** Use the folder that contains this repo as the parent (for example `C:\code` or
`~/code`).
- `Gwin_Shared`: if `<parent>/Gwin_Shared` exists and is a clone of `gwincode/Gwin_Shared`, run `git pull`
  there. If not, clone `https://github.com/gwincode/Gwin_Shared.git` to `<parent>/Gwin_Shared`. If the clone
  fails, stop and tell me the error.
- The kit: clone `https://github.com/gwincode/gwin-claude-agent-pipeline-kit.git` to a temporary folder
  outside this repo. If the clone fails with "not found" or an access error, stop and tell me to ask the owner
  for access to the kit. Copy its `pipeline-kit/` folder into this repo's root (the kit's install expects it
  there). Do not commit `pipeline-kit/`.

**3. Preview the shared rules.** Run the `gwinrules` preview from `<parent>/Gwin_Shared/scripts/`:
`gwinrules.ps1` on Windows, `gwinrules.sh` on macOS or Linux, with no apply flag. Keep its output for step 4.

**4. Prepare the pipeline install.** Open `pipeline-kit/INSTALL-PROMPT.md` and follow its steps 1 to 4
exactly (read the kit, detect what you can, scan the project commands). Then send me **one message** with:
- the `gwinrules` preview from step 3, in plain words (which files it adds, and the block it adds to
  `CLAUDE.md`);
- every question from the kit's step 3 interview, with your proposed values;
- the kit's step 4d summary of project commands.
Wait for my answer. Ask again only if an answer contradicts another.

**5. Install the shared rules.** Run `gwinrules` again with `-Apply` (PowerShell) or `--apply` (shell).

**6. Install the pipeline.** Follow steps 5 to 8 of `pipeline-kit/INSTALL-PROMPT.md` exactly. The shared-rules
block that step 5 added to `CLAUDE.md` stays where it is; append the pipeline block after it.

**7. Report and finish.**
- Report in the shape of the kit's step 9, plus: the shared-rule files installed and their stamp
  (`gwincode/Gwin_Shared@<commit>`).
- Ask whether to remove the `pipeline-kit/` copy from this repo. Remove it only on a yes.
- Ask whether to commit. On a yes: create a new branch `claude/install-gwin-rules-and-pipeline` off the
  staging branch (or the default branch if there is no staging branch), commit only the installed files,
  push that branch, and open a PR against the same base. Never push to the production branch. Do not
  merge the PR.
- Tell me to start a new Claude Code session, then to run `/agents` and `/status` to check the install.

---

## To update later

- **Shared rules:** run `git pull` in `Gwin_Shared`, then run `gwinrules` (preview, then apply) in each
  project and commit the result.
- **Pipeline:** follow the kit's own update notes in its README.
