# Glab iOS MVP Phase 3

Last updated: 2026-07-28

Status: planned. No Phase 3 implementation has started.

## Product goal

Turn Glab from a read-and-review client into a safe mobile work and CI client:

1. Edit issues and merge requests without losing another person's changes.
2. Complete description task lists and resolve merge-request discussions.
3. Create issues and manage their labels, assignees, state, and supported
   workflow status.
4. See who approved a merge request, who can still approve, and participate in
   the approval workflow.
5. Browse merge-request pipelines, jobs, and large job logs responsively.
6. Run permitted pipeline and merge-request actions with clear confirmation,
   delivery certainty, and server reconciliation.

Phase 3 extends the existing SwiftUI Model-View architecture with focused
observable models and injected services at each feature boundary. It does not
authorize an app-wide architecture rewrite or one shared object that owns all
issue, merge-request, approval, and pipeline state.

## Working agreement

- Complete the first unchecked core feature before starting another core
  feature.
- **Always write and record an engineering plan before writing implementation
  code.** Each plan must describe scope, official API contracts, self-managed
  compatibility, tier and permission limitations, state ownership,
  dependencies, mutation delivery certainty, cache invalidation and
  reconciliation, failure and cancellation behavior, tests, performance
  risks, UI verification, accessibility, and explicit non-goals.
- Inspect the current implementation before planning. Extend the existing API,
  mutation-certainty, cache, Markdown, discussion, draft, diff, account, and
  detail-model boundaries instead of creating parallel implementations.
- Use current official GitLab API documentation as the source of truth. Do not
  rely on undocumented endpoints, response fields, HTTP range behavior, or
  GitLab.com-only observations.
- Implement one end-to-end vertical slice at a time and keep `master`
  buildable. Add core-logic tests with the implementation and push small,
  verified commits frequently.
- Never automatically retry an ambiguous mutation. Preserve the user's input,
  explain when GitLab might already have accepted an action, and provide a
  safe refresh or reconciliation path.
- Treat OAuth or personal access token `read_api` sessions as read-only. Hide
  or disable mutations with an accurate explanation while preserving every
  read experience.
- Capability-detect GitLab tier, version, and permission-sensitive features.
  A `403`, `404`, or unavailable GraphQL field must degrade only the affected
  control, not the whole issue, merge request, discussion, or pipeline screen.
- Require explicit confirmation for destructive, costly, or difficult-to-undo
  actions such as closing, canceling, retrying, triggering, or merging.
- Keep credentials in Keychain. Account identifiers, caches, drafts, logs,
  screenshots, mutation state, and in-flight work must never expose secrets or
  cross into another account.
- The configured self-managed read-only token may be used for live read
  verification in Simulator. Never print, commit, bundle, or place it in test
  fixtures. Do not attempt live mutations with that credential.
- Test mutations with protocol fakes or `URLProtocol` stubs unless the owner
  explicitly provides a disposable write-enabled account and authorizes live
  mutation testing.
- Add deterministic unit tests for all core logic: endpoint and body
  construction, decoding, permissions, state transitions, stale-result
  rejection, cache invalidation, mutation reconciliation, cancellation,
  pagination, formatting, parsing, and performance-sensitive indexing.
- Launch, inspect, and tap through every changed UI on the iPhone 17 Pro
  Simulator in light and dark appearance. Verify relevant loading, empty,
  success, failure, read-only, Dynamic Type, VoiceOver, Reduce Motion, and
  Reduce Transparency states. Do not use the owner's physical devices.
- **Every feature ends with a dedicated deep code review. Review all code
  added or changed for bugs, bad code, duplicated code, incorrect state
  ownership, concurrency or cancellation races, security or privacy mistakes,
  and code that needs refactoring.**
- **If a feature review finds anything material, write a repair plan before
  changing code, add regression or performance tests where applicable, fix
  every finding, rerun the feature verification, and repeat the review.**
- Do not mark a checkbox complete without recording its verification evidence
  and review findings in the feature's engineering plan.

## Phase 3 definition of done

Phase 3 is complete when:

- P3-01 through P3-12 are complete. Stretch features do not block Phase 3.
- Every core feature has a written engineering plan created before its
  implementation.
- Every core feature has deterministic core-logic tests and Simulator UI
  verification.
- Every core feature's post-implementation deep review is complete and every
  material finding has been planned, fixed, reverified, and reviewed again.
- Issue, merge-request, discussion, approval, pipeline, job, and merge
  mutations reconcile authoritative server responses without leaking stale
  state into other screens or accounts.
- Description and checklist mutations cannot silently overwrite a known newer
  server description.
- Large pipeline histories and job logs remain responsive and bounded in
  memory, with parsing and indexing kept off the main actor.
- Unsupported GitLab tiers, older self-managed versions, insufficient project
  roles, and read-only credentials degrade honestly without breaking related
  read-only content.
- The complete test suite, performance fixtures, Release Simulator build,
  Xcode static analysis, and credential/privacy scans pass.

## Ordered Phase 3 core checklist

### [ ] P3-01 — Build the shared mutation foundation

Outcome:

- GitLab features can perform typed `PUT` requests while preserving the
  existing authorization, cancellation, delivery-certainty, cache, and account
  isolation guarantees.
- Later Phase 3 features share mutation invariants without sharing one
  feature-spanning state owner.

Todo:

- [ ] Inspect `GitLabAPIRequest`, request construction, `GitLabSessionClient`,
  write-access enforcement, mutation delivery certainty, retry policy,
  response caching, account switching, and existing Todo, discussion, and
  reaction mutations.
- [ ] Before writing production code, create
  `docs/P3_01_ENGINEERING_PLAN.md`. Document the exact HTTP additions, request
  body rules, authorization behavior, error and cancellation mapping,
  delivery-certainty semantics, invalidation hooks, test seams, migration
  impact, and non-goals.
- [ ] Write failing tests for typed `PUT` requests with and without JSON
  bodies, query encoding, OAuth and personal-token authorization, secret
  redaction, `read_api` rejection before transport, cancellation before
  transport, representative success responses, and every relevant failure
  category.
- [ ] Write failing tests proving ambiguous writes are not automatically
  retried and that a late response from an inactive account or canceled owner
  cannot mutate current feature state.
- [ ] Add the minimum generic `PUT` support required by documented GitLab
  endpoints. Do not add speculative HTTP methods or a generic mutation
  framework that hides feature-specific reconciliation.
- [ ] Reuse and, only where necessary, extend the existing mutation-delivery
  certainty model so features can distinguish a definitely rejected request
  from an action GitLab might already have accepted.
- [ ] Define small cache invalidation and authoritative-response reconciliation
  seams that later feature services can call without directly owning UI state.
- [ ] Verify existing POST and DELETE behavior remains unchanged and all
  existing authentication, caching, Todo, discussion, and reaction tests still
  pass.
- [ ] Run focused API tests, the complete test suite, a Release Simulator
  build, Xcode static analysis, and credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-01. Look
  for bugs, bad code, duplicated request or mutation logic, incorrect delivery
  certainty, accidental retries, stale-account writes, credential leakage,
  concurrency or cancellation races, and code that needs refactoring. Record
  every finding in `docs/P3_01_ENGINEERING_PLAN.md`.
- [ ] If the P3-01 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-01 verification, and repeat the deep code review until no material finding
  remains.

### [ ] P3-02 — Edit issue and merge-request titles and descriptions

Outcome:

- A permitted user can edit an issue or merge-request title and GitLab
  Flavored Markdown description, preview it with the existing renderer, and
  recover an unfinished draft.
- Glab refuses to silently save over a description it knows changed on GitLab
  after editing began.

Todo:

- [ ] Inspect issue and merge-request detail ownership, REST models,
  `updated_at`, response cache behavior, Markdown rendering, account-scoped
  discussion drafts, link handling, and current detail refresh semantics.
- [ ] Before writing production code, create
  `docs/P3_02_ENGINEERING_PLAN.md`. Document issue and merge-request update
  endpoints, edit-session identity, draft schema, stale-content detection,
  authoritative reconciliation, cache invalidation, permissions, UI states,
  tests, accessibility, and non-goals.
- [ ] Write failing endpoint and decoding tests for issue and merge-request
  title/description updates, empty descriptions, maximum accepted content
  boundaries, Unicode, Markdown, malformed responses, `403`, `404`, `409`,
  validation failures, cancellation, and ambiguous delivery.
- [ ] Write failing model tests for draft restoration, account and resource
  isolation, edit cancellation, unchanged submissions, stale server content,
  late responses, failed saves, successful reconciliation, and switching
  accounts during an edit.
- [ ] Add an account- and resource-scoped edit draft store. Never put
  credentials, authorization headers, or unrelated response data in a draft.
- [ ] Before saving, perform a documented best-effort freshness check and
  compare the authoritative title, description, and update identity with the
  edit baseline. Present a conflict instead of silently overwriting a known
  newer value.
- [ ] Build one native editor flow shared at the presentation level where that
  reduces duplication, while keeping issue and merge-request endpoint and
  reconciliation rules explicit.
- [ ] Reuse the existing Markdown renderer for preview and preserve raw
  Markdown exactly when the user has not changed it.
- [ ] Reconcile the returned issue or merge request into its detail owner,
  invalidate only affected cache entries, and discard the draft only after an
  authoritative success.
- [ ] Verify issue and MR editing, preview, draft recovery, conflict handling,
  read-only access, permission denial, network failure, account switching,
  long Markdown, keyboard behavior, Dynamic Type, and VoiceOver in the iPhone
  17 Pro Simulator.
- [ ] Run focused edit and cache tests, Markdown performance fixtures, the
  complete test suite, a Release Simulator build, Xcode static analysis, and
  credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-02. Look
  for bugs, bad code, duplicated issue/MR editor logic, lost drafts, false or
  missed conflicts, stale cache state, ambiguous-write mistakes, main-actor
  parsing, account leakage, concurrency or cancellation races, and code that
  needs refactoring. Record every finding in
  `docs/P3_02_ENGINEERING_PLAN.md`.
- [ ] If the P3-02 review finds anything material, write a repair plan before
  editing code, add regression and performance tests where applicable,
  implement every fix, rerun the complete P3-02 verification, and repeat the
  deep code review until no material finding remains.

### [ ] P3-03 — Make description task lists interactive

Outcome:

- A permitted user can tap an incomplete or complete task marker in an issue
  or MR description and update only that exact task in the source Markdown.
- Inapplicable `[~]` tasks remain accurately rendered and read-only until a
  documented interaction is deliberately designed.

Todo:

- [ ] Inspect the current Markdown intent parser, task-marker normalization,
  immutable render tree, render cache identity, list UI, description editing,
  resource refresh, and performance fixtures.
- [ ] Before writing production code, create
  `docs/P3_03_ENGINEERING_PLAN.md`. Document source-range identity, supported
  task syntax, nested and duplicate-task behavior, mutation flow, stale-source
  protection, optimistic UI and rollback, render-cache invalidation,
  performance budgets, accessibility, tests, and non-goals.
- [ ] Create fixtures for simple, nested, quoted, repeated, Unicode, mixed
  line-ending, indented, malformed, very long, and large task-list Markdown.
- [ ] Write failing parser tests proving each interactive task maps to a stable
  location in the original source and toggling one task preserves every other
  byte, including whitespace, indentation, casing, line endings, and unrelated
  Markdown.
- [ ] Write failing model tests for complete-to-incomplete and
  incomplete-to-complete changes, rapid taps, duplicate labels, stale
  descriptions, save failure rollback, ambiguous delivery, refresh during a
  toggle, read-only credentials, and account switching.
- [ ] Extend the Markdown representation with the minimum stable source
  identity needed for task interaction. Keep parsing and source rewriting away
  from the main actor and preserve the existing immutable render output.
- [ ] Route task updates through the P3-02 description mutation path rather
  than creating a second resource-update implementation.
- [ ] Revalidate the latest description before mutation. If source identity no
  longer matches, cancel the toggle, refresh, and explain that the description
  changed.
- [ ] Make task controls accessible buttons with accurate checked state,
  disabled/read-only explanations, sufficient hit targets, and no loss of the
  existing list reading order.
- [ ] Measure parse, source-index, rewrite, first-render, and scrolling
  performance with large task fixtures. Keep memory bounded and ensure toggling
  one item does not synchronously reparse a large document on the main actor.
- [ ] Verify issue and MR task lists, nested and repeated tasks, stale
  conflicts, rollback, long content, fast scrolling, read-only access, Dynamic
  Type, VoiceOver, and Reduce Motion in the iPhone 17 Pro Simulator.
- [ ] Run focused correctness and performance tests, the complete test suite,
  a Release Simulator build, Xcode static analysis, and credential/privacy
  scans.
- [ ] Perform a deep code review of all code added or changed for P3-03. Look
  for bugs, bad code, duplicated description mutation paths, wrong task
  offsets, Unicode or line-ending corruption, stale writes, unstable render
  identity, main-actor work, unbounded caches, accessibility mistakes,
  concurrency or cancellation races, and code that needs refactoring. Record
  every finding in `docs/P3_03_ENGINEERING_PLAN.md`.
- [ ] If the P3-03 review finds anything material, write a repair plan before
  editing code, add regression and performance tests where applicable,
  implement every fix, rerun the complete P3-03 verification, and repeat the
  deep code review until no material finding remains.

### [ ] P3-04 — Resolve and reopen merge-request discussions

Outcome:

- Eligible users can resolve or reopen resolvable MR discussions from the
  discussion list and inline diff threads.
- Issue discussions remain read-only for resolution because the current
  official REST Discussions API documents resolution for merge requests only.

Todo:

- [ ] Inspect the existing discussion resource model, decoded `resolvable`,
  `resolved`, `resolved_by`, and `resolved_at` fields, discussion pagination,
  activity partitioning, inline diff index, mutation service, cache
  invalidation, and optimistic reaction behavior.
- [ ] Before writing production code, create
  `docs/P3_04_ENGINEERING_PLAN.md`. Document the MR discussion resolution
  endpoint, eligibility and permission behavior, optimistic state,
  coalescing, rollback, authoritative reconciliation, cache invalidation,
  inline-thread updates, tests, accessibility, and non-goals.
- [ ] Write failing endpoint tests for resolve and reopen bodies, path
  encoding, write-access enforcement, updated discussion decoding, permission
  denial, not found, validation, cancellation, and ambiguous delivery.
- [ ] Write failing model tests for resolvable and non-resolvable threads,
  already-resolved threads, rapid repeated taps, resolve followed by reopen,
  failed rollback, returned resolver metadata, pagination, stale responses,
  and account switching.
- [ ] Extend the existing discussion mutator with one MR-only resolution
  operation and reconcile the returned discussion into the current collection.
  Do not create a second discussion store.
- [ ] Show resolved state and resolver metadata consistently in ordinary and
  inline threads while preserving the current compact discussion and activity
  presentation.
- [ ] Coalesce an in-flight action per discussion, disable unavailable actions,
  and present an honest state when the user's role cannot resolve the thread.
- [ ] Invalidate only the affected MR discussion cache and refresh the MR
  readiness discussion check after an authoritative change.
- [ ] Verify resolve/reopen in ordinary and inline threads, rollback,
  read-only access, insufficient role, outdated diffs, pagination, Dynamic
  Type, VoiceOver, Reduce Motion, and dark/light appearance in the iPhone 17
  Pro Simulator.
- [ ] Run focused discussion mutation tests, the complete test suite, a
  Release Simulator build, Xcode static analysis, and credential/privacy
  scans.
- [ ] Perform a deep code review of all code added or changed for P3-04. Look
  for bugs, bad code, duplicated discussion state, incorrect permission
  assumptions, wrong discussion identity, stale readiness state, optimistic
  rollback errors, cache over-invalidation, account leakage, concurrency or
  cancellation races, and code that needs refactoring. Record every finding in
  `docs/P3_04_ENGINEERING_PLAN.md`.
- [ ] If the P3-04 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-04 verification, and repeat the deep code review until no material finding
  remains.

### [ ] P3-05 — Create new issues

Outcome:

- A user can select a project in the active account, compose an issue, and
  navigate directly to the authoritative issue returned by GitLab.
- The initial form supports a required title, Markdown description, existing
  labels, assignees allowed by the instance tier, confidentiality, and an
  optional due date.

Todo:

- [ ] Inspect project search and routing, project identity, issue models,
  account-scoped drafts, Markdown preview, project labels, project members,
  mutation delivery certainty, and native issue-detail navigation.
- [ ] Before writing production code, create
  `docs/P3_05_ENGINEERING_PLAN.md`. Document project selection, create-issue
  endpoint and tier differences, form state, validation, draft identity,
  project metadata loading, ambiguous delivery, successful routing, cache
  updates, rate limits, tests, accessibility, and non-goals.
- [ ] Write failing endpoint tests for minimal and complete issue bodies,
  Unicode and Markdown, labels, Free versus paid assignee shapes,
  confidentiality, due date, validation errors, permissions, rate limiting,
  cancellation, and ambiguous delivery.
- [ ] Write failing form-model tests for project changes, required title,
  metadata loading and pagination, draft restoration and isolation, failed
  submission, duplicate-tap prevention, uncertain submission, authoritative
  success, and account switching.
- [ ] Add project-scoped label and member loaders using documented paginated
  endpoints, cache them by account and project, and cancel or reject results
  when the selected project changes.
- [ ] Build a native creation flow available from a clear Home action, with
  project search, Markdown editing and preview, validation, saved draft, and
  accurate read-only or permission messaging.
- [ ] Never automatically retry issue creation. On an uncertain result,
  preserve the form and help the user refresh or search before attempting a
  duplicate submission.
- [ ] Route a confirmed result to its native issue detail, invalidate affected
  issue/project caches, and clear the draft only after authoritative success.
- [ ] Verify minimal and complete creation forms with deterministic stubs,
  project switching, long Markdown, draft recovery, failures, uncertain
  delivery, read-only access, keyboard behavior, Dynamic Type, VoiceOver, and
  dark/light appearance in the iPhone 17 Pro Simulator.
- [ ] Run focused creation, metadata, draft, and routing tests, the complete
  test suite, a Release Simulator build, Xcode static analysis, and
  credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-05. Look
  for bugs, bad code, duplicated editor or project-picker logic, invalid tier
  assumptions, duplicate creation, lost drafts, stale project metadata,
  incorrect cache updates, account leakage, concurrency or cancellation races,
  and code that needs refactoring. Record every finding in
  `docs/P3_05_ENGINEERING_PLAN.md`.
- [ ] If the P3-05 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-05 verification, and repeat the deep code review until no material finding
  remains.

### [ ] P3-06 — Edit labels, assignees, reviewers, and open/closed state

Outcome:

- A permitted user can add or remove issue and MR labels, change assignees,
  change MR reviewers, and close or reopen an issue or MR.
- Glab distinguishes assigning an existing label, explicitly creating a new
  project label through GitLab's update behavior, assigning a reviewer, and
  configuring an approval rule.

Todo:

- [ ] Inspect issue/MR detail metadata, project label and member APIs, list and
  Home caches, review-request queries, current user display, account switching,
  and P3-02 update services.
- [ ] Before writing production code, create
  `docs/P3_06_ENGINEERING_PLAN.md`. Document each issue and MR update field,
  full-replacement versus additive semantics, project metadata pagination,
  Free versus paid assignee behavior, reviewer semantics, explicit new-label
  confirmation, close/reopen confirmation, reconciliation, tests,
  accessibility, and non-goals.
- [ ] Write failing endpoint tests for `add_labels`, `remove_labels`, complete
  label replacement where required, `assignee_ids`, `reviewer_ids`, and
  `state_event`, including empty arrays, special characters, permission
  denial, validation, cancellation, and ambiguous delivery.
- [ ] Write failing model tests for metadata pagination and search, rapid
  selection changes, additive label changes, explicit label creation,
  preserving server members during replacement, unassigning everyone,
  close/reopen transitions, stale responses, rollback, and account switching.
- [ ] Reuse the project-scoped label and member loaders introduced for issue
  creation. Do not load an unbounded instance-wide user list.
- [ ] Refetch replacement-based metadata before submission when necessary so a
  stale local array does not silently remove a newer assignee or reviewer.
- [ ] Require an explicit Create Label action when typed text does not match an
  existing label. Never turn an accidental typo into a new project label
  without confirmation.
- [ ] Build compact native metadata editors for issues and MRs, sharing
  presentation components only where their semantics are genuinely the same.
- [ ] Keep reviewers and approval-rule approvers visibly distinct in wording
  and accessibility labels.
- [ ] Reconcile the returned resource into detail, list, Home, search, Todo,
  and review-request owners through bounded invalidation or refresh rather than
  mutating unrelated cached JSON.
- [ ] Verify issue and MR labels, explicit label creation, single/multiple
  assignees as supported, reviewer changes, close/reopen, read-only access,
  insufficient permissions, stale metadata, Dynamic Type, VoiceOver, and
  dark/light appearance in the iPhone 17 Pro Simulator.
- [ ] Run focused metadata and state tests, the complete test suite, a Release
  Simulator build, Xcode static analysis, and credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-06. Look
  for bugs, bad code, duplicated issue/MR mutation paths, accidental label
  creation, lost assignees or reviewers, reviewer/approver confusion, stale
  list state, permission mistakes, cache over-invalidation, account leakage,
  concurrency or cancellation races, and code that needs refactoring. Record
  every finding in `docs/P3_06_ENGINEERING_PLAN.md`.
- [ ] If the P3-06 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-06 verification, and repeat the deep code review until no material finding
  remains.

### [ ] P3-07 — Support GitLab work-item status for issues

Outcome:

- On compatible Premium or Ultimate instances, an eligible user can see the
  issue's current work-item status and choose from its allowed lifecycle
  statuses.
- Free, older, disabled, or GraphQL-incompatible instances retain ordinary
  open/closed issue state without a broken or misleading status control.

Todo:

- [ ] Inspect the existing GraphQL client and error envelope, issue REST
  identity, host/version behavior, issue state presentation, account
  isolation, and P3-06 state mutation controls.
- [ ] Before writing production code, create
  `docs/P3_07_ENGINEERING_PLAN.md`. Reconfirm the current official GraphQL
  schema and document work-item identity, status and allowed-status queries,
  update mutation, lifecycle categories, tier/version detection, permission
  behavior, open/closed interaction, fallback states, tests, and non-goals.
- [ ] Write failing GraphQL construction and decoding tests for current status,
  allowed statuses, pagination, update success, partial data with errors,
  missing fields, unsupported schema, insufficient tier, permission denial,
  validation, cancellation, and ambiguous delivery.
- [ ] Write failing model tests for unavailable and supported instances,
  status ordering, selecting the current status, rapid changes, a status whose
  category closes the issue, rollback, authoritative reconciliation, stale
  responses, and account switching.
- [ ] Capability-detect the documented API surface. Do not infer support solely
  from a hard-coded GitLab version or assume a licensed feature exists because
  the host is GitLab.com.
- [ ] Keep work-item status separate from the universal REST open/closed state
  in domain and UI terminology.
- [ ] Present only server-allowed statuses. Confirm when a selected status
  category will close the issue and reconcile both status and issue state from
  the mutation result.
- [ ] Treat unsupported fields or tiers as feature unavailability, not an issue
  detail failure, and retain the P3-06 open/reopen control where permitted.
- [ ] Verify supported, unsupported, unlicensed, partial GraphQL, permission
  denied, closing and reopening categories, read-only access, Dynamic Type,
  VoiceOver, and dark/light appearance in the iPhone 17 Pro Simulator.
- [ ] Run focused GraphQL/status tests, the complete test suite, a Release
  Simulator build, Xcode static analysis, and credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-07. Look
  for bugs, bad code, duplicated state controls, brittle schema or version
  assumptions, tier leakage, wrong work-item identity, state/status
  divergence, partial GraphQL mistakes, stale-account writes, concurrency or
  cancellation races, and code that needs refactoring. Record every finding in
  `docs/P3_07_ENGINEERING_PLAN.md`.
- [ ] If the P3-07 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-07 verification, and repeat the deep code review until no material finding
  remains.

### [ ] P3-08 — Show and manage merge-request approvals

Outcome:

- A user can see who approved an MR, approval rules and their progress when the
  instance exposes them, and eligible approvers still pending for each rule.
- An eligible user can approve or unapprove the current MR revision.
- A sufficiently privileged user can deliberately add an approver to a
  selected editable MR approval rule when its full membership can be preserved
  safely.

Todo:

- [ ] Inspect the existing approval summary loader and readiness derivation,
  decoded `approved_by` users, MR reviewers, current-user identity, head SHA,
  GraphQL usage, detail refresh, and mutation delivery certainty.
- [ ] Before writing production code, create
  `docs/P3_08_ENGINEERING_PLAN.md`. Document `/approvals`,
  `/approval_state`, approve/unapprove, MR-level approval-rule read/create/
  update contracts, Free versus Premium/Ultimate behavior, rule membership
  replacement risks, hidden and system-generated rules, SHA safety,
  permissions, reconciliation, tests, accessibility, and non-goals.
- [ ] Write failing decoding and presentation tests for approving users,
  approval timestamps, zero and multiple rules, overlapping eligible users,
  satisfied and pending rules, hidden groups, unavailable rule details,
  partial responses, and Community Edition semantics.
- [ ] Write failing endpoint and model tests for approve with the current head
  SHA, stale-SHA conflict, unapprove, rapid taps, approval resets, permission
  denial, read-only access, cancellation, ambiguous delivery, and
  authoritative reconciliation.
- [ ] Write failing tests for adding an approver to an existing editable
  regular rule and, if deliberately included by the engineering plan, creating
  a new MR-level regular rule. Prove all visible existing users/groups and the
  required count are preserved in replacement payloads.
- [ ] Reuse the existing approval loader for the basic approving-user list and
  readiness summary. Add detailed rule loading as an independently failing,
  tier-gated enhancement.
- [ ] Present Approved, Pending, and Eligible states per rule without implying
  every eligible user must approve when a rule requires fewer approvals.
- [ ] Submit the MR head SHA when approving and reject stale responses after a
  new commit or account switch.
- [ ] Treat reviewer assignment as P3-06 and approval-rule membership as
  P3-08. Label both concepts accurately.
- [ ] Never edit code-owner or report-approver rules. Disable unsafe rule
  editing when hidden membership cannot be preserved, and explain the reason.
- [ ] Refresh approval details and readiness after mutations while preserving
  the rest of the MR detail if approval APIs fail.
- [ ] Verify basic and detailed approvals, approve/unapprove, stale SHA,
  editable and locked rules, hidden members, reviewers versus approvers,
  read-only and insufficient permissions, Dynamic Type, VoiceOver, and
  dark/light appearance in the iPhone 17 Pro Simulator.
- [ ] Run focused approval tests, the complete test suite, a Release Simulator
  build, Xcode static analysis, and credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-08. Look
  for bugs, bad code, duplicated approval/readiness state, incorrect rule
  math, reviewer/approver confusion, omitted rule members, unsafe hidden-group
  updates, stale-SHA approvals, optimistic rollback errors, tier/permission
  mistakes, concurrency or cancellation races, and code that needs
  refactoring. Record every finding in `docs/P3_08_ENGINEERING_PLAN.md`.
- [ ] If the P3-08 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-08 verification, and repeat the deep code review until no material finding
  remains.

### [ ] P3-09 — Browse merge-request pipelines and jobs

Outcome:

- An MR has a native paginated pipeline history.
- Opening a pipeline shows authoritative pipeline metadata and a
  stage-oriented, paginated list of jobs with accurate status and timing.

Todo:

- [ ] Inspect the MR readiness pipeline summary, existing pagination and cache
  models, detail navigation, status formatting, account switching, and current
  project/MR route identity.
- [ ] Before writing production code, create
  `docs/P3_09_ENGINEERING_PLAN.md`. Document MR pipeline-list, pipeline-detail,
  pipeline-jobs, retried-job, bridge/child-pipeline, pagination, polling, cache,
  navigation, state ownership, performance, tests, accessibility, and
  non-goals.
- [ ] Define immutable pipeline, detailed-status, user, job, stage, runner, and
  artifact-summary models that tolerate documented optional fields and unknown
  future status values.
- [ ] Write failing endpoint and decoding tests for MR pipeline pagination,
  pipeline detail, job pagination, retried jobs, empty pipelines, child or
  bridge information selected by the plan, unknown statuses, missing optional
  data, malformed responses, and untrusted next-page URLs.
- [ ] Write failing model tests for first/next-page loading, deduplication,
  refresh, retained content on failure, running-to-terminal transitions,
  visible-only polling, cancellation on navigation, stale responses, and
  account switching.
- [ ] Add an independently owned MR pipeline history model and pipeline detail
  model with injected services. Do not make the MR detail model own job pages
  or polling tasks.
- [ ] Open pipeline history from the MR readiness pipeline row or another
  compact native control without blocking the existing MR detail if pipeline
  APIs fail.
- [ ] Group jobs by server stage while preserving deterministic server order,
  status, duration, allowed failure, retry lineage, and manual state.
- [ ] Poll only visible running content with a documented bounded interval and
  cancellation. Cache completed pipelines longer than active pipelines and
  isolate cache keys by account, project, pipeline, query, and page.
- [ ] Verify empty, single, long, paginated, running, failed, manual, canceled,
  retried, partial-error, offline-cache, and account-switch states with
  deterministic fixtures and in the iPhone 17 Pro Simulator.
- [ ] Run focused pipeline/job tests, pagination and cache tests, the complete
  test suite, a Release Simulator build, Xcode static analysis, and
  credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-09. Look
  for bugs, bad code, duplicated pagination or status mapping, lost or repeated
  jobs, unbounded polling, stale-account results, cache-key collisions,
  over-fetching, main-actor decoding, navigation ownership mistakes,
  concurrency or cancellation races, and code that needs refactoring. Record
  every finding in `docs/P3_09_ENGINEERING_PLAN.md`.
- [ ] If the P3-09 review finds anything material, write a repair plan before
  editing code, add regression and performance tests where applicable,
  implement every fix, rerun the complete P3-09 verification, and repeat the
  deep code review until no material finding remains.

### [ ] P3-10 — Build a performant pipeline job-log viewer

Outcome:

- A user can open a job trace, scroll and search large logs responsively, jump
  to useful failure output, and manually refresh a running job.
- Raw trace bytes, parsed line indexes, and cached logs remain bounded,
  account-scoped, and off the main actor.

Todo:

- [ ] Inspect the JSON-oriented API client, raw HTTP transport, file response
  cache, diff parser and collection view, Markdown performance work,
  cancellation behavior, and Simulator performance fixtures.
- [ ] Before writing production code, create
  `docs/P3_10_ENGINEERING_PLAN.md`. Document the raw trace endpoint and content
  type, transport boundary, temporary and persistent storage, cache identity
  and limits, encoding and ANSI/control-sequence handling, line indexing,
  rendering approach, search, refresh behavior, performance budgets,
  security/privacy, tests, accessibility, and non-goals.
- [ ] Do not assume undocumented byte-range, streaming, or incremental trace
  guarantees. Measure documented full-response behavior and make running-log
  refresh explicit and bounded.
- [ ] Create small, medium, large, very-long-line, Unicode, invalid-UTF-8,
  CRLF, ANSI-colored, control-sequence, truncated, empty, erased, archived, and
  actively growing trace fixtures.
- [ ] Write failing transport, storage, parser, search, cancellation, cache,
  corruption, eviction, and account-isolation tests.
- [ ] Add the minimum authenticated raw-response path required for traces
  without weakening URL validation, authorization redaction, cancellation, or
  JSON request behavior.
- [ ] Download trace data away from the main actor into an account-scoped
  file-backed store, derive immutable line offsets incrementally, and avoid
  retaining duplicate full-log strings in memory.
- [ ] Strip or safely interpret ANSI and terminal control sequences without
  executing links, escapes, or commands from untrusted job output.
- [ ] Render only visible lines. Profile SwiftUI first, and use a focused UIKit
  collection view as the existing diff viewer does if measurement shows it is
  required; do not create a speculative general-purpose text framework.
- [ ] Add bounded text search, next/previous match, a useful first-failure jump,
  scroll-to-end, and explicit refresh for non-terminal jobs.
- [ ] Measure download-to-first-lines time, indexing time, search latency,
  memory, scrolling hitching, cancellation, repeated navigation, and cache
  eviction with every performance fixture.
- [ ] Verify representative logs, huge logs, long lines, invalid data, search,
  refresh, cancellation, memory pressure, Dynamic Type, VoiceOver, Reduce
  Motion, and dark/light appearance in the iPhone 17 Pro Simulator.
- [ ] Run focused correctness and performance tests, the complete test suite,
  a Release Simulator build, Xcode static analysis, and credential/privacy
  scans.
- [ ] Perform a deep code review of all code added or changed for P3-10. Look
  for bugs, bad code, duplicated transport or renderer logic, path traversal,
  credential or log leakage, unbounded memory/disk use, wrong line offsets,
  unsafe escape handling, main-actor file or parse work, stale-account data,
  cache corruption, concurrency or cancellation races, and code that needs
  refactoring. Record every finding in
  `docs/P3_10_ENGINEERING_PLAN.md`.
- [ ] If the P3-10 review finds anything material, write a repair plan before
  editing code, add regression and performance tests where applicable,
  implement every fix, rerun the complete P3-10 verification, and repeat the
  deep code review until no material finding remains.

### [ ] P3-11 — Retry, play, trigger, and cancel pipelines and jobs

Outcome:

- A permitted user can retry a failed/canceled pipeline or job, play a manual
  job, trigger a new MR pipeline, and cancel a running pipeline or job.
- Every action is status-aware, confirmed where appropriate, deduplicated,
  reconciled, and honest about uncertain delivery.

Todo:

- [ ] Inspect P3-09 pipeline/job state, P3-10 logs, current mutation certainty,
  API write-access gating, current user/session scope, polling, cache
  invalidation, and GitLab job/pipeline status values.
- [ ] Before writing production code, create
  `docs/P3_11_ENGINEERING_PLAN.md`. Document retry-pipeline, retry-job,
  play-job, create-MR-pipeline, cancel-pipeline, and cancel-job contracts,
  valid source statuses, input/variable compatibility, confirmations,
  deduplication, ambiguous delivery, polling handoff, reconciliation, tests,
  accessibility, and non-goals.
- [ ] Write failing endpoint tests for every action, path and body encoding,
  write-access enforcement, current and older self-managed response shapes,
  permissions, conflicts, validation, cancellation, and ambiguous delivery.
- [ ] Write failing model tests for allowed and unavailable actions by status,
  rapid duplicate taps, action replacement, confirmation cancellation,
  returned status changes, failed rollback, uncertain results, polling after
  success, stale responses, and account switching.
- [ ] Expose only actions valid for the current server status and credential
  capability. Let GitLab remain authoritative for role and protected
  environment permissions.
- [ ] Require confirmation for cancel, retry, and trigger actions. Explain that
  retrying or triggering can consume CI resources.
- [ ] Do not collect arbitrary secret variables in the initial implementation.
  If documented job inputs are supported, compatibility-gate them and ensure
  their values never enter logs, debug descriptions, screenshots, analytics,
  or persistent response caches.
- [ ] Coalesce one in-flight action per pipeline or job and never
  automatically retry a POST whose delivery is uncertain.
- [ ] Reconcile the returned pipeline or job, invalidate only affected
  pipeline/job/log caches, and resume bounded polling when the new status is
  non-terminal.
- [ ] Verify every visible and hidden action state, confirmations,
  read-only/permission denial, success, failure, uncertain delivery, rapid
  taps, running transitions, Dynamic Type, VoiceOver, and dark/light appearance
  in the iPhone 17 Pro Simulator.
- [ ] Run focused action and reconciliation tests, the complete test suite, a
  Release Simulator build, Xcode static analysis, and credential/privacy
  scans.
- [ ] Perform a deep code review of all code added or changed for P3-11. Look
  for bugs, bad code, duplicated action logic, invalid status transitions,
  missing confirmations, duplicate CI actions, accidental retries, secret
  input leakage, stale pipeline/job/log state, over-invalidation,
  concurrency or cancellation races, and code that needs refactoring. Record
  every finding in `docs/P3_11_ENGINEERING_PLAN.md`.
- [ ] If the P3-11 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-11 verification, and repeat the deep code review until no material finding
  remains.

### [ ] P3-12 — Merge or auto-merge a merge request safely

Outcome:

- A permitted user can merge a currently mergeable MR or request auto-merge
  when checks are pending.
- Glab always confirms the action, submits the current MR head SHA, and
  reconciles GitLab's authoritative result.

Todo:

- [ ] Inspect the MR readiness summary, approval and pipeline refresh,
  detailed merge status, head SHA lifecycle, existing detail actions,
  mutation certainty, cache invalidation, and native navigation after a state
  change.
- [ ] Before writing production code, create
  `docs/P3_12_ENGINEERING_PLAN.md`. Document the current merge API, SHA
  requirement, immediate versus auto-merge behavior, merge trains, squash and
  source-branch choices deliberately included or excluded, eligibility,
  confirmation, stale revisions, error mapping, reconciliation, tests,
  accessibility, and non-goals.
- [ ] Write failing endpoint tests for immediate merge and `auto_merge`,
  current SHA encoding, documented optional choices selected by the plan,
  permission denial, non-mergeable state, stale-SHA conflict, validation,
  cancellation, and ambiguous delivery.
- [ ] Write failing model tests for ready, blocked, pending, draft, closed,
  merged, conflict, unresolved-discussion, missing-readiness, stale-head,
  rapid-tap, uncertain-result, authoritative success, and account-switch
  states.
- [ ] Load or refresh the authoritative MR immediately before confirmation and
  submit its exact current head SHA. Never merge using a stale list or cached
  detail SHA.
- [ ] Present the checks that permit or block the action, distinguish Merge
  from Auto-merge, and require an explicit confirmation that names the MR and
  target branch.
- [ ] Do not expose merge when GitLab reports an unsupported or unsafe state.
  Still handle server rejection because permissions and mergeability can
  change after confirmation.
- [ ] Never automatically retry a merge request. For uncertain delivery,
  refresh the MR and show its authoritative merged/open state before offering
  another attempt.
- [ ] Reconcile the returned MR into detail, lists, Home, search, Todos,
  approvals, discussions, and pipeline/readiness state through bounded
  invalidation and refresh.
- [ ] Verify immediate and auto-merge, blocked reasons, stale SHA, permission
  denial, uncertain delivery, confirmation cancellation, state reconciliation,
  Dynamic Type, VoiceOver, Reduce Motion, and dark/light appearance in the
  iPhone 17 Pro Simulator.
- [ ] Run focused merge/readiness tests, the complete test suite, a Release
  Simulator build, Xcode static analysis, and credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-12. Look
  for bugs, bad code, duplicated readiness or mutation state, stale-SHA merges,
  incorrect auto-merge semantics, missing confirmation, accidental retries,
  wrong target branch, stale downstream caches, permission assumptions,
  concurrency or cancellation races, and code that needs refactoring. Record
  every finding in `docs/P3_12_ENGINEERING_PLAN.md`.
- [ ] If the P3-12 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-12 verification, and repeat the deep code review until no material finding
  remains.

## Phase 3 stretch checklist

Stretch work begins only after P3-01 through P3-12. These items do not block
the Phase 3 definition of done, but each still requires planning, tests,
Simulator verification, and the complete deep-review and repair gate.

### [ ] P3-S01 — Edit or delete the current user's comments

Todo:

- [ ] Inspect note ownership, issue and MR discussion-note endpoints,
  Markdown drafts, reactions, pagination, inline discussions, cache
  invalidation, and mutation certainty.
- [ ] Before writing production code, create
  `docs/P3_S01_ENGINEERING_PLAN.md` with API contracts, eligibility, edit and
  delete confirmations, draft/reconciliation behavior, tests, accessibility,
  and non-goals.
- [ ] Write endpoint and model tests for eligible/ineligible notes, edits,
  deletion, inline and ordinary threads, stale content, pagination, failure,
  cancellation, ambiguous delivery, and account switching.
- [ ] Implement the smallest edit/delete flow through the existing discussion
  service and reconcile the authoritative thread without rebuilding discussion
  state.
- [ ] Verify the complete UI and failure matrix in the iPhone 17 Pro Simulator,
  then run focused tests, the complete suite, Release build, static analysis,
  and credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-S01. Look
  for bugs, bad code, duplicated discussion mutation paths, incorrect author
  checks, deleted-thread corruption, lost drafts or reactions, stale cache
  state, concurrency or cancellation races, and code that needs refactoring.
  Record every finding in `docs/P3_S01_ENGINEERING_PLAN.md`.
- [ ] If the P3-S01 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-S01 verification, and repeat the deep code review until no material
  finding remains.

### [ ] P3-S02 — Browse pipeline test reports and download artifacts

Todo:

- [ ] Inspect pipeline/job models, raw downloads, cache/storage limits,
  authenticated redirects, file previews, Quick Look, and account removal.
- [ ] Before writing production code, create
  `docs/P3_S02_ENGINEERING_PLAN.md` with test-report and artifact API
  contracts, storage and eviction, file safety, supported previews,
  cancellation, tests, performance, accessibility, and non-goals.
- [ ] Write endpoint, decoding, raw-download, redirect-validation, path,
  eviction, cancellation, corruption, account-isolation, and performance tests.
- [ ] Add compact report summaries and explicit artifact downloads with bounded
  account-scoped storage and safe system previews.
- [ ] Verify representative reports and artifacts in the iPhone 17 Pro
  Simulator, then run focused tests, the complete suite, Release build, static
  analysis, and credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-S02. Look
  for bugs, bad code, duplicated download logic, unsafe redirects or paths,
  credential leakage, unbounded files, stale artifacts, preview security,
  concurrency or cancellation races, and code that needs refactoring. Record
  every finding in `docs/P3_S02_ENGINEERING_PLAN.md`.
- [ ] If the P3-S02 review finds anything material, write a repair plan before
  editing code, add regression and performance tests where applicable,
  implement every fix, rerun the complete P3-S02 verification, and repeat the
  deep code review until no material finding remains.

### [ ] P3-S03 — Add MR draft/ready and resource subscription controls

Todo:

- [ ] Reconfirm current official API contracts and inspect MR edit state,
  issue/MR subscription state, detail actions, cache invalidation, and
  mutation certainty.
- [ ] Before writing production code, create
  `docs/P3_S03_ENGINEERING_PLAN.md` with draft/ready, subscribe/unsubscribe,
  permissions, reconciliation, tests, accessibility, and non-goals.
- [ ] Write endpoint and model tests for every state, permission, failure,
  cancellation, ambiguous delivery, stale response, and account switch.
- [ ] Add compact, accurately labeled controls through the existing issue/MR
  mutation boundaries and reconcile authoritative responses.
- [ ] Verify the complete UI matrix in the iPhone 17 Pro Simulator, then run
  focused tests, the complete suite, Release build, static analysis, and
  credential/privacy scans.
- [ ] Perform a deep code review of all code added or changed for P3-S03. Look
  for bugs, bad code, duplicated resource state, incorrect draft or
  subscription semantics, stale controls, cache over-invalidation,
  concurrency or cancellation races, and code that needs refactoring. Record
  every finding in `docs/P3_S03_ENGINEERING_PLAN.md`.
- [ ] If the P3-S03 review finds anything material, write a repair plan before
  editing code, add regression tests, implement every fix, rerun the complete
  P3-S03 verification, and repeat the deep code review until no material
  finding remains.

## Deferred beyond Phase 3

These features are useful but are not part of the Phase 3 core or stretch
queue:

- Live Activities, push notifications, and background refresh.
- A combined cross-account inbox.
- Repository browsing, file editing, commit creation, and branch management.
- Creating merge requests.
- Offline mutation queues and automatic conflict resolution.
- Side-by-side iPhone diffs.
- A full custom-emoji browser.
- Administering project-wide approval policies or protected branches.
- Editing CI/CD configuration, pipeline schedules, trigger tokens, runners,
  protected environments, or project variables.

Every deferred feature requires its own written engineering plan before any
implementation, core-logic tests, Simulator verification, and the same
post-implementation deep code-review, repair-plan, fix, reverification, and
repeat-review cycle required by Phase 3.

## Official GitLab contracts

- [REST API and pagination](https://docs.gitlab.com/api/rest/)
- [OAuth 2.0 and PKCE](https://docs.gitlab.com/api/oauth2/)
- [Access token scopes](https://docs.gitlab.com/user/profile/personal_access_tokens/)
- [Issues API](https://docs.gitlab.com/api/issues/)
- [Merge requests API](https://docs.gitlab.com/api/merge_requests/)
- [Discussions API](https://docs.gitlab.com/api/discussions/)
- [Merge request approvals
  API](https://docs.gitlab.com/api/merge_request_approvals/)
- [Pipelines API](https://docs.gitlab.com/api/pipelines/)
- [Jobs API](https://docs.gitlab.com/api/jobs/)
- [Job artifacts API](https://docs.gitlab.com/api/job_artifacts/)
- [Project and group members API](https://docs.gitlab.com/api/group_members/)
- [Project labels API](https://docs.gitlab.com/api/labels/)
- [GitLab Flavored Markdown](https://docs.gitlab.com/user/markdown/)
- [Work-item status](https://docs.gitlab.com/user/work_items/status/)
- [GraphQL API](https://docs.gitlab.com/api/graphql/)
- [GraphQL API reference](https://docs.gitlab.com/api/graphql/reference/)
