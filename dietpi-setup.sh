#!/bin/bash
set -e

# === Startup Check ===
if ! mountpoint -q /mnt/storage; then
  echo "[!] /mnt/storage is not mounted. Please mount it before running this script."
  exit 1
fi

# === Constants and Paths ===
BASE_DIR="/mnt/storage"
MOUNT_DIR="$BASE_DIR/mounts"
SMB_MOUNT="$MOUNT_DIR/audiobooks"
FTP_MOUNT="$MOUNT_DIR/seedbox"
WRITE_DIR="$BASE_DIR/books-writeable"
MERGED_DIR="$BASE_DIR/books-merged"
CREDENTIALS_DIR="/etc/dietpi-setup"
SHARE_CREDENTIALS="$CREDENTIALS_DIR/smbcred"
FTP_CREDENTIALS="$CREDENTIALS_DIR/ftpcred"
DASHY_DIR="$BASE_DIR/docker/dashy"

sudo mkdir -p "$SMB_MOUNT" "$FTP_MOUNT" "$DASHY_DIR" "$WRITE_DIR" "$MERGED_DIR" "$CREDENTIALS_DIR"

# === Menu ===
function main_menu() {
  clear
  echo "=== DietPi Setup Menu ==="
  echo "1) Prompt for SMB/FTP credentials"
  echo "2) Install XFCE and dependencies"
  echo "3) Mount SMB share"
  echo "4) Mount FTP share"
  echo "5) Deploy Docker stack"
  echo "6) Configure symlinks"
  echo "7) Run All"
  echo "8) Exit"
  echo ""
  read -rp "Choose an option: " choice
  case $choice in
    1) prompt_credentials ;;
    2) install_dependencies ;;
    3) mount_smb ;;
    4) mount_ftp ;;
    5) deploy_docker_stack ;;
    6) setup_symlinks ;;
    7) prompt_credentials; install_dependencies; mount_smb; mount_ftp; deploy_docker_stack; setup_symlinks ;;
    8) exit 0 ;;
    *) echo "Invalid option."; sleep 1 ;;
  esac
  read -rp "Press Enter to return to the menu..." _
  main_menu
}

# === Functions ===
function prompt_credentials() {
  read -rp "Enter SMB username: " SMB_USER
  read -rsp "Enter SMB password: " SMB_PASS; echo
  read -rp "Enter FTP username: " FTP_USER
  read -rsp "Enter FTP password: " FTP_PASS; echo
  read -rp "Enter SMB IP (e.g., 192.168.68.116): " SMB_IP
  read -rp "Enter FTP host (e.g., nl88.seedit4.me:52404): " FTP_HOST

  echo -e "username=$SMB_USER\npassword=$SMB_PASS" | sudo tee "$SHARE_CREDENTIALS" >/dev/null
  echo -e "$FTP_USER\n$FTP_PASS" | sudo tee "$FTP_CREDENTIALS" >/dev/null
  sudo chmod 600 "$SHARE_CREDENTIALS" "$FTP_CREDENTIALS"
}

function install_dependencies() {
  sudo apt update
  sudo apt install -y xfce4 lightdm thunar firefox curl fuse cifs-utils curlftpfs \
    docker.io docker-compose openssh-server ffmpeg git xrdp tailscale vsftpd samba \
    nfs-kernel-server nfs-common unrar
  sudo systemctl enable lightdm
  sudo systemctl enable docker
  sudo systemctl start docker
}

function mount_smb() {
  sudo mount -t cifs "//$SMB_IP/Data/books" "$SMB_MOUNT" -o credentials="$SHARE_CREDENTIALS",iocharset=utf8,vers=3.0,_netdev,nofail
  grep -q "$SMB_MOUNT" /etc/fstab || echo "//$SMB_IP/Data/books $SMB_MOUNT cifs credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0,_netdev,nofail 0 0" | sudo tee -a /etc/fstab
}

function mount_ftp() {
  sudo curlftpfs -o "user=${FTP_USER}:${FTP_PASS},_netdev,nofail" "$FTP_HOST" "$FTP_MOUNT"
  grep -q "$FTP_MOUNT" /etc/fstab || echo "curlftpfs#$FTP_HOST $FTP_MOUNT fuse user=${FTP_USER}:${FTP_PASS},_netdev,nofail 0 0" | sudo tee -a /etc/fstab
}

function deploy_docker_stack() {
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
  title: "DietPi Dashboard"
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
EOF

  cd "$DASHY_DIR"
  sudo docker compose up -d
}

function setup_symlinks() {
  sudo tee /etc/systemd/system/audiobooks-symlinks.service > /dev/null <<EOF
[Unit]
Description=Ensure Audiobookshelf symlinks exist
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ln -sf $SMB_MOUNT $MERGED_DIR/media && ln -sf $WRITE_DIR $MERGED_DIR/write'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable audiobooks-symlinks.service
  sudo systemctl start audiobooks-symlinks.service
}

main_menu
