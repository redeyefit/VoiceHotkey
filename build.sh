#!/bin/bash
set -euo pipefail

# VoiceHotkey Build & Install Script
# Compiles Swift, creates .app bundle, codesigns, installs

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJECT_DIR/VoiceHotkey/main.swift"
INFO_PLIST="$PROJECT_DIR/VoiceHotkey/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/VoiceHotkey/VoiceHotkey.entitlements"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="VoiceHotkey"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
SIGNING_ID="889977587632369F6808CD6C156F21E531B9A84C"

echo "=== VoiceHotkey Build ==="

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Compile
echo "[1/4] Compiling..."
swiftc "$SRC" \
    -o "$BUILD_DIR/$APP_NAME" \
    -target arm64-apple-macos13 \
    -framework Cocoa \
    -framework CoreGraphics \
    -O

echo "  -> Binary: $(du -h "$BUILD_DIR/$APP_NAME" | cut -f1) compiled"

# Step 2: Create .app bundle
echo "[2/4] Creating .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

# Step 3: Codesign
echo "[3/4] Codesigning..."
codesign --force --deep --sign "$SIGNING_ID" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

# Verify signature
codesign --verify --verbose "$APP_BUNDLE" 2>&1 | head -2
echo "  -> Signed OK"

# Step 4: Install
echo "[4/4] Installing..."
mkdir -p "$INSTALL_DIR"

# Kill existing if running
pkill -f "VoiceHotkey" 2>/dev/null || true

# Remove old installation
rm -rf "$INSTALL_DIR/$APP_NAME.app"

# Copy new build
cp -R "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "=== Build Complete ==="
echo "Installed: $INSTALL_DIR/$APP_NAME.app"
echo ""
echo "Next steps:"
echo "  1. Open System Settings > Privacy & Security > Accessibility"
echo "     -> Add $INSTALL_DIR/$APP_NAME.app"
echo "  2. Open System Settings > Privacy & Security > Input Monitoring"
echo "     -> Add $INSTALL_DIR/$APP_NAME.app"
echo "  3. Run: ./install-service.sh  (to auto-start on login)"
echo ""
echo "Or test manually: open $INSTALL_DIR/$APP_NAME.app"
