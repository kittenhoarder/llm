#!/bin/bash

# Script to add "Install to Applications" build phase via Xcode
# This is a helper - you can also add it manually in Xcode

echo "To add auto-install to Applications:"
echo ""
echo "1. Open FoundationChat.xcodeproj in Xcode"
echo "2. Select the 'FoundationChat' target"
echo "3. Go to 'Build Phases' tab"
echo "4. Click the '+' button and select 'New Run Script Phase'"
echo "5. Name it 'Install to Applications'"
echo "6. Move it to the end (after Resources)"
echo "7. Paste this script:"
echo ""
cat << 'SCRIPT'
APP_NAME="FoundationChat.app"
BUILT_APP="${BUILT_PRODUCTS_DIR}/${APP_NAME}"
APPLICATIONS_DIR="/Applications"
TARGET_APP="${APPLICATIONS_DIR}/${APP_NAME}"

if [ ! -d "${BUILT_APP}" ]; then
    echo "Error: ${BUILT_APP} not found"
    exit 1
fi

if [ -d "${TARGET_APP}" ]; then
    echo "Removing existing ${TARGET_APP}..."
    rm -rf "${TARGET_APP}"
fi

echo "Installing ${APP_NAME} to ${APPLICATIONS_DIR}..."
cp -R "${BUILT_APP}" "${TARGET_APP}"
chmod -R 755 "${TARGET_APP}"

echo "✅ Successfully installed ${APP_NAME} to ${APPLICATIONS_DIR}"
SCRIPT

echo ""
echo "Or use the build_and_install.sh script to build and install manually."




