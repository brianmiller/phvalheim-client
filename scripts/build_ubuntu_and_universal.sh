#!/bin/bash

# Tell us our build environment
source /etc/os-release
echo "Build environment: $PRETTY_NAME"
echo

# Just known starting point
mkdir /dooyet
cd /dooyet

# Setup git
git config --global user.name "Brian Miller"
git config --global user.email "brian@phospher.com"
git config --global credential.helper "cache"
git config --global url."ssh://git@github.com/".insteadOf "https://github.com/"

# Git clone phvalheim-client
git clone https://github.com/brianmiller/phvalheim-client

# Compile the source and build Ubuntu and universal tarball packages
cd phvalheim-client/scripts
bash both.sh

# Clean the working directory
rm -rf bin/ obj/

# Let's see it
ls -al /dooyet/phvalheim-client/published_build/*

# Push to git
git add /dooyet/phvalheim-client/published_build/*
git commit -a -m "Automated Build: $PRETTY_NAME"
git push --set-upstream origin master
