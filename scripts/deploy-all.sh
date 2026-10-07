#!/bin/zsh
# Gzowo Concierge - smoke test, then deploy only what changed since the last deploy: host (LaunchAgent), Mac app, Firebase hosting, Pages mirror, database rules.
set -u
cd "$(dirname "$0")/.."
MARK=".claude/.last-deploy"
HEAD_SHA="$(git rev-parse HEAD)"
FROM="$( [ -f "$MARK" ] && cat "$MARK" || git rev-list --max-parents=0 HEAD | tail -1 )"
CHANGED="$(git diff --name-only "$FROM" "$HEAD_SHA"; git status --porcelain | awk '{print $2}')"
has() { echo "$CHANGED" | grep -qE "$1"; }

echo "deploy-all: $FROM -> $HEAD_SHA"
fail() { echo "SMOKE TEST FAILED: $1 (nothing deployed)"; exit 1; }

for f in host/*.mjs host/tools/*.mjs host/connectors/*.mjs scripts/*.mjs web/*.js web/ui/*.js; do
  [ -f "$f" ] && { node --check "$f" 2>/dev/null || fail "syntax error in $f"; }
done
[ -f web/index.html ] || fail "web/index.html missing"
echo "smoke: syntax ok"

HOST=0; WEB=0; MAC=0; RULES=0
has '^(host/|skills/|package.json|scripts/install.sh)' && HOST=1
has '^web/' && { WEB=1; HOST=1; }
has '^mac/' && MAC=1
has '^database.rules.json' && RULES=1

if [ $HOST = 1 ]; then
  ./scripts/install.sh >/tmp/deploy-host.log 2>&1 || fail "host install (see /tmp/deploy-host.log)"
  ok=0; for i in $(seq 1 20); do sleep 1; curl -s -m 2 localhost:2040/api/health | grep -q '"ok":true' && { ok=1; break; }; done
  [ $ok = 1 ] || fail "host did not come back healthy"
  echo "host: deployed and healthy"
fi
if [ $RULES = 1 ]; then firebase deploy --only database --project gzowo-concierge >/tmp/deploy-rules.log 2>&1 && echo "database rules: deployed" || echo "database rules: FAILED (see /tmp/deploy-rules.log)"; fi
if [ $WEB = 1 ]; then
  firebase deploy --only hosting --project gzowo-concierge >/tmp/deploy-hosting.log 2>&1 && echo "firebase hosting: deployed" || echo "firebase hosting: FAILED (see /tmp/deploy-hosting.log)"
  ./scripts/publish-pages.sh >/tmp/deploy-pages.log 2>&1 && echo "concierge.gzowo.fun: published" || echo "pages publish: FAILED (see /tmp/deploy-pages.log)"
fi
if [ $MAC = 1 ]; then
  WAS=$(pgrep -x Concierge || true)
  ./mac/build.sh >/tmp/deploy-mac.log 2>&1 && echo "mac app: built and installed" || echo "mac app: FAILED (see /tmp/deploy-mac.log)"
  [ -n "$WAS" ] && open "/Applications/Gzowo Concierge.app"
fi

echo "$HEAD_SHA" > "$MARK"
echo "deploy-all: done"
