#!/bin/bash
#
# SwiftLint Build Phase Script for Xcode
# Add this as a "Run Script" build phase in Xcode
#
# To add to Xcode:
# 1. Select project in navigator
# 2. Select target > Build Phases
# 3. Click + > New Run Script Phase
# 4. Paste: "${SRCROOT}/Scripts/swiftlint-xcode.sh"
# 5. Move this phase after "Compile Sources"

set -e

# Check if SwiftLint is installed
if command -v swiftlint &> /dev/null; then
    SWIFTLINT_PATH=$(command -v swiftlint)
elif [ -f /opt/homebrew/bin/swiftlint ]; then
    SWIFTLINT_PATH="/opt/homebrew/bin/swiftlint"
elif [ -f /usr/local/bin/swiftlint ]; then
    SWIFTLINT_PATH="/usr/local/bin/swiftlint"
else
    echo "warning: SwiftLint not installed. Install with: brew install swiftlint"
    exit 0
fi

# Run SwiftLint
cd "${SRCROOT}"

if [ "${CONFIGURATION}" = "Debug" ]; then
    # In Debug mode, run with warnings
    ${SWIFTLINT_PATH} lint --config .swiftlint.yml --quiet
else
    # In Release mode, treat warnings as errors
    ${SWIFTLINT_PATH} lint --config .swiftlint.yml --strict --quiet
fi

exit 0
