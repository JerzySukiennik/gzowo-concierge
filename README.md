# Gzowo Concierge

A personal AI concierge that runs as a background host on a Mac and gets things done: it reads and edits your iCloud calendar, researches the live web, and remembers what matters. Built on Gemini (free tier), zero npm dependencies.

## How it works

- `host/` is a Node host (built-in `node:sqlite`, `fetch`, `http`): agent loop with Gemini function calling, tools, per-action approval policy, NDJSON streaming API.
- `host/mac/cal.swift` is a small EventKit helper packaged as `ConciergeCal.app` so macOS grants it its own Calendar permission.
- `web/` is the chat UI served by the host.
- Per-action policy: every tool action is either `auto` or `ask`; `ask` actions wait for a one-tap approval in the app.

## Run

```sh
cp .env.example .env        # add GEMINI_API_KEY
npm run build:mac           # builds bin/ConciergeCal.app (first run asks for Calendar access)
npm start                   # http://localhost:2040
./scripts/install.sh        # deploy as a LaunchAgent (auto-start, auto-restart, no idle sleep)
```

Non-loopback requests need the `CONCIERGE_TOKEN` from `.env` (bearer header or `?t=` once).
