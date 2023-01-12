#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd $SCRIPT_DIR
cd ../

# Generate the changelog
/bin/bash ./scripts/generate-changelog.sh

# Generate the control file from csproj
/bin/bash ./scripts/generate-control.sh

# Generate the rules file
/bin/bash ./scripts/generate-rules.sh

# Generate the compat file
/bin/bash ./scripts/generate-compat.sh

# Generate the postinst file
/bin/bash ./scripts/create-postinst.sh

# Build the debian package
dpkg-buildpackage -us -uc -b 

# Move the package to published_build
mv ../*.deb ./published_build

# Cleanup the debian folder
rm -rf ./debian