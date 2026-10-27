#!/bin/bash
# Concierge Pokój - installs the room app on MacPetite over SSH: the app, settings (host address, token, contacts), Gemini keys and a LaunchAgent.
set -euo pipefail
TARGET="${1:-jerzysukiennik@MacPetite.local}"
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
./build.sh
APP="$ROOT/Niepotrzebne/room-build/Concierge Pokój.app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

HOSTS=("http://$(scutil --get LocalHostName).local:2040")
IP="$(ipconfig getifaddr en0 || true)"
[ -n "$IP" ] && HOSTS+=("http://$IP:2040")
TOKEN="$(grep '^CONCIERGE_TOKEN=' "$HOME/.gzowo-concierge/.env" | head -1 | cut -d= -f2-)"
CONTACTS="$ROOT/Niepotrzebne/room-contacts.json"
python3 - "$STAGE/config.json" "$TOKEN" "$CONTACTS" "${HOSTS[@]}" <<'EOF'
import json, os, sys
out, token, contacts, *hosts = sys.argv[1:]
c = json.load(open(contacts)) if os.path.exists(contacts) else {}
json.dump({"hosts": hosts, "token": token, "trusted": c.get("trusted", {}), "contacts": c.get("contacts", {}),
           "latitude": c.get("latitude", 52.2297), "longitude": c.get("longitude", 21.0122), "place": c.get("place", "Warszawa")},
          open(out, "w"), ensure_ascii=False, indent=1)
EOF
keys write "$STAGE" gemini >/dev/null
chmod 600 "$STAGE/config.json" "$STAGE/.env"

cat > "$STAGE/fun.gzowo.concierge.room.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>fun.gzowo.concierge.room</string>
	<key>ProgramArguments</key><array><string>/Applications/ConciergeRoom.app/Contents/MacOS/ConciergeRoom</string></array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ProcessType</key><string>Interactive</string>
	<key>StandardErrorPath</key><string>/tmp/concierge-room.log</string>
</dict>
</plist>
EOF

SUP="Library/Application Support/ConciergeRoom"
ssh "$TARGET" "mkdir -p '$SUP' Library/LaunchAgents && (launchctl bootout gui/\$(id -u)/fun.gzowo.concierge.room 2>/dev/null || launchctl unload Library/LaunchAgents/fun.gzowo.concierge.room.plist 2>/dev/null; pkill -x ConciergeRoom; true)"
tar -C "$(dirname "$APP")" -cf - "$(basename "$APP")" | ssh "$TARGET" "rm -rf /Applications/ConciergeRoom.app && mkdir -p /Applications/ConciergeRoom.app && tar -xf - -C /Applications/ConciergeRoom.app --strip-components 1"
ssh "$TARGET" "umask 077 && cat > '$SUP/config.json'" < "$STAGE/config.json"
ssh "$TARGET" "umask 077 && cat > '$SUP/.env'" < "$STAGE/.env"
ssh "$TARGET" "cat > Library/LaunchAgents/fun.gzowo.concierge.room.plist" < "$STAGE/fun.gzowo.concierge.room.plist"
ssh "$TARGET" "(launchctl bootstrap gui/\$(id -u) Library/LaunchAgents/fun.gzowo.concierge.room.plist 2>/dev/null || launchctl load -w Library/LaunchAgents/fun.gzowo.concierge.room.plist) && sleep 4 && pgrep -x ConciergeRoom >/dev/null && echo 'room: running on MacPetite' && tail -3 /tmp/concierge-room.log"
