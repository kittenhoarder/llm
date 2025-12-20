#!/bin/bash

# Script to install FoundationChat.app to /Applications
# This script runs as a build phase in Xcode

set -e

APP_NAME="FoundationChat.app"
BUILT_APP="${BUILT_PRODUCTS_DIR}/${APP_NAME}"
APPLICATIONS_DIR="/Applications"
TARGET_APP="${APPLICATIONS_DIR}/${APP_NAME}"

# Check if the built app exists
if [ ! -d "${BUILT_APP}" ]; then
    echo "Error: ${BUILT_APP} not found"
    exit 1
fi

# Remove existing app in Applications if it exists (for upgrade)
if [ -d "${TARGET_APP}" ]; then
    echo "Removing existing ${TARGET_APP}..."
    rm -rf "${TARGET_APP}"
fi

# Copy the app to Applications
echo "Installing ${APP_NAME} to ${APPLICATIONS_DIR}..."
cp -R "${BUILT_APP}" "${TARGET_APP}"

# Set proper permissions
chmod -R 755 "${TARGET_APP}"

echo "Successfully installed ${APP_NAME} to ${APPLICATIONS_DIR}"



