#!/bin/bash

# gdrive — Interactive management CLI for the Google Drive sync service
# Install: sudo cp gdrive.sh /usr/local/bin/gdrive && chmod +x /usr/local/bin/gdrive
# Usage:   sudo gdrive

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD="\e[1m"; DIM="\e[2m"; RESET="\e[0m"
RED="\e[91m"; GREEN="\e[92m"; YELLOW="\e[93m"
BLUE="\e[94m"; MAGENTA="\e[95m"; CYAN="\e[96m"; WHITE="\e[97m"

SERVICE="gdrive.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE"
CONFIG_DIR="/etc/gdrive"
CONFIG_FILE="$CONFIG_DIR/rclone.conf"
SA_FILE="$CONFIG_DIR/gdrive-cloud.json"
LOG_FILE="/var/log/gdrive/gdrive.log"
RCLONE="/usr/bin/rclone"

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Run as root:${RESET} sudo gdrive"
  exit 1
fi

# ── UI Helpers ────────────────────────────────────────────────────────────────
clear_screen() { clear; }
divider()      { echo -e "${DIM}  ──────────────────────────────────────────────────────────${RESET}"; }
ok()           { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()         { echo -e "  ${YELLOW}⚠${RESET}   $*"; }
info()         { echo -e "  ${CYAN}→${RESET}  $*"; }
err()          { echo -e "  ${RED}✘${RESET}  $*"; }

press_enter() {
  echo ""
  echo -ne "  ${DIM}Press Enter to continue...${RESET}"
  read -r
}

banner() {
  clear_screen
  echo -e "${CYAN}${BOLD}"
  echo "    ██████╗ ██████╗ ██████╗ ██╗██╗   ██╗███████╗ "
  echo "   ██╔════╝ ██╔══██╗██╔══██╗██║██║   ██║██╔════╝ "
  echo "   ██║  ███╗██║  ██║██████╔╝██║██║   ██║█████╗   "
  echo "   ██║   ██║██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝   "
  echo "   ╚██████╔╝██████╔╝██║  ██║██║ ╚████╔╝ ███████╗ "
  echo "    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝ "
  echo -e "${RESET}${DIM}     Google Drive Sync Tool  ·  Management CLI${RESET}"
  echo ""
}

# ── Service status helpers ────────────────────────────────────────────────────
service_status_color() {
  local status
  status=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "inactive")
  case "$status" in
    active)   echo -e "${GREEN}${BOLD}● active${RESET}" ;;
    inactive) echo -e "${RED}○ inactive${RESET}" ;;
    failed)   echo -e "${RED}${BOLD}✘ failed${RESET}" ;;
    *)        echo -e "${YELLOW}~ $status${RESET}" ;;
  esac
}

service_enabled_color() {
  local enabled
  enabled=$(systemctl is-enabled "$SERVICE" 2>/dev/null || echo "disabled")
  case "$enabled" in
    enabled)  echo -e "${GREEN}enabled${RESET}" ;;
    disabled) echo -e "${YELLOW}disabled${RESET}" ;;
    *)        echo -e "${DIM}$enabled${RESET}" ;;
  esac
}

# ── Parse sync pairs from service file ───────────────────────────────────────
get_sync_pairs() {
  if [ ! -f "$SERVICE_FILE" ]; then echo ""; return; fi
  # Parses `--local-path "X" --remote-path "Y"`
  grep -oP '(?<=--local-path ")[^"]+' "$SERVICE_FILE" > /tmp/locals.txt || true
  grep -oP '(?<=--remote-path ")[^"]+' "$SERVICE_FILE" > /tmp/remotes.txt || true
  if [ -s /tmp/locals.txt ] && [ -s /tmp/remotes.txt ]; then
    paste /tmp/locals.txt /tmp/remotes.txt -d':'
  fi
}

get_exec_start() {
  grep "^ExecStart=" "$SERVICE_FILE" 2>/dev/null | sed 's/^ExecStart=//'
}

# ── Dashboard ─────────────────────────────────────────────────────────────────
show_dashboard() {
  banner
  divider
  echo ""

  # Service info
  echo -e "  ${BOLD}Service status${RESET}"
  echo -e "    Status:   $(service_status_color)"
  echo -e "    Boot:     $(service_enabled_color)"

  # Last log line
  if [ -f "$LOG_FILE" ]; then
    LAST_LOG=$(tail -1 "$LOG_FILE" 2>/dev/null)
    echo -e "    Last log: ${DIM}${LAST_LOG:-—}${RESET}"
  fi
  echo ""

  # Sync pairs
  echo -e "  ${BOLD}Sync pairs${RESET}"
  PAIRS=$(get_sync_pairs)
  if [ -z "$PAIRS" ]; then
    echo -e "    ${DIM}No sync pairs configured.${RESET}"
  else
    while IFS= read -r pair; do
      local_path="${pair%%:*}"
      remote_path="${pair#*:}"
      STATUS_ICON="${GREEN}✔${RESET}"
      [ ! -d "$local_path" ] && STATUS_ICON="${YELLOW}?${RESET}"
      echo -e "    $STATUS_ICON ${CYAN}$local_path${RESET}  →  ${MAGENTA}$remote_path${RESET}"
    done <<< "$PAIRS"
  fi
  echo ""

  # Config info
  if [ -f "$CONFIG_FILE" ]; then
    echo -e "  ${BOLD}Configuration${RESET}"
    echo -e "    Rclone config: ${DIM}$CONFIG_FILE${RESET}"
    echo -e "    Auth method:   ${DIM}Web OAuth Token${RESET}"
    echo ""
  fi
  divider
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    show_dashboard
    echo -e "\n  ${BOLD}${WHITE}What would you like to do?${RESET}\n"
    echo -e "    ${CYAN}[1]${RESET}  Start service"
    echo -e "    ${CYAN}[2]${RESET}  Stop service"
    echo -e "    ${CYAN}[3]${RESET}  Restart service"
    echo -e "    ${CYAN}[4]${RESET}  View live logs"
    echo -e "    ${CYAN}[5]${RESET}  Add sync pair"
    echo -e "    ${CYAN}[6]${RESET}  Remove sync pair"
    echo -e "    ${CYAN}[7]${RESET}  Run manual sync now"
    echo -e "    ${CYAN}[8]${RESET}  Full service status (systemctl)"
    echo -e "    ${RED}[0]${RESET}  Exit"
    echo ""
    echo -ne "  ${GREEN}›${RESET} "
    read -r choice

    case "$choice" in
      1) do_start ;;
      2) do_stop ;;
      3) do_restart ;;
      4) do_logs ;;
      5) do_add_pair ;;
      6) do_remove_pair ;;
      7) do_manual_sync ;;
      8) do_systemctl_status ;;
      0) echo -e "\n  ${DIM}Goodbye.${RESET}\n"; exit 0 ;;
      *) warn "Unknown option, try again." ;;
    esac
  done
}

# ── Actions ───────────────────────────────────────────────────────────────────
do_start() {
  echo ""
  if systemctl start "$SERVICE" 2>/dev/null; then
    ok "Service started"
  else
    err "Failed to start service"
    systemctl status "$SERVICE" --no-pager 2>&1 | tail -10
  fi
  press_enter
}

do_stop() {
  echo ""
  if systemctl stop "$SERVICE" 2>/dev/null; then
    ok "Service stopped"
  else
    err "Failed to stop service"
  fi
  press_enter
}

do_restart() {
  echo ""
  systemctl daemon-reload &>/dev/null
  if systemctl restart "$SERVICE" 2>/dev/null; then
    ok "Service restarted"
  else
    err "Failed to restart service"
    systemctl status "$SERVICE" --no-pager 2>&1 | tail -10
  fi
  press_enter
}

do_logs() {
  echo ""
  echo -e "  ${DIM}Streaming live logs — press ${BOLD}Ctrl+C${RESET}${DIM} to return to menu${RESET}\n"
  divider
  trap 'echo ""; return' INT
  tail -n 40 -f "$LOG_FILE" 2>/dev/null || echo "  Log file not found: $LOG_FILE"
  trap - INT
}

do_systemctl_status() {
  echo ""
  divider
  systemctl status "$SERVICE" --no-pager 2>&1
  divider
  press_enter
}

do_add_pair() {
  echo ""
  echo -e "  ${BOLD}Add a sync pair${RESET}\n"

  echo -ne "  ${WHITE}Local folder path (absolute):${RESET}\n  ${GREEN}›${RESET} "
  read -r NEW_LOCAL
  if [ -z "$NEW_LOCAL" ]; then
    err "Path cannot be empty. Please try again."
    press_enter; return
  fi
  if [ ! -d "$NEW_LOCAL" ]; then
    warn "Directory does not exist: $NEW_LOCAL"
    echo -ne "  Continue anyway? [y/N] "
    read -r ans; [[ ! "$ans" =~ ^[Yy] ]] && return
  fi

  # List available buckets via rclone
  echo ""
  echo -e "  ${DIM}Fetching shared Google Drive folders...${RESET}"
  AVAIL_FOLDERS=$("$RCLONE" lsd gdrive: --config "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$AVAIL_FOLDERS" ]; then
    echo ""
    echo -e "  ${BOLD}Available Folders:${RESET}"
    mapfile -t FLIST < <(awk '{for (i=5; i<=NF; i++) printf $i " "; print ""}' <<< "$AVAIL_FOLDERS" | sed 's/ $//')
    for i in "${!FLIST[@]}"; do
      echo -e "    ${DIM}[$((i+1))]${RESET}  ${CYAN}${FLIST[$i]}${RESET}"
    done
    echo ""
    echo -ne "  Select number or type custom name:\n  ${GREEN}›${RESET} "
    read -r FOLDER_INPUT
    
    if [[ "$FOLDER_INPUT" =~ ^[0-9]+$ ]] && [ "$FOLDER_INPUT" -ge 1 ] && [ "$FOLDER_INPUT" -le "${#FLIST[@]}" ]; then
      NEW_REMOTE="gdrive:/${FLIST[$((FOLDER_INPUT-1))]}"
      echo -ne "  ${WHITE}Optional: Enter a nested sub-folder path (or press Enter to leave blank):${RESET}\n  ${GREEN}›${RESET} "
      read -r SUB_INPUT
      if [ -n "$SUB_INPUT" ]; then
        SUB_INPUT="${SUB_INPUT#/}"
        NEW_REMOTE="$NEW_REMOTE/$SUB_INPUT"
      fi
    else
      if [ -z "$FOLDER_INPUT" ]; then
        err "Folder name cannot be empty."
        press_enter; return
      fi
      NEW_REMOTE="gdrive:/$FOLDER_INPUT"
    fi
  else
    echo -ne "\n  Enter Google Drive destination folder name:\n  ${GREEN}›${RESET} "
    read -r NEW_FOLDER
    if [ -z "$NEW_FOLDER" ]; then
      err "Folder name cannot be empty."
      press_enter; return
    fi
    NEW_REMOTE="gdrive:/$NEW_FOLDER"
  fi

  ok "Adding pair: ${CYAN}$NEW_LOCAL${RESET}  →  ${MAGENTA}$NEW_REMOTE${RESET}"

  # Append to ExecStart in service file (quoted)
  CURRENT_EXEC=$(get_exec_start)
  NEW_EXEC="$CURRENT_EXEC --local-path \"$NEW_LOCAL\" --remote-path \"$NEW_REMOTE\""
  sed -i "s|^ExecStart=.*|ExecStart=$NEW_EXEC|" "$SERVICE_FILE"

  systemctl daemon-reload
  ok "Service file updated. Restart to apply changes."
  echo -ne "\n  Restart now? [Y/n] "
  read -r ans
  [[ "${ans:-y}" =~ ^[Yy] ]] && do_restart || press_enter
}

do_remove_pair() {
  echo ""
  echo -e "  ${BOLD}Remove a sync pair${RESET}\n"

  PAIRS=$(get_sync_pairs)
  if [ -z "$PAIRS" ]; then
    warn "No sync pairs configured."
    press_enter; return
  fi

  mapfile -t PAIR_ARRAY <<< "$PAIRS"
  for i in "${!PAIR_ARRAY[@]}"; do
    local_p="${PAIR_ARRAY[$i]%%:*}"
    remote_p="${PAIR_ARRAY[$i]#*:}"
    echo -e "    ${DIM}[$((i+1))]${RESET}  ${CYAN}$local_p${RESET}  →  ${MAGENTA}$remote_p${RESET}"
  done
  echo ""
  echo -ne "  Select pair to remove (number):\n  ${GREEN}›${RESET} "
  read -r IDX

  if [[ "$IDX" =~ ^[0-9]+$ ]] && [ "$IDX" -ge 1 ] && [ "$IDX" -le "${#PAIR_ARRAY[@]}" ]; then
    REMOVE_PAIR="${PAIR_ARRAY[$((IDX-1))]}"
    RM_LOCAL="${REMOVE_PAIR%%:*}"
    RM_REMOTE="${REMOVE_PAIR#*:}"

    CURRENT_EXEC=$(get_exec_start)
    NEW_EXEC=$(echo "$CURRENT_EXEC" | sed "s| --local-path \"$RM_LOCAL\" --remote-path \"$RM_REMOTE\"||g")
    sed -i "s|^ExecStart=.*|ExecStart=$NEW_EXEC|" "$SERVICE_FILE"

    systemctl daemon-reload
    ok "Removed: ${CYAN}$RM_LOCAL${RESET}  →  ${MAGENTA}$RM_REMOTE${RESET}"
    echo -ne "\n  Restart service now? [Y/n] "
    read -r ans
    [[ "${ans:-y}" =~ ^[Yy] ]] && do_restart || press_enter
  else
    warn "Invalid selection."
    press_enter
  fi
}

do_manual_sync() {
  echo ""
  echo -e "  ${DIM}Running one-off sync for all pairs...${RESET}\n"

  EXEC_LINE=$(get_exec_start | sed 's|--interval [0-9]*||g' | sed 's|/usr/local/bin/sync_to_gdrive.sh||')
  if [ -z "$EXEC_LINE" ]; then
    warn "No sync configuration found in $SERVICE_FILE"
    press_enter; return
  fi

  PAIRS=$(get_sync_pairs)
  if [ -z "$PAIRS" ]; then
    warn "No sync pairs configured."
    press_enter; return
  fi

  eval /usr/local/bin/sync_to_gdrive.sh $EXEC_LINE --interval 0 2>&1 | tail -20 && ok "Manual sync complete" || err "Sync encountered errors — see $LOG_FILE"
  press_enter
}

# ── Entry point ───────────────────────────────────────────────────────────────
main_menu
