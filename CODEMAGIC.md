# Shipping Turnstile to TestFlight with Codemagic (no Mac)

Same rig as Vault Seven / TagTerm / TagStream: Codemagic's cloud macOS
workers do the Xcode archive + upload. The account, App Store Connect key
integration (`Codemagic_Admin`) and the signing key group
(`appstore_credentials`, `CERTIFICATE_PRIVATE_KEY`) already exist.

## One-time setup

1. **App record** in App Store Connect: platform iOS, bundle ID
   `tech.advancedfield.Turnstile`, name **Turnstile** (the CI's
   `--create` registers the bundle ID and profile on the first signed build if
   the identifier does not exist yet).
2. **Repo**: this folder pushed to GitHub with `codemagic.yaml` at the root
   (next to `Turnstile.xcodeproj`). Connect the repo in the Codemagic UI
   (Apps → Add application → GitHub) and pick the `ios-testflight` workflow.
3. **TestFlight Test Information** (beta description, feedback email, beta
   review contact) once in App Store Connect → Turnstile → TestFlight before
   external testers can be added. Internal testers need nothing.

## Every build

Push to the connected branch, or Start new build in the UI. Steps: unique
build number → fetch/create certificate + profile → `build-ipa` → upload to
TestFlight. About 12-15 minutes on `mac_mini_m2`. Install through the
TestFlight app once processing finishes.

## Gotchas (from the sibling apps)

- **Keep the pbxproj classic.** Xcode 16 synchronized groups break
  `use-profiles`. New source files must be added to `project.pbxproj` by hand
  (FileReference, BuildFile, group, Sources phase) with the deterministic
  `D…01xx` / `D…02xx` ids, or regenerated with XcodeGen from `project.yml`.
- **No Swift toolchain on Windows.** Codemagic is the compiler. The deploy
  target is iOS 16, so avoid iOS 17-only APIs (`.topBarLeading`,
  `ContentUnavailableView`, two-parameter `.onChange`, `@Observable`,
  `.symbolEffect`, `.sensoryFeedback`). `docs/codex_swift_brief.md` is the
  pre-build review checklist Codex runs against the sources.
- If `use-profiles` writes nothing, the yaml's fallback step injects
  `DEVELOPMENT_TEAM` / `PROVISIONING_PROFILE_SPECIFIER` from the downloaded
  profile.
- `ITSAppUsesNonExemptEncryption = NO` is set in the project, so there is no
  export-compliance prompt after upload.
