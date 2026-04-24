#!/bin/bash
# sync_to_gdrive.sh — syncs multiple local folders to Google Drive via rclone
# Usage: sync_to_gdrive.sh --local-path <path> --remote-path <gdrive:/...> --pair-mode <copy|mirror> [--interval <s>]

LOG_FILE="/var/log/gdrive/gdrive.log"
RCLONE="/usr/bin/rclone"
CONFIG_FILE="/etc/gdrive/rclone.conf"
INTERVAL=0
PATH_PAIRS=()

# Per-pair state machine
PENDING_LOCAL=""
PENDING_REMOTE=""
PENDING_MODE="copy"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }
usage() { echo "Usage: $0 --local-path <path> --remote-path <gdrive:/...> [--pair-mode copy|mirror] [--interval <s>]"; exit 1; }

commit_pair() {
  local mode="${1:-copy}"
  if [ -n "$PENDING_LOCAL" ] && [ -n "$PENDING_REMOTE" ]; then
    PATH_PAIRS+=("$PENDING_LOCAL|$PENDING_REMOTE|$mode")
  fi
  PENDING_LOCAL=""
  PENDING_REMOTE=""
  PENDING_MODE="copy"
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --local-path)  commit_pair "$PENDING_MODE"; PENDING_LOCAL="$2"; shift ;;
    --remote-path) PENDING_REMOTE="$2"; shift ;;
    --pair-mode)   PENDING_MODE="$2"; shift ;;
    --interval)    INTERVAL="$2"; shift ;;
    --delete)      PENDING_MODE="mirror" ;;   # backward compat
    *) log "Unknown parameter: $1"; usage ;;
  esac
  shift
done
commit_pair "$PENDING_MODE"

[ ${#PATH_PAIRS[@]} -eq 0 ] && { log "Error: no path pairs specified"; usage; }

for PAIR in "${PATH_PAIRS[@]}"; do
  LOCAL="${PAIR%%|*}"
  [ ! -d "$LOCAL" ] && { log "Error: local path not found: $LOCAL"; exit 1; }
done

command -v "$RCLONE" &>/dev/null || { log "Error: rclone not found at $RCLONE"; exit 1; }
[ -f "$CONFIG_FILE" ] || { log "Error: rclone config not found at $CONFIG_FILE"; exit 1; }

sync_folder() {
  local LOCAL="$1" REMOTE="$2" MODE="${3:-copy}"
  log "Syncing $LOCAL → $REMOTE [mode: $MODE]"

  local OUTPUT
  if [ "$MODE" = "mirror" ]; then
    log "WARNING: delete mode active (mirroring) for $REMOTE"
    if OUTPUT=$("$RCLONE" sync "$LOCAL" "$REMOTE" --config "$CONFIG_FILE" -v 2>&1); then
      echo "$OUTPUT" >> "$LOG_FILE"
      log "✔ Sync done: $LOCAL → $REMOTE"
    else
      echo "$OUTPUT" >> "$LOG_FILE"
      log "✘ Sync failed: $LOCAL → $REMOTE"
      echo "$OUTPUT" | grep "ERROR :" | while IFS= read -r line; do
        FAILED_MSG=$(echo "$line" | sed 's/.*ERROR : //')
        log "  - Failed: $FAILED_MSG"
      done
    fi
  else
    if OUTPUT=$("$RCLONE" copy "$LOCAL" "$REMOTE" --config "$CONFIG_FILE" -v 2>&1); then
      echo "$OUTPUT" >> "$LOG_FILE"
      log "✔ Copy done: $LOCAL → $REMOTE"
    else
      echo "$OUTPUT" >> "$LOG_FILE"
      log "✘ Copy failed: $LOCAL → $REMOTE"
      echo "$OUTPUT" | grep "ERROR :" | while IFS= read -r line; do
        FAILED_MSG=$(echo "$line" | sed 's/.*ERROR : //')
        log "  - Failed: $FAILED_MSG"
      done
    fi
  fi
}

if [ "$INTERVAL" -gt 0 ]; then
  log "Starting continuous sync every ${INTERVAL}s"
  while true; do
    for PAIR in "${PATH_PAIRS[@]}"; do
      LOCAL="${PAIR%%|*}"
      rest="${PAIR#*|}"
      REMOTE="${rest%|*}"
      MODE="${rest##*|}"
      sync_folder "$LOCAL" "$REMOTE" "$MODE"
    done
    sleep "$INTERVAL"
  done
else
  for PAIR in "${PATH_PAIRS[@]}"; do
    LOCAL="${PAIR%%|*}"
    rest="${PAIR#*|}"
    REMOTE="${rest%|*}"
    MODE="${rest##*|}"
    sync_folder "$LOCAL" "$REMOTE" "$MODE"
  done
fi
