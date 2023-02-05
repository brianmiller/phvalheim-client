#!/bin/bash

# Tell us our build environment
source /etc/os-release
echo "Build environment: $PRETTY_NAME"
echo

# Just known starting point
mkdir /runthis
cd /runthis

# Setup git
git config --global user.name "Brian Miller"
git config --global user.email "brian@phospher.com"
git config --global credential.helper "cache"
git config --global url."ssh://git@github.com/".insteadOf "https://github.com/"

# Git clone phvalheim-client
git clone https://github.com/brianmiller/phvalheim-client

# Compile the source and build Ubuntu and universal tarball packages
cd phvalheim-client/scripts
echo "Hello world!"
#bash both.sh

# Clean the working directory
#rm -rf bin/ obj/

# Let's see it
ls -al /runthis/phvalheim-client/builds/*

# Push to git
git add /runthis/phvalheim-client/builds/*
git commit -a -m "Automated Build: $PRETTY_NAME"
git push --set-upstream origin master
