#!/usr/bin/env bash
set -e

echo "Installing devops-desk..."

sudo mkdir -p /opt/devops-desk
sudo cp -R bin commands lib config k9s /opt/devops-desk

chmod +x /opt/devops-desk/bin/devops-desk
chmod +x /opt/devops-desk/commands/*.sh
chmod +x /opt/devops-desk/lib/*.sh

sudo ln -sf /opt/devops-desk/bin/devops-desk /usr/local/bin/devops-desk

mkdir -p ~/.devops-desk

echo "Installation complete"
echo ""
echo "Run:"
echo "  devops-desk env"
