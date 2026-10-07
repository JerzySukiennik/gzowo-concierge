# Gzowo Concierge (project notes for Claude)

Personal AI assistant for Jurek. Mac host (Node, LaunchAgent `fun.gzowo.concierge`, runtime copy in `~/.gzowo-concierge`), native Mac app (`mac/`, Swift), web UI (`web/`, phone PWA at https://concierge.gzowo.fun and https://gzowo-concierge.web.app), Firebase RTDB relay, Gemini models. Full decisions: `~/.claude/project-notes/gzowo-concierge.md`.

## Deploying (autodeploy is armed in this project)
- Do NOT use the generic deploy skill's root `vX.Y` snapshots here. This repo is code, not a served site. Run `./scripts/deploy-all.sh` after committing: it smoke-tests (syntax of all JS, web entry point), then deploys only what changed (host via `scripts/install.sh`, Mac app via `mac/build.sh`, `firebase deploy --only hosting`, `scripts/publish-pages.sh` which creates the immutable `vX.Y` snapshot in the separate `JerzySukiennik/concierge` repo, database rules).
- Run the secret scan before committing (`~/.claude/skills/deploy/scripts/scan-secrets.sh .`). `.env`, `data/`, `bin/`, `Niepotrzebne/` are never committed.
- If the smoke test fails, commit locally, do not deploy, tell Jurek what broke. The host restart takes a few seconds.

## Hard rules
- Mac app window stays OPAQUE and uses no `glassEffect` (60-95% GPU idle on Jurek's Intel MBP). Measure GPU with `ioreg -r -d 1 -w0 -c IOAccelerator | grep "Device Utilization"`.
- Never test against the live host on port 2040 or put the real `HOST_PASSWORD`/owner password anywhere. Use dev hosts on other ports with `RELAY=off DATA_DIR=$(mktemp -d)`.
- After changing prompts or tools run `node scripts/eval.mjs` (13 scenarios, real model, paced).
- UI: Polish copy, no em-dashes, monochrome graphite, red only for errors, flat 2D black and white avatar.
