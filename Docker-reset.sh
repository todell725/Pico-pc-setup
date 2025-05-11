#!/bin/bash
set -e

echo "[*] Purging Docker packages..."
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[*] Cleaning up Docker directories..."
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker

echo "[*] Updating package index..."
sudo apt update

echo "[*] Reinstalling Docker components..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[*] Enabling and starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

echo "[✓] Docker reinstallation complete."
sudo systemctl status docker --no-pager
