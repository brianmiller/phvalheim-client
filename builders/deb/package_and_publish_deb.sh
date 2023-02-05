#!/bin/bash

# Get the directory of the script
scriptDir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


# set the working directory to the root directory
gitRoot=$scriptDir/..
cd $gitRoot


# include _helpers.sh
source $gitRoot/scripts/_helpers.sh


# get the version of this release
thisVersion=$(grep -oPm1 "(?<=<Version>)[^<]+" $gitRoot/phvalheim-client.csproj)


# if the staging directory exists, then delete it
if [ ! -d ./scripts/staging/deb/debian ]; then
     mkdir -p ./scripts/staging/deb/debian
fi


# generate .desktop file for the x-url-handler
echo "[Desktop Entry]
Name=PhValheim-Client
Comment=PhValheim-Client
Exec=/usr/bin/phvalheim-client %U
Terminal=false
Type=Application
MimeType=x-scheme-handler/phvalheim;
" > ./scripts/staging/deb/debian/phvalheim-client.desktop


# generate control
echo "Source: phvalheim-client
Section: games
Priority: optional
Maintainer: Brian Miller <brian@phospher.com>

Package: phvalheim-client
Architecture: amd64
Depends: \${shlibs:Depends}, \${misc:Depends}
Description: PhValheim Client
" > ./scripts/staging/deb/debian/control


# generate rules
echo "#!/usr/bin/make -f
# Uncomment this to turn on verbose mode.
export DH_VERBOSE=1

%:
	dh \$@

override_dh_auto_install:
	mkdir -p \$(CURDIR)/debian/phvalheim-client/usr/bin
	cp -r \$(CURDIR)/../../../bin/Release/net6.0/linux-x64/publish/phvalheim-client \$(CURDIR)/debian/phvalheim-client/usr/bin
	mkdir -p \$(CURDIR)/debian/phvalheim-client/usr/share/applications
	cp -r \$(CURDIR)/debian/phvalheim-client.desktop \$(CURDIR)/debian/phvalheim-client/usr/share/applications

#override_dh_strip:
#	dh_strip --exclude=phvalheim-client
	" > ./scripts/staging/deb/debian/rules


# generate postinst
echo "#!/bin/sh
set -e

if [ \"$1\" = \"configure\" ]; then
  update-desktop-database -q
  gio mime x-scheme-handler/phvalheim phvalheim-client.desktop
fi
" > ./scripts/staging/deb/debian/postinst

# generate changelog
generate_changelog $gitRoot

# generate compat
echo "10" > ./scripts/staging/deb/debian/compat


# .desktop destination path
mkdir -p $gitRoot/scripts/staging/deb/debian/phvalheim-client/usr/share/applications


# assemble the .deb
cd $gitRoot/scripts/staging/deb
dpkg-buildpackage -us -uc -b
