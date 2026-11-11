#!/bin/bash
# Build ShareMount (Release) and install it to /Applications.
# Usage:  ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ShareMount"
DEST="/Applications/$APP_NAME.app"
DERIVED="build/DerivedData"
LOCAL_SIGNING="Config/Signing.local.xcconfig"

command -v xcodegen >/dev/null || { echo "XcodeGen is missing. Run: brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null || { echo "Xcode is missing. Install it from the App Store."; exit 1; }

# --- Signing: find your Team ID once and remember it -------------------------
if [ ! -f "$LOCAL_SIGNING" ]; then
    # The OU field of your "Apple Development" certificate is your Team ID.
    # Xcode creates that certificate the first time you pick a Team and build.
    TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -n1 || true)
    if [ -n "${TEAM:-}" ]; then
        echo "DEVELOPMENT_TEAM = $TEAM" > "$LOCAL_SIGNING"
        echo "Using Team ID $TEAM (saved to $LOCAL_SIGNING)."
    fi
fi

SIGN_ARGS=()
if [ -f "$LOCAL_SIGNING" ] && grep -q "DEVELOPMENT_TEAM *= *[A-Z0-9]" "$LOCAL_SIGNING"; then
    SIGN_ARGS=(-allowProvisioningUpdates)
else
    echo "No Apple Development certificate found, so building with a local-only"
    echo "signature. It works, but macOS may ask for Keychain access again after"
    echo "each reinstall. To fix: open the project in Xcode, pick your Team under"
    echo "Signing & Capabilities, press ⌘B once, then run this script again."
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

# --- Build --------------------------------------------------------------------
echo "Generating project…"
xcodegen generate --quiet

echo "Building (this takes a minute the first time)…"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -derivedDataPath "$DERIVED" -quiet "${SIGN_ARGS[@]}" build

BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$BUILT" ] || { echo "Build finished but $BUILT is missing."; exit 1; }

# --- Install --------------------------------------------------------------------
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Quitting the running $APP_NAME…"
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
    sleep 1
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

echo "Installing to $DEST…"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

open "$DEST"
echo "Done. ShareMount is running from /Applications — look for its icon in the menu bar."
