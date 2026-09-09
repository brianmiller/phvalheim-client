#!/bin/bash

# find docker
docker=$(which docker 2> /dev/null)
if [ $? = 0 ]; then
        docker=$docker
else
        podman=$(which podman 2> /dev/null)
        if [  $? = 0 ]; then
                docker=$podman
        else
                echo "ERROR: Docker or Podman are required, exiting..."
                exit 1
        fi
fi


# pull pre-built docker environment
echo "Pulling pre-built fedora environment..."
echo
$docker image pull docker.io/theoriginalbrian/fedora-env:latest

gitRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." &>/dev/null && pwd)

$docker run -v "$gitRoot":'/git' -ti fedora-env /bin/bash
