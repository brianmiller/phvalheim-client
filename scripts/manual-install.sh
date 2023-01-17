#!/bin/bash

# Get the directory of the script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# set the working directory to the root directory
ROOT=$SCRIPT_DIR/../
cd $ROOT

source $SCRIPT_DIR/_helpers.sh

# Get latest tag from github
VERSION=$(get_version $ROOT)

# if the staging directory exists, then delete it
if [ -d $ROOT/scripts/staging ]; then
    rm -rf $ROOT/scripts/staging
fi

echo "Building $VERSION"

# Build release
dotnet publish \
		-c Release \
        -r linux-x64 \
        -p:PublishSingleFile=true \
        --self-contained true \
        ./phvalheim-client.csproj \
        /property:GenerateFullPaths=true \
        /consoleloggerparameters:NoSummary \
		/p:PublishTrimmed=false



mkdir -p ./scripts/staging

cp bin/Release/net6.0/linux-x64/publish/phvalheim-client ./scripts/staging/phvalheim-client

# Add a .Desktop file for the x-url-handler
echo "[Desktop Entry]
Name=PhValheim-Client
Comment=PhValheim-Client
Exec=/usr/bin/phvalheim-client %U
Terminal=false
Type=Application
MimeType=x-scheme-handler/phvalheim;
" > ./scripts/staging/phvalheim-client.desktop

# Create a install / uninstall script
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

# Archive the files
cd ./scripts/staging
tar -czvf $ROOT/published_build/phvalheim-client-$VERSION-linux_x64.tar.gz phvalheim-client phvalheim-client.desktop phvalheim-client-installer.sh

cd $ROOT

# Remove the files
rm ./scripts/staging/phvalheim-client
rm ./scripts/staging/phvalheim-client.desktop
rm ./scripts/staging/phvalheim-client-installer.sh
rmdir ./scripts/staging