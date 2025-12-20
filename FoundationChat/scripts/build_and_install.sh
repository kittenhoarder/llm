#!/bin/bash

# Build and install FoundationChat to /Applications
# Usage: ./build_and_install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODE_PROJECT="$PROJECT_DIR/FoundationChat.xcodeproj"
APP_NAME="FoundationChat.app"
APPLICATIONS_DIR="/Applications"
TARGET_APP="${APPLICATIONS_DIR}/${APP_NAME}"

echo "Building FoundationChat..."
cd "$PROJECT_DIR"

# Build the app
xcodebuild -project "$XCODE_PROJECT" \
    -scheme FoundationChat \
    -configuration Release \
    -derivedDataPath "$PROJECT_DIR/build" \
    clean build

# Find the built app
BUILT_APP=$(find "$PROJECT_DIR/build" -name "$APP_NAME" -type d | head -1)

if [ -z "$BUILT_APP" ]; then
    echo "Error: Could not find built app"
    exit 1
fi

echo "Found built app at: $BUILT_APP"

# Remove existing app if it exists
if [ -d "$TARGET_APP" ]; then
    echo "Removing existing $TARGET_APP..."
    rm -rf "$TARGET_APP"
fi

# Copy to Applications
echo "Installing $APP_NAME to $APPLICATIONS_DIR..."
cp -R "$BUILT_APP" "$TARGET_APP"

# Set proper permissions
chmod -R 755 "$TARGET_APP"

echo "✅ Successfully installed $APP_NAME to $APPLICATIONS_DIR"
echo "You can now launch it from Applications or Spotlight"



