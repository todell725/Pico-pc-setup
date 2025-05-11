#!/bin/bash
set -e

# === Centralized Credentials ===
SMB_USER="#insert_user_here#"
SMB_PASS="#insert_password_here#"
FTP_USER="#insert_user_here#"
FTP_PASS="#insert_password_here#"

# === Paths ===
BASE_DIR="/opt/pico-data"
MOUNT_DIR="$BASE_DIR/mounts"
SMB_MOUNT="$MOUNT_DIR/audiobooks"
FTP_MOUNT="$MOUNT_DIR/seedbox"
SHARE_CREDENTIALS="/etc/smbcred-books"
FTP_CREDENTIALS="/etc/ftpcred-seedbox"
MOUNT_FILE="/etc/fstab"
DASHY_DIR="$BASE_DIR/docker/dashy"

function main_menu() {
  clear
  echo "=== Pico-Setup (Libre Computer) ==="
  echo "0) Prepare Repos, Fixes & Permissions"
  echo "1) Desktop Glow-Up (XFCE + Tools)"
  echo "2) Mount SMB Share"
  echo "3) Mount FTP Share"
  echo "4) Docker Stack (Portainer, Dashy, Audiobookshelf, FileBrowser)"
  echo "5) Install Tailscale"
  echo "6) Utilities / Performance Tools"
  echo "7) Run ALL"
  echo "8) Exit"
  echo ""
  read -rp "Choose an option: " choice
  case $choice in
    0) add_repos; pause_and_return ;;
    1) glow_up; pause_and_return ;;
    2) smb_share; pause_and_return ;;
    3) ftp_share; pause_and_return ;;
    4) docker_stack; pause_and_return ;;
    5) install_tailscale; pause_and_return ;;
    6) utilities_menu ;;
    7) add_repos; glow_up; smb_share; ftp_share; docker_stack; install_tailscale; symlink_creation; pause_and_return ;;
    8) exit 0 ;;
    *) echo "Invalid option"; sleep 1; main_menu ;;
  esac
}

function pause_and_return() {
  echo ""
  read -rp "Press Enter to return to the menu..." _
  main_menu
}

function add_repos() {
  echo "[*] Setting root password..."
  echo "root:#insert_password_here#" | sudo chpasswd
  iface=$(ip -o link show | awk -F': ' '/state UP/ && $2 != "lo" {print $2; exit}')
  sudo rm -f /etc/netplan/*.yaml
  cat << EOF | sudo tee /etc/netplan/01-network-manager.yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    $iface:
      dhcp4: true
EOF
  sudo netplan apply
  sudo touch /etc/cloud/cloud-init.disabled
  sudo apt update
  sudo apt install -y software-properties-common apt-transport-https ca-certificates curl gnupg lsb-release fuse cifs-utils curlftpfs
  sudo mkdir -p "$SMB_MOUNT" "$FTP_MOUNT" "$DASHY_DIR"
  sudo chmod -R 755 "$BASE_DIR"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main" | sudo tee /etc/apt/sources.list.d/tailscale.list
  sudo apt update
}

function glow_up() {
  sudo apt install -y xfce4 lightdm arc-theme papirus-icon-theme fonts-ubuntu thunar firefox plank picom xrdp
  sudo systemctl enable lightdm
  mkdir -p ~/.config/autostart
  echo -e "[Desktop Entry]\nType=Application\nExec=picom --config /dev/null\nName=Picom" > ~/.config/autostart/picom.desktop
  echo -e "[Desktop Entry]\nType=Application\nExec=plank\nName=Plank" > ~/.config/autostart/plank.desktop
}

function smb_share() {
  sudo mkdir -p "$SMB_MOUNT"
  echo -e "username=$SMB_USER\npassword=$SMB_PASS" | sudo tee "$SHARE_CREDENTIALS"
  sudo chmod 600 "$SHARE_CREDENTIALS"
  sudo mount -t cifs //#insert_smb_ip#/Data/books "$SMB_MOUNT" -o credentials="$SHARE_CREDENTIALS",iocharset=utf8,vers=3.0,_netdev,nofail
  if ! grep -q "$SMB_MOUNT" "$MOUNT_FILE"; then
    echo "//$insert_smb_ip#/Data/books $SMB_MOUNT cifs credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0,_netdev,nofail 0 0" | sudo tee -a "$MOUNT_FILE"
  fi
}

function ftp_share() {
  sudo mkdir -p "$FTP_MOUNT"
  echo -e "$FTP_USER\n$FTP_PASS" | sudo tee "$FTP_CREDENTIALS"
  sudo chmod 600 "$FTP_CREDENTIALS"
  sudo curlftpfs -o user=$FTP_USER:$FTP_PASS,_netdev,nofail #insert_ftp_host# "$FTP_MOUNT"
  if ! grep -q "$FTP_MOUNT" "$MOUNT_FILE"; then
    echo "curlftpfs##insert_ftp_host# $FTP_MOUNT fuse user=$FTP_USER:$FTP_PASS,_netdev,nofail 0 0" | sudo tee -a "$MOUNT_FILE"
  fi
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
      - title: System Stats
        icon: cpu
        widget:
          type: system-info
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
  echo "=== Utilities / Performance Tools ==="
  echo "1) Docker Reset & Reinstall"
  echo "2) Emergency Boot Fixer (FSTAB Cleanup)"
  echo "3) Create 24GB Swapfile"
  echo "4) Enable TRIM"
  echo "5) Apply SSD FSTAB Tweaks"
  echo "6) Swappiness Tuner"
  echo "7) Symlink Creation"
  echo "8) Back"
  echo ""
  read -rp "Choose an option: " uchoice
  case $uchoice in
    1) docker_reset ;;
    2) emergency_fstab_fix ;;
    3) create_swap ;;
    4) sudo fstrim -v /; pause_and_return ;;
    5) sudo sed -i 's/errors=remount-ro/defaults,noatime,nodiratime,discard,commit=60,_netdev,nofail/' /etc/fstab; echo "[✓] Tweaks applied."; pause_and_return ;;
    6) swappiness_tuner ;;
    7) symlink_creation ;;
    8) main_menu ;;
    *) echo "Invalid option"; sleep 1; utilities_menu ;;
  esac
}

function create_swap() {
  sudo swapoff -a
  sudo rm -f /swapfile
  sudo fallocate -l 24G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  echo "[✓] 24GB swap created and enabled."
}

function swappiness_tuner() {
  clear
  echo "=== Swappiness Tuner ==="
  echo "1) Set swappiness to 10 (SSD-friendly)"
  echo "2) Set swappiness to 60 (default)"
  echo "3) Set swappiness to 100 (aggressive)"
  echo "4) View current value"
  echo "5) Back"
  read -rp "Choose: " s
  case $s in
    1) sudo sysctl vm.swappiness=10; echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf ;;
    2) sudo sysctl vm.swappiness=60; echo 'vm.swappiness=60' | sudo tee -a /etc/sysctl.conf ;;
    3) sudo sysctl vm.swappiness=100; echo 'vm.swappiness=100' | sudo tee -a /etc/sysctl.conf ;;
    4) cat /proc/sys/vm/swappiness; pause_and_return ;;
    5) utilities_menu ;;
  esac
  echo "[✓] Swappiness updated."
  sleep 1
  swappiness_tuner
}

function emergency_fstab_fix() {
  sudo mount -o remount,rw /
  sudo cp /etc/fstab /etc/fstab.bak.$(date +%s)
  sudo sed -i.bak '/curlftpfs\|cifs/ s/^/#/' /etc/fstab
  echo "[✓] Commented out potentially failing mount lines."
  echo "[!] Reboot now with: sudo reboot"
}

function docker_reset() {
  sudo systemctl stop docker || true
  sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker
}

function symlink_creation() {
  echo "[*] Creating Audiobookshelf symlink structure..."
  sudo mkdir -p /opt/books-writeable /opt/books-merged
  sudo rm -f /opt/books-merged/media /opt/books-merged/write
  sudo ln -s /mnt/smb/books /opt/books-merged/media
  sudo ln -s /opt/books-writeable /opt/books-merged/write
  sudo tee /etc/systemd/system/audiobooks-symlinks.service > /dev/null <<EOF
[Unit]
Description=Ensure Audiobookshelf symlinks exist
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ln -sf /mnt/smb/books /opt/books-merged/media && ln -sf /opt/books-writeable /opt/books-merged/write'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable audiobooks-symlinks.service
  sudo systemctl start audiobooks-symlinks.service
  echo "[✓] Symlinks created and will persist across reboots."
  pause_and_return
}

main_menu
