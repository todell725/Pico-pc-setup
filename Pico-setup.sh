#!/bin/bash
set -e

# === DietPi Compatibility Header ===
if [[ -f /boot/dietpi/.version ]]; then
  echo "[✓] DietPi detected — applying compatibility settings..."
  DISABLE_SWAP_SETUP=true
  DISABLE_TRIM=true
  DISABLE_DOCKER_RESET=false
  if [[ -x /usr/sbin/dietpi-software ]]; then
    echo "[*] Recommended: use dietpi-software for installing Docker, XFCE, etc."
    echo "    Run: sudo dietpi-software"
  fi
else
  echo "[!] Not a DietPi system — aborting for safety."
  exit 1
fi

# === Load environment file if present ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[!] .env not found. Creating template..."
  cat << EOF > "$ENV_FILE"
SMB_USER=your_smb_username
SMB_PASS=your_smb_password
FTP_USER=your_ftp_username
FTP_PASS=your_ftp_password
SMB_HOST=192.168.68.116
FTP_HOST=nl88.seedit4.me:52404
EOF
  echo "[✓] .env created. Please fill it out and rerun the script."
  exit 1
fi

set -o allexport
source "$ENV_FILE"
set +o allexport

# === Paths ===
BASE_DIR="/opt/pico-data"
MOUNT_DIR="$BASE_DIR/mounts"
SMB_MOUNT="$MOUNT_DIR/audiobooks"
FTP_MOUNT="$MOUNT_DIR/seedbox"
SHARE_CREDENTIALS="/etc/smbcred-books"
FTP_CREDENTIALS="/etc/ftpcred-seedbox"
DASHY_DIR="$BASE_DIR/docker/dashy"

mkdir -p "$SMB_MOUNT" "$FTP_MOUNT" "$DASHY_DIR" /opt/books-writeable /opt/books-merged

# === Functions ===
function smb_share() {
  echo -e "username=$SMB_USER\npassword=$SMB_PASS" | sudo tee "$SHARE_CREDENTIALS"
  sudo chmod 600 "$SHARE_CREDENTIALS"
  sudo mount -t cifs "//$SMB_HOST/Data/books" "$SMB_MOUNT" -o credentials="$SHARE_CREDENTIALS",iocharset=utf8,vers=3.0,_netdev,nofail || echo "[!] SMB mount failed"
  grep -q "$SMB_MOUNT" /etc/fstab || echo "//$SMB_HOST/Data/books $SMB_MOUNT cifs credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0,_netdev,nofail 0 0" | sudo tee -a /etc/fstab
}

function ftp_share() {
  echo -e "$FTP_USER\n$FTP_PASS" | sudo tee "$FTP_CREDENTIALS"
  sudo chmod 600 "$FTP_CREDENTIALS"
  sudo curlftpfs -o "user=${FTP_USER}:${FTP_PASS},_netdev,nofail" "$FTP_HOST" "$FTP_MOUNT" || echo "[!] FTP mount failed"
  grep -q "$FTP_MOUNT" /etc/fstab || echo "curlftpfs#$FTP_HOST $FTP_MOUNT fuse user=$FTP_USER:$FTP_PASS,_netdev,nofail 0 0" | sudo tee -a /etc/fstab
}

function docker_stack() {
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo docker volume create portainer_data
  sudo docker run -d --name portainer --restart=always -p 9000:9000 \
    -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce

  mkdir -p "$DASHY_DIR"
  cat << EOF > "$DASHY_DIR/docker-compose.yml"
version: '3.8'
services:
  dashy:
    image: lissy93/dashy
    container_name: dashy
    restart: always
    ports:
      - 8080:80
    volumes:
      - ./conf.yml:/app/public/conf.yml
  audiobookshelf:
    image: ghcr.io/advplyr/audiobookshelf
    container_name: audiobookshelf
    restart: always
    ports:
      - 13378:80
    volumes:
      - $SMB_MOUNT:/audiobooks
      - $BASE_DIR/docker/audiobookshelf/config:/config
      - $BASE_DIR/docker/audiobookshelf/metadata:/metadata
  filebrowser:
    image: filebrowser/filebrowser
    container_name: filebrowser
    restart: always
    ports:
      - 8081:80
    volumes:
      - $BASE_DIR:/srv
      - /opt/books-merged:/srv/books-merged
EOF

  cat << EOF > "$DASHY_DIR/conf.yml"
appConfig:
  title: "pico-pc Dashboard"
  theme: colorful
  layout: auto
  showStats: true
  statusCheck: true
pages:
  - name: Home
    items:
      - title: Portainer
        icon: docker
        url: http://localhost:9000
      - title: Audiobookshelf
        icon: book
        url: http://localhost:13378
      - title: FileBrowser
        icon: folder
        url: http://localhost:8081
      - title: Books (Writeable)
        icon: folder
        url: http://localhost:8081/books-merged/write
      - title: Books (Read-Only)
        icon: folder
        url: http://localhost:8081/books-merged/media
EOF

  cd "$DASHY_DIR"
  sudo docker compose up -d
}

function install_tailscale() {
  sudo apt install -y tailscale
  echo "[!] Run 'sudo tailscale up' to authenticate."
}

function utilities_menu() {
  clear
  echo "=== Utilities ==="
  echo "1) Docker Reset & Reinstall"
  echo "2) Emergency FSTAB Cleanup"
  echo "3) Create 24GB Swapfile"
  echo "4) Enable TRIM"
  echo "5) Apply SSD Mount Tweaks"
  echo "6) Swappiness Tuner"
  echo "7) Back"
  read -rp "Choose: " u
  case $u in
    1) docker_reset ;;
    2) emergency_fstab_fix ;;
    3) [[ "$DISABLE_SWAP_SETUP" == true ]] && echo "[!] Swap disabled on DietPi." || create_swap ;;
    4) [[ "$DISABLE_TRIM" == true ]] && echo "[!] TRIM disabled on DietPi." || sudo fstrim -v / ;;
    5) sudo sed -i 's/errors=remount-ro/defaults,noatime,nodiratime,discard,commit=60,_netdev,nofail/' /etc/fstab ;;
    6) swappiness_tuner ;;
    7) return ;;
    *) echo "Invalid"; sleep 1 ;;
  esac
  read -rp "Press enter to return..." _
  utilities_menu
}

function create_swap() {
  sudo swapoff -a
  sudo rm -f /swapfile
  sudo fallocate -l 24G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
}

function swappiness_tuner() {
  echo "1) 10 (SSD safe)"
  echo "2) 60 (default)"
  echo "3) 100 (aggressive)"
  echo "4) View current"
  read -rp "Select: " s
  case $s in
    1) sudo sysctl vm.swappiness=10; echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf ;;
    2) sudo sysctl vm.swappiness=60; echo 'vm.swappiness=60' | sudo tee -a /etc/sysctl.conf ;;
    3) sudo sysctl vm.swappiness=100; echo 'vm.swappiness=100' | sudo tee -a /etc/sysctl.conf ;;
    4) cat /proc/sys/vm/swappiness ;;
  esac
}

function docker_reset() {
  if [[ "$DISABLE_DOCKER_RESET" == true ]]; then
    echo "[!] Docker reset disabled for DietPi."
    return
  fi
  sudo systemctl stop docker || true
  sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker
}

function emergency_fstab_fix() {
  sudo cp /etc/fstab /etc/fstab.bak.$(date +%s)
  sudo sed -i '/curlftpfs\\|cifs/ s/^/#/' /etc/fstab
  echo "[✓] Commented out problematic lines."
}

function symlink_creation() {
  echo "[*] Creating Audiobookshelf symlink structure..."
  sudo rm -f /opt/books-merged/media /opt/books-merged/write
  sudo ln -sf "$SMB_MOUNT" /opt/books-merged/media
  sudo ln -sf /opt/books-writeable /opt/books-merged/write

  sudo tee /etc/systemd/system/audiobooks-symlinks.service > /dev/null <<EOF
[Unit]
Description=Ensure Audiobookshelf symlinks exist
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ln -sf "$SMB_MOUNT" /opt/books-merged/media && ln -sf /opt/books-writeable /opt/books-merged/write'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable audiobooks-symlinks.service
  sudo systemctl start audiobooks-symlinks.service
  echo "[✓] Symlinks created and service enabled."
}

# === Menu ===
function main_menu() {
  while true; do
    clear
    echo "=== Pico Setup Menu (DietPi) ==="
    echo "1) Mount SMB Share"
    echo "2) Mount FTP Share"
    echo "3) Deploy Docker Stack"
    echo "4) Install Tailscale"
    echo "5) Utilities"
    echo "6) Create Audiobookshelf Symlinks"
    echo "7) Exit"
    read -rp "Choice: " choice
    case $choice in
      1) smb_share ;;
      2) ftp_share ;;
      3) docker_stack ;;
      4) install_tailscale ;;
      5) utilities_menu ;;
      6) symlink_creation ;;
      7) exit 0 ;;
      *) echo "Invalid option." ;;
    esac
    read -rp "Press Enter to return to menu..." _
  done
}

main_menu
