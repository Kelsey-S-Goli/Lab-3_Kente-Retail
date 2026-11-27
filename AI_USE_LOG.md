# AI-use Log

**Author:** Kelsey Goli · **Lab:** SE03 Kente Retail handover · **Date:** 27 November 2026
**Tool:** Claude (Anthropic), used as a lightweight command and formatting reference.

## How I used AI, in short

I handled the repository analysis, server audit, troubleshooting, code fixes, and documentation myself. I used Claude strictly as a quick reference assistant—mainly to help structure my initial comprehension memo and to double-check Linux and Git command syntax at different stages (logging, auditing, applying fixes, and committing). **I ran every command on the server myself, diagnosed all issues from my own output, and wrote all final scripts and documentation.**

## Log

| # | Time (UTC) | What I asked | What the AI produced | What I did with it / how I checked it |
|---|---|---|---|---|
| 1 | 08:24 | Help organize my initial thoughts on the repo and policy into a clear structure | A rough outline for a comprehension memo | Used the outline as a starting point, then filled in my own analysis and verdicts after reviewing the files myself. |
| 2 | 10:15–10:48 | Syntax for recording terminal sessions and keeping SSH alive; standard Git branching workflow | Commands for `script`, SSH keep-alive flags, and creating a feature branch | Used the `script` and Git commands to log my session and commit `COMPREHENSION_MEMO.md` via a PR before touching the server. |
| 3 | 11:08–11:42 | Command to inspect my local Git remote configuration | `git remote -v` | Ran it, identified the mismatch with the assessed repo, and updated the remote URL myself. |
| 4 | 14:03 | Why my first `script` terminal log appeared empty after a connection drop | Mentioned output buffering and suggested adding `-f` (`script -af`) alongside `tmux` | Re-ran my initial audit steps with `-f` so the log flushed immediately to disk. |
| 5 | 14:25–15:17 | Read-only Linux command syntax to verify services, permissions, and cron jobs | Standard inspection commands (`systemctl`, `grep`, `crontab`, etc.) | Adapted and ran the commands on the server, capturing the output in my audit log and screenshots. |
| 6 | 15:49 | Why `sudo grep … /etc/sudoers.d/*` gave a `No such file or directory` error | Explained shell wildcard expansion before `sudo` executes and gave a subshell alternative | Ran the corrected check command on the server to verify the sudoers configuration. |
| 7 | 16:22–16:46 | Syntax check for `sed` and service-restart commands during my server fixes | Standard one-liner syntax examples | Applied my six fixes in order. When a pasted `sed` line broke across lines, I typed it cleanly myself and verified each service state. |
| 8 | 17:04–17:20 | Windows PowerShell equivalents for setting executable file permissions in Git | `git update-index --chmod=+x` | Used the command on my Windows laptop to mark my updated scripts executable before pushing my PRs. |
| 9 | 17:23–17:27 | Quick syntax for comparing configuration files before deploying | `diff` command flags | Used `diff` to verify the server configs matched my repo changes before running `deploy.sh`. |

## Decisions and work that were mine

- Reading the inherited codebase and policy PDF, diagnosing the root causes (including the 9-field health-check log bug and the 12 Nov outage timeline), and writing the comprehension memo.
- Designing the audit-first workflow and deciding what to leave untouched (such as keeping `maintenance.sh` disabled until backups exist).
- Writing all fixes for `deploy.sh`, `install_cron.sh`, `server.py`, the systemd unit, `CONTRIBUTING.md`, and the PR template, and managing every PR.
- Designing, coding, and testing the `scripts/policy_audit.sh` value-add script, as well as authoring `HANDOVER.md`, the assumptions log, and the incident note.

## What I learned about working with AI here

- **AI is best kept to syntax lookups.** Relying on it for system-specific assumptions doesn't replace reading real terminal output—for example, it assumed I was on Linux rather than Windows until I specified otherwise.
- **Keep terminal commands simple.** Pasting long one-liners from a chat window into SSH can break line endings; typing commands directly or editing files locally is much safer.