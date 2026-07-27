# MVP-15 engineering plan: release verification

Last updated: 2026-07-27

Status: in progress. Release configuration and repeatable checks can be
completed locally. Live OAuth and GitLab.com token rows remain dependent on
credentials and registered OAuth applications that are not currently
configured.

## Outcome

Prove that the MVP is ready for a TestFlight candidate without weakening the
clean-install or live-authentication requirements:

- complete the required app icon, privacy-policy, export-compliance, version,
  bundle, signing, and privacy-manifest configuration;
- build and inspect a signed Release archive;
- exercise each available authentication path from a genuinely clean install;
- verify empty, populated, read-only, expired-session, offline, rate-limited,
  and mutation recovery behavior with the strongest safe evidence available;
- walk Home and Todos on small and large iPhones in light/dark appearance and
  at a large accessibility text size;
- document the supported GitLab/iOS baseline and every external release
  dependency precisely.

MVP-15 is not complete until every live account row passes. Unit tests or
constructed callbacks do not replace a real GitLab.com OAuth callback,
self-managed web login with 2FA, or token validation against the named
offering.

## Baseline and constraints

- The project targets iPhone on iOS 26 or newer, uses bundle identifier
  `com.glab.ios`, version `1.0` build `1`, automatic signing, and the configured
  Apple development team.
- The asset catalog has the GitLab sign-in logo but no `AppIcon` set. Apple
  requires an app icon before distribution.
- The app explains its API scope and privacy behavior, but the repository has
  no public privacy policy and the app has no privacy-policy link. Apple
  requires the policy in App Store Connect and inside the app.
- The app uses only system HTTPS/TLS cryptography, but
  `ITSAppUsesNonExemptEncryption` is absent. Declaring exempt encryption as
  `NO` avoids repeating App Store Connect's export questionnaire.
- The privacy manifest declares app-owned `UserDefaults` reason `CA92.1`, no
  tracking, and no collected data. The final archive must contain that exact
  manifest.
- Local `.env` contains only `GITLAB_URL` and `GITLAB_API_TOKEN`; values must
  never enter logs, commands, screenshots, fixtures, or committed files. The
  user identified the token as read-only.
- No GitLab.com OAuth Application ID, self-managed OAuth Application ID,
  GitLab.com token, or web-login credentials are configured. Glab must not
  invent or persist substitutes.
- A clean-install row uses a newly created simulator or an explicitly erased
  Glab-only test simulator. Reinstalling over an existing app does not qualify
  because Keychain data can survive app deletion.
- The production app gets no hidden fixture/debug mode solely to make a manual
  checklist appear complete. Deterministic tests can prove constructed failure
  states, but the release record distinguishes them from live interaction.

## Official contracts and compatibility

- GitLab recommends Authorization Code with PKCE for public/mobile clients.
  The OAuth application must be registered on the GitLab instance first, and
  the normal GitLab web page owns username, password, 2FA, and SSO.
- A refresh invalidates the prior access and refresh tokens and returns a new
  pair. Clean-install and expiry checks must therefore exercise persisted token
  rotation, not reuse old fixtures.
- The complete MVP needs `api`; `read_api` supports browsing but not Todo
  completion.
- `GET /personal_access_tokens/self`, used to inspect PAT scope and expiry, was
  introduced in GitLab 15.5. GitLab 15.5 is therefore the initial documented
  self-managed minimum unless another exercised endpoint requires a newer
  version.
- GitLab documents single-Todo completion as
  `POST /todos/:id/mark_as_done` and mark-all as
  `POST /todos/mark_as_done`, returning `204` for mark-all.
- Apple requires a unique bundle ID, version/build string, launch screen, and
  app icon in a distributable archive. Xcode archive validation remains a
  separate external check after a local archive succeeds.

Sources:

- [GitLab OAuth 2.0 and PKCE](https://docs.gitlab.com/api/oauth2/)
- [GitLab REST authentication](https://docs.gitlab.com/api/rest/authentication/)
- [GitLab access-token scopes](https://docs.gitlab.com/security/tokens/access_token_scopes/)
- [GitLab personal access-token API](https://docs.gitlab.com/api/personal_access_tokens/)
- [GitLab To-Do List API](https://docs.gitlab.com/api/todos/)
- [Apple preparing an app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Apple app-icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon/)
- [Apple app privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple App Review privacy-policy rule](https://developer.apple.com/app-store/review/guidelines/)
- [Apple exempt-encryption property](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
- [Apple archive and validation workflow](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/)

## Test-first implementation order

### 1. Complete distributable app metadata

Write failing bundle tests that require:

- a primary iPhone app icon in the built app;
- `ITSAppUsesNonExemptEncryption` to be `false`;
- a valid HTTPS privacy-policy URL exposed by the privacy/access presentation;
- the existing privacy manifest declarations.

Then:

- add a distinctive Glab icon that does not present the unofficial client as
  an official GitLab app;
- add a public root privacy policy describing local credential storage,
  request-time GitLab data handling, third parties, retention/deletion, and
  user controls;
- link the policy from the existing sign-in and Account privacy presentation;
- add the exempt-encryption declaration.

Build, launch, inspect the icon on the Home Screen, and tap the privacy-policy
link before committing.

### 2. Produce and inspect a Release archive

- Build the app in Release for a generic iOS device with signing.
- Create an `.xcarchive` outside the repository and confirm it is an iOS app
  archive with the expected bundle identifier, version, build, minimum OS,
  app icon, privacy manifest, URL scheme, encryption declaration, and no test
  bundle.
- Inspect signing and entitlements without printing provisioning-profile
  details or account identifiers into committed artifacts.
- Run the complete signed tests, static analyzer, property-list checks, and
  production secret/logging scan against the release commit.
- Treat Organizer/App Store Connect validation as pending until an app record
  and distribution flow are intentionally used; do not upload as a side
  effect of this checklist.

### 3. Run the clean-install authentication matrix

Use a fresh dedicated simulator per row and record only pass/fail evidence:

| Row | Required evidence | Current availability |
| --- | --- | --- |
| GitLab.com OAuth | Real authorization, callback, user validation, relaunch, refresh | Blocked: no registered Application ID |
| GitLab.com PAT | Real token validation, scope/expiry display, relaunch | Blocked: no GitLab.com token |
| Self-managed OAuth | Real normal web login with username/password and 2FA, callback, relaunch, refresh | Blocked: no Application ID or web credentials |
| Self-managed PAT | Real validation, read-only capability, populated Home/Todos, relaunch | Available through local `.env` |

Do not mark a blocked row passed based on unit tests. Do not write a live token
into a Maestro flow, launch argument, shell history, screenshot, or test
result.

### 4. Exercise the state and device matrix

- Use model/client tests for deterministic empty, expired-session, offline,
  rate-limit, permission, decoding, retained-refresh, and mutation rollback
  behavior.
- Re-exercise every naturally available state in the installed app and label
  evidence as live or deterministic.
- On dedicated iPhone 13 mini and iPhone 17 Pro Max simulators, walk Home,
  every shortcut, lists, search, refresh, details, browser routing, Todos
  filters, read-only completion explanation, Account, privacy, and sign-out
  confirmation.
- Cover light and dark appearance and a large accessibility text category.
  Use temporary local screenshots only when visual comparison is necessary;
  delete any screenshot containing real GitLab data after inspection.
- Do not mutate the user's GitLab data with the provided read-only credential
  or broaden its scope for testing.

### 5. Record compatibility and close honestly

- Document iOS 26+ and GitLab 15.5+ as the declared compatibility floor, plus
  HTTPS with a system-trusted certificate. Record the actual live server
  version separately instead of calling the floor tested.
- Record any older-server or administrator-policy limitations observed.
- Add a release-verification audit with the exact tested device/runtime,
  archive, suite, and live-account matrix results.
- Keep MVP-05 and MVP-15 unchecked while their live OAuth criteria remain
  blocked. Check MVP-15 only after every authentication row and exit criterion
  passes.

## Verification gates

1. Metadata tests fail without the icon, privacy link, encryption declaration,
   or privacy manifest and pass in the release candidate.
2. The icon is legible on the Home Screen in default, dark, and tinted system
   appearances and remains visually distinct from official GitLab branding.
3. Privacy policy and in-app/API-scope explanations agree with the app's actual
   behavior.
4. A signed Release archive contains the expected production bundle and no
   secrets or test code.
5. Every available clean-install authentication row restores its session after
   relaunch; OAuth rows also prove a real callback and refresh.
6. Required states and complete Home/Todos navigation are exercised on small
   and large iPhones with appearance and Dynamic Type coverage.
7. Full signed tests, analyzer, build, archive, property lists, privacy scan,
   and repository cleanliness pass.
8. Each verified slice is committed and pushed to `master`; blocked external
   rows remain visible and are never converted into false checkmarks.
