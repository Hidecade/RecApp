#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${VERSION:-1.0}
NOTARY_PROFILE=${NOTARY_PROFILE:-Aureline-notary}
APP_IDENTITY=${APP_IDENTITY:-Developer ID Application: Hideki Konishi (8H7SC722UJ)}
INSTALLER_IDENTITY=${INSTALLER_IDENTITY:-Developer ID Installer: Hideki Konishi (8H7SC722UJ)}
APP="$ROOT/dist/RecApp.app"
PKG="$ROOT/dist/RecApp-$VERSION-macOS.pkg"

"$ROOT/scripts/build-app.sh"

codesign --force --deep --options runtime --timestamp \
    --sign "$APP_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$PKG"
productbuild \
    --component "$APP" /Applications \
    --identifier com.hidecade.recapp.installer \
    --version "$VERSION" \
    --sign "$INSTALLER_IDENTITY" \
    "$PKG"

xcrun notarytool submit "$PKG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
spctl --assess --type install --verbose=2 "$PKG"

echo "$PKG"
