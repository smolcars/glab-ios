# Glab iOS MVP Phase 2

Last updated: 2026-07-28

## Product goal

Turn Glab into a focused mobile code-review client:

1. Switch safely between GitLab accounts.
2. Understand an issue or merge request without opening a browser.
3. Read and participate in its discussion.
4. Review merge-request changes with consistently responsive scrolling.
5. See whether a merge request is ready to merge.
6. Find and open GitLab work from search or a GitLab URL.

Phase 2 extends the existing SwiftUI Model-View architecture. It does not
authorize an app-wide architecture rewrite.

## Working agreement

- Complete the first unchecked feature before starting another feature.
- **Always write and record an engineering plan before writing implementation
  code.** The plan must describe scope, API contracts, state ownership,
  dependencies, failure behavior, tests, performance risks, UI verification,
  and explicit non-goals.
- Inspect the current implementation before planning. Do not design a parallel
  abstraction when an existing service or model already provides the required
  boundary.
- Use current official GitLab API documentation as the source of truth,
  including self-managed compatibility and tier limitations.
- Implement one end-to-end vertical slice at a time and keep `master`
  buildable. Add core-logic tests with the implementation and push small,
  verified commits frequently.
- Every feature ends with a dedicated deep code-review and repair pass. A
  feature is not complete merely because its first implementation works.
- Run unit tests and static analysis in proportion to the change. Launch,
  inspect, and tap through every changed UI on an iPhone 17 Pro Simulator in
  light and dark appearance. Do not use the owner's physical devices.
- The configured self-managed read-only token may be used for live read
  verification in Simulator. Never print, commit, bundle, or place it in test
  fixtures. Do not attempt live mutations with that credential.
- Test mutations with protocol fakes or `URLProtocol` stubs unless the owner
  explicitly provides a disposable write-enabled account and authorizes live
  mutation testing.
- Keep account credentials in Keychain. Account identifiers, cached responses,
  drafts, logs, screenshots, and in-flight work must never expose or cross into
  another account.
- Do not mark a checkbox complete without recording the verification result in
  the feature's engineering plan.

## Phase 2 definition of done

Phase 2 is complete when:

- P2-01 through P2-09 are complete.
- Each feature has a written plan created before its implementation.
- Each feature has core-logic regression tests and Simulator UI verification.
- Each feature's post-implementation deep review is complete and every
  material finding has been planned, fixed, and reverified.
- Performance fixtures cover large Markdown documents, long discussions, and
  large diffs without doing parsing or other expensive work on the main actor.
- Multiple accounts cannot share credentials, cached data, drafts, mutations,
  or stale in-flight results.
- The complete test suite and Xcode static analysis pass.

## Ordered Phase 2 checklist

### [x] P2-01 — Add multiple accounts and account switching

Outcome:

- A user can add, switch, and remove GitLab.com or self-managed accounts
  without signing out of every other account.
- Authentication, requests, caches, drafts, and UI state remain isolated by
  canonical GitLab host and GitLab user ID.

Todo:

- [x] Inspect the existing single-session storage, `AppSession`, client
  composition, cache scoping, authentication restoration, and sign-out paths.
- [x] Before writing code, create `docs/P2_01_ENGINEERING_PLAN.md`. Document
  the storage migration, account identity, active-account ownership,
  dependency reconstruction, cancellation behavior, UI states, tests,
  security boundaries, and non-goals.
- [x] Write failing tests for replacing the unreleased single-account storage,
  storing multiple accounts, restoring the active account, handling the same
  username on different hosts, and removing one account without removing the
  others. The owner explicitly authorized a breaking persistence change, so
  the old `current-session` Keychain item does not require migration.
- [x] Write failing tests proving that a switch cancels or rejects stale
  in-flight results and that credentials, response-cache entries, drafts, and
  authentication failures affect only their owning account.
- [x] Implement a stable non-secret account index and active-account ID while
  retaining secret credentials and refresh tokens only in Keychain.
- [x] Recompose the active session client and root feature hierarchy when the
  account changes. Do not retain feature models that belong to the prior
  account.
- [x] Add an account switcher to the Account presentation with Add Account,
  Switch Account, and Remove Account actions. Require confirmation before
  removing an account.
- [x] Preserve the existing GitLab.com OAuth, self-managed OAuth, and personal
  access-token flows when adding another account.
- [x] Verify account addition, switching, relaunch restoration, removal,
  read-only presentation, loading cancellation, and cache isolation in the
  iPhone 17 Pro Simulator.
- [x] Run the focused tests, complete test suite, static analysis, and a
  credential/privacy scan.
- [x] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated code, incorrect state ownership,
  concurrency or cancellation races, credential/data leakage, and code that
  needs refactoring. Record the findings in the engineering plan.
- [x] If the review finds anything material, write a repair plan before
  editing code, add regression tests where applicable, implement every fix,
  and repeat the feature verification and review.

### [x] P2-02 — Render issue and merge-request descriptions as Markdown

Outcome:

- Issue and merge-request descriptions render as responsive native content,
  with a documented high-fidelity subset of GitLab Flavored Markdown.
- Rendering does not require a GitLab Markdown API request and does not
  repeatedly parse content during SwiftUI view updates.

Todo:

- [x] Inspect the issue/MR detail models, current raw-description views,
  navigation behavior, response cache, image loading, and existing text/link
  handling.
- [x] Before writing code, create `docs/P2_02_ENGINEERING_PLAN.md`. Document
  supported Markdown syntax, parser/renderer selection, GitLab-reference
  resolution, cache identity and invalidation, isolation boundaries,
  accessibility, performance fixtures, tests, fallback behavior, and
  non-goals.
- [x] Benchmark candidate native parsing/rendering approaches before selecting
  one. Record dependency, maintenance, correctness, memory, and scrolling
  tradeoffs; do not select a WebView or dependency without measured reasons.
- [x] Define fixtures for small, medium, and large documents containing
  headings, lists, task lists, block quotes, links, images, inline/fenced code,
  tables, strikethrough, and GitLab references.
- [x] Write failing parser, link-routing, cancellation, malformed-input, cache
  invalidation, accessibility-label, and unsupported-syntax fallback tests.
- [x] Implement parsing away from the main actor and publish an immutable
  render model. Never parse from a SwiftUI `body`.
- [x] Cache parsed output by account, resource identity, content hash, and
  renderer version with a bounded storage policy.
- [x] Render large content incrementally or lazily, load remote images lazily
  with size/network limits, and keep links safe and account-aware.
- [x] Support the agreed common GitLab Flavored Markdown subset. Provide a
  readable fallback and Open in GitLab action for unsupported diagrams, math,
  multimedia, or server-specific constructs.
- [x] Measure parse time, first meaningful render, memory, and scroll behavior
  with every performance fixture. Record the baseline and final measurements.
- [x] Verify representative issue and MR descriptions, links, rotation,
  Dynamic Type, VoiceOver labels, light/dark appearance, and rapid navigation
  cancellation in the iPhone 17 Pro Simulator.
- [x] Run the focused tests, complete test suite, static analysis, and source
  privacy scan.
- [x] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated code, unsafe HTML or links, repeated
  parsing, unbounded caches, main-actor work, memory retention, and code that
  needs refactoring. Record the findings in the engineering plan.
- [x] If the review finds anything material, write a repair plan before
  editing code, add regression and performance tests where applicable,
  implement every fix, and repeat the feature verification and review.

### [x] P2-03 — View issue and merge-request discussions

Outcome:

- A user can read paginated, threaded issue and merge-request discussions,
  including replies and clearly distinguished system activity.

Todo:

- [x] Inspect issue/MR routing, detail loaders, pagination, cache behavior, and
  any existing note decoding.
- [x] Before writing code, create `docs/P2_03_ENGINEERING_PLAN.md`. Document
  the Discussions API contract, model identity, issue/MR endpoint sharing,
  pagination, system-note presentation, Markdown integration, caching,
  cancellation, tests, performance, UI states, and non-goals.
- [x] Use the Discussions API rather than flattening the feature onto the Notes
  API. Preserve thread and reply identities and decode evolving note types
  defensively.
- [x] Write failing tests for issue and MR endpoints, first/next-page loading,
  nested replies, system notes, unknown fields, empty discussions, cache-first
  refresh, stale fallback, duplicate suppression, and cancellation.
- [x] Implement one shared discussion domain model and service without
  duplicating issue and MR orchestration.
- [x] Render note bodies through the P2-02 Markdown pipeline and maintain stable
  row identity so refreshed discussions do not visibly jump.
- [x] Cache the first discussion page by account and resource, keep later pages
  in memory, and retain visible content when refresh fails.
- [x] Use lazy/virtualized presentation for long discussions and compact or
  collapse system activity without hiding it.
- [x] Add loading, empty, pagination, retained-error, retry, and offline states.
- [x] Verify populated, empty, long, cached, failed-refresh, and paginated
  discussions for both issues and MRs in the iPhone 17 Pro Simulator.
- [x] Run the focused tests, complete test suite, static analysis, and cache
  privacy scan.
- [x] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated issue/MR paths, pagination errors,
  unstable identities, lost replies, loading races, excessive rendering work,
  and code that needs refactoring. Record the findings in the engineering
  plan.
- [x] If the review finds anything material, write a repair plan before
  editing code, add regression tests where applicable, implement every fix,
  and repeat the feature verification and review.

### [ ] P2-04 — Post comments and threaded replies

Outcome:

- A write-enabled user can create an issue/MR discussion or reply to an
  existing thread, while read-only users receive a clear capability
  explanation.

Todo:

- [ ] Inspect credential capability handling, existing Todo mutation patterns,
  API error mapping, discussion refresh behavior, and account-scoped storage.
- [ ] Before writing code, create `docs/P2_04_ENGINEERING_PLAN.md`. Document
  create/reply endpoints, draft ownership, request state, duplicate-prevention
  policy, reconciliation, cache invalidation, read-only UX, tests, Simulator
  strategy, and non-goals.
- [ ] Write failing tests for new discussions, replies, empty/invalid bodies,
  read-only capability, successful reconciliation, server validation errors,
  cancellation, ambiguous connectivity failures, and cache invalidation.
- [ ] Persist unfinished drafts by account, resource, and optional discussion.
  Clear a draft only after the server confirms creation.
- [ ] Add an accessible composer for new comments and replies with explicit
  sending, failure, retry, and dismissal states.
- [ ] Do not automatically retry an ambiguous failed comment POST. Preserve
  the draft and require an intentional user retry to avoid duplicates.
- [ ] Reconcile the returned server discussion/note instead of inventing a
  permanent local ID, then refresh or invalidate only the affected discussion
  cache.
- [ ] Disable posting for `read_api` sessions and explain the required
  capability without pressuring the user to broaden access.
- [ ] Verify the complete composer and read-only experience with deterministic
  services in the iPhone 17 Pro Simulator. Do not perform a live mutation with
  the configured read-only token.
- [ ] Run the focused tests, complete test suite, static analysis, and draft
  storage/privacy scan.
- [ ] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated mutation paths, duplicate-post risks,
  draft loss or cross-account leakage, unsafe retry behavior, stale-cache
  races, and code that needs refactoring. Record the findings in the
  engineering plan.
- [ ] If the review finds anything material, write a repair plan before
  editing code, add regression tests where applicable, implement every fix,
  and repeat the feature verification and review.

### [ ] P2-05 — Add emoji reactions

Outcome:

- A user can view and, when authorized, add or remove emoji reactions on an
  issue, merge request, or discussion note.

Todo:

- [ ] Inspect discussion/resource models, current-user identity, mutation
  capability handling, optimistic Todo updates, and cache invalidation.
- [ ] Before writing code, create `docs/P2_05_ENGINEERING_PLAN.md`. Document
  resource/note reaction endpoints, award identity, grouping, current-user
  state, picker scope, optimistic mutation/rollback, cache invalidation,
  tests, accessibility, and non-goals.
- [ ] Write failing tests for decoding grouped reactions, current-user awards,
  issue/MR/note endpoint construction, add/remove success, permission errors,
  optimistic rollback, repeated taps, cancellation, and account switching.
- [ ] Model individual award IDs even when the UI groups identical emoji,
  because removal targets a specific award.
- [ ] Add a compact accessible reaction summary and a deliberately bounded
  common-emoji picker. Defer custom-emoji browsing unless the plan proves it
  is necessary for the first slice.
- [ ] Implement optimistic add/remove with duplicate-action coalescing and
  exact rollback on failure.
- [ ] Invalidate or reconcile only the affected resource/note reaction state.
- [ ] Disable mutations for read-only sessions while continuing to display
  reactions.
- [ ] Verify issue, MR, and note reactions; rapid taps; rollback; read-only
  behavior; Dynamic Type; and light/dark appearance with deterministic
  services in the iPhone 17 Pro Simulator.
- [ ] Run the focused tests, complete test suite, static analysis, and
  account-isolation checks.
- [ ] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated endpoint logic, incorrect award IDs,
  count drift, optimistic-state races, accessibility gaps, and code that needs
  refactoring. Record the findings in the engineering plan.
- [ ] If the review finds anything material, write a repair plan before
  editing code, add regression tests where applicable, implement every fix,
  and repeat the feature verification and review.

### [ ] P2-06 — Build a performant merge-request diff viewer

Outcome:

- A user can browse an MR's changed files and inspect a large unified diff
  without blocking the main actor or constructing one enormous text view.

Todo:

- [ ] Inspect MR detail routing, API/client pagination, response cache, current
  navigation/UI components, and available UIKit bridges.
- [ ] Before writing code, create `docs/P2_06_ENGINEERING_PLAN.md`. Document
  the MR diffs endpoint, self-managed compatibility, file/hunk/line models,
  parser isolation, view virtualization, memory/cache budgets, pagination,
  cancellation, large-diff fallback, accessibility, benchmarks, tests, UI
  verification, and non-goals.
- [ ] Do not build on the deprecated MR `/changes` endpoint. Use the paginated
  `/diffs` endpoint and preserve file metadata such as renamed, deleted,
  generated, collapsed, and too-large state when the server supplies it.
- [ ] Create unified-diff fixtures covering ordinary changes, context, missing
  newlines, renames, binary/generated files, malformed hunks, Unicode, very
  long lines, and approximately 1,000, 10,000, and 50,000 changed lines.
- [ ] Write failing parser, pagination, malformed-input, cancellation, cache
  identity, head-SHA invalidation, and too-large fallback tests.
- [ ] Implement parsing away from the main actor into immutable file, hunk,
  and line values. Propagate cancellation during long parses.
- [ ] Show a paginated changed-file summary and load/render one file at a time.
  Do not eagerly parse every file in an MR.
- [ ] Use a virtualized line presentation. Profile SwiftUI first, and use a
  focused UIKit collection-view/TextKit surface if measured SwiftUI behavior
  cannot meet the recorded performance budget.
- [ ] Provide fixed-width text, additions/deletions/context styling,
  horizontal access to long lines, selectable content where practical, hunk
  navigation, and clear file-status indicators.
- [ ] Cache parsed diffs by account, project, MR, head SHA, path, and parser
  version with explicit byte/count limits and least-recently-used eviction.
- [ ] Provide an honest unavailable state and Open in GitLab action for files
  GitLab reports as collapsed, too large, binary, or otherwise unavailable.
- [ ] Measure parsing, first file render, memory, and scroll hitching with every
  fixture. Record baseline/final measurements and verify that leaving a file
  cancels unnecessary work.
- [ ] Verify file pagination, file navigation, long lines, huge fixtures,
  light/dark appearance, Dynamic Type, Reduce Motion, and rapid back navigation
  in the iPhone 17 Pro Simulator.
- [ ] Run focused correctness/performance tests, the complete suite, static
  analysis, and cache/privacy scans.
- [ ] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated parsing/rendering logic, parser
  correctness errors, main-actor work, unbounded memory/cache growth,
  cancellation failures, stale-head data, and code that needs refactoring.
  Record the findings in the engineering plan.
- [ ] If the review finds anything material, write a repair plan before
  editing code, add regression and performance tests where applicable,
  implement every fix, and repeat the feature verification and review.

### [ ] P2-07 — Show and create inline diff discussions

Outcome:

- A user can see which diff lines have discussions and, when authorized, start
  or reply to a positional discussion without commenting on the wrong diff
  version.

Todo:

- [ ] Inspect the completed diff line identity, discussion model, comment
  composer, reaction behavior, and MR version/head-SHA handling.
- [ ] Before writing code, create `docs/P2_07_ENGINEERING_PLAN.md`. Document
  GitLab position payloads, base/start/head SHA ownership, old/new path and
  line mapping, outdated threads, UI placement, write reconciliation,
  invalidation, tests, performance, and non-goals.
- [ ] Write failing tests for old/new line positions, additions, deletions,
  context lines, renamed paths, replies, outdated discussions, changed head
  SHAs, server validation errors, read-only sessions, and cancellation.
- [ ] Map positional discussions onto stable diff line identities without
  scanning every discussion for every visible line.
- [ ] Display existing inline threads and distinguish current from outdated
  positions without hiding either.
- [ ] Reuse the shared Markdown renderer, discussion composer, draft storage,
  and reaction components rather than creating diff-only duplicates.
- [ ] Build position requests only from the exact diff version supplied by
  GitLab. Reject or refresh stale UI state before sending a line comment.
- [ ] Reconcile successful writes and update only the affected thread/line.
  Preserve drafts and avoid automatic retries after ambiguous POST failures.
- [ ] Measure scrolling with representative inline-thread density and ensure
  collapsed threads do not eagerly render every comment.
- [ ] Verify old/new line threads, outdated threads, reply/reaction UI,
  read-only behavior, rapid navigation, and simulated version changes in the
  iPhone 17 Pro Simulator.
- [ ] Run focused tests, the complete suite, static analysis, and
  account/version-isolation checks.
- [ ] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated discussion UI or services, off-by-one
  line mapping, wrong-SHA writes, stale-version races, scrolling regressions,
  and code that needs refactoring. Record the findings in the engineering
  plan.
- [ ] If the review finds anything material, write a repair plan before
  editing code, add regression and performance tests where applicable,
  implement every fix, and repeat the feature verification and review.

### [ ] P2-08 — Add an MR readiness summary

Outcome:

- An MR clearly communicates whether it is ready for review or merge through
  pipeline, approval, conflict, draft, and unresolved-discussion state.

Todo:

- [ ] Inspect the MR detail model, available decoded merge-status fields,
  discussion resolution data, API capability handling, and cache policy.
- [ ] Before writing code, create `docs/P2_08_ENGINEERING_PLAN.md`. Document
  MR/pipeline/approval endpoint contracts, GitLab tier/version differences,
  readiness derivation, partial-data behavior, caching, refresh, tests,
  presentation, accessibility, and non-goals.
- [ ] Define a small readiness domain model that preserves unknown and
  unavailable states instead of treating them as failure or success.
- [ ] Write failing tests for passing/running/failed/missing pipelines,
  approved/pending/unavailable approvals, merge conflicts, draft MRs,
  unresolved discussions, unknown detailed merge statuses, partial failures,
  cache refresh, and account switching.
- [ ] Load only the minimum additional data required for the summary and avoid
  serial requests when independent API calls can execute concurrently.
- [ ] Handle GitLab tiers and self-managed versions gracefully. Do not show a
  paid or unavailable approval capability as a network failure.
- [ ] Add a compact, accessible readiness summary to MR details with a clear
  path to pipeline, approval, and unresolved-discussion information.
- [ ] Keep Phase 2 readiness read-only. Approve, unapprove, merge, and pipeline
  retry actions require separate future plans and explicit mutation safety.
- [ ] Verify every readiness state, partial failure, cached/stale refresh,
  read-only account, Dynamic Type, and light/dark appearance in the iPhone 17
  Pro Simulator.
- [ ] Run focused tests, the complete suite, static analysis, and API
  compatibility checks.
- [ ] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated loading/state derivation, false-ready
  states, tier/version assumptions, request waterfalls, stale summaries, and
  code that needs refactoring. Record the findings in the engineering plan.
- [ ] If the review finds anything material, write a repair plan before
  editing code, add regression tests where applicable, implement every fix,
  and repeat the feature verification and review.

### [ ] P2-09 — Add global search and GitLab deep links

Outcome:

- A user can find projects, issues, and merge requests for the active account,
  and a supported GitLab URL opens in the matching native screen and account.

Todo:

- [ ] Inspect existing list search, navigation routes, URL opening, host
  normalization, account identity, and project/issue/MR models.
- [ ] Before writing code, create `docs/P2_09_ENGINEERING_PLAN.md`. Document
  supported search scopes, tier/version differences, debounce/cancellation,
  pagination, result identity, deep-link URL grammar, account matching,
  authentication fallback, security, tests, UI states, and non-goals.
- [ ] Write failing tests for project/issue/MR search requests, debounce,
  cancellation, pagination, unknown result fields, account isolation, and
  unavailable scopes.
- [ ] Write failing deep-link tests for GitLab.com and self-managed project,
  issue, and MR URLs; encoded namespaces; unmatched hosts; missing accounts;
  malicious/lookalike URLs; and signed-out routing.
- [ ] Implement active-account search with cancellation and pagination. Do not
  merge results from accounts or imply a search scope exists when the server
  does not support it.
- [ ] Add a native search screen with useful empty, recent-query, loading,
  paginated, partial, permission, and failure states.
- [ ] Route a trusted GitLab URL to the matching account and native resource.
  Ask the user to add/select an account when no safe match exists; never send
  one host's credential to another host.
- [ ] Keep unsupported URLs visible and openable in the system browser after
  explicit validation.
- [ ] Verify search, cancellation, pagination, result navigation, account
  switching, supported links, unsupported links, and signed-out links in the
  iPhone 17 Pro Simulator.
- [ ] Run focused tests, the complete suite, static analysis, and URL/security
  scans.
- [ ] Perform a deep code review of all code added or changed for this feature.
  Look for bugs, bad code, duplicated routing/search models, credential-host
  confusion, unsafe URL acceptance, stale results, cancellation races, tier
  assumptions, and code that needs refactoring. Record the findings in the
  engineering plan.
- [ ] If the review finds anything material, write a repair plan before
  editing code, add regression and security tests where applicable, implement
  every fix, and repeat the feature verification and review.

## Deferred beyond Phase 2

These features are useful but are not part of the Phase 2 completion gate:

- Side-by-side diffs on iPhone.
- A full custom-emoji browser.
- Offline comment/reaction queues and conflict resolution.
- Editing or deleting comments.
- Attachments in comments.
- Approve, unapprove, merge, close, reopen, or retry-pipeline mutations.
- Pipeline job logs and artifact browsing.
- Push notifications.
- A combined cross-account inbox or background refresh for every account.
- Repository browsing, file editing, and commit creation.

Each deferred feature requires its own written engineering plan before any code
is written, core-logic tests, Simulator verification, and the same
post-implementation deep code-review and repair cycle required above.

## Official GitLab contracts

- [REST API and pagination](https://docs.gitlab.com/api/rest/)
- [OAuth 2.0 and PKCE](https://docs.gitlab.com/api/oauth2/)
- [GitLab Flavored Markdown](https://docs.gitlab.com/user/markdown/)
- [Markdown API](https://docs.gitlab.com/api/markdown/)
- [Discussions API](https://docs.gitlab.com/api/discussions/)
- [Emoji reactions API](https://docs.gitlab.com/api/emoji_reactions/)
- [Merge requests API](https://docs.gitlab.com/api/merge_requests/)
- [Merge request approvals
  API](https://docs.gitlab.com/api/merge_request_approvals/)
- [Pipelines API](https://docs.gitlab.com/api/pipelines/)
- [Search API](https://docs.gitlab.com/api/search/)
