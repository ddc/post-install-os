#!/usr/bin/env bash
#############################################################################
VERSION="550"
#############################################################################
sudo apt install -y linux-modules-nvidia-$VERSION-generic \
                    nvidia-dkms-$VERSION \
                    nvidia-utils-$VERSION \
                    nvidia-compute-utils-$VERSION \
                    libnvidia-compute-$VERSION \
                    libnvidia-cfg1-$VERSION \
                    libnvidia-extra-$VERSION \
                    libnvidia-decode-$VERSION \
                    libnvidia-common-$VERSION \
                    libnvidia-decode-$VERSION \
                    libnvidia-fbc1-$VERSION \
                    libnvidia-gl-$VERSION \
                    xserver-xorg-video-nvidia-$VERSION \
                    nvidia-prime \
                    nvidia-settings
