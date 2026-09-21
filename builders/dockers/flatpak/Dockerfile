# Flatpak build + test image for phvalheim-client.
#
# Two jobs, deliberately in one image:
#
#   1. flatpak-builder, to turn the published linux-x64 binary into a
#      single-file .flatpak bundle.
#   2. a full desktop test rig -- Xvfb, a real browser, xdotool -- because the
#      whole point of the Flatpak is the phvalheim:// URL handler, and the only
#      honest way to test a URL handler is to click a link in a browser.
#
# It must be run --privileged. Flatpak builds and runs apps with bubblewrap,
# which needs user namespaces and mount privileges that a default Docker
# container does not have. Without it flatpak-builder fails at the first
# sandbox setup with a confusing "No such file or directory" on /proc.
#
# The runtime (org.freedesktop.Platform) is NOT baked in: installing it needs
# the same privileges, which docker build does not grant. The outie mounts a
# host cache directory over /root/.local/share/flatpak so the ~1.5 GB download
# happens once instead of every build.

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      flatpak \
      flatpak-builder \
      ca-certificates \
      file \
      xz-utils \
      zstd \
      python3 \
      python3-pil \
      desktop-file-utils \
      shared-mime-info \
      xdg-utils \
      appstream \
      libglib2.0-bin \
      imagemagick \
      xvfb \
      xdotool \
      x11-utils \
      dbus-x11 \
      procps \
      chromium \
      firefox-esr \
      fonts-dejavu-core \
      xterm \
      x11-xserver-utils \
      zip \
      libicu76 \
    && rm -rf /var/lib/apt/lists/*

# libicu is for test_native_passthrough.py, which runs the published binary
# OUTSIDE any flatpak. A self-contained .NET build still needs the system ICU
# and dies with "Couldn't find a valid ICU package" without it.
#
# Worth knowing beyond this image: the Flatpak is unaffected because
# org.freedesktop.Platform ships ICU, but the .deb and .rpm declare NO
# dependencies at all, so they hit exactly this crash on a minimal install.
# That is a pre-existing defect in those two packages, not something the
# Flatpak work introduced.

# The desktop entry is Terminal=true, matching the .deb and .rpm. GLib honours
# that by looking for a terminal emulator from a fixed list and REFUSING to
# launch if it finds none. Without a terminal installed here, every test that
# opens a phvalheim:// link through the desktop file would fail for a reason
# that has nothing to do with the package under test.
RUN update-alternatives --install /usr/bin/x-terminal-emulator \
      x-terminal-emulator /usr/bin/xterm 50

# Chromium refuses to launch an unknown URL scheme without an "Open xdg-open?"
# confirmation dialog that nothing can click reliably. This enterprise policy
# makes it hand phvalheim:// straight to the system handler, which is exactly
# what a user who ticked "always allow" gets. Without it the browser test can
# only ever prove the dialog appeared, not that the handler ran.
RUN mkdir -p /etc/chromium/policies/managed \
    && printf '%s\n' \
      '{' \
      '  "AutoLaunchProtocolsFromOrigins": [' \
      '    {"protocol": "phvalheim", "allowed_origins": ["*"]}' \
      '  ],' \
      '  "DefaultBrowserSettingEnabled": false,' \
      '  "MetricsReportingEnabled": false' \
      '}' > /etc/chromium/policies/managed/phvalheim-test.json

# ImageMagick's default policy in Debian blocks some coders; the screenshot
# comparisons here only ever touch PNG, but be explicit rather than debugging
# a policy denial later.
ENV MAGICK_CONFIGURE_PATH=/tmp

WORKDIR /git
