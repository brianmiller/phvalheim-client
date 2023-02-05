#!/bin/bash
# Get the directory of the script
scriptDir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


# set the working directory to the root directory
gitRoot=$scriptDir/../
cd $gitRoot


# get the version of this release
thisVersion=$(grep -oPm1 "(?<=<Version>)[^<]+" $gitRoot/phvalheim-client.csproj)


# if the staging directory exists, then delete it
if [ ! -d ./scripts/staging ]; then
     mkdir ./scripts/staging
fi


# generate .desktop file for the x-url-handler
echo "[Desktop Entry]
Name=PhValheim-Client
Comment=PhValheim-Client
Exec=/usr/bin/phvalheim-client %U
Terminal=false
Type=Application
MimeType=x-scheme-handler/phvalheim;
" > ./scripts/staging/phvalheim-client.desktop


# generate installer script
echo "#!/bin/bash

# Get the directory of the script
SCRIPT_DIR=\$( cd -- \"\$( dirname -- \"\${BASH_SOURCE[0]}\" )\" &> /dev/null && pwd )

# set the working directory to the script directory
cd \$SCRIPT_DIR

# check first argument for install or uninstall
if [ \"\$1\" = \"install\" ]; then
    # install
    cp ./phvalheim-client /usr/bin/phvalheim-client
    cp ./phvalheim-client.desktop /usr/share/applications/phvalheim-client.desktop
    update-desktop-database -q
elif [ \"\$1\" = \"uninstall\" ]; then
    # uninstall
    rm /usr/bin/phvalheim-client
    rm /usr/share/applications/phvalheim-client.desktop
    update-desktop-database -q
else
    echo \"Invalid argument. Use install or uninstall\"
fi
" > ./scripts/staging/phvalheim-client-installer.sh


# remove phvalheim-client's linux binary from staging directory, if exists
if [ -f ./scripts/staging/phvalheim-client ]; then
	rm ./scripts/staging/phvalheim-client
fi


# copy in phvalheim-client's linux binary
cp $gitRoot/bin/Release/net6.0/linux-x64/publish/phvalheim-client ./scripts/staging/.

# echo the date
echo
echo "Today's date: `date`"

# build tarball
echo
echo "Packaging \"PhValheim Universal Linux Client v$thisVersion\"..."
cd ./scripts/staging
tar -czvf $gitRoot/builds/phvalheim-client-$thisVersion-universal-x86_64.tar.gz phvalheim-client phvalheim-client.desktop phvalheim-client-installer.sh


# publish to github
echo
echo "Publishing to Github..."
git add $gitRoot/builds/phvalheim-client-$thisVersion-universal-x86_64.tar.gz
git commit -m "Universal Linux build $thisVersion"
git push
echo
