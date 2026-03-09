#!/bin/bash
# Move to the directory where this script is located
cd "$(dirname "$0")"

echo "Building QuickTray..."
./build.sh

echo "Launching QuickTray..."
open build/QuickTray.app
