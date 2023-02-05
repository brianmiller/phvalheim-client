#!/bin/bash

# Get the directory of the script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# set the working directory to the script directory
cd $SCRIPT_DIR

# check first argument for install or uninstall
if [ "$1" = "install" ]; then
    # install
    cp ./phvalheim-client /usr/bin/phvalheim-client
    cp ./phvalheim-client.desktop /usr/share/applications/phvalheim-client.desktop
    update-desktop-database -q
elif [ "$1" = "uninstall" ]; then
    # uninstall
    rm /usr/bin/phvalheim-client
    rm /usr/share/applications/phvalheim-client.desktop
    update-desktop-database -q
else
    echo "Invalid argument. Use install or uninstall"
fi

