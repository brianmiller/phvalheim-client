#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

ROOT=$SCRIPT_DIR/../
cd $ROOT

source $SCRIPT_DIR/_helpers.sh

# Generate the changelog
generate_changelog $ROOT

# Generate the control file from csproj
generate_control $ROOT

# Generate the rules file
generate_rules $ROOT

# Generate the compat file
echo "10" > $ROOT/debian/compat

# Generate the postinst file
generate_postinst $ROOT

# Build the debian package
dpkg-buildpackage -us -uc -b

# Move the package to published_build
mv ../*.deb ./published_build

# Cleanup the debian folder
rm -rf ./debian
