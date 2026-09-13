# Turnstile — App Store checklist

Everything below the "owner" line needs a human in a browser or a permission
the automation does not have; everything else is scripted and idempotent.

## Owner steps (in this order)

1. **Bundle id** in the Developer Portal: `python3 tools\asc_bundle_id.py`
   (registers `tech.advancedfield.Turnstile`, prints "exists" on re-runs).
2. **App record**: DONE 2026-09-13 — app id **6811698279**, store name
   **"Turnstile AI"** (plain "Turnstile" was already taken), SKU
   `TurnStile_01`, bundle `tech.advancedfield.Turnstile`. The home-screen
   name matches the listing ("Turnstile AI"); the target, scheme, repo and
   in-app titles stay "Turnstile".
3. **Build**: `python tools\codemagic.py start` (app id 6aa6d854710b2eedf0f3636f
   is already added; the first build 6aa6d888e0e1aa5c16416155 failed only
   because step 1 had not happened). Then `python tools\codemagic.py builds`
   and `log <id>`.
4. **Scheduled tasks** for the house agents, once, from PowerShell:
   `powershell -ExecutionPolicy Bypass -File agent\install_house_agents.ps1`
   (tokens are already in `~/.turnstile/`; setters are flagged).
5. **Metadata**: DONE — `set REVIEW_PHONE=+1 541 490 2474 && python3
   C:\Users\M5\Downloads\setup_turnstile_asc.py` (idempotent) set the
   subtitle, categories (Games / Puzzle / Board), description, keywords,
   promo text, URLs, copyright, review contact + notes, age rating 4+,
   content rights, TestFlight test info and all ten screenshots.
6. **Screenshots**: DONE — `python3 tools/make_screenshots.py` renders the
   five iPhone 6.7 (1290x2796) and five iPad 13 (2048x2732) images from the
   screen designs; every tile sequence in them is labelled by the real
   engine. Replace with real TestFlight captures whenever convenient:
   drop PNGs in `appstore/iphone-6.7/` and re-run step 5.
7. **Price and build**: DONE — `python3 tools/asc_finish.py --apply` set the
   Free price schedule and attached build 6 to version 1.0. Re-run it after
   any new build.
8. **App Privacy** questionnaire in the browser (the only remaining
   blocker; no public API). Honest answers: no data collected that is
   linked to identity; the random player id is an app identifier used for
   app functionality only; nickname is optional user content. "Data Not
   Collected" was accepted for the Vault apps with the same posture.
9. **Add for Review** and **Submit** in the browser.

## Store copy (source of truth is setup_turnstile_asc.py)

- Name: Turnstile AI (app id 6811698279)
- Subtitle: Crack the machine's rule
- Category: Games / Puzzle, Board
- Keywords: logic,puzzle,daily,deduction,induction,rule,brain,ai,claude,gpt,zendo,science,experiment,thinking,game
- Support / marketing: https://turnstile.advancedfield.tech
- Privacy: https://turnstile.advancedfield.tech/privacy

## Review notes (what the reviewer sees)

Free daily logic game, no account. Two machines a day; tap one, read the
examples, build sequences with the tile palette and ask the machine (up to
four times), show the tests, classify, lock in. The reveal shows the rule,
an optional rule guess for a star, statistics and the AI players'
transcripts. Only nicknames are user-generated and visible to others
(word filter + Llama Guard + report button); hypothesis notes are private.
The AI players are separate programs using the same public API; the app
never contacts an AI service.
