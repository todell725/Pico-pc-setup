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
  echo "=== pico-pc Setup Menu ==="
  echo "0) Add All Required Repos and Keyrings"
  echo "1) Desktop Glow-Up (XFCE + Themes + Tools)"
  echo "2) Mount SMB Share (\\\\BOTFARM\\\\Data\\\\books)"
  echo "3) Mount FTP Server (nl88.seedit4.me)"
  echo "4) Docker Stack (Portainer + Dashy + Audiobookshelf + FileBrowser)"
  echo "5) Install Tailscale"
  echo "6) Run ALL"
  echo "7) Exit"
  echo ""
  read -p "Choose an option: " choice
  case $choice in
    0) add_repos ;;
    1) glow_up ;;
    2) smb_share ;;
    3) ftp_share ;;
    4) docker_stack ;;
    5) install_tailscale ;;
    6) add_repos; glow_up; smb_share; ftp_share; docker_stack; install_tailscale ;;
    7) exit 0 ;;
    *) echo "Invalid option"; sleep 1; main_menu ;;
  esac
}

### MODULE 0: Add Repos & Keyrings
function add_repos() {
  echo "[*] Ensuring required APT sources and tools..."
  echo "1991" | sudo -S true || { echo "Sudo failed"; exit 1; }

  sudo apt update
  REQUIRED_PKGS=(lsb-release dpkg curl gpg software-properties-common apt-transport-https ca-certificates fuse)

  for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      sudo apt install -y "$pkg"
    fi
  done

  sudo add-apt-repository universe -y

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main" | \
  sudo tee /etc/apt/sources.list.d/tailscale.list

  sudo apt update
  echo "[✓] All repos and tools installed."
  sleep 2
}

### MODULE 1: XFCE Setup
function glow_up() {
  echo "[*] Installing XFCE and essentials..."
  sudo apt install -y xfce4 lightdm arc-theme papirus-icon-theme fonts-ubuntu thunar firefox-esr plank picom xrdp
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

### MODULE 2: Mount SMB Share
function smb_share() {
  echo "[*] Mounting SMB share..."
  sudo apt install -y cifs-utils
  sudo mkdir -p $SMB_MOUNT
  echo -e "username=Audiobooks\npassword=1" | sudo tee $SHARE_CREDENTIALS
  sudo chmod 600 $SHARE_CREDENTIALS

  sudo mount -t cifs //BOTFARM/Data/books $SMB_MOUNT -o credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0
  if ! grep -q "$SMB_MOUNT" $MOUNT_FILE; then
    echo "//BOTFARM/Data/books $SMB_MOUNT cifs credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0 0 0" | sudo tee -a $MOUNT_FILE
  fi

  sudo chown -R $USER:$USER $SMB_MOUNT
  sudo chmod -R 755 $SMB_MOUNT
}

### MODULE 3: Mount FTP Server
function ftp_share() {
  echo "[*] Mounting FTP..."
  sudo apt install -y curlftpfs
  sudo mkdir -p $FTP_MOUNT
  echo -e "seedit4me\n@Kscb1019" | sudo tee $FTP_CREDENTIALS
  sudo chmod 600 $FTP_CREDENTIALS

  sudo curlftpfs -o user=seedit4me:@Kscb1019 nl88.seedit4.me:52404 $FTP_MOUNT
  if ! grep -q "$FTP_MOUNT" $MOUNT_FILE; then
    echo "curlftpfs#nl88.seedit4.me:52404 $FTP_MOUNT fuse user=seedit4me:@Kscb1019,allow_other 0 0" | sudo tee -a $MOUNT_FILE
  fi

  sudo chown -R $USER:$USER $FTP_MOUNT
  sudo chmod -R 755 $FTP_MOUNT
}

### MODULE 4: Docker Stack
function docker_stack() {
  echo "[*] Installing Docker + Compose..."
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker

  sudo docker volume create portainer_data
  sudo docker run -d --name portainer --restart=always -p 9000:9000 \
    -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce

  mkdir -p "$DASHY_DIR"
  sudo chown -R $USER:$USER $BASE_DIR
  sudo chmod -R 755 $BASE_DIR

  cat << EOF > $DASHY_DIR/docker-compose.yml
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

  cat << EOF > $DASHY_DIR/conf.yml
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
      - title: pico-pc Stats
        icon: cpu
        widget:
          type: system-info
EOF

  cd $DASHY_DIR
  sudo docker compose -f docker-compose.yml up -d
}

### MODULE 5: Tailscale
function install_tailscale() {
  sudo apt install -y tailscale
  echo "[*] Now run: sudo tailscale up"
}

### RUN MENU
main_menu
