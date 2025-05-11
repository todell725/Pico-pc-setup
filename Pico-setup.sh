#!/bin/bash

set -e

### GLOBALS
SMB_MOUNT="/mnt/audiobooks"
FTP_MOUNT="/mnt/seedbox"
SHARE_CREDENTIALS="/etc/smbcred-books"
FTP_CREDENTIALS="/etc/ftpcred-seedbox"
MOUNT_FILE="/etc/fstab"
HOSTNAME="pico-pc"
DASHY_DIR="$HOME/dashy"

### MENU
function main_menu() {
  clear
  echo "=== pico-pc Setup Menu ==="
  echo "1) Desktop Glow-Up (XFCE + Themes + Tools)"
  echo "2) Mount SMB Share (\\BOTFARM\\Data\\books)"
  echo "3) Mount FTP Server (nl88.seedit4.me)"
  echo "4) Docker Stack (Portainer + Dashy + Audiobookshelf + FileBrowser)"
  echo "5) Install Tailscale"
  echo "6) Run ALL"
  echo "7) Exit"
  echo ""
  read -p "Choose an option: " choice
  case $choice in
    1) glow_up ;;
    2) smb_share ;;
    3) ftp_share ;;
    4) docker_stack ;;
    5) install_tailscale ;;
    6) glow_up; smb_share; ftp_share; docker_stack; install_tailscale ;;
    7) exit 0 ;;
    *) echo "Invalid option"; sleep 1; main_menu ;;
  esac
}

### MODULE 1: XFCE + Customizations
function glow_up() {
  echo "[*] Installing XFCE + themes + essentials..."
  sudo apt update
  sudo apt install -y xfce4 lightdm arc-theme papirus-icon-theme fonts-ubuntu thunar firefox-esr plank picom xrdp
  sudo systemctl enable lightdm
  mkdir -p ~/.config/autostart

  # Autostart Picom and Plank
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

  echo "[*] XFCE setup complete. Customize via Settings > Appearance."
  sleep 2
}

### MODULE 2: SMB Mount
function smb_share() {
  echo "[*] Setting up SMB mount for //BOTFARM/Data/books..."
  sudo apt install -y cifs-utils
  sudo mkdir -p $SMB_MOUNT

  echo "username=Audiobooks" | sudo tee $SHARE_CREDENTIALS
  echo "password=1" | sudo tee -a $SHARE_CREDENTIALS
  sudo chmod 600 $SHARE_CREDENTIALS

  sudo mount -t cifs //BOTFARM/Data/books $SMB_MOUNT -o credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0

  if ! grep -q "$SMB_MOUNT" $MOUNT_FILE; then
    echo "//BOTFARM/Data/books $SMB_MOUNT cifs credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0 0 0" | sudo tee -a $MOUNT_FILE
  fi

  echo "[*] SMB share mounted and persistent."
  sleep 2
}

### MODULE 3: FTP Mount
function ftp_share() {
  echo "[*] Setting up FTP mount..."
  sudo apt install -y curlftpfs
  sudo mkdir -p $FTP_MOUNT

  echo "seedit4me" | sudo tee $FTP_CREDENTIALS
  echo "@Kscb1019" | sudo tee -a $FTP_CREDENTIALS
  sudo chmod 600 $FTP_CREDENTIALS

  sudo curlftpfs -o user="$(head -n1 $FTP_CREDENTIALS):$(tail -n1 $FTP_CREDENTIALS)" nl88.seedit4.me:52404 $FTP_MOUNT

  if ! grep -q "$FTP_MOUNT" $MOUNT_FILE; then
    echo "curlftpfs#nl88.seedit4.me:52404 $FTP_MOUNT fuse user=$(head -n1 $FTP_CREDENTIALS):$(tail -n1 $FTP_CREDENTIALS),allow_other 0 0" | sudo tee -a $MOUNT_FILE
  fi

  echo "[*] FTP mounted and persistent."
  sleep 2
}

### MODULE 4: Docker + Stack
function docker_stack() {
  echo "[*] Installing Docker and Docker Compose..."
  sudo apt install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -m 0755 -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker

  echo "[*] Launching Portainer..."
  sudo docker volume create portainer_data
  sudo docker run -d --name portainer --restart=always -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce

  echo "[*] Launching Dashy + Audiobookshelf + FileBrowser..."
  mkdir -p $DASHY_DIR && cd $DASHY_DIR

  cat << EOF > docker-compose.yml
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
      - audiobookshelf_config:/config
      - audiobookshelf_metadata:/metadata

  filebrowser:
    image: filebrowser/filebrowser
    container_name: filebrowser
    restart: always
    ports:
      - 8081:80
    volumes:
      - /:/srv
volumes:
  audiobookshelf_config:
  audiobookshelf_metadata:
EOF

  cat << EOF > conf.yml
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
        description: Docker GUI
        icon: docker
        url: http://localhost:9000
      - title: Audiobookshelf
        description: Stream your audiobooks
        icon: book
        url: http://localhost:13378
      - title: FileBrowser
        description: Browse files on pico-pc
        icon: folder
        url: http://localhost:8081
      - title: pico-pc Stats
        description: CPU, RAM, and Disk
        icon: cpu
        widget:
          type: system-info
EOF

  sudo docker compose up -d
  echo "[*] Docker stack online. Dashy @ :8080, Portainer @ :9000, Audiobookshelf @ :13378, FileBrowser @ :8081"
  sleep 2
}

### MODULE 5: Tailscale
function install_tailscale() {
  echo "[*] Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "[*] Now run: sudo tailscale up (to authenticate via browser)"
  sleep 2
}

### RUN MENU
main_menu
