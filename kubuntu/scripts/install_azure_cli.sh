#!/usr/bin/env bash

sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
sudo mkdir -p /usr/share/keyrings
curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
sudo chmod go+r /usr/share/keyrings/microsoft.gpg

AZ_DIST=$(lsb_release -cs)
echo "Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${AZ_DIST}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /usr/share/keyrings/microsoft.gpg" | sudo tee /etc/apt/sources.list.d/azure-cli.sources

sudo apt-get update
sudo apt-get install azure-cli


# Uninstall Azure CLI
#sudo apt-get remove -y azure-cli
#sudo rm /etc/apt/sources.list.d/azure-cli.sources
#sudo rm /usr/share/keyrings/microsoft.gpg
#sudo apt autoremove -y
