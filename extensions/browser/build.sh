#!/usr/bin/env bash
# Build pad browser extension for Chrome and Firefox

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Clean and create dist directories
rm -rf dist
mkdir -p dist/chrome dist/firefox

# Copy shared files and icons
cp shared/* dist/chrome/
cp shared/* dist/firefox/
cp icons/*.png dist/chrome/
cp icons/*.png dist/firefox/

# Copy browser-specific manifests
cp chrome/manifest.json dist/chrome/
cp firefox/manifest.json dist/firefox/

# Create zip packages (if zip is available)
cd dist
if command -v zip &> /dev/null; then
  zip -r pad-chrome.zip chrome
  zip -r pad-firefox.zip firefox
  echo "Built:"
  echo "  dist/pad-chrome.zip"
  echo "  dist/pad-firefox.zip"
else
  echo "Built (unzipped):"
  echo "  dist/chrome/"
  echo "  dist/firefox/"
  echo ""
  echo "To create .zip packages, install zip and run:"
  echo "  cd dist && zip -r pad-chrome.zip chrome && zip -r pad-firefox.zip firefox"
fi
