# Focused code audit

Last updated: 2026-07-27

## Scope

This audit covers all production Swift, unit tests, app configuration, and MVP
documentation present through MVP-08. It intentionally excludes naming or
formatting preferences that do not affect correctness, security, testability,
or near-term feature work.

Baseline:

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
- The complete signed suite reached 157 passing test invocations and Xcode
  static analysis was clean before the final refresh/pagination repair; focused
  regression suites pass after that repair.
- The configured read-only self-managed instance returned 4 assigned merge
  requests, 1 review request, and a valid detail response matching the decoded
  contract. No response content or credential was recorded.
- Final interactive simulator verification remains open because the Mac UI is
  locked; the installed build and screenshot-only Home check are not counted as
  a tap-through.

### Repair checklist

- [x] Share API user normalization, validated external URLs, Markdown
  formatting, labels, user rows, retry rows, detail sections, and the
  “Open in GitLab” control instead of creating merge-request copies.
- [x] Keep a failed refresh warning authoritative by preventing stale
  pagination from clearing it in both issues and merge requests.
- [ ] Consolidate the duplicated issue/merge-request pagination and detail
  state machines behind small generic engines. Preserve the existing
  domain-named initializers and properties so views and tests remain explicit.
- [ ] Run the complete signed suite and static analyzer after the shared-state
  refactor.
- [ ] Tap both Home shortcuts, populated list rows, details, scrolling, search,
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
