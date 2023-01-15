#!/bin/bash

# Get the directory of the script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# set the working directory to the root directory
ROOT=$SCRIPT_DIR/../

cd $ROOT

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



mkdir -p ./scripts/steam-deck

cp bin/Release/net6.0/linux-x64/publish/phvalheim-client ./scripts/steam-deck/phvalheim-client

# Add a .Desktop file for the x-url-handler
echo "[Desktop Entry]
Name=PhValheim-Client
Comment=PhValheim-Client
Exec=/usr/bin/phvalheim-client %U
Terminal=true
Type=Application
MimeType=x-scheme-handler/phvalheim;
" > ./scripts/steam-deck/phvalheim-client.desktop

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
    gio mime x-scheme-handler/phvalheim phvalheim-client.desktop
elif [ \"\$1\" = \"uninstall\" ]; then
    # uninstall
    rm /usr/bin/phvalheim-client
    rm /usr/share/applications/phvalheim-client.desktop
    update-desktop-database -q
    gio mime x-scheme-handler/phvalheim phvalheim-client.desktop
else
    echo \"Invalid argument. Use install or uninstall\"
fi
" > ./scripts/steam-deck/phvalheim-steam-deck.sh

# Get latest tag from github
LATEST_TAG=$(curl -s https://api.github.com/repos/brianmiller/phvalheim-client/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')

# Archive the files
cd ./scripts/steam-deck
tar -czvf $ROOT/published_build/phvalheim-client-$LATEST_TAG-steam-deck.tar.gz phvalheim-client phvalheim-client.desktop phvalheim-steam-deck.sh

cd $ROOT

# Remove the files
rm ./scripts/steam-deck/phvalheim-client
rm ./scripts/steam-deck/phvalheim-client.desktop
rm ./scripts/steam-deck/phvalheim-steam-deck.sh
rmdir ./scripts/steam-deck