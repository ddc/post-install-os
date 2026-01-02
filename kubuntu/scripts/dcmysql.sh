#!/usr/bin/env bash

pushd /home/ddc/Workspaces/docker/mysql
if [[ ! $1 ]]; then
    echo "up or down"
elif [[ $1 == "up" ]]; then
    docker-compose up --build -d
elif [[ $1 == "down" ]]; then
    docker-compose down
else
    echo "Wrong option"
fi
popd
