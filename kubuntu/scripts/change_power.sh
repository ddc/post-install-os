#!/usr/bin/env bash
#sudo apt-get install -y cpufrequtils
#sudo systemctl disable ondemand

sleep 120
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
#sudo sed -i 's/.*GOVERNOR="ondemand"/GOVERNOR="performance"/g' /etc/init.d/cpufrequtils
#sudo sed -i 's/MAX_SPEED="0"/MAX_SPEED="5700000"/g' /etc/init.d/cpufrequtils
#sudo sed -i 's/MIN_SPEED="0"/MIN_SPEED="5700000"/g' /etc/init.d/cpufrequtils
#sudo systemctl restart cpufrequtils.service && sudo systemctl daemon-reload
#cat /proc/cpuinfo | grep -i mhz
