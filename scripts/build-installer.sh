#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${VERSION:-1.0.3}
BUILD_NUMBER=${BUILD_NUMBER:-6}
NOTARY_PROFILE=${NOTARY_PROFILE:-Aureline-notary}
APP_IDENTITY=${APP_IDENTITY:-Developer ID Application: Hideki Konishi (8H7SC722UJ)}
INSTALLER_IDENTITY=${INSTALLER_IDENTITY:-Developer ID Installer: Hideki Konishi (8H7SC722UJ)}
APP="$ROOT/dist/build-$VERSION/RecApp.app"
PKG="$ROOT/dist/RecApp-$VERSION-macOS.pkg"
STAGING_ROOT="$ROOT/dist/.installer-root"
VERIFY_ROOT="$ROOT/dist/.installer-verify"

APP_PATH="$APP" "$ROOT/scripts/build-app.sh"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
codesign --force --deep --options runtime --timestamp \
    --sign "$APP_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$STAGING_ROOT"
mkdir -p "$STAGING_ROOT/Applications"
cp -R "$APP" "$STAGING_ROOT/Applications/RecApp.app"
codesign --verify --deep --strict --verbose=2 "$STAGING_ROOT/Applications/RecApp.app"

rm -f "$PKG"
pkgbuild \
    --root "$STAGING_ROOT" \
    --install-location / \
    --component-plist "$ROOT/Resources/InstallerComponents.plist" \
    --identifier com.hidecade.recapp \
    --version "$VERSION" \
    --sign "$INSTALLER_IDENTITY" \
    "$PKG"

rm -rf "$VERIFY_ROOT"
pkgutil --expand-full "$PKG" "$VERIFY_ROOT"
codesign --verify --deep --strict --verbose=2 "$VERIFY_ROOT/Payload/Applications/RecApp.app"

# Prevent Installer from discovering the signed build as an existing app.
rm -rf "$STAGING_ROOT" "$VERIFY_ROOT" "$APP"

xcrun notarytool submit "$PKG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
spctl --assess --type install --verbose=2 "$PKG"
pkgutil --check-signature "$PKG"

echo "$PKG"
