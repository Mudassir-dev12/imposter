#!/usr/bin/env bash
set -euo pipefail

# scripts/run_phone.sh
# Runs Impostor on the connected Android phone with required SeriousPython env vars.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../app" && pwd)"

export SERIOUS_PYTHON_VERSION=3.12
export SERIOUS_PYTHON_SITE_PACKAGES="$APP_DIR/build/site-packages"

# Ensure site packages exist
if [ ! -d "$SERIOUS_PYTHON_SITE_PACKAGES" ]; then
    echo "Site packages directory not found. Running packaging script first..."
    "$SCRIPT_DIR/package_python.sh"
fi

cd "$APP_DIR"

# Check if a device is connected
DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"

if [ -z "$DEVICE_ID" ]; then
    echo "ERROR: No Android device found via ADB."
    echo "Please plug in your phone via USB and ensure USB Debugging is enabled."
    adb devices
    exit 1
fi

echo "Connected device detected: $DEVICE_ID"
flutter run -d "$DEVICE_ID" "$@"
