# MVP-15 engineering plan: release verification

Last updated: 2026-07-27

Status: repository-side release work is complete. Live OAuth, GitLab.com
token, App Store distribution validation, and the remaining environment-owned
visual rows are still pending; the results are recorded below.

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
- The asset catalog contains a distinctive Glab app icon that does not use
  official GitLab or GitHub branding.
- The repository contains a public privacy policy and the app links to it from
  the signed-out and Account privacy presentations.
- The app uses only system HTTPS/TLS cryptography and declares
  `ITSAppUsesNonExemptEncryption` as `false`.
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

## Release-candidate verification record

Candidate code commit: `f788c44`

### Automated gates

- The complete signed suite passes 244 logical tests in 44 suites on a fresh,
  credential-free iPhone 17 Pro simulator running iOS 26.5.
- Xcode static analysis succeeds. Its only diagnostic is the Xcode toolchain's
  skipped App Intents metadata extraction for a target that does not use App
  Intents.
- The signed Release archive succeeds and contains one `arm64` iPhone app,
  bundle identifier `com.glab.ios`, version `1.0` build `1`, minimum iOS 26.0,
  the `glab` callback scheme, the primary app icon, privacy manifest, and
  `ITSAppUsesNonExemptEncryption = false`. It contains no test bundle.
- The archived privacy manifest declares no tracking, tracking domains, or
  collected data, and only the app-owned `UserDefaults` required-reason
  category `CA92.1`.
- Tracked-source and archive scans find no configured token or host value.
  Production-source scans find no logging calls that could expose API data.
- The local archive is development-signed, including
  `get-task-allow = true`. Organizer/App Store Connect distribution signing and
  validation remain a separate release-owner action; a successful local
  archive is not presented as App Store validation.
- A fresh archive at repository checkpoint `084c2bb` also succeeds and passes
  strict local code-signature verification. A non-uploading App Store Connect
  export reaches signing resolution but fails with Xcode reporting no
  authenticated accounts and no distribution provisioning profile for
  `com.glab.ios`. An Apple Distribution identity is installed, so the remaining
  requirement is the Xcode account/profile session rather than app source.
- Xcode's `validation` export method requires `destination = upload`; it was
  not used because this plan explicitly forbids uploading as an incidental
  verification side effect. Organizer/App Store Connect validation therefore
  remains pending.

### Authentication matrix

| Row | Result |
| --- | --- |
| GitLab.com OAuth | Blocked: no registered Glab Application ID is configured |
| GitLab.com personal access token | Blocked: no GitLab.com test token is configured |
| Self-managed OAuth | Blocked: no instance Application ID or web-login test account is configured |
| Self-managed personal access token | Passed from a fresh install: live validation, read-only capability, and Keychain-backed relaunch restoration |

The available self-managed host later became unreachable from both macOS and
the simulator. The outage prevented a current server-version query and the
remaining populated large-device rows; it did not affect the deterministic
client/model gates or the already completed fresh-install session proof.

### State and device matrix

- The live read-only self-managed session covered Home, Todos, every
  pending/done and all/issues/merge-requests filter combination, disabled
  mutation explanations, account/privacy, sign-out confirmation, and all five
  Home shortcut routes on iPhone 13 mini.
- The small-device pass covered dark appearance and the largest accessibility
  text size. The redesigned signed-out flow was separately inspected on iPhone
  17 Pro Max in light/default and dark/large-text configurations, including
  the privacy, OAuth setup, and token sheets.
- Empty, expired-session, offline, rate-limit, permission, retained-refresh,
  pagination, retry, cancellation, and optimistic mutation rollback states are
  covered deterministically by the signed test suite. Live timeout/retry and
  empty-retry loading behavior were also exercised without mutating GitLab
  data.
- The default Home Screen app icon is visually legible. Dark/tinted Home
  Screen variants remain pending because the host Mac was locked and Simulator
  command-line automation cannot change the system icon treatment.
- A signed-in large-device walkthrough and a repeated live server-version
  query remain pending until the configured self-managed host is reachable.

### Compatibility declaration

- Glab supports iPhone on iOS 26 or newer.
- The declared self-managed GitLab floor is 15.5 because the token capability
  check uses `GET /personal_access_tokens/self`, introduced in GitLab 15.5.
- Self-managed instances must use HTTPS with a certificate trusted by iOS.
- The configured live server version could not be recorded during this pass
  because the server became unreachable; the declared floor is therefore
  documentation-derived, not claimed as a live older-server compatibility
  test.

MVP-15 and MVP-05 remain unchecked until the live OAuth rows, GitLab.com token
row, outstanding device rows, and distribution validation are completed. The
Mac must also be unlocked before Xcode's account state and the system icon
treatments can be inspected interactively.
