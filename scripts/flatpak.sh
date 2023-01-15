#!/bin/bash

# Get the directory of the script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# set the working directory to the script directory
cd $SCRIPT_DIR/../

# Check if flatpak is installed
if ! command -v flatpak &> /dev/null
then
    echo "flatpak could not be found"
    exit
fi

# Check if flatpak-builder is installed
if ! command -v flatpak-builder &> /dev/null
then
    echo "flatpak-builder could not be found"
    exit
fi

# Check if flatpak manifest exists
if [ ! -f "flatpak.json" ]; then
    echo "flatpak.json could not be found"
    exit
fi

# Check if flatpak manifest is valid
if ! flatpak-builder --show-manifest flatpak.json &> /dev/null
then
    echo "flatpak.json is not valid"
    exit
fi

# Get latest tag from github
LATEST_TAG=$(curl -s https://api.github.com/repos/brianmiller/phvalheim-client/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')


# Build flatpak
flatpak-builder --force-clean --repo=.flatpak-repo ./.flatpak-build-dir ./flatpak.json

# Create single file bundle 
flatpak build-bundle ./.flatpak-repo ./published_build/phvalheim-client_$LATEST_TAG.flatpak com.github.brianmiller.phvalheim-client

# Cleanup
rm -rf .flatpak-build-dir
rm -rf .flatpak-repo

