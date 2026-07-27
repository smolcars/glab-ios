# MVP-14 engineering plan: resilience, accessibility, and privacy

Last updated: 2026-07-27

Status: complete. Bounded read retry, unified recovery, API-access
explanations, accessibility repairs, privacy hardening, simulator inspection,
the complete signed suite, and static analysis all pass.

## Outcome

Finish the product-quality work needed before release verification:

- failures explain what happened and offer the correct recovery action;
- transient read failures receive bounded, cancellable retry/backoff;
- failed refreshes never discard already-loaded GitLab content;
- the complete authentication, Home, Todos, detail, and sign-out paths remain
  usable with VoiceOver and large text;
- credentials and response bodies cannot leak through descriptions, errors,
  logs, analytics, committed screenshots, or test fixtures;
- users can understand why write-enabled sign-in asks GitLab for the broad
  `api` scope.

This phase hardens existing MVP behavior. It does not add offline persistence,
background refresh, analytics, new API resources, or automatic mutation
retries.

## Assumptions and official contracts

- GitLab returns `401` when authentication is missing or no longer valid.
  Glab must clear the unusable stored credential and return to sign-in.
- GitLab returns `403` when the authenticated account cannot perform a
  request. Glab must retain the session and explain the permission failure.
- A throttled request returns `429`. When supplied, `Retry-After` is a
  nonnegative number of seconds until another attempt should be made.
- GitLab's `api` scope grants complete read/write API access for the token's
  scope. `read_api` grants read-only API access.
- OAuth credentials stay in Keychain, OAuth application IDs stay in
  `UserDefaults`, and personal access tokens stay in Keychain. No credential
  belongs in view state longer than sign-in requires.
- Keychain items use the foreground-only,
  device-bound `WhenUnlockedThisDeviceOnly` accessibility class.
- The app privacy manifest declares only its app-owned `UserDefaults` access
  with required reason `CA92.1`; Glab declares no tracking or collected data.
- A GET or server-issued next-page URL is idempotent and may be retried.
  Todo completion POST requests are not replayed automatically because the
  client cannot prove whether GitLab applied a request whose connection was
  interrupted.
- Automatic retry is bounded to two additional attempts. It applies only to
  transient timeouts, lost/failed connections, transport failures, and
  `5xx` responses. Offline, permission, authentication, validation, decoding,
  and rate-limit failures return immediately to recovery UI.
- Rate-limit UI respects `Retry-After`; it does not hide a long wait behind an
  indefinite loading state or retry earlier than GitLab requested.
- Standard SwiftUI controls supply semantics and Dynamic Type by default.
  Custom rows, symbols, combined content, and progress/error states need
  explicit labels, values, hints, identifiers, or announcements where the
  inferred result is incomplete.
- Interactive hit regions are at least 44 by 44 points. Increased Contrast,
  Differentiate Without Color, and Reduce Motion must not remove meaning or
  access to an action.
- Mark-all and sign-out retain their existing confirmations. Completing one
  Todo is reversible in product navigation because it remains under Done, so
  an extra confirmation would add friction without protecting data.

Sources:

- [GitLab REST API authentication](https://docs.gitlab.com/api/rest/authentication/)
- [GitLab REST API troubleshooting](https://docs.gitlab.com/api/rest/troubleshooting/)
- [GitLab user and IP rate-limit headers](https://docs.gitlab.com/administration/settings/user_and_ip_rate_limits/#response-headers)
- [GitLab access token scopes](https://docs.gitlab.com/security/tokens/access_token_scopes/)
- [Apple SwiftUI accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [Apple accessible appearance APIs](https://developer.apple.com/documentation/swiftui/accessible-appearance)
- [Apple button guidance](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Apple sensitive-content guidance](https://developer.apple.com/documentation/swiftui/protecting-sensitive-content-when-screen-sharing)
- [Apple Keychain accessibility while unlocked](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)
- [Apple privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple `UserDefaults` required-reason API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

## Architecture

Keep the existing Model-View architecture and injected loader/mutator seams.
This work needs three small, independently testable additions.

### Read retry policy

- Add a pure `GitLabReadRetryPolicy` that classifies retryable API errors and
  computes exponential delays for an attempt.
- Inject a sendable async sleeper into `GitLabClient`, with a production
  `Task.sleep` default and deterministic tests.
- Build the request once per operation, then run transport and response
  decoding through the bounded retry loop.
- Retry only `.get` initial requests and next-page requests. Never retry a
  POST, even when its endpoint is accidentally declared as read access.
- Check cancellation before every attempt and after every sleep. Cancellation
  remains `.cancelled`, and no extra transport call occurs.
- Preserve the final classified error after the retry budget is exhausted.

The policy stays below OAuth refresh so each attempt uses one established
credential. A `401` continues through the existing single-refresh path and is
not consumed by transient retry logic.

### Recovery presentation

- Add a pure `GitLabRecoveryPresentation` derived from
  `GitLabSessionClientError`.
- Give offline, timeout, server, permission, expired-session, rate-limit, data,
  and generic failures consistent titles, symbols, messages, and retry
  availability.
- Keep `AppSession` authoritative for expired authentication. Recovery views
  must not offer a retry after the app has invalidated that session.
- Update full-page and inline retry views to accept this presentation while
  retaining a message-only overload for aggregate Home failures.
- A rate-limited presentation shows the server wait when known and prevents an
  immediate retry until the delay elapses. Manual retry remains available when
  GitLab omits `Retry-After`.
- Existing paginated models continue to retain content on refresh failure.
  Add regression coverage for every failure class instead of duplicating
  preservation logic per feature.

### Accessibility and privacy

- Audit sign-in, both tabs, Home shortcuts, filters, resource rows, refresh and
  pagination errors, Todo completion, native details, account, and sign-out in
  VoiceOver order.
- Keep text on semantic fonts, allow vertical growth, avoid fixed text
  heights, and verify the largest accessibility Dynamic Type category on a
  small-screen simulator.
- Give custom icon-only controls clear labels and hints; hide decorative
  symbols and avatars from VoiceOver; combine dense read-only rows into one
  concise element.
- Give loading and mutation progress states a status trait/announcement that
  does not repeatedly speak during view recomputation.
- Use system semantic colors and symbols so Increased Contrast and
  Differentiate Without Color preserve state. Disable nonessential custom
  motion under Reduce Motion.
- Keep stable accessibility identifiers for the sign-in choices and fields,
  tab shell, account/sign-out, Todo controls and rows, retry actions, and
  native detail roots. Exercise them in simulator automation.
- Add a short “Privacy & API access” explanation before OAuth sign-in and in
  Account. State what `api` enables, why `read_api` cannot complete Todos,
  where credentials are stored, and that Glab has no analytics.
- Continue to render server content while signed in, but mark credential input
  and other secret-bearing views as privacy-sensitive. Visual QA screenshots
  containing real GitLab content remain temporary, local, and are deleted
  after inspection; committed screenshots and fixtures use synthetic content.

## Test-first implementation order

### 1. Add bounded retry/backoff for reads

Write failing tests for:

- retry classification and the two exponential delays;
- a GET succeeding after one transient failure;
- a next-page GET succeeding after a transient failure;
- exhaustion returning the final error;
- a POST never being retried;
- offline, `401`, `403`, decoding, and `429` failures returning immediately;
- cancellation during backoff stopping before another transport call.

Then add the pure policy, sleeper seam, and the smallest client retry loop.

### 2. Unify recovery presentation

Write failing tests for every error category, retry availability, known and
unknown rate-limit waits, and reauthentication behavior. Then connect the
presentation to initial, refresh, and pagination failures without changing the
feature models.

### 3. Explain privacy and API access

Add tested presentation copy for OAuth/read-write and token/read-only
sessions. Show it from sign-in and Account, verify it never contains a
credential, and add accessibility identifiers for both entry points.

### 4. Complete the accessibility pass

Audit and fix one flow at a time:

1. OAuth and personal-token sign-in.
2. Home, account, and sign-out.
3. Todos, completion, filters, and tab badge.
4. Issue, merge-request, and project lists/details.
5. Loading, empty, error, refresh, and pagination states.

Each flow is built and tapped at default and accessibility text sizes, in
light/dark and standard/increased contrast where applicable. VoiceOver
semantics and identifier presence are inspected through the simulator
hierarchy. Fix only verified gaps.

### 5. Run the privacy and release-preflight audit

- Extend redaction tests across authorization, stored sessions, sign-in
  failures, API errors, request construction, OAuth exchange, and Keychain.
- Scan production code for logging, analytics, force casts, force tries,
  embedded credentials, and response-body interpolation.
- Confirm `.env`, DerivedData, simulator artifacts, and real-data screenshots
  are ignored and untracked.
- Run the full signed suite, static analyzer, property-list validation, and a
  final iPhone 17 Pro interaction pass.

## Verification gates

1. Deterministic tests prove only idempotent reads retry, delays are bounded,
   rate limits are respected, writes never replay, and cancellation stops.
2. Every recovery category has specific, redacted copy and the correct action.
3. Existing content survives all failed refresh categories.
4. Critical authentication, tab, refresh, Todo, detail, and sign-out elements
   are reachable with stable accessibility identifiers.
5. The largest accessibility text size has no clipped required action on a
   small-screen iPhone; default text remains visually balanced on iPhone 17
   Pro.
6. Light/dark, Increased Contrast, Differentiate Without Color, and Reduce
   Motion checks reveal no lost meaning or blocked action.
7. No credential, authorization header, OAuth code/verifier, response body, or
   real GitLab screenshot is committed or printed.
8. The complete signed suite and static analyzer pass with no app-code
   warnings or findings.
9. Each passing slice is committed and pushed to `master`.

## Completion record

- Idempotent reads retry at most twice with cancellable exponential backoff.
  Writes, rate limits, authentication, permission, decoding, and offline
  failures are never replayed automatically.
- Shared recovery presentation now covers offline, timeout, server,
  permission, expired-session, rate-limit, data, and generic failures while
  preserving already-loaded content.
- Sign-in and Account explain the broad `api` scope, the read-only
  `read_api` limitation, credential storage, and the absence of analytics.
- The signed-out and signed-in flows were inspected on iPhone 17 Pro at
  default and maximum accessibility text sizes, in light/dark appearance and
  standard/Increased Contrast. Critical controls and routes expose stable
  accessibility identifiers.
- PKCE values, credentials, submitted tokens, authorization headers, response
  bodies, errors, stores, and stored sessions have redaction coverage.
  Keychain uses `WhenUnlockedThisDeviceOnly`, and the bundled privacy manifest
  is validated by a test.
- `.env` is ignored and untracked. Production contains no logging, analytics,
  force casts, force tries, embedded credential shapes, or committed real-data
  screenshots.
- The final signed run passes 241 logical tests and 352 parameterized
  executions on iPhone 17 Pro, iOS 26.5. Xcode static analysis and both
  property lists pass. Xcode only reports its toolchain diagnostic that unused
  App Intents metadata extraction was skipped; there are no compiler or
  analyzer findings.
