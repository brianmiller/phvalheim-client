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


$docker login
if [ ! $? = 0 ]; then
	echo "Could not login to Dockerhub, exiting..."
	exit 1
fi


$docker buildx build -t theoriginalbrian/fedora-env .
if [ ! $? = 0 ]; then
        echo "Build failed, exiting..."
        exit 1
fi


$docker push theoriginalbrian/fedora-env:latest
