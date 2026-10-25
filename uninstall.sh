#!/bin/bash
# Removes the app, its settings and its login item.
pkill -x ADHDKiller 2>/dev/null || true
rm -rf "/Applications/СДВГ Киллер.app" "$HOME/Applications/СДВГ Киллер.app"
rm -f "$HOME/Library/LaunchAgents/com.valikw.adhdkiller.plist"
rm -rf "$HOME/Library/Application Support/ADHDKiller"
echo "Removed. Remember to remove the app from System Settings → Privacy & Security → Accessibility."
