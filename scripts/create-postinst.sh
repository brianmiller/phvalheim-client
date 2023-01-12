#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Get path to debian folder
DEBIAN_DIR=$SCRIPT_DIR/../debian

# Create a minimal postinst file
echo "#!/bin/sh
set -e

if [ \"$1\" = \"configure\" ]; then
  update-desktop-database -q
  gio mime x-scheme-handler/phvalheim phvalheim.desktop
fi
" > $DEBIAN_DIR/postinst

# Make sure path exists
mkdir -p $DEBIAN_DIR/phvalheim-client/usr/share/applications

# Add a .Desktop file for the x-url-handler
echo "[Desktop Entry]
Name=PhValheim-Client
Comment=PhValheim-Client
Exec=/usr/bin/phvalheim-client %U
Terminal=true
Type=Application
MimeType=x-scheme-handler/phvalheim;
" > $DEBIAN_DIR/phvalheim.desktop


#  phvalheim://?bGF1bmNoP3Rlc3QtYmFzaWM/aGFtbWVydGltZT92YWxoZWltLmdhbWV6LmltbWFkdWNrLnh5ej8yNTAwMj90b3dlci5sb2NhbDo4MDYxP2h0dHA=