#!/bin/bash
# PhValheim Client - macOS installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/macinstall.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/macinstall.sh | bash -s -- uninstall
#   curl -fsSL https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/macinstall.sh | bash -s -- diags

set -e

GITHUB_REPO="brianmiller/phvalheim-client"
INSTALL_BIN="/usr/local/bin/phvalheim-client"
INSTALL_APP="/Applications/PhValheim Client.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
STEAM_DIR="$HOME/Library/Application Support/Steam"
VALHEIM_APP="$STEAM_DIR/steamapps/common/Valheim/Valheim.app"
PHVALHEIM_CONFIG="$HOME/Library/Application Support/PhValheim"

ok()   { echo "  [OK]  $*"; }
warn() { echo "  [!!]  $*"; }
fail() { echo "  [XX]  $*"; }

ACTION="${1:-install}"

# ── install ────────────────────────────────────────────────────────────────────
do_install() {
    echo
    echo "=== PhValheim Client - macOS Installer ==="
    echo

    # fetch latest release version from GitHub API
    echo "Fetching latest release info..."
    RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest")
    VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    if [ -z "$VERSION" ]; then
        echo "ERROR: Could not determine latest release version."
        echo "       Check: https://github.com/$GITHUB_REPO/releases"
        exit 1
    fi
    echo "Latest version: $VERSION"

    # build download URL
    TARBALL="phvalheim-client-${VERSION}-macos-universal.tar.gz"
    DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$VERSION/$TARBALL"

    # download to temp dir
    TMPDIR=$(mktemp -d)
    trap "rm -rf '$TMPDIR'" EXIT

    echo "Downloading $TARBALL..."
    curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMPDIR/$TARBALL"

    echo "Extracting..."
    tar xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"

    # install binary
    echo "Installing binary..."
    sudo mkdir -p /usr/local/bin
    sudo cp "$TMPDIR/phvalheim-client" "$INSTALL_BIN"
    sudo chmod 755 "$INSTALL_BIN"
    sudo xattr -rd com.apple.quarantine "$INSTALL_BIN" 2>/dev/null || true

    # install .app bundle
    echo "Installing URL handler app..."
    sudo rm -rf "$INSTALL_APP"
    sudo cp -r "$TMPDIR/PhValheim Client.app" "$INSTALL_APP"
    sudo xattr -rd com.apple.quarantine "$INSTALL_APP" 2>/dev/null || true

    # register phvalheim:// URL scheme
    echo "Registering phvalheim:// URL scheme..."
    "$LSREGISTER" -f "$INSTALL_APP"

    echo
    echo "Done. PhValheim Client $VERSION installed."
    echo "  Binary:      $INSTALL_BIN"
    echo "  URL handler: $INSTALL_APP"
    echo
    echo "Click any phvalheim:// link to launch."
    echo
}

# ── uninstall ──────────────────────────────────────────────────────────────────
do_uninstall() {
    echo
    echo "=== PhValheim Client - Uninstall ==="
    echo
    echo "Removing $INSTALL_BIN..."
    sudo rm -f "$INSTALL_BIN"
    echo "Removing $INSTALL_APP..."
    "$LSREGISTER" -u "$INSTALL_APP" 2>/dev/null || true
    sudo rm -rf "$INSTALL_APP"
    echo
    echo "Done. PhValheim Client uninstalled."
    echo
}

# ── diags ──────────────────────────────────────────────────────────────────────
do_diags() {
    echo
    echo "=== PhValheim Client Diagnostics ==="
    echo

    echo "-- phvalheim-client binary --"
    if [ -f "$INSTALL_BIN" ]; then
        ok "Binary present: $INSTALL_BIN"
        INSTALLED_VER=$(defaults read "$INSTALL_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "unknown")
        ok "Installed version: $INSTALLED_VER"
        QUARANTINE=$(xattr "$INSTALL_BIN" 2>/dev/null | grep quarantine || true)
        if [ -n "$QUARANTINE" ]; then
            warn "Quarantine xattr set on binary (may be blocked)"
        else
            ok "No quarantine xattr on binary"
        fi
    else
        fail "Binary NOT found: $INSTALL_BIN"
    fi
    echo

    echo "-- PhValheim Client.app --"
    if [ -d "$INSTALL_APP" ]; then
        ok "App bundle present: $INSTALL_APP"
        HANDLER="$INSTALL_APP/Contents/MacOS/PhValheim Client"
        if [ -f "$HANDLER" ]; then
            ok "URL handler binary present"
        else
            fail "URL handler binary MISSING: $HANDLER"
        fi
        QUARANTINE=$(xattr "$INSTALL_APP" 2>/dev/null | grep quarantine || true)
        if [ -n "$QUARANTINE" ]; then
            warn "Quarantine xattr set on .app (URL scheme may be blocked)"
        else
            ok "No quarantine xattr on .app"
        fi
    else
        fail "App bundle NOT found: $INSTALL_APP"
    fi
    echo

    echo "-- phvalheim:// URL scheme --"
    REGISTERED=$("$LSREGISTER" -dump 2>/dev/null | grep -i "phvalheim" || true)
    if [ -n "$REGISTERED" ]; then
        ok "phvalheim:// scheme is registered"
    else
        warn "phvalheim:// scheme NOT found in LaunchServices database"
        warn "Try: $LSREGISTER -f \"$INSTALL_APP\""
    fi
    echo

    echo "-- Steam --"
    if [ -d "$STEAM_DIR" ]; then
        ok "Steam dir found: $STEAM_DIR"
    else
        fail "Steam dir NOT found: $STEAM_DIR"
    fi
    STEAM_EXE="/Applications/Steam.app/Contents/MacOS/steam_osx"
    if [ -f "$STEAM_EXE" ]; then
        ok "Steam executable found"
    else
        fail "Steam executable NOT found: $STEAM_EXE"
    fi
    echo

    echo "-- Valheim --"
    if [ -d "$VALHEIM_APP" ]; then
        ok "Valheim.app found: $VALHEIM_APP"
        VALHEIM_BIN="$VALHEIM_APP/Contents/MacOS/Valheim"
        if [ -f "$VALHEIM_BIN" ]; then
            ok "Valheim binary present"
            ARCHS=$(lipo -info "$VALHEIM_BIN" 2>/dev/null || echo "unknown")
            ok "Architectures: $ARCHS"
        else
            fail "Valheim binary NOT found: $VALHEIM_BIN"
        fi
        MONO_LIB="$VALHEIM_APP/Contents/Frameworks/libmonobdwgc-2.0.dylib"
        if [ -f "$MONO_LIB" ]; then
            ok "Mono lib present: $MONO_LIB"
        else
            warn "Mono lib NOT found: $MONO_LIB"
        fi
        ENTITLEMENTS=$(codesign -d --entitlements - "$VALHEIM_BIN" 2>/dev/null || true)
        if echo "$ENTITLEMENTS" | grep -q "allow-dyld-environment-variables"; then
            ok "Valheim has allow-dyld-environment-variables entitlement"
        else
            warn "allow-dyld-environment-variables entitlement NOT found (doorstop injection may fail)"
        fi
        if echo "$ENTITLEMENTS" | grep -q "disable-library-validation"; then
            ok "Valheim has disable-library-validation entitlement"
        else
            warn "disable-library-validation entitlement NOT found (unsigned dylibs may be blocked)"
        fi
    else
        fail "Valheim.app NOT found: $VALHEIM_APP"
        LIBFOLDERS="$STEAM_DIR/steamapps/libraryfolders.vdf"
        if [ -f "$LIBFOLDERS" ]; then
            warn "Check other Steam library paths in: $LIBFOLDERS"
        fi
    fi
    echo

    echo "-- PhValheim config --"
    if [ -d "$PHVALHEIM_CONFIG" ]; then
        ok "Config dir present: $PHVALHEIM_CONFIG"
        WORLD_COUNT=$(find "$PHVALHEIM_CONFIG/worlds" -maxdepth 3 -name "*.db" 2>/dev/null | wc -l | tr -d ' ')
        ok "World files found: $WORLD_COUNT"
    else
        ok "Config dir not yet created (normal before first launch)"
    fi
    echo

    echo "=== Diagnostics complete ==="
    echo
}

case "$ACTION" in
    install)   do_install   ;;
    uninstall) do_uninstall ;;
    diags)     do_diags     ;;
    *)
        echo "Usage: bash macinstall.sh [install|uninstall|diags]"
        echo "  install   (default) — download and install latest release"
        echo "  uninstall           — remove phvalheim-client"
        echo "  diags               — check installation health"
        exit 1
        ;;
esac
