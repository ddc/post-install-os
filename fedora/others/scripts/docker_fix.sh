#!/usr/bin/env bash
#############################################################################
[[ $EUID -eq 0 ]] && echo "Script cannot be run by root" && 1>&2 exit 1
#############################################################################
echo -e "\n\n>> DOWNGRADING TO DOCKER 28.x"
## Remove current Docker 29
#sudo dnf remove -y docker-ce docker-ce-cli
## Install the latest 28.x version available
#sudo dnf install -y docker-ce-3:28.* docker-ce-cli-1:28.*
## Version lock to avoid updates
#sudo dnf versionlock delete docker-ce docker-ce-cli


######
#sudo vi /usr/lib/systemd/system/docker.service
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/override.conf > /dev/null << 'EOF'
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF
######


sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl restart docker
sudo systemctl status docker
docker version
