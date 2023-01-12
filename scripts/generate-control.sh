#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# make sure the debian folder exists
if [ ! -f $SCRIPT_DIR/../debian ]; then
    mkdir -p $SCRIPT_DIR/../debian
fi

# Create a minimal control file from the csproj and github api
echo "Source: phvalheim-client
Section: games
Priority: optional
Maintainer: Brian Miller <>

Package: phvalheim-client
Architecture: amd64
Depends: \${shlibs:Depends}, \${misc:Depends}
Description: A x-url-handler for PhValheim
" > $SCRIPT_DIR/../debian/control
