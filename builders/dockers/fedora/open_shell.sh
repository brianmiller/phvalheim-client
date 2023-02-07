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

$docker run -v '/mnt/cerebrum/development/phvalheim-client/git':'/git' -ti fedora-env /bin/bash
