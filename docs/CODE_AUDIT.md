# Focused code audit

Last updated: 2026-07-27

## Scope

This audit covers all production Swift, unit tests, app configuration, and MVP
documentation present through MVP-08. It intentionally excludes naming or
formatting preferences that do not affect correctness, security, testability,
or near-term feature work.

Baseline:

- 103 unit tests pass on iPhone 17 Pro, iOS 26.5.
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

- [ ] Add deterministic unit coverage for every core-logic repair.
- [ ] Run the complete test suite and static analyzer.
- [ ] Launch the app and retest the changed authentication and signed-in UI on
  iPhone 17 Pro in light and dark appearance.

## Deliberately unchanged

- The feature-level MV structure is small, explicit, and already has useful
  protocol seams; adding a framework or more layers would not solve a current
  problem.
- The separate issue, merge-request, and project response types resemble one
  another today but represent independently evolving GitLab API resources.
- Home preview routes intentionally contain three items until their full
  paginated MVP list features are implemented.
