# Focused code audit

Last updated: 2026-07-27

## Scope

This is a living audit of production Swift, unit tests, app configuration, and
MVP documentation. The initial baseline below was recorded after MVP-08; each
later phase has its own full-tree audit section. Naming and formatting
preferences that do not affect correctness, security, testability, or
near-term feature work are intentionally excluded.

Initial baseline:

- 112 tests (130 parameterized invocations) pass on iPhone 17 Pro, iOS 26.5.
- Swift 6 complete concurrency checking passes.
- Xcode static analysis passes without code findings.
- The existing SwiftUI Model-View architecture remains appropriate; no
  architecture migration is justified.

## Repair checklist

### Correctness and session ownership

- [x] Make refresh-token persistence conditional on the original stored
  session still being current, so an in-flight refresh cannot restore
  credentials after sign-out.
- [x] Reuse the exact credential-store instance owned by `AppSession` in the
  signed-in client instead of constructing a second live store.
- [x] Synchronize a successfully refreshed session back into `AppSession` so
  later features never create a client from an expired, rotated credential.

### OAuth robustness

- [x] Cancel the active `ASWebAuthenticationSession` when its Swift task is
  cancelled, complete the continuation exactly once, and allow a later sign-in
  attempt.
- [x] Fail cleanly when no foreground presentation window is available instead
  of crashing in the presentation-context callback.
- [x] Reject malformed OAuth token timestamps that overflow when `created_at`
  and `expires_in` are combined.

### Focused duplication

- [x] Centralize GitLab user display-name and avatar-initial normalization used
  by Home and Account.
- [x] Collapse the five repeated Home work-item request/mapping blocks behind
  one typed helper while keeping each endpoint explicit.

### Verification

- [x] Add deterministic unit coverage for every core-logic repair.
- [x] Run the complete test suite and static analyzer.
- [x] Launch the app and retest the changed authentication and signed-in UI on
  iPhone 17 Pro in light and dark appearance.

## Deliberately unchanged

- The feature-level MV structure is small, explicit, and already has useful
  protocol seams; adding a framework or more layers would not solve a current
  problem.
- The separate issue, merge-request, and project response types resemble one
  another today but represent independently evolving GitLab API resources.
- Home preview routes intentionally contain three items until their full
  paginated MVP list features are implemented.

## Post-MVP-09 audit

Baseline after assigned issues, issue details, and the audit repairs:

- 138 test invocations pass on iPhone 17 Pro, iOS 26.5.
- Swift 6 complete concurrency checking and Xcode static analysis pass.
- The new feature follows the existing Model-View and injected-loader
  boundaries; an architecture migration is still not justified.

### Repair checklist

- [x] Preserve loaded issues while making a failed pull-to-refresh visible and
  retryable instead of silently retaining stale content.
- [x] Reuse the established GitLab user display-name and avatar presentation
  path for issue users so future merge-request users do not create a third
  normalization implementation.
- [x] Present opened, closed, and unknown issue states with accurate text,
  symbols, and semantic colors in both list rows and details.
- [x] Add focused unit tests for each repaired state or formatting rule.
- [x] Run the complete test suite, static analyzer, and the changed issue UI in
  light and dark appearance before closing this audit.

### Forward design gate

All production endpoints through MVP-09 are read-only, so adding speculative
mutation types now would not improve current correctness. Before MVP-13 adds
the first Todo mutation, requests must explicitly declare whether they require
read or write access, the session client must reject unsupported writes before
transport, and mutation controls must remain visible but disabled with an
accessible explanation for `read_api` sessions.

## Post-MVP-09A documentation audit

The repository-documentation phase changed only `README.md`, `LICENSE`, and MVP
documentation. The production Swift, tests, project configuration, and the 138
passing-test baseline are identical to the fully reviewed post-MVP-09 tree.

Checks:

- [x] Every README local link resolves to a tracked repository path.
- [x] The documented iPhone 17 Pro, iOS 26.5 simulator destination is
  available.
- [x] `.env` remains ignored and no local credential or OAuth Application ID
  is present in the documentation diff.
- [x] The standard MIT grant and unofficial-app disclaimer are present.

No material code finding was introduced by this documentation-only phase.

## Post-MVP-10 audit

Scope:

- All production Swift, tests, project configuration, and MVP documentation
  were reviewed again after merge-request lists and details were added.
- The complete signed suite passes all 157 tests (196 parameterized
  executions) on iPhone 17 Pro, iOS 26.5, after the final shared-state
  refactor. Xcode static analysis is clean.
- The configured read-only self-managed instance returned 4 assigned merge
  requests, 1 review request, and a valid detail response matching the decoded
  contract. No response content or credential was recorded.
- Both list modes and native details were exercised on iPhone 17 Pro in light
  and dark appearance. Search, refresh, scrolling, row routing, and back
  navigation all passed.

### Repair checklist

- [x] Share API user normalization, validated external URLs, Markdown
  formatting, labels, user rows, retry rows, detail sections, and the
  “Open in GitLab” control instead of creating merge-request copies.
- [x] Keep a failed refresh warning authoritative by preventing stale
  pagination from clearing it in both issues and merge requests.
- [x] Consolidate the duplicated issue/merge-request pagination and detail
  state machines behind small generic engines. Preserve the existing
  domain-named initializers and properties so views and tests remain explicit.
- [x] Run the complete signed suite and static analyzer after the shared-state
  refactor.
- [x] Tap both Home shortcuts, populated list rows, details, scrolling, search,
  refresh, and back navigation on iPhone 17 Pro; inspect assigned and review
  modes plus a detail in light and dark appearance.

### Refactor plan

1. Use the existing issue and merge-request model suites as characterization
   tests.
2. Move common pagination/loading/error/search behavior into one generic
   observable model parameterized by item identity, page loader, and searchable
   values.
3. Move common detail load/retry/cancellation behavior into one generic
   observable model parameterized by resource, route, and loader.
4. Keep thin issue and merge-request extensions that adapt domain loaders and
   retain `issues`, `displayedIssues`, `mergeRequests`, and
   `displayedMergeRequests`.
5. Verify focused suites before running the complete gates.

### Deliberately unchanged

- Issue and merge-request response types remain separate because GitLab evolves
  those resources independently.
- Resource-specific rows and details remain separate; their visible metadata
  and future behavior differ even though they reuse small design-system views.
- No mergeability field is decoded or presented. GitLab documents list
  merge-status data as potentially stale unless an expensive recheck is
  requested.

## Post-MVP-11 audit

Scope:

- All production Swift, tests, app/project configuration, and MVP
  documentation were reviewed again after recent and starred project browsing
  was added.
- The complete signed suite passes all 171 tests (219 parameterized
  executions) on iPhone 17 Pro, iOS 26.5. Xcode static analysis and property
  list validation are clean.
- Both project modes and both merge-request modes were exercised against the
  configured read-only self-managed instance. Search, refresh, pagination
  triggers, rows, details, scrolling, safe external routing, and back
  navigation were checked without recording credentials or API response
  payloads.

### Repair checklist

- [x] Keep empty and initial-error resource states inside a scroll container
  so pull to refresh remains available when GitLab returns no rows.
- [x] Remove GitLab template comments and ATX heading markers from the
  intentionally limited native description rendering, with unit coverage.
- [x] Prevent the long “Assigned Merge Requests” navigation title from
  truncating on iPhone 17 Pro while keeping both list modes consistent.
- [x] Update the README and ordered MVP checklist to match the verified
  merge-request and project implementation.
- [x] Re-run the complete signed suite and analyzer after the repairs, then
  inspect the affected screens in light and dark appearance.

### Deliberately unchanged

- Project rows open validated GitLab web URLs because native repository/project
  details are outside MVP-11.
- Issue, merge-request, and project row layouts remain feature-specific. Their
  loading state is shared, but a generic resource-row or resource-list view
  would erase useful domain differences for little reduction in code.
- Full GitLab Flavored Markdown rendering remains post-MVP. This repair only
  removes non-content template syntax that visibly disrupts otherwise readable
  descriptions.

## Post-MVP-12 audit

Scope:

- All production Swift, tests, app/project configuration, and MVP
  documentation were reviewed again after the pending/done Todos inbox was
  added.
- The complete signed suite passes all 192 logical tests (264 parameterized
  executions) on iPhone 17 Pro, iOS 26.5. Swift 6 complete concurrency
  checking, Xcode static analysis, property-list validation, and the
  production secret/logging scan are clean.
- All six pending/done and target-filter combinations, scrolling, pull to
  refresh, pagination behavior, empty/populated states, and the optional badge
  were exercised in the simulator. The changed authentication sheets were
  separately tapped and visually inspected on iPhone 17 Pro in light and dark
  appearance.

### Repair checklist

- [x] Preserve the last meaningful refresh or pagination error when a retry is
  cancelled, so stale data never regains a reliable badge or loses its retry
  warning without a successful response.
- [x] Prevent a non-cooperative authentication response from establishing a
  session after its sign-in task is cancelled, with deterministic OAuth and
  personal-token regression tests.
- [x] Make dismissible sign-in sheets own and cancel their in-flight task, and
  keep the token sheet's title and Cancel control visible at iPhone width.
- [x] Replace nullable Home shortcut mappings with exhaustive routing and
  remove the now-unreachable generic fallback list.
- [x] Re-run focused regression suites, the complete signed suite, static
  analysis, and light/dark simulator interaction flows after the repairs.

### Deliberately unchanged

- The existing feature-level Model-View structure and injected loader seams
  remain small and testable; adding an architecture framework would not solve
  a current problem.
- Todo, issue, merge-request, and project response and row types remain
  feature-specific because their GitLab contracts and presentation needs
  evolve independently.
- Todo rows remain noninteractive in MVP-12. MVP-13 must first make every API
  request declare read versus write access and enforce that declaration before
  transport, then add native/browser routing and completion controls.

## Post-MVP-13 audit

Scope:

- All production Swift, tests, app/project configuration, and MVP
  documentation were reviewed after native Todo routing and completion were
  added.
- Request access declarations, OAuth and personal-token authentication,
  refresh/cancellation behavior, Keychain storage, pagination, cached filter
  state, optimistic mutations, URL validation, and error redaction were
  checked as complete flows rather than as isolated files.
- Production logging and secret scans found no response-body logging,
  credential interpolation, analytics, or committed local configuration.
  Test credentials remain obviously synthetic and are used only to verify
  header construction and redaction.

### Repair checklist

- [x] Snapshot the cached pending Todo IDs affected by mark-all so a failure
  restores only that operation and preserves earlier successful completions.
- [x] Reconcile a successful pending refresh after mark-all, allowing newly
  created Todos to appear instead of remaining hidden for the app session.
- [x] Keep completed IDs out of the pending badge when GitLab briefly returns a
  stale page, while accepting a server-authoritative lower total.
- [x] Capture the exact Todo query and page model before an asynchronous load,
  so changing filters during a refresh cannot reconcile the wrong cache.
- [x] Stop already-cancelled REST and OAuth token operations before transport,
  with regression tests proving that no request is recorded.
- [x] Update the README, OAuth wording, MVP checklist, and MVP-13 status to
  match the implemented product.
- [x] Re-run the complete signed suite, static analyzer, property-list and
  privacy scans, then launch and tap the final build in the iPhone 17 Pro
  simulator.

### Deliberately unchanged

- Issue, merge-request, project, and Todo rows remain feature-specific. Their
  data and interaction requirements are different enough that a generic row
  or list abstraction would obscure behavior without removing meaningful
  duplication.
- `TodosModel` continues to compose the shared pagination model rather than
  moving optimistic writes into that generic type. Mutation overlays are
  Todo-specific, while the shared model remains a small read-only state
  engine.
- A successful mark-all remains optimistic until the next pending refresh.
  The app does not poll, persist optimistic state, or add undo outside the MVP
  contract.

## MVP-14 accessibility audit

Scope:

- Authentication, Home, Account, sign-out, both tabs, Todo filters and rows,
  issue and merge-request rows/details, project rows, loading states, and Todo
  mutation progress were exercised on iPhone 17 Pro.
- The changed flows were inspected at the largest accessibility text size and
  at the default size. Light and dark appearance plus standard and Increased
  Contrast rendering were covered across the signed-out and signed-in
  simulators.
- Simulator accessibility hierarchy inspection confirmed stable identifiers
  and complete synthesized labels for the authentication choices, tab bar,
  account/sign-out controls, Todo controls, and resource rows.

### Repair checklist

- [x] Keep sign-in branding, setup guidance, error copy, and token controls
  vertically expandable, with an inline self-managed navigation title at
  accessibility sizes.
- [x] Replace segmented instance and Todo filters with scalable menu pickers
  only at accessibility text sizes; preserve the existing dense segmented
  presentation at standard sizes.
- [x] Stack issue, merge-request, project, and Todo metadata vertically at
  accessibility sizes so titles, references, paths, states, people, and
  actions remain visible instead of collapsing to icons or ellipses.
- [x] Give root tabs and session restoration stable identifiers, ensure the
  Home account control has a 44-point hit region, and announce loading and
  Todo-mutation progress once per status change.
- [x] Inspect the privacy explanation, account sheet, sign-out confirmation,
  empty states, list navigation, and native details without changing the real
  read-only simulator session.
- [x] Re-run the complete signed suite: 238 logical tests and 349 parameterized
  executions pass. Property-list validation and the accessibility-change
  static analysis are clean.

### Deliberately unchanged

- Standard-size resource rows keep their existing compact presentation. The
  vertical variants activate only for accessibility Dynamic Type categories.
- The app has no custom animation whose meaning or access changes under Reduce
  Motion. Semantic state continues to use text and symbols as well as color,
  so Differentiate Without Color does not remove information.
- Pure SwiftUI layout branches and accessibility modifiers do not add core
  logic, so they rely on the existing model tests plus simulator hierarchy and
  interaction verification rather than duplicative unit tests.

## MVP-14 privacy and release-preflight audit

Scope:

- Authorization, OAuth exchange/refresh/PKCE, personal-token sign-in, stored
  sessions, Keychain, API responses, errors, and request descriptions were
  reviewed as secret-bearing boundaries.
- Tracked files were scanned for production logging, analytics, force casts,
  force tries, embedded credential shapes, local configuration, and
  real-account screenshots.
- The final signed suite passes 241 logical tests and 352 parameterized
  executions on iPhone 17 Pro, iOS 26.5. Xcode static analysis and app/privacy
  property-list validation pass.

### Repair checklist

- [x] Redact OAuth state, verifier, and challenge from both normal and
  reflected PKCE descriptions.
- [x] Prove submitted OAuth refresh tokens and rejected personal access tokens
  do not enter user-facing or reflected failures.
- [x] Restrict Keychain sessions to
  `WhenUnlockedThisDeviceOnly` on both insert and replacement, with tests that
  inspect the stored accessibility class.
- [x] Bundle and test a privacy manifest that declares app-owned
  `UserDefaults` access under `CA92.1`, no tracking, no tracking domains, and
  no collected data.
- [x] Confirm `.env` is ignored and untracked, and that the sole tracked raster
  image is the intentional GitHub design reference.
- [x] Install the hardened build and confirm the existing signed-in session
  restores to Home without exposing or recording credentials.

### Deliberately unchanged

- The OAuth presentation anchor retains one `preconditionFailure` for the
  framework invariant that the callback follows a successfully resolved
  presentation window. The public start path handles a missing window as a
  tested error; there are no force tries or force casts in production.
- The self-managed OAuth Application ID remains in `UserDefaults`. It is a
  public application identifier rather than a user secret, and the privacy
  manifest declares this app-owned preference use.
- Xcode 26.6 invokes its App Intents metadata processor even though Glab and
  its tests do not link App Intents, then reports that extraction was skipped.
  This is an unused-toolchain diagnostic; the Swift compiler and static
  analyzer report no findings.

## MVP-15 release-candidate audit

Scope:

- All production Swift, tests, app/project configuration, release metadata,
  privacy declarations, and MVP documentation were reviewed after the release
  archive and live verification pass.
- The complete signed suite passes 244 logical tests in 44 suites on a fresh,
  credential-free iPhone 17 Pro simulator running iOS 26.5. Xcode static
  analysis and the signed Release archive succeed.
- Authentication, request retries, empty/retained resource states,
  cancellation, Todos mutations, destructive confirmations, Keychain session
  restoration, archive contents, and secret-bearing boundaries were examined
  as complete flows.

### Repair checklist

- [x] Stop retrying a request after Foundation's full request timeout, avoiding
  multiple 60-second waits while retaining bounded retries for fast
  connection-loss and server failures.
- [x] Keep an empty resource visibly loading when the user retries, rather than
  clearing its error into a false empty state while the request is in flight.
- [x] Use native alerts for destructive Account and Todo confirmations so the
  destructive action and Cancel remain reachable at the largest accessibility
  text size on a small iPhone.
- [x] Run the complete suite on a fresh simulator so a retained live Keychain
  session cannot affect otherwise isolated app-host tests.
- [x] Align client retry coverage with the bounded timeout contract and add
  deterministic regression tests before keeping each production repair.
- [x] Inspect and scan the Release archive for its app icon, privacy manifest,
  export declaration, bundle/version metadata, test bundles, and configured
  host/token values.

### Deliberately unchanged or externally blocked

- A 60-second request timeout remains Foundation's default. The app no longer
  compounds that delay automatically, and a shorter arbitrary timeout would
  penalize legitimately slow self-managed instances.
- Feature-specific issue, merge-request, project, and Todo rows/models remain
  separate. The audit found no meaningful duplication that warrants erasing
  their distinct API and interaction behavior.
- GitLab.com OAuth and personal-token live verification require credentials or
  a registered application that is not configured. Unit tests are not
  substituted for those rows.
- The self-managed host outage was transient. A resumed pass recorded GitLab
  18.11.3-ee and completed the signed-in large-device rows with the available
  read-only personal token.
- The local archive is development-signed. Distribution signing and App Store
  validation remain external release actions and are not inferred from a
  successful local archive. A non-uploading App Store Connect export was
  attempted and Xcode reported no authenticated accounts and no distribution
  profile for the app bundle identifier; the separate validation method
  requires an upload and was intentionally not used.

## Resumed MVP-15 live-verification audit

Scope:

- The resumed pass has no production Swift, test Swift, or Xcode-project delta
  from candidate code commit `f788c44`, whose full 27,122-line audit and
  244-test result therefore remain current.
- A Release build was exercised against GitLab 18.11.3-ee on one dedicated
  iPhone 17 Pro Max simulator running iOS 26.5, then the app and simulator were
  shut down.
- The review re-ran the full source smell scan. Its only force casts are
  type-directed generic test doubles; its production precondition is the
  already documented OAuth presentation-anchor invariant. No new crash,
  duplication, or refactor candidate was found.

### Live verification checklist

- [x] Reconfirm the configured host with successful live version, user, and
  personal-token capability requests without recording its private values.
- [x] Restore the Keychain-backed read-only session after relaunch.
- [x] Exercise all five Home routes and native issue/merge-request details.
- [x] Exercise pending/done with all/issues/merge-request Todo filters and
  native Done Todo routing. The live account had no pending Todos, and the
  empty state rendered correctly.
- [x] Inspect Home and Todos in dark appearance with accessibility-extra-large
  text, including scrolling and tab reachability.
- [x] Shut down the sole test simulator and confirm no Simulator remains
  booted.

Two failed automation assertions were rejected as test-script mistakes rather
than app defects: one used the nonexistent identifier `rootTab.home` instead
of `tab.home`, and one expected a pending issue Todo on an account whose live
pending result was empty.

### Deliberately unchanged or deferred

- The feature-specific issue, merge-request, project, and Todo models remain
  intentionally separate; no new duplication justified merging their API or
  interaction behavior.
- GitLab.com OAuth and personal-token live rows remain unverified. Self-managed
  OAuth activation, App Store distribution, and Icon Composer work are
  explicitly deferred by the project owner.
