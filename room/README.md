# Concierge Pokój

The room speaker for Gzowo Concierge. It runs on MacPetite (MacBook 12" 2016, macOS 12) next to a speaker.

- **Wake word "Hej Gzowo" / "OK Gzowo"** is a model trained for this house (`room/train/train_wake.py`, run on Kaggle). It is a small classifier on top of openWakeWord's melspectrogram and speech-embedding models (Apache 2.0, `Resources/oww/`). Training audio:
  - 1080 phrases from five Polish Piper voices and 16 from Gemini TTS voices;
  - 45 of Jurek's own recordings through the phone microphone;
  - room reverb (MIT impulse responses), room noise and babble;
  - near-miss phrases ("do Gzowa", "Hej, w Gzowie…") and everyday Polish sentences as negatives;
  - openWakeWord's ACAV100M features as general negatives.
  On 20 held-out recordings it caught 90% (also with added noise), with 0 false alarms in 10.7 h of openWakeWord's validation audio. The Swift port (`WakeModel.swift`, ONNX Runtime 1.17.3) matches the Python reference to within 5e-5.
  While it is being tried, the older Vosk detector also runs: a closed grammar where "hej gazowa" competes with about 2000 everyday words (`Resources/wake-words.txt`, FrequencyWords, MIT), plus a word-timing check.
  Each wake and each rejected match saves a short clip in `~/Library/Application Support/ConciergeRoom/wakes/` (last 60). No audio leaves the house until a wake word is heard.
- **Microphone:** the phone app "Concierge Ucho" (`android/ear`) streams the room from a Samsung M15 over Wi-Fi (raw MIC source; MacPetite adds automatic gain). MacPetite's own microphone is the fallback.
- **When the main Mac is on**, the app connects to the Concierge host's `/live` with `client=room`. The host adds the room tools (`room_*`) to its own, forwards their calls back to the room, and stores the conversation in the thread "Pokój".
- **When the main Mac is off**, the app talks to Gemini Live directly with its own keys. It uses the host prompt cached from the last connection and only the room tools. Conversations are queued and imported into "Pokój" (`POST /api/room/turns`) once the host is back.
- **Room tools:** timers, spoken reminders, alarms (classic bell) with spoken snooze and a morning brief after "Hej Gzowo, wstałem", weather for any Polish place up to a week ahead (Open-Meteo), Apple Music through Music.app, iMessage through Messages.app (trusted contacts send right away; anyone else needs a short spoken "tak" within 30 s), volume, and the calendar (EventKit, offline mode only).
- **Screen:** the Concierge face is always on. Between conversations it sleeps (dimmed, closed eyes, Core Animation breathing and floating z's) and the backlight drops to 12% (2% from 22:00 to 7:00). The wake word opens its eyes, and it follows the person in front of the camera (Vision face detection, camera on only while awake). A click or key while it sleeps steps the window aside for 10 minutes.
- **Conversation:** after every answer it keeps listening for about 9 s, so talk continues without the wake word.
- **Upkeep:** the app restarts itself at 3:30 at night when idle (memory creeps up slowly); alarms survive in `alarms.json`.

## Build and install

```
./build.sh                         # app in Niepotrzebne/room-build (Vosk library and model downloaded to Niepotrzebne/room-vendor)
./deploy.sh                        # to jerzysukiennik@MacPetite.local: app, settings, Gemini keys and LaunchAgent over SSH
```

Trusted contacts and location live in `Niepotrzebne/room-contacts.json`, which is never committed:

```json
{ "trusted": { "mama": "+48...", "tata": "+48..." }, "contacts": {}, "place": "Warszawa", "latitude": 52.23, "longitude": 21.01 }
```

## Testing without a microphone

`ROOM_NO_MIC=1 ROOM_HEADLESS=1 ROOM_MUTE=1 ROOM_DRY_MESSAGES=1` runs the app with no microphone, no window, no sound and no real messages. Post the DistributedNotification `fun.gzowo.concierge.room-test` with the path of a 16 kHz mono WAV as its object, and the recording goes through the whole pipeline.

## Sounds (freesound.org, CC0)

- `alarm.m4a`: "Twin Bell Alarm Clock Continuous Ringing", sound 743963, trimmed to 8 s.
- `timer.m4a`: "bell8.wav", sound 531031.
- `wake.m4a`: "SingleDing", sound 759839.
