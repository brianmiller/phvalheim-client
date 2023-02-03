#!/bin/bash

# Get the directory of the script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# set the working directory to the script directory
cd $SCRIPT_DIR

# Package isntall script assets
/bin/bash ./manual-install.sh

# Make .deb
/bin/bash ./debian-build-pkg.sh

