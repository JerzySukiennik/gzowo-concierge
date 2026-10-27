# Concierge Pokój

The room speaker for Gzowo Concierge. It runs on MacPetite (MacBook 12" 2016, macOS 12) next to a speaker.

- **Wake word "Hej Gzowo"** is detected offline with [Vosk](https://alphacephei.com/vosk/) (Apache 2.0) and the small Polish model. The model does not know the word "Gzowo"; it hears it as "hej gazowa". The detector therefore uses a closed grammar in which that phrase competes with about 200 everyday Polish words. No audio leaves the machine until the phrase is heard.
- **When the main Mac is on**, the app connects to the Concierge host's `/live` with `client=room`. The host adds the room tools (`room_*`) to its own, forwards their calls back to the room, and stores the conversation in the thread "Pokój".
- **When the main Mac is off**, the app talks to Gemini Live directly with its own keys. It uses the host prompt cached from the last connection and only the room tools. Conversations are queued and imported into "Pokój" (`POST /api/room/turns`) once the host is back.
- **Room tools:** timers, alarms (classic bell), Apple Music through Music.app, iMessage through Messages.app (trusted contacts send right away; anyone else needs a short spoken "tak" within 30 s), weather (Open-Meteo), volume, and the calendar (EventKit, offline mode only).
- **Screen:** dark at rest. After the wake word, the Concierge face appears and follows the person in front of the camera (Vision face detection, camera on only while the face is shown).

## Build and install

```
./build.sh                         # app in Niepotrzebne/room-build (Vosk library and model downloaded to Niepotrzebne/room-vendor)
./deploy.sh jurek@MacPetite.local  # app, settings, Gemini keys and LaunchAgent over SSH
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
