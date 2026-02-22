#!/bin/bash
# Uninstall VoiceHotkey completely

PLIST_NAME="com.fieldvision.voicehotkey"

echo "Uninstalling VoiceHotkey..."

# Stop service
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

# Kill process
pkill -f "VoiceHotkey" 2>/dev/null || true

# Remove files
rm -f "$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
rm -rf "$HOME/Applications/VoiceHotkey.app"
rm -f /tmp/voicehotkey.log /tmp/voicehotkey.error.log

echo "Done. Remove from Accessibility & Input Monitoring manually if desired."
