#!/bin/bash

# Claudacity Build Script
# Usage: ./scripts/build.sh [release|debug]

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
SCHEME="Claudacity"
CONFIGURATION="${1:-Release}"

echo "🔨 Building Claudacity..."
echo "   Configuration: ${CONFIGURATION}"
echo "   Build Directory: ${BUILD_DIR}"
echo ""

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Build the app
xcodebuild \
    -project "${PROJECT_DIR}/Claudacity.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -destination "platform=macOS" \
    build

# Find and copy the app bundle
APP_PATH=$(find "${BUILD_DIR}/DerivedData" -name "Claudacity.app" -type d | head -1)

if [ -n "${APP_PATH}" ]; then
    cp -R "${APP_PATH}" "${BUILD_DIR}/"
    echo ""
    echo "✅ Build successful!"
    echo "   App location: ${BUILD_DIR}/Claudacity.app"
    echo ""
    echo "   To install, run:"
    echo "   cp -R \"${BUILD_DIR}/Claudacity.app\" /Applications/"
else
    echo "❌ Build failed: Could not find Claudacity.app"
    exit 1
fi
