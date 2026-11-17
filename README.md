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
- **Sending:** when Jurek says "wyślij plan", `class_plan_send` posts the PDF to "Ogłoszenia klasowe 8K" with a short plain caption built in code ("Załączam PDF z planem na cały tydzień 2-6 listopada."), followed by the same note as the PDF in italics and "Made by Gzowo Concierge". A plan that was already sent is not sent again unless he asks.

The Anthropic key comes from the key saved in settings or `ANTHROPIC_API_KEY(S)` in `.env`.

## WhatsApp messages

`whatsapp_send` sends a text message from Jurek's WhatsApp on the main Mac, by voice or chat, without a confirmation step (his choice).
- **Finding the chat:** the host looks up the name in WhatsApp Desktop's local database (`host/whatsapp.mjs`). An exact name wins; several partial matches come back as a list, so the assistant asks which one.
- **Sending:** the Concierge Mac app (`mac/Sources/WhatsAppSender.swift`, needs Accessibility) brings WhatsApp to the front, types the chat name into search, opens the chat and checks its header, clicks the composer, pastes the text (or the file, with the text as its caption), checks that it arrived intact and presses Send. It restores the clipboard and the previous app. It stops before any keystroke if WhatsApp is not in front, if the screen is locked or if the chat already has an unsent draft.
- **Signature:** code adds "Made by Gzowo Concierge" to every message. In the class groups it also adds the note that the information comes from Jurek and may be incomplete, in italics.

## The island

The Mac app draws a black island at the top of the screen (`mac/Sources/Notch*.swift`). It is one shape that springs between live activities; content melts in and out with a blur.
- **Priority:** volume or brightness, dictation, the screen agent, a finished timer, a track change, then Concierge at work, a running timer, the next event (within 30 minutes), and music. The second activity shows as a small bubble next to the island.
- **Volume, brightness, keyboard light:** `SystemLevels.swift` takes over the media keys with an event tap (needs Accessibility) and sets volume (CoreAudio), screen brightness (DisplayServices) and the keyboard light (CoreBrightness) itself, so the level shows on the island instead of the system bezel. Option plus a key still opens the system settings, Option+Shift gives fine steps. Changes made elsewhere (the Touch Bar slider, AirPods) show too.
- **Now playing:** macOS no longer lets ordinary apps read MediaRemote, so `mac/media/nowplaying.m` is a small library that the app loads into `/usr/bin/perl`, which still may. It prints one JSON line per change (title, app, progress, artwork) and reads play, pause, next, previous and seek commands from stdin. The island shows the artwork with an equalizer; opening it shows a card with progress and controls.
- **Hover:** the island grows a little under the pointer and opens after 0.25 s; a click opens it at once with the text field focused. Opened by click it stays until a click outside or Esc.
- **Fullscreen:** the island hides, except for levels, a finished timer and agent questions.
- Menu View: "Głośność i jasność na wyspie", "Teraz grane na wyspie".

## Offline mode

The "Lokalnie" button in the opened island switches the quick chat to a model that runs on the Mac itself, with no internet. Without internet the island switches by itself (dashed outline), and a chat that fails because the network is down is answered locally too.
- **Model:** Gemma 4 E4B (Q4_K_M, 5 GB) through llama.cpp's `llama-server` on the CPU (`host/local.mjs`), 4 threads for writing and 6 for reading the prompt, at low priority. It loads when the island opens in offline mode (7 to 20 s), writes about 6 tokens per second and unloads after 10 idle minutes. Picked over Bielik 4.5B, Qwen 3.5 4B and Gemma 4 E2B on 15 Polish questions (arithmetic, school, translation, facts).
- **Replies** stream into the island word by word (`delta` events go only to the asking client, not to the relay). The conversation stays in the same thread history; titles are made locally, nothing is sent to Gemini.
- **Selected text and clipboard:** the island reads the selection in the app in front (Accessibility) and shows it as a chip that can be removed; the clipboard is added by its chip or when the message mentions it. The text goes to the model as data, up to 4000 characters each.
- **Dictation:** with offline mode on, or when Gemini cannot be reached or does not answer in time, ⌃⌥ is transcribed by whisper.cpp (`large-v3-turbo` q5, `whisper-cli` from Homebrew) on the Mac: about 3 to 5 s after release for a sentence or two, about 20 s for 45 s of speech. Online, Gemini Live is first; if it has no text 1.5 s after release, a recording up to 30 s also starts whisper on the Mac, and after 2.5 s Gemini Flash Lite and Flash get the audio in parallel (no retries on 503). Live stays open and the first answer wins. Waiting times grow with the length of the recording, and if everything fails the recording is kept in `data/dictation-failed.wav` (only the latest one).
- **Setup:** `scripts/local-setup.sh` downloads llama.cpp for Intel macOS, the model and the whisper model into `~/.gzowo-concierge/local` (kept across host installs). Another model from the table in `host/local.mjs` can be set with the `localModel` setting.
- Live talk and the screen agent need Gemini, so the island hides them in offline mode.

## Timers

"Ustaw timer na 10 minut" starts a countdown (`host/timers.mjs`, tools `timer_start`, `timer_list`, `timer_cancel`). It shows on the island with a ring and the time left. When it ends the Mac rings and the phone gets a push; a timer set in the room is also announced by the room speaker. The island can add a minute or cancel it.

## Menu bar panel

The Concierge icon in the menu bar shows live CPU, GPU and RAM (right click: turn the numbers off). A click opens the control panel (`mac/Sources/ControlPanel.swift`), which replaces the Vorssaint utility:
- **Klapa:** stay-awake mode. The Mac never sleeps and the open screen never dims; with the lid shut it keeps working with the screen off, on battery too, until it is switched off (survives restarts). It runs `pmset disablesleep` through a sudoers rule that allows only that command; the existing `/etc/sudoers.d/vorssaint-clamshell` rule is used, and if it is missing the app asks for the admin password once to write its own (`PowerControl.swift`).
- **Ekran:** turns the display off now. **Klawiatura:** cleaning mode that ignores every key, media key and the Touch Bar until a click or a quiet minute (`KeyboardClean.swift`).
- **Monitor:** CPU and GPU load with temperatures from the SMC, fans, RAM with memory pressure, free disk space and disk activity, network speed, battery with power draw, cycles and health (`SystemStats.swift`). The hungriest apps are listed with a quit button.
- **Sound:** master volume plus a slider per app that plays sound. Below 100% the app is captured with a Core Audio process tap and played back quieter; at 100% nothing is tapped (`AppMixer.swift`).
- **Zatrzymaj wszystko:** open apps, menu bar apps, background services (launchd agents, booted out until next login) and stray background processes such as renders or AI servers, each with a checkbox. Claude starts unchecked; Concierge itself, its host and app extensions are never listed. Anything that starts again at login has a "Wyłącz autostart" button (`ProcessControl.swift`).
- **Uruchamiane przy starcie:** your LaunchAgents, other apps' agents, system daemons (admin password) and login items, each with a switch; stale login items of deleted apps can be removed (`StartupItems.swift`).
- **Porządki:** third-party caches, Xcode DerivedData and week-old logs, cleaned weekly after 6:00 or on demand; caches of running apps, Apple, Playwright browsers and Gzowo projects are kept. **Odinstaluj apkę:** the app and its leftovers in `~/Library` go to the Trash. **Aktualizacje apek:** Sparkle appcasts and the App Store (`Housekeeping.swift`).

## Touch Bar

The Concierge icon in the Control Strip opens a full-width bar: close, the text you type, live voice and "open in island". The reply is one continuous line you can scroll with a finger.

## Run

```sh
cp .env.example .env        # add GEMINI_API_KEY
npm run build:mac           # builds bin/ConciergeCal.app (first run asks for Calendar access)
npm start                   # http://localhost:2040
./scripts/install.sh        # deploy as a LaunchAgent (auto-start, auto-restart, no idle sleep)
```

Non-loopback requests need the `CONCIERGE_TOKEN` from `.env` (bearer header or `?t=` once).
