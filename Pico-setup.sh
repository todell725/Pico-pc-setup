#!/bin/bash
set -e

### GLOBALS
BASE_DIR="/opt/pico-data"
MOUNT_DIR="$BASE_DIR/mounts"
SMB_MOUNT="$MOUNT_DIR/audiobooks"
FTP_MOUNT="$MOUNT_DIR/seedbox"
SHARE_CREDENTIALS="/etc/smbcred-books"
FTP_CREDENTIALS="/etc/ftpcred-seedbox"
MOUNT_FILE="/etc/fstab"
DASHY_DIR="$BASE_DIR/docker/dashy"

### MENU
function main_menu() {
  clear
  echo "=== Pico-Setup (ARM64 – Sweet Potato) ==="
  echo "0) Prepare Repos & Permissions"
  echo "1) Desktop Glow-Up (XFCE + Tools)"
  echo "2) Mount SMB Share"
  echo "3) Mount FTP Share"
  echo "4) Docker Stack (Portainer, Dashy, Audiobookshelf, FileBrowser)"
  echo "5) Install Tailscale"
  echo "6) Run ALL"
  echo "7) Exit"
  echo ""
  read -rp "Choose an option: " choice
  case $choice in
    0) add_repos; pause_and_return ;;
    1) glow_up; pause_and_return ;;
    2) smb_share; pause_and_return ;;
    3) ftp_share; pause_and_return ;;
    4) docker_stack; pause_and_return ;;
    5) install_tailscale; pause_and_return ;;
    6) add_repos; glow_up; smb_share; ftp_share; docker_stack; install_tailscale; pause_and_return ;;
    7) exit 0 ;;
    *) echo "Invalid option"; sleep 1; main_menu ;;
  esac
}

function pause_and_return() {
  echo ""
  read -rp "Press Enter to return to the menu..." _
  main_menu
}

### MODULE 0: Repos & Permissions
function add_repos() {
  echo "[*] Setting root password to 19911019..."
  echo "root:19911019" | sudo chpasswd

  echo "[*] Installing essentials..."
  sudo apt update
  sudo apt install -y software-properties-common apt-transport-https ca-certificates \
    curl gnupg lsb-release fuse cifs-utils curlftpfs

  echo "[*] Enabling universe repo..."
  sudo add-apt-repository universe -y

  echo "[*] Adding Docker repo..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  echo "[*] Adding Tailscale repo..."
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  echo \
    "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main" | \
    sudo tee /etc/apt/sources.list.d/tailscale.list

  sudo apt update

  echo "[*] Creating directory structure..."
  sudo mkdir -p "$SMB_MOUNT" "$FTP_MOUNT" "$DASHY_DIR"
  sudo chmod -R 755 "$BASE_DIR"

  echo "[✓] Base prep complete."
}

### MODULE 1: XFCE + Enhancements
function glow_up() {
  echo "[*] Installing XFCE desktop + extras..."
  sudo apt install -y xfce4 lightdm arc-theme papirus-icon-theme fonts-ubuntu thunar firefox plank picom xrdp
  sudo systemctl enable lightdm

  mkdir -p ~/.config/autostart
  cat << EOF > ~/.config/autostart/picom.desktop
[Desktop Entry]
Type=Application
Exec=picom --config /dev/null
Name=Picom
EOF

  cat << EOF > ~/.config/autostart/plank.desktop
[Desktop Entry]
Type=Application
Exec=plank
Name=Plank
EOF
}

### MODULE 2: SMB Share
function smb_share() {
  echo "[*] Mounting SMB share..."
  sudo mkdir -p "$SMB_MOUNT"
  echo -e "username=Audiobooks\npassword=1" | sudo tee "$SHARE_CREDENTIALS"
  sudo chmod 600 "$SHARE_CREDENTIALS"

  sudo mount -t cifs //192.168.68.121/Data/books "$SMB_MOUNT" -o credentials="$SHARE_CREDENTIALS",iocharset=utf8,vers=3.0
  if ! grep -q "$SMB_MOUNT" "$MOUNT_FILE"; then
    echo "//192.168.68.1121/Data/books $SMB_MOUNT cifs credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0 0 0" | sudo tee -a "$MOUNT_FILE"
  fi
}

### MODULE 3: FTP Share
function ftp_share() {
  echo "[*] Mounting FTP..."
  sudo mkdir -p "$FTP_MOUNT"
  echo -e "seedit4me\n@Kscb1019" | sudo tee "$FTP_CREDENTIALS"
  sudo chmod 600 "$FTP_CREDENTIALS"

  sudo curlftpfs -o user=seedit4me:@Kscb1019 nl88.seedit4.me:52404 "$FTP_MOUNT"
  if ! grep -q "$FTP_MOUNT" "$MOUNT_FILE"; then
    echo "curlftpfs#nl88.seedit4.me:52404 $FTP_MOUNT fuse user=seedit4me:@Kscb1019,allow_other 0 0" | sudo tee -a "$MOUNT_FILE"
  fi
}

### MODULE 4: Docker Stack
function docker_stack() {
  echo "[*] Installing Docker + Compose..."
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker

  echo "[*] Launching Portainer..."
  sudo docker volume create portainer_data
  sudo docker run -d --name portainer --restart=always -p 9000:9000 \
    -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data \
    portainer/portainer-ce

  echo "[*] Setting up Dashy, Audiobookshelf, and FileBrowser..."
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

### MODULE 5: Tailscale
function install_tailscale() {
  echo "[*] Installing Tailscale..."
  sudo apt install -y tailscale
  echo "[!] Run 'sudo tailscale up' to authenticate via browser."
}

### START
main_menu
