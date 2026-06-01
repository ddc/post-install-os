#!/usr/bin/env bash
#############################################################################
USERNAME="ddc"
#############################################################################
ARCH=$(uname -m)
echo "System Architecture: $ARCH"
#############################################################################
if [ "$ARCH" = "x86_64" ]; then
    REMOTE_PODMAN="podman-remote-static-linux_amd64.tar.gz"
elif [ "$ARCH" = "aarch64" ]; then
    REMOTE_PODMAN="podman-remote-static-linux_arm64.tar.gz"
else
    echo "✗ Unsupported architecture: $ARCH"
    echo "This script only supports x86_64 and ARM64 systems."
    exit 1
fi
#############################################################################
function update_podman {
    local local_path
    local temp_dir
    local temp_path
    local bin_path
    local current_version
    local latest_version
    local podman_binary

    local_path=/home/${USERNAME}/Programs/podman/podman
    temp_dir=/home/${USERNAME}/tmp/
    bin_path=/usr/bin/podman
    current_version=$($local_path --version | awk '{print $3}')
    latest_version=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/containers/podman/releases/latest)
    latest_version=${latest_version##*/}

    if [[ 'v'$current_version != $latest_version ]]; then
        echo -e "Updating podman $current_version -> $latest_version"
        sudo rm -rf $local_path
        sudo rm -rf $bin_path
        pushd $temp_dir
        curl -L https://github.com/containers/podman/releases/download/$latest_version/${REMOTE_PODMAN} -o podman.tar.gz
        tar -xvzf podman.tar.gz

        # Find the actual binary name dynamically
        podman_binary=$(find "$temp_dir/bin" -name "podman-remote-static-linux*" -type f | head -1)
        if [ -z "$podman_binary" ]; then
            echo "Error: Could not find podman binary"
            exit 1
        fi

        cp $temp_dir/bin/$podman_binary $local_path
        # cp $temp_dir/bin/podman-remote-static-linux_amd64 $local_path
        sudo chmod 755 $local_path
        sudo ln -s $local_path $bin_path
        sudo chmod 755 $bin_path
        sudo rm -rf $temp_dir/bin
        sudo rm -rf podman.tar.gz
        popd
    else
        echo "podman is already at latest version $latest_version"
    fi
}
#############################################################################
update_podman
echo -e "\nDone"
