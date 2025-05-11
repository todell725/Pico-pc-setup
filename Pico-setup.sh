#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
MODULE_DIR="$SCRIPT_DIR/modules"

# === Auto-create .env if missing ===
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[!] .env not found. Creating with placeholder values..."
  cat << EOF > "$ENV_FILE"
SMB_USER=your_smb_username
SMB_PASS=your_smb_password
FTP_USER=your_ftp_username
FTP_PASS=your_ftp_password
EOF
  echo "[✓] Created .env. Please edit it before continuing."
fi

# === Load .env ===
set -o allexport
source "$ENV_FILE"
set +o allexport

# === Ensure modules directory exists ===
if [[ ! -d "$MODULE_DIR" ]]; then
  echo "[!] modules/ directory not found. Creating it..."
  mkdir -p "$MODULE_DIR"
  echo "#!/bin/bash" > "$MODULE_DIR/sample.sh"
  echo "echo '[!] Sample module loaded (replace with real ones).'" >> "$MODULE_DIR/sample.sh"
  chmod +x "$MODULE_DIR/sample.sh"
  echo "[✓] Created modules/sample.sh. Add your real setup modules to continue."
fi

# === Ensure critical folders exist ===
mkdir -p /opt/pico-data/mounts /opt/pico-data/docker

# === Menu System ===
function main_menu() {
  clear
  echo "=== Pico Setup Launcher ==="
  echo "0) Prepare Repos & Network"
  echo "1) Desktop Glow-Up"
  echo "2) Mount SMB Share"
  echo "3) Mount FTP Share"
  echo "4) Docker Stack"
  echo "5) Install Tailscale"
  echo "6) Utilities / Performance Tools"
  echo "7) Create Audiobookshelf Symlinks"
  echo "8) Run ALL"
  echo "9) Exit"
  echo ""
  read -rp "Choose an option: " choice
  case $choice in
    0) source "$MODULE_DIR/prepare.sh" ;;
    1) source "$MODULE_DIR/glow_up.sh" ;;
    2) source "$MODULE_DIR/smb_share.sh" ;;
    3) source "$MODULE_DIR/ftp_share.sh" ;;
    4) source "$MODULE_DIR/docker_stack.sh" ;;
    5) source "$MODULE_DIR/install_tailscale.sh" ;;
    6) source "$MODULE_DIR/utilities.sh" ;;
    7) source "$MODULE_DIR/symlinks.sh" ;;
    8)
      source "$MODULE_DIR/prepare.sh"
      source "$MODULE_DIR/glow_up.sh"
      source "$MODULE_DIR/smb_share.sh"
      source "$MODULE_DIR/ftp_share.sh"
      source "$MODULE_DIR/docker_stack.sh"
      source "$MODULE_DIR/install_tailscale.sh"
      source "$MODULE_DIR/symlinks.sh"
      ;;
    9) exit 0 ;;
    *) echo "Invalid choice"; sleep 1 ;;
  esac
  read -rp "Press Enter to return to the menu..." _
  main_menu
}

main_menu
