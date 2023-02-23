#!/bin/bash


# image to delete
image="debian-env"


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

echo
echo "Erasing all containers and the image from: \"$image\""
$docker rm -f $image
