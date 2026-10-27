#!/usr/bin/env bash
set -euo pipefail

# scripts/package_python.sh
# Bundles engine/, server/, and pure-Python dependencies (websockets)
# for embedded execution on Android via serious_python.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/app"
STAGE_DIR="$APP_DIR/build/python_app_stage"
SITE_PACKAGES_DIR="$APP_DIR/build/site-packages"
ASSET_ZIP="$APP_DIR/assets/app.zip"

echo "=== Impostor Embedded Python Packaging ==="
echo "Project root: $PROJECT_ROOT"
echo "App directory: $APP_DIR"
echo "Python version: 3.12"

# 1. Clean and prepare staging directory
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
mkdir -p "$SITE_PACKAGES_DIR"
mkdir -p "$APP_DIR/assets"

# 2. Copy source modules into staging directory (excluding pycache and tests)
echo "Staging engine/ and server/..."
rsync -av --exclude '__pycache__' --exclude '*.pyc' "$PROJECT_ROOT/engine" "$STAGE_DIR/"
rsync -av --exclude '__pycache__' --exclude '*.pyc' "$PROJECT_ROOT/server" "$STAGE_DIR/"

# 3. Export environment variables required by serious_python CLI and Gradle build
export SERIOUS_PYTHON_VERSION=3.12
export SERIOUS_PYTHON_SITE_PACKAGES="$SITE_PACKAGES_DIR"

# 4. Run serious_python package command
echo "Packaging Python app with dart run serious_python:main package..."
(
    cd "$APP_DIR"
    dart run serious_python:main package "$STAGE_DIR" \
        -p Android \
        --python-version 3.12 \
        -a assets/app.zip \
        -r websockets==17.3
)

echo "=== Packaging Complete ==="
echo "Asset Zip: $ASSET_ZIP ($(du -h "$ASSET_ZIP" | cut -f1))"
echo "Site packages directory: $SITE_PACKAGES_DIR"
