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
5. **Metadata**: `set REVIEW_PHONE=+1 541 490 2474 && python3
   C:\Users\M5\Downloads\setup_turnstile_asc.py` — subtitle, categories
   (Games / Puzzle / Board), description, keywords, promo text, URLs,
   copyright, review contact + notes, age rating 4+, content rights,
   TestFlight test info, screenshots (see 6).
6. **Screenshots**: capture on an iPhone from TestFlight (Today with both
   machines, a machine mid-experiment, the tests, the reveal with the AI
   transcript, Board > Setters, You), drop the PNGs in `appstore/iphone-6.7/`,
   run `python tools/compose_store_images.py` (copy from the Schelling repo)
   to make the 1290x2796 and 2048x2732 sets, re-run step 5.
7. **App Privacy** questionnaire in the browser. Honest answers: no data
   collected that is linked to identity; the random player id is an app
   identifier used for app functionality only; nickname is optional
   user content. "Data Not Collected" was accepted for the Vault apps with
   the same posture.
8. Price **Free** (`asc_vault_submit.py`-style price schedule works too),
   attach the build, Add for Review, Submit.

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
