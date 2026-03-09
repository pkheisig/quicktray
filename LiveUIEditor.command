#!/bin/bash
# Move to the directory where this script is located
cd "$(dirname "$0")"

echo "Opening Xcode for Real-Time UI Editing..."
open Package.swift

echo ""
echo "================================================="
echo "To see your changes in real-time:"
echo "1. In Xcode, open Sources > Views > ContentView.swift"
echo "2. Look at the right side of the screen (the Canvas)."
echo "3. If the Canvas is paused, click the 'Refresh' arrow or press Option+Cmd+P."
echo "4. Any changes you make to the SwiftUI code will now update instantly!"
echo "================================================="
echo ""
