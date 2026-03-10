# shellbash
Bash scripting utilities for this repository.

## Git Auto-Push Loop (Git Bash)
This repo includes `git_auto_push.sh` for automatic commit + push in a foreground loop.

### Start
Open **Git Bash** in this repo and run:

```bash
./git_auto_push.sh
```

### Stop
Press `Ctrl+C` in the same terminal.

### Optional flags
```bash
./git_auto_push.sh --interval-sec 300
./git_auto_push.sh --log-file "$HOME/git-auto-push-shellbash.log"
./git_auto_push.sh --message-prefix "auto: sync"
```

### What it does each cycle
- Detects the currently checked-out branch.
- Stages all repo changes with `git add -A`.
- Commits only if changes exist, using a timestamped message.
- Runs `git pull --rebase origin <branch>` when the remote branch exists.
- If rebase fails, aborts rebase (when active), logs the error, and skips push for that cycle.
- Pushes normally when upstream exists; otherwise uses `git push -u origin <branch>` to set upstream.

### Defaults
- Interval: `300` seconds.
- Message prefix: `auto: sync`.
- Log file: outside repo at `$HOME/git-auto-push-<repo>.log` (or `$USERPROFILE/...` on Windows fallback).
