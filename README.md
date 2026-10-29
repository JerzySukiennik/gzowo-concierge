# Gzowo Concierge

A personal AI concierge that runs as a background host on a Mac and gets things done: it reads and edits your iCloud calendar, researches the live web, and remembers what matters. Built on Gemini (free tier), zero npm dependencies.

## How it works

- `host/` is a Node host (built-in `node:sqlite`, `fetch`, `http`): agent loop with Gemini function calling, tools, per-action approval policy, NDJSON streaming API.
- `host/mac/cal.swift` is a small EventKit helper packaged as `ConciergeCal.app` so macOS grants it its own Calendar permission.
- `web/` is the chat UI served by the host.
- Per-action policy: every tool action is either `auto` or `ask`; `ask` actions wait for a one-tap approval in the app.

## Class plan

On request ("zrób plan klasy") the assistant starts a background job (`host/classplan.mjs`) that makes a one-week PDF for class 8K:
- **What goes in:** tests and quizzes with what each one covers (scope only, no notes or example tasks), days off and school events, and homework.
- **Who does the work:** Claude Sonnet 5.5, over raw HTTP with streaming (`host/claude.mjs`).
- **Sources:**
  - the school calendar;
  - Pupka;
  - both class WhatsApp groups, read only from WhatsApp Desktop's local database (`host/whatsapp.mjs`), including photos of notes;
  - scans and PDFs in `~/Documents/Szkoła/<subject>/`.
- **Questions:** when Sonnet needs Jurek, the question comes back through the channel the job came from. That is the live voice session (Gemini asks him and passes his answer with `class_plan_answer`), the room speaker, or the chat thread with a push notification.
- **The PDF:** it is printed by headless Chrome in the Minimal look (`host/classplan-render.mjs`). Every page carries a note that the information comes from Jurek and may be incomplete. The PDF opens on the Mac and is copied to `~/Documents/Szkoła/Plany klasy/`.
- **Sending:** nothing is posted to WhatsApp yet. When it is, the PDF goes with a short plain message built in code ("Załączam PDF z planem na cały tydzień 2-6 listopada."), followed by the same note as the PDF in italics and "Made by Gzowo Concierge". Every message the assistant sends there carries that note.

The Anthropic key comes from the key saved in settings or `ANTHROPIC_API_KEY(S)` in `.env`.

## Run

```sh
cp .env.example .env        # add GEMINI_API_KEY
npm run build:mac           # builds bin/ConciergeCal.app (first run asks for Calendar access)
npm start                   # http://localhost:2040
./scripts/install.sh        # deploy as a LaunchAgent (auto-start, auto-restart, no idle sleep)
```

Non-loopback requests need the `CONCIERGE_TOKEN` from `.env` (bearer header or `?t=` once).
