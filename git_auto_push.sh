#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
INTERVAL_SEC=300
MESSAGE_PREFIX="auto: sync"
LOG_FILE=""

print_usage() {
  cat <<EOF
Usage:
  ./$SCRIPT_NAME [--interval-sec N] [--log-file PATH] [--message-prefix TEXT]

Options:
  --interval-sec N        Loop interval in seconds (default: 300)
  --log-file PATH         Log file path (default: \$HOME/git-auto-push-<repo>.log)
  --message-prefix TEXT   Commit message prefix (default: "auto: sync")
  -h, --help              Show this help and exit
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval-sec)
      [[ $# -ge 2 ]] || fail "--interval-sec requires a value"
      INTERVAL_SEC="$2"
      shift 2
      ;;
    --interval-sec=*)
      INTERVAL_SEC="${1#*=}"
      shift
      ;;
    --log-file)
      [[ $# -ge 2 ]] || fail "--log-file requires a value"
      LOG_FILE="$2"
      shift 2
      ;;
    --log-file=*)
      LOG_FILE="${1#*=}"
      shift
      ;;
    --message-prefix)
      [[ $# -ge 2 ]] || fail "--message-prefix requires a value"
      MESSAGE_PREFIX="$2"
      shift 2
      ;;
    --message-prefix=*)
      MESSAGE_PREFIX="${1#*=}"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

[[ "$INTERVAL_SEC" =~ ^[1-9][0-9]*$ ]] || fail "--interval-sec must be a positive integer"

command -v git >/dev/null 2>&1 || fail "git is not installed or not in PATH"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a Git repository"
cd "$REPO_ROOT" || fail "unable to enter repository root: $REPO_ROOT"

git remote get-url origin >/dev/null 2>&1 || fail "remote 'origin' is not configured"

INITIAL_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || fail "detached HEAD is not supported"

REPO_NAME="$(basename "$REPO_ROOT")"
if [[ -z "$LOG_FILE" ]]; then
  HOME_DIR="${HOME:-${USERPROFILE:-$REPO_ROOT}}"
  LOG_FILE="$HOME_DIR/git-auto-push-$REPO_NAME.log"
fi

mkdir -p "$(dirname "$LOG_FILE")" || fail "unable to create log directory for: $LOG_FILE"
touch "$LOG_FILE" || fail "unable to write log file: $LOG_FILE"

log() {
  local timestamp line
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  line="[$timestamp] $*"
  printf '%s\n' "$line" | tee -a "$LOG_FILE"
}

has_upstream() {
  git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1
}

remote_branch_exists() {
  local branch="$1"
  git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
}

rebase_in_progress() {
  local rebase_merge rebase_apply
  rebase_merge="$(git rev-parse --git-path rebase-merge)"
  rebase_apply="$(git rev-parse --git-path rebase-apply)"
  [[ -d "$rebase_merge" || -d "$rebase_apply" ]]
}

run_cycle() {
  local branch commit_message output

  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
    log "Detached HEAD detected; skipping this cycle."
    return
  }

  log "Cycle started on branch '$branch'."

  if ! output="$(git add -A 2>&1)"; then
    log "git add failed: $output"
    return
  fi

  if git diff --cached --quiet; then
    log "No staged changes detected; skipping commit."
  else
    commit_message="$MESSAGE_PREFIX $(date '+%Y-%m-%d %H:%M')"
    if output="$(git commit -m "$commit_message" 2>&1)"; then
      log "Created commit: $commit_message"
    else
      log "git commit failed: $output"
      return
    fi
  fi

  if remote_branch_exists "$branch"; then
    if output="$(git pull --rebase origin "$branch" 2>&1)"; then
      log "Rebase pull completed from origin/$branch."
    else
      log "Rebase pull failed for '$branch': $output"
      if rebase_in_progress; then
        if output="$(git rebase --abort 2>&1)"; then
          log "Aborted in-progress rebase."
        else
          log "Rebase abort failed: $output"
        fi
      fi
      log "Skipping push for this cycle."
      return
    fi
  else
    log "Remote branch origin/$branch does not exist yet; skipping pull --rebase."
  fi

  if has_upstream; then
    if output="$(git push 2>&1)"; then
      log "Push completed for '$branch'."
    else
      log "git push failed for '$branch': $output"
    fi
  else
    if output="$(git push -u origin "$branch" 2>&1)"; then
      log "Push completed and upstream set for '$branch'."
    else
      log "git push -u failed for '$branch': $output"
    fi
  fi
}

trap 'log "Received interrupt signal. Stopping auto-push loop."; exit 0' INT TERM

log "Starting auto-push loop."
log "Repository: $REPO_ROOT"
log "Initial branch: $INITIAL_BRANCH"
log "Interval: ${INTERVAL_SEC}s"
log "Log file: $LOG_FILE"

while true; do
  run_cycle
  sleep "$INTERVAL_SEC"
done
