#!/bin/bash
set -e

# === Constants and Paths ===
BASE_DIR="/opt/dietpi-data"
MOUNT_DIR="$BASE_DIR/mounts"
SMB_MOUNT="$MOUNT_DIR/audiobooks"
FTP_MOUNT="$MOUNT_DIR/seedbox"
WRITE_DIR="/opt/books-writeable"
MERGED_DIR="/opt/books-merged"
CREDENTIALS_DIR="/etc/dietpi-setup"
SHARE_CREDENTIALS="$CREDENTIALS_DIR/smbcred"
FTP_CREDENTIALS="$CREDENTIALS_DIR/ftpcred"
DASHY_DIR="$BASE_DIR/docker/dashy"

mkdir -p "$SMB_MOUNT" "$FTP_MOUNT" "$DASHY_DIR" "$WRITE_DIR" "$MERGED_DIR" "$CREDENTIALS_DIR"

# === Prompt for Credentials ===
read -rp "Enter SMB username: " SMB_USER
read -rsp "Enter SMB password: " SMB_PASS; echo
read -rp "Enter FTP username: " FTP_USER
read -rsp "Enter FTP password: " FTP_PASS; echo
read -rp "Enter SMB IP (e.g., 192.168.68.116): " SMB_IP
read -rp "Enter FTP host (e.g., nl88.seedit4.me:52404): " FTP_HOST

echo -e "username=$SMB_USER\npassword=$SMB_PASS" | sudo tee "$SHARE_CREDENTIALS" >/dev/null
echo -e "$FTP_USER\n$FTP_PASS" | sudo tee "$FTP_CREDENTIALS" >/dev/null
sudo chmod 600 "$SHARE_CREDENTIALS" "$FTP_CREDENTIALS"

# === Install XFCE and supporting tools ===
sudo apt update
sudo apt install -y xfce4 lightdm thunar firefox curl fuse cifs-utils curlftpfs docker.io docker-compose

sudo systemctl enable lightdm
sudo systemctl enable docker
sudo systemctl start docker

# === Mount SMB ===
sudo mount -t cifs "//$SMB_IP/Data/books" "$SMB_MOUNT" -o credentials="$SHARE_CREDENTIALS",iocharset=utf8,vers=3.0,_netdev,nofail
grep -q "$SMB_MOUNT" /etc/fstab || echo "//$SMB_IP/Data/books $SMB_MOUNT cifs credentials=$SHARE_CREDENTIALS,iocharset=utf8,vers=3.0,_netdev,nofail 0 0" | sudo tee -a /etc/fstab

# === Mount FTP ===
sudo curlftpfs -o "user=${FTP_USER}:${FTP_PASS},_netdev,nofail" "$FTP_HOST" "$FTP_MOUNT"
grep -q "$FTP_MOUNT" /etc/fstab || echo "curlftpfs#$FTP_HOST $FTP_MOUNT fuse user=${FTP_USER}:${FTP_PASS},_netdev,nofail 0 0" | sudo tee -a /etc/fstab

# === Docker stack ===
sudo docker volume create portainer_data

sudo docker run -d --name portainer --restart=always -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce

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

# === Symlink Setup with systemd persistence ===
sudo tee /etc/systemd/system/audiobooks-symlinks.service > /dev/null <<EOF
[Unit]
Description=Ensure Audiobookshelf symlinks exist
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ln -sf $SMB_MOUNT /opt/books-merged/media && ln -sf $WRITE_DIR /opt/books-merged/write'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable audiobooks-symlinks.service
sudo systemctl start audiobooks-symlinks.service

echo "[✓] DietPi setup complete. XFCE, Docker stack, mounts, and symlinks are all configured."
