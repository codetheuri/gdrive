#!/bin/bash

# Google Drive Sync — Interactive Installer
# Usage: sudo ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD="\e[1m"; DIM="\e[2m"; RESET="\e[0m"
RED="\e[91m"; GREEN="\e[92m"; YELLOW="\e[93m"
BLUE="\e[94m"; MAGENTA="\e[95m"; CYAN="\e[96m"; WHITE="\e[97m"

# ── UI Helpers ────────────────────────────────────────────────────────────────
banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "    ██████╗ ██████╗ ██████╗ ██╗██╗   ██╗███████╗ "
  echo "   ██╔════╝ ██╔══██╗██╔══██╗██║██║   ██║██╔════╝ "
  echo "   ██║  ███╗██║  ██║██████╔╝██║██║   ██║█████╗   "
  echo "   ██║   ██║██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝   "
  echo "   ╚██████╔╝██████╔╝██║  ██║██║ ╚████╔╝ ███████╗ "
  echo "    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝ "
  echo -e "${RESET}${DIM}     Google Drive Sync Tool  ·  Installer v1.0${RESET}"
  echo ""
  divider
  echo ""
}

_step=0
step()    { _step=$((_step+1)); echo -e "\n${BLUE}${BOLD}  [$_step]${RESET} ${BOLD}$*${RESET}"; }
ok()      { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}   $*"; }
info()    { echo -e "  ${CYAN}→${RESET}  $*"; }
err()     { echo -e "  ${RED}✘${RESET}  $*"; }
divider() { echo -e "${DIM}  ──────────────────────────────────────────────────────────${RESET}"; }

spinner() {
  local pid=$1 msg="${2:-Please wait}"
  local sp="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏" i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}${sp:$((i%10)):1}${RESET}  ${DIM}%s...${RESET}" "$msg"
    sleep 0.08; i=$((i+1))
  done
  printf "\r\033[K"
}

ask() {
  local prompt="$1" default="$2" varname="$3"
  echo -e ""
  echo -e "  ${WHITE}${BOLD}$prompt${RESET}"
  [ -n "$default" ] && echo -e "  ${DIM}Default → ${CYAN}$default${RESET}"
  echo -ne "  ${GREEN}›${RESET} "
  read -r "$varname"
  eval "${varname}=\${${varname}:-${default}}"
}

confirm() {
  local msg="$1" default="${2:-y}"
  local hint; [[ "$default" =~ [Yy] ]] && hint="Y/n" || hint="y/N"
  echo -ne "\n  ${YELLOW}?${RESET} ${BOLD}$msg${RESET} ${DIM}[$hint]${RESET}: "
  local ans; read -r ans; ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy] ]]
}

# ── Paths ─────────────────────────────────────────────────────────────────────
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/gdrive"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log/gdrive"
SCRIPT_NAME="sync_to_gdrive.sh"
CTL_NAME="gdrive"
SERVICE_NAME="gdrive.service"
CONFIG_NAME="rclone.conf"
DEFAULT_CREDENTIALS="$SCRIPT_DIR/gdrive-cloud.json"
SYSTEM_CONFIG_FILE="$CONFIG_DIR/config.env"

# ═════════════════════════════════════════════════════════════════════════════
banner

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  err "Run this script as root:  ${BOLD}sudo ./install.sh${RESET}"
  exit 1
fi

# ── Step 1 · Base dependencies ────────────────────────────────────────────────
step "Checking base dependencies (curl, unzip)"
MISSING=""
for pkg in curl unzip; do
  if ! command -v "$pkg" &>/dev/null; then MISSING="$MISSING $pkg"; fi
done
if [ -n "$MISSING" ]; then
  info "Installing missing dependencies:$MISSING"
  (apt-get update -o APT::Update::Error-Mode=any &>/dev/null || true) &
  spinner $! "Updating package lists"
  apt-get install -y --fix-missing $MISSING &>/dev/null &
  spinner $! "Installing packages"
  ok "Packages installed"
else
  ok "All base dependencies present"
fi

# ── Step 2 · Rclone Installation ──────────────────────────────────────────────
step "Checking Rclone"
if command -v rclone &>/dev/null; then
  RCLONE_VER=$(rclone version | head -1)
  ok "Already installed — $RCLONE_VER"
else
  info "Installing Rclone via official script..."
  curl -fsSL https://rclone.org/install.sh | bash &>/dev/null &
  spinner $! "Downloading and installing rclone"
  ok "Rclone installed successfully"
fi

# ── Step 3 · Google Drive Authentication ─────────────────────────────────────
step "Google Drive Authentication"
echo ""
echo -e "  To bypass Google's 0-byte upload limit, we authenticate directly with your Google account."
echo -e "  Please follow these 3 steps on your ${BOLD}personal computer (Windows/Mac)${RESET}:"
echo -e "    1. Download rclone: ${CYAN}https://rclone.org/downloads/${RESET}"
echo -e "    2. Extract it, open a terminal/command prompt there, and run: ${BOLD}rclone authorize \"drive\"${RESET}"
echo -e "    3. After your browser login, copy the secret code starting with ${GREEN}{\"access_token\":...}${RESET}"
echo ""
echo -e "  ${WHITE}${BOLD}Paste that entire JSON block below and press Enter:${RESET}"
echo -ne "  ${GREEN}›${RESET} "
read -r USER_TOKEN

if [[ ! "$USER_TOKEN" =~ ^\{.*\}$ ]]; then
  err "Invalid token. It must be a complete JSON block starting with { and ending with }"
  exit 1
fi
ok "Token accepted"

mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$INSTALL_DIR"

# ── Step 4 · Setup Rclone config  ────────────────────────────────────────────
step "Configuring Rclone for Google Drive"
cat << EOF > "$CONFIG_DIR/$CONFIG_NAME"
[gdrive]
type = drive
scope = drive
token = $USER_TOKEN
EOF
chown www-data:www-data "$CONFIG_DIR/$CONFIG_NAME"
chmod 600 "$CONFIG_DIR/$CONFIG_NAME"
ok "Generated Rclone config at $CONFIG_DIR/$CONFIG_NAME"

# ── Step 5 · Directories & permissions ───────────────────────────────────────
step "Setting up directories and permissions"
chown www-data:www-data "$LOG_DIR"
chmod 755 "$LOG_DIR"
touch "$LOG_DIR/gdrive.log"
chown www-data:www-data "$LOG_DIR/gdrive.log"
chmod 664 "$LOG_DIR/gdrive.log"

# Rclone cache dirs setup
mkdir -p /var/www/.config/rclone /var/www/.cache/rclone
chown -R www-data:www-data /var/www/.config /var/www/.cache
chmod -R 700 /var/www/.config /var/www/.cache
ok "Directories and permissions configured"

# ── Step 6 · Test connection & list folders ──────────────────────────────────
step "Testing Google Drive connection"
FOLDER_LIST_RAW=""
(sudo -u www-data bash -c "
  rclone lsd gdrive: --config $CONFIG_DIR/$CONFIG_NAME
" > /tmp/gdrive_folders.txt 2>/tmp/gdrive_test.log) &
spinner $! "Authenticating with Google Drive..."

if [ $? -ne 0 ]; then
  warn "Could not list root folders. Make sure your account has folders."
  echo ""
  echo -e "  ${DIM}Test Log output:${RESET}"
  cat /tmp/gdrive_test.log
  echo ""
  confirm "Ignore this warning and continue setup anyway?" "y" || exit 1
else
  ok "Authentication successful"
  if [ -s /tmp/gdrive_folders.txt ]; then
    echo ""
    echo -e "  ${BOLD}Your Google Drive Folders:${RESET}"
  # rclone lsd output is like: "- 1 2023-01-01 12:00:00 -1 FolderName"
  mapfile -t FOLDERS < <(awk '{for (i=5; i<=NF; i++) printf $i " "; print ""}' /tmp/gdrive_folders.txt | sed 's/ $//')
    for i in "${!FOLDERS[@]}"; do
      echo -e "    ${DIM}[$((i+1))]${RESET}  ${CYAN}${FOLDERS[$i]}${RESET}"
    done
  fi
fi

# ── Step 7 · Configure sync pairs ────────────────────────────────────────────
step "Configure sync pairs"
echo ""
echo -e "  Map local folders → Google Drive folders."
echo -e "  Enter each sync pair, then choose to add more or continue."
echo ""

SYNC_PAIRS=()
while true; do
  divider
  PAIR_NUM=$(( ${#SYNC_PAIRS[@]} + 1 ))
  echo -e "\n  ${MAGENTA}${BOLD}Sync pair #$PAIR_NUM${RESET}"

  ask "Local folder path (absolute):" "" LOCAL_PATH_INPUT
  if [ -z "$LOCAL_PATH_INPUT" ]; then
    err "Path cannot be empty. Please try again."
    continue
  fi
  if [ ! -d "$LOCAL_PATH_INPUT" ]; then
    warn "Directory not found: $LOCAL_PATH_INPUT  (it will be validated at runtime)"
  fi

  echo ""
  if [ ${#FOLDERS[@]} -gt 0 ]; then
    echo -e "  Select a Google Drive folder (enter number) or type a custom name:"
    for i in "${!FOLDERS[@]}"; do
      echo -e "    ${DIM}[$((i+1))]${RESET}  ${CYAN}${FOLDERS[$i]}${RESET}"
    done
    echo -ne "\n  ${GREEN}›${RESET} "
    read -r FOLDER_INPUT

    # numeric selection
    if [[ "$FOLDER_INPUT" =~ ^[0-9]+$ ]] && [ "$FOLDER_INPUT" -ge 1 ] && [ "$FOLDER_INPUT" -le ${#FOLDERS[@]} ]; then
      FOLDER_CHOSEN="${FOLDERS[$((FOLDER_INPUT-1))]}"
      echo -ne "  ${WHITE}Optional: Enter a nested sub-folder path (or press Enter to leave blank):${RESET}\n  ${GREEN}›${RESET} "
      read -r SUB_INPUT
      if [ -n "$SUB_INPUT" ]; then
        SUB_INPUT="${SUB_INPUT#/}" # remove leading slash
        FOLDER_CHOSEN="$FOLDER_CHOSEN/$SUB_INPUT"
      fi
    else
      # Used custom text
      if [ -z "$FOLDER_INPUT" ]; then
        err "Folder name cannot be empty."
        continue
      fi
      FOLDER_CHOSEN="$FOLDER_INPUT"
    fi
  else
    ask "Enter Google Drive destination folder name:" "Server Backups" FOLDER_CHOSEN
  fi

  ok "${LOCAL_PATH_INPUT}  →  ${CYAN}gdrive:/$FOLDER_CHOSEN${RESET}"
  SYNC_PAIRS+=("$LOCAL_PATH_INPUT:gdrive:/$FOLDER_CHOSEN")

  confirm "Add another sync pair?" "n" || break
done

# ── Step 8 · Sync interval ───────────────────────────────────────────────────
step "Sync interval"
echo -e "  How often should the service sync? (seconds; 0 = run once and exit)"
ask "Interval in seconds:" "300" SYNC_INTERVAL
ok "Sync every ${BOLD}${SYNC_INTERVAL}s${RESET}"

# ── Step 9 · Delete flag ─────────────────────────────────────────────────────
step "Delete mode"
echo -e "  ${YELLOW}⚠${RESET}   With delete enabled, files in Google Drive that don't exist locally are ${RED}removed${RESET}."
DELETE_FLAG=""
confirm "Enable delete (strict mirror mode)?" "n" && DELETE_FLAG="--delete"
if [ -n "$DELETE_FLAG" ]; then warn "Delete mode enabled (rclone sync)"; else ok "Delete mode disabled (rclone copy)"; fi

# ── Step 10 · Build ExecStart ────────────────────────────────────────────────
step "Writing configuration files"
EXEC_ARGS=""
for PAIR in "${SYNC_PAIRS[@]}"; do
  LOCAL="${PAIR%%:*}"
  # quote remote path because GDrive folders often have spaces
  REMOTE="${PAIR#*:}"
  EXEC_ARGS="$EXEC_ARGS --local-path \"$LOCAL\" --remote-path \"$REMOTE\""
done
EXEC_ARGS="$EXEC_ARGS --interval $SYNC_INTERVAL"
[ -n "$DELETE_FLAG" ] && EXEC_ARGS="$EXEC_ARGS $DELETE_FLAG"

# Write system config to store credentials paths for CTL tool
cat << EOF > "$SYSTEM_CONFIG_FILE"
CONFIG_FILE="$CONFIG_DIR/$CONFIG_NAME"
EOF

# ── Install sync_to_gdrive.sh wrapper ────────────────────────────────────────
cat << 'SYNCEOF' > "$INSTALL_DIR/$SCRIPT_NAME"
#!/bin/bash
# sync_to_gdrive.sh — syncs multiple local folders to Google Drive via rclone
# Usage: sync_to_gdrive.sh --local-path <path> --remote-path <gdrive:/...> [--interval <s>] [--delete]

set -e

LOG_FILE="/var/log/gdrive/gdrive.log"
RCLONE="/usr/bin/rclone"
CONFIG_FILE="/etc/gdrive/rclone.conf"
INTERVAL=0
DELETE=false
PATH_PAIRS=()

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }

usage() { echo "Usage: $0 --local-path <path> --remote-path <gdrive:/...> [--interval <s>] [--delete]"; exit 1; }

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --local-path)  LOCAL_PATH="$2"; shift ;;
    --remote-path) REMOTE_PATH="$2"; PATH_PAIRS+=("$LOCAL_PATH:$REMOTE_PATH"); shift ;;
    --interval)    INTERVAL="$2"; shift ;;
    --delete)      DELETE=true ;;
    *) log "Unknown parameter: $1"; usage ;;
  esac
  shift
done

[ ${#PATH_PAIRS[@]} -eq 0 ] && { log "Error: no path pairs specified"; usage; }

for PAIR in "${PATH_PAIRS[@]}"; do
  LOCAL="${PAIR%%:*}"
  [ ! -d "$LOCAL" ] && { log "Error: local path not found: $LOCAL"; exit 1; }
done

command -v "$RCLONE" &>/dev/null || { log "Error: rclone not found at $RCLONE"; exit 1; }
[ -f "$CONFIG_FILE" ] || { log "Error: rclone config not found at $CONFIG_FILE"; exit 1; }

sync_folder() {
  local LOCAL="$1" REMOTE="$2"
  log "Syncing $LOCAL → $REMOTE"
  
  if [ "$DELETE" = true ]; then
    log "WARNING: delete mode active (mirroring) for $REMOTE"
    # use rclone sync
    if "$RCLONE" sync "$LOCAL" "$REMOTE" --config "$CONFIG_FILE" -v >> "$LOG_FILE" 2>&1; then
      log "✔ Sync done: $LOCAL → $REMOTE"
    else
      log "✘ Sync failed: $LOCAL → $REMOTE"
    fi
  else
    # use rclone copy (safe mode)
    if "$RCLONE" copy "$LOCAL" "$REMOTE" --config "$CONFIG_FILE" -v >> "$LOG_FILE" 2>&1; then
      log "✔ Copy done: $LOCAL → $REMOTE"
    else
      log "✘ Copy failed: $LOCAL → $REMOTE"
    fi
  fi
}

if [ "$INTERVAL" -gt 0 ]; then
  log "Starting continuous sync every ${INTERVAL}s"
  while true; do
    for PAIR in "${PATH_PAIRS[@]}"; do
      sync_folder "${PAIR%%:*}" "${PAIR#*:}"
    done
    sleep "$INTERVAL"
  done
else
  for PAIR in "${PATH_PAIRS[@]}"; do
    sync_folder "${PAIR%%:*}" "${PAIR#*:}"
  done
fi
SYNCEOF
chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"
ok "Installed $INSTALL_DIR/$SCRIPT_NAME"

# ── Write systemd service ─────────────────────────────────────────────────────
cat << EOF > "$SERVICE_DIR/$SERVICE_NAME"
[Unit]
Description=Google Drive Sync Service
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www
ExecStart=/usr/local/bin/$SCRIPT_NAME $EXEC_ARGS
Restart=always
RestartSec=10
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ProtectHome=false
ProtectSystem=false
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$SERVICE_DIR/$SERVICE_NAME"
ok "Wrote $SERVICE_DIR/$SERVICE_NAME"

# ── Install gdrive CLI tool ───────────────────────────────────────────────────
cp "$SCRIPT_DIR/gdrive.sh" "$INSTALL_DIR/$CTL_NAME" 2>/dev/null || true
if [ -f "$INSTALL_DIR/$CTL_NAME" ]; then
  chmod 755 "$INSTALL_DIR/$CTL_NAME"
  ok "Installed management CLI → ${CYAN}gdrive${RESET}"
fi

# ── Step 11 · Enable service ──────────────────────────────────────────────────
step "Enabling systemd service"
systemctl daemon-reload &>/dev/null
systemctl enable "$SERVICE_NAME" &>/dev/null
ok "Service enabled"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
divider
echo -e "\n  ${GREEN}${BOLD}✔ Installation complete!${RESET}\n"
echo -e "  ${BOLD}Sync pairs configured:${RESET}"
for PAIR in "${SYNC_PAIRS[@]}"; do
  echo -e "    ${CYAN}${PAIR%%:*}${RESET}  →  ${MAGENTA}${PAIR#*:}${RESET}"
done
echo -e "\n  ${BOLD}Interval:${RESET}  ${SYNC_INTERVAL}s"
echo -e "  ${BOLD}Delete:${RESET}    ${DELETE_FLAG:-disabled (using rclone copy)}"
echo -e "\n  ${BOLD}Quick commands:${RESET}"
echo -e "    ${CYAN}sudo systemctl start $SERVICE_NAME${RESET}   — start syncing"
echo -e "    ${CYAN}sudo systemctl status $SERVICE_NAME${RESET}  — check status"
echo -e "    ${CYAN}tail -f $LOG_DIR/gdrive.log${RESET}          — view logs"
echo -e "    ${CYAN}sudo gdrive${RESET}                          — management CLI"
echo ""
divider
echo ""
