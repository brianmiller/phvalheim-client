# Build environment for the Windows .msi.
#
# Pinned to trixie, not bookworm: bookworm carries wixl 0.101, trixie carries
# 0.106. 0.101 has no `--ext ui` at all, so pinning trixie keeps the option of
# adding an install wizard later without changing base images.
#
# Also carries wine (to smoke-install the MSI -- Linux MSI builds get no ICE
# validation, so an actual install is the only real check) and osslsigncode
# (Authenticode signing, the Linux stand-in for signtool.exe).
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# wine pulls i386 for the 32-bit loader
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wixl \
      msitools \
      osslsigncode \
      openssl \
      ca-certificates \
      xz-utils \
      wine \
      wine64 \
 && rm -rf /var/lib/apt/lists/*

# wine needs a writable HOME for its prefix; the builder runs as root in-container
ENV WINEPREFIX=/tmp/wineprefix \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES=mscoree=d

CMD ["/bin/bash"]
