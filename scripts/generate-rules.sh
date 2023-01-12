#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Get path to debian folder
DEBIAN_DIR=$SCRIPT_DIR/../debian

echo "#!/usr/bin/make -f
# Uncomment this to turn on verbose mode.
#export DH_VERBOSE=1

%: 
	dh \$@

override_dh_auto_build:
	dotnet publish \
		-c Release \
        -r linux-x64 \
        -p:PublishSingleFile=true \
        --self-contained true \
        ./phvalheim-client.csproj \
        /property:GenerateFullPaths=true \
        /consoleloggerparameters:NoSummary \
		/p:PublishTrimmed=false \

override_dh_auto_install:
	mkdir -p \$(CURDIR)/debian/phvalheim-client/usr/bin
	cp -r \$(CURDIR)/bin/Release/net6.0/linux-x64/publish/phvalheim-client \$(CURDIR)/debian/phvalheim-client/usr/bin
	mkdir -p \$(CURDIR)/debian/phvalheim-client/usr/share/applications
	cp -r \$(CURDIR)/debian/phvalheim.desktop \$(CURDIR)/debian/phvalheim-client/usr/share/applications

override_dh_strip:
	dh_strip --exclude=phvalheim-client
	" > $SCRIPT_DIR/../debian/rules