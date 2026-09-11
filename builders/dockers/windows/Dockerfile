# Build environment for the Windows .msi.
#
# Pinned to trixie, not bookworm: bookworm carries wixl 0.101, trixie carries
# 0.106. 0.101 has no `--ext ui` at all, so pinning trixie keeps the option of
# adding an install wizard later without changing base images.
#
# Also carries wine (to smoke-install the MSI -- Linux MSI builds get no ICE
# validation, so an actual install is the only real check) and osslsigncode
# (Authenticode signing, the Linux stand-in for signtool.exe).
#
# Xvfb + xdotool + ImageMagick are for builders/test_install_matrix.sh, which
# runs the wizard in FULL UI on a virtual display, screenshots each page and
# asserts on the pixels. That is not a luxury: of the six bugs that shipped in
# 2.0.13, four were rendering faults (maroon stock bitmap, blue body text,
# truncated paragraphs, wrong typeface) that every table assertion passed and
# only a human looking at the screen caught.
#
# python3 is the analysis language for those screenshots and for MSI tables,
# whose records span lines and defeat line-oriented awk.
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
      xvfb \
      xdotool \
      x11-utils \
      imagemagick \
      python3 \
      python3-pil \
 && rm -rf /var/lib/apt/lists/*

# wine needs a writable HOME for its prefix; the builder runs as root in-container
ENV WINEPREFIX=/tmp/wineprefix \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES=mscoree=d

CMD ["/bin/bash"]
