#!/bin/bash

# Usage: ./build_deb_package.sh <package_name> <version> <architecture>

package_name=$1
version=$2
architecture=$3

# Create a Debian package directory structure
mkdir -p $package_name-$version/DEBIAN
mkdir -p $package_name-$version/usr/local/$package_name

# Create a control file with the provided information
echo "Package: $package_name" >> $package_name-$version/DEBIAN/control
echo "Version: $version" >> $package_name-$version/DEBIAN/control
echo "Architecture: $architecture" >> $package_name-$version/DEBIAN/control
echo "Maintainer: Your Name <your.email@example.com>" >> $package_name-$version/DEBIAN/control
echo "Description: Package description goes here" >> $package_name-$version/DEBIAN/control

# Add files to the package directory
# ...

# Build the Debian package
dpkg-deb --build $package_name-$version

