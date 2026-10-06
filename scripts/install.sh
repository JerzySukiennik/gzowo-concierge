#!/bin/zsh
# Gzowo Concierge - deploys a runtime copy to ~/.gzowo-concierge and (re)loads the LaunchAgent.
# The runtime lives outside ~/Downloads because launchd jobs cannot read that folder.
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)"
RT="$HOME/.gzowo-concierge"
LABEL="fun.gzowo.concierge"
PL="$HOME/Library/LaunchAgents/$LABEL.plist"
NODE="$(command -v node)"

mkdir -p "$RT/data" "$HOME/Library/LaunchAgents"
rsync -a --delete --exclude data --exclude .env --exclude node_modules --exclude .git "$SRC/host" "$SRC/web" "$SRC/bin" "$SRC/skills" "$SRC/package.json" "$RT/"
[ -f "$RT/.env" ] || cp "$SRC/.env" "$RT/.env"
chmod 600 "$RT/.env"
[ -f "$SRC/data/concierge.db" ] && [ ! -f "$RT/data/concierge.db" ] && [ "${COPY_DB:-0}" = "1" ] && cp "$SRC/data/concierge.db" "$RT/data/" || true

cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array>
<string>/usr/bin/caffeinate</string><string>-is</string><string>$NODE</string><string>$RT/host/server.mjs</string>
</array>
<key>WorkingDirectory</key><string>$RT</string>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>5</integer>
<key>StandardOutPath</key><string>$RT/data/server.log</string>
<key>StandardErrorPath</key><string>$RT/data/server.log</string>
</dict></plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "installed to $RT, agent $LABEL loaded"
