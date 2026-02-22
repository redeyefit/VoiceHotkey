#!/bin/bash
set -euo pipefail

# Install VoiceHotkey as a login LaunchAgent

PLIST_NAME="com.fieldvision.voicehotkey"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
APP_PATH="$HOME/Applications/VoiceHotkey.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: VoiceHotkey.app not found at $APP_PATH"
    echo "Run ./build.sh first"
    exit 1
fi

# Unload existing service if present
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

# Write the plist
cat > "$PLIST_PATH" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.fieldvision.voicehotkey</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-W</string>
		<string>__APP_PATH__</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>StandardOutPath</key>
	<string>/tmp/voicehotkey.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/voicehotkey.error.log</string>
	<key>ThrottleInterval</key>
	<integer>10</integer>
</dict>
</plist>
PLIST

# Replace placeholder with actual path
sed -i '' "s|__APP_PATH__|$APP_PATH|g" "$PLIST_PATH"

# Bootstrap (load) the service
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "=== VoiceHotkey Service Installed ==="
echo "Plist: $PLIST_PATH"
echo ""
echo "Status:"
launchctl print "gui/$(id -u)/$PLIST_NAME" 2>&1 | grep -E "state|pid|path" || echo "  Running"
echo ""
echo "Commands:"
echo "  Stop:    launchctl bootout gui/$(id -u)/$PLIST_NAME"
echo "  Restart: launchctl kickstart -k gui/$(id -u)/$PLIST_NAME"
echo "  Logs:    tail -f /tmp/voicehotkey.log"
echo "  Errors:  tail -f /tmp/voicehotkey.error.log"
