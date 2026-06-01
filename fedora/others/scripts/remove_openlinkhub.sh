#!/usr/bin/env bash

sudo dnf remove -y OpenLinkHub
sudo rm -rf /etc/udev/rules.d/99-corsair.rules
sudo rm -rf /etc/systemd/system/OpenLinkHub.service.d
sudo rm -rf /etc/tmpfiles.d/openlinkhub.conf
sudo rm -rf /var/lib/openlinkhub
sudo dnf copr disable -y jurkovic-nikola/OpenLinkHub
sudo userdel openlinkhub
sudo groupdel openlinkhub
getent passwd openlinkhub
getent group openlinkhub
