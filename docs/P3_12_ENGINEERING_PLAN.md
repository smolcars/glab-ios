# P3-12 Engineering Plan — Safe Merge and Auto-Merge

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Implementation: not started
- Simulator verification: not started
- Deep review: not started

Research date: July 29, 2026.

This plan must be committed and pushed before any P3-12 production or test
code is changed.

## Outcome

A signed-in user with GitLab API write access can:

- merge an open merge request only when fresh, authoritative GitLab state says
  it is immediately mergeable; or
- request auto-merge when every locally verifiable hard requirement is
  satisfied and only an in-progress head pipeline is pending.

Every action is compact, explicitly confirmed, account-scoped, single-flight,
submitted once with the exact fresh source-branch HEAD SHA, and reconciled
against GitLab's authoritative result. GitLab remains authoritative for
permissions, project policies, merge trains, and mergeability.

## Existing-code audit

- `GitLabMergeRequest` already decodes state, draft state, source and target
  branches, `sha`, diff HEAD SHA, detailed merge status, conflicts, blocking
  discussion state, and head-pipeline state. It does not yet decode the
  current user's `can_merge` projection or the auto-merge flag returned as
  `merge_when_pipeline_succeeds`.
- `GitLabMergeRequestReadiness` already gives one projection of pipeline,
  approvals, conflicts, discussions, and draft state. It recognizes every
  currently documented `detailed_merge_status` value. P3-12 will consume this
  projection instead of duplicating those checks in the view.
- Mergeability is asynchronous. The single-MR loader uses a network read, and
  detail refresh can replace the rendered MR and approval summary. A safe
  action still needs a purpose-built preflight that refreshes both immediately
  before confirmation and captures the resulting HEAD SHA.
- Approval management already demonstrates the required patterns: fresh
  preflight, exact HEAD SHA comparison, account replacement checks,
  single-flight mutation state, no automatic retry, delivery certainty, and
  authoritative post-mutation reconciliation.
- `GitLabClient` retries only `GET`; a merge `PUT` is sent once.
  `GitLabMutationDeliveryCertainty` distinguishes explicit rejection from
  ambiguous delivery.
- `GitLabResourceEditResult.mergeRequest` already reconciles an authoritative
  MR into detail, assigned/review-requested lists, Home, global search, and
  Todos. A successful merge removes it from open-work projections.
- Approval, discussion, pipeline history/detail, MR detail, and list responses
  are cached independently. The merge service must invalidate exact
  MR-specific state plus the first affected open-work pages, without purging
  another project or account.
- The detail screen already has compact Liquid Glass toolbar actions and a
  collapsible readiness summary. The merge control belongs beside readiness,
  not in another large card or the top toolbar.

## Official GitLab contracts

Primary documentation:

- Merge requests API:
  <https://docs.gitlab.com/api/merge_requests/#merge-a-merge-request>
- Auto-merge:
  <https://docs.gitlab.com/user/project/merge_requests/auto_merge/>
- Merge trains:
  <https://docs.gitlab.com/ci/pipelines/merge_trains/>

Both actions use:

`PUT /projects/:id/merge_requests/:merge_request_iid/merge`

| Action | Body |
| --- | --- |
| Merge now | `sha: <fresh HEAD SHA>` |
| Auto-merge | `sha: <fresh HEAD SHA>, auto_merge: true` |

The app always sends `sha`, even on GitLab versions where it is optional.
GitLab 19.2 added an administrator setting that can require it. A mismatch
returns `409`, which is a stale revision rather than a retryable failure.

`merge_when_pipeline_succeeds` was deprecated as a request parameter in
GitLab 17.11. P3-12 never sends it. The response field with that older name
remains the documented indicator that auto-merge is set, so it is decoded only
for authoritative reconciliation.

Current documented merge failures include:

- `400`: required SHA missing;
- `401`: user cannot accept the merge request;
- `405`: merge request cannot merge;
- `409`: submitted SHA no longer matches source HEAD; and
- `422`: branch failed to merge.

The success response is a merge-request object. With `auto_merge: true`, an
instance using merge trains may enqueue the MR instead of merging directly.
GitLab 19.1 made this routing the merge API's standard behavior. The app does
not call the merge-trains API directly or promise an immediate merge.

## Deliberate scope decisions

### Included

- Exact fresh HEAD SHA on every request.
- Immediate merge only for an authoritative `mergeable` MR whose readiness
  checks are all satisfied or not required.
- Auto-merge only when the MR is open, not a draft, has a nonempty fresh HEAD
  SHA, has no reported conflict, approvals and discussions are satisfied or
  not required, and the head pipeline is in a recognized in-progress state.
- An explicit confirmation naming the MR, source branch, and target branch.
- Existing project merge method, squash setting, commit messages, and
  source-branch deletion preference remain server/project controlled.
- Display and authoritative reconciliation of an already requested
  auto-merge.

### Excluded

- Custom merge or squash commit messages.
- Overriding squash behavior.
- Overriding source-branch deletion.
- Bypassing approvals, unresolved discussions, conflicts, requested changes,
  security policies, status checks, Jira/title rules, locks, merge time,
  dependencies, or rebase requirements.
- Direct merge-train management or queue-position display.
- Canceling auto-merge.
- Merge-after scheduling.
- Optimistic state changes or automatic retry.

These exclusions keep P3-12 safe across GitLab.com and older self-managed
instances while leaving GitLab project policy authoritative.

## Eligibility

Add a pure `GitLabMergeRequestMergeEligibility` projection with one of:

- `mergeNow`;
- `autoMerge`;
- `alreadyAutoMerging`;
- `blocked(reasons:)`;
- `checking`;
- `unavailable`.

The projection consumes a fresh `GitLabMergeRequest`, fresh approval
availability, and `GitLabMergeRequestReadiness`.

### Merge now

Offer only when all are true:

- API access can write;
- account and route are current;
- `user.can_merge` is not explicitly `false`;
- state is open and draft is explicitly false;
- `detailed_merge_status == "mergeable"`;
- nonempty `diffHeadSHA` exists;
- readiness overall is `.ready`; and
- auto-merge is not already set.

### Auto-merge

Offer only when all are true:

- every common merge-now requirement above except immediate `mergeable`;
- readiness has no blocked, unknown, or unavailable hard check;
- approvals, conflicts, discussions, and review-state checks are satisfied or
  not required;
- the head pipeline is present and in `created`, `waiting_for_resource`,
  `preparing`, `pending`, `running`, `scheduled`, or `manual`;
- the pipeline readiness check is `.pending`; and
- detailed status is `ci_still_running` or another state that remains
  compatible with that exact pending-pipeline evidence.

`checking`, `unchecked`, and `approvals_syncing` do not expose an action: the
app refreshes rather than guessing. `ci_must_pass` without an in-progress head
pipeline remains blocked. All documented hard-block statuses remain blocked.

An omitted `user.can_merge` on an older self-managed response does not claim
permission; the app may offer the action when all safety state is known, but
the confirmation explains GitLab will recheck permission and policy.
An explicit `false` always hides the action.

## Architecture and state ownership

### Data and endpoints

- Extend `GitLabMergeRequest` with optional decoded `user.can_merge` and
  `merge_when_pipeline_succeeds`.
- Add a typed merge request body containing exact `sha` and optional
  `auto_merge`. `nil` omits `auto_merge` for immediate merge.
- Add endpoint tests before implementation for method, `.write`, path, body,
  current SHA, omitted optional choices, response decoding, and invalid
  request construction.

### Service

- Add a focused `GitLabMergeRequestMergeServing` protocol and live service.
- The service loads a fresh MR and approval summary for preflight, sends one
  merge request, validates the returned route, and performs bounded cache
  invalidation on success or delivery-unknown failure.
- Explicit rejection does not invalidate unrelated caches. A stale-SHA
  conflict invalidates the exact MR/readiness reads so the next load cannot
  reuse the rejected revision.
- Never log or expose request/response bodies, commit SHAs, tokens, or private
  URLs in descriptions or debug output.

### Model

- A dedicated `GitLabMergeRequestMergeModel` owns eligibility, confirmation,
  mutation phase, failure, and one pending-delivery snapshot. The detail model
  remains the source of rendered MR state.
- Requesting an action performs an authoritative preflight first. The model
  reconciles the returned MR and approval summary, derives eligibility, and
  only then presents confirmation.
- Confirmation captures action, route, MR title, source branch, target branch,
  and exact fresh HEAD SHA.
- Confirming verifies current account, route, rendered SHA, and current
  confirmation before dispatch. Rapid taps and conflicting actions are
  ignored.
- A mutation is sent once. Swift task cancellation after dispatch is
  delivery-unknown, not permission to send again.
- Confirmed responses reconcile immediately. Then load one fresh MR and
  approval summary to establish merged, open/auto-merging, or not-applied
  state.
- For ambiguous delivery, perform the same authoritative refresh before
  offering another attempt. If GitLab reports merged or auto-merge set, treat
  the operation as applied. If it reports the same open HEAD without
  auto-merge, report not applied. If the HEAD changed, report stale revision.
- Account replacement or route mismatch cancels publication and clears
  confirmation without mutating another account.

## Cache and screen reconciliation

On confirmed success, stale SHA, or delivery-unknown failure, invalidate only
the affected account's:

- exact single-MR response;
- approval summary and approval-state/detail responses for that MR;
- first MR pipeline-history page and loaded head-pipeline detail reads;
- first assigned and review-requested MR pages;
- Home dashboard response;
- current global MR-search reads; and
- current Todo reads that can target the MR.

The authoritative returned/refreshed MR is passed through
`GitLabResourceEditResult.mergeRequest`, which updates detail, loaded lists,
Home, search, and Todos immediately. Approval, discussion, pipeline, and
readiness models receive a bounded refresh; no global cache purge or duplicate
poller is added.

## UI and accessibility

- Add one compact icon-led Liquid Glass action next to the collapsed readiness
  summary. Use `arrow.triangle.merge` for immediate merge and a clock/merge
  treatment for auto-merge. Do not add a full-width button or another large
  card.
- Hide the control for read-only, unsafe, unsupported, merged, closed, draft,
  conflicted, or uncertain state. Existing readiness details explain blockers.
- While preflighting or reconciling, show a compact progress indicator in the
  same location.
- Confirmation title distinguishes “Merge” from “Set auto-merge.” Its message
  names the MR and `source → target`, and auto-merge copy explains GitLab may
  use a merge train.
- Success is reflected by authoritative state, not a transient success toast.
  Rejection, stale SHA, and uncertain delivery use concise actionable alerts.
- The control keeps a 44-point target, VoiceOver label/hint/value, Dynamic Type
  layout, stable accessibility identifier, Reduce Motion compatibility, and
  no overlap with diff or tab-bar pills.

## Tests

### Endpoint and service tests

- Immediate merge and `auto_merge` exact method, path, `.write`, body, SHA,
  and omitted optional choices.
- Current and older response shapes, including omitted `user` and auto-merge
  fields.
- Read-only rejection before transport.
- `401`, `403`, `405`, stale-SHA `409`, `422`, validation, connectivity,
  timeout, `5xx`, cancellation, malformed response, and contradictory route.
- Exactly one transport attempt for every merge `PUT`.
- Bounded invalidation after success, stale SHA, and delivery-unknown failure;
  no unrelated account/project invalidation.

### Model tests

- Ready, pipeline-pending, hard-blocked, draft, closed, merged, conflict,
  unresolved discussion, approval missing, readiness missing, checking,
  unknown status, explicit permission denial, and older permission omission.
- Already-auto-merging state and merge-train-compatible reconciliation.
- Fresh preflight before confirmation, exact SHA capture, stale rendered SHA,
  changed preflight SHA, and changed SHA after delivery.
- Confirmation accept/cancel, correct MR/target copy, rapid tap,
  single-flight, route mismatch, task cancellation, and account replacement.
- Explicit rejection, uncertain result, authoritative merged success,
  authoritative auto-merge success, and authoritative not-applied result.
- Detail/list/Home/search/Todo reconciliation and bounded approval,
  discussion, pipeline, and readiness refresh.

### Simulator and quality gates

Use deterministic iPhone 17 Pro fixtures:

- immediate merge, auto-merge, blocked, checking, stale, rejected, uncertain,
  merged, and already-auto-merging states;
- confirmation cancellation and duplicate taps;
- dark/light appearance, default and accessibility-extra-large text;
- VoiceOver labels/order, Increase Contrast, and Reduce Motion.

For each implementation slice, run only its focused unit tests. After P3-12 is
functionally complete, run the focused P3-12 suite, the complete test suite
once as required by the MVP checklist, one Release Simulator build, Xcode
static analysis, plist/privacy/credential scans, and targeted simulator UI
flows. Do not run the broad UI suite for each small change.

No live merge is required. The developer token must not be used to merge a
real MR merely to verify UI. If live verification is ever explicitly approved,
use only the authorized demo project, create an isolated test MR, verify its
HEAD immediately, do not notify or assign people, and never repeat an
uncertain merge action.

## Implementation order

1. Commit and push this plan and the first two P3-12 checklist items.
2. Add failing data, eligibility, endpoint, response-validation,
   delivery-certainty, and cache-invalidation tests.
3. Implement the data projection, endpoint, and merge service; run focused
   tests; commit and push.
4. Add failing merge-model state-machine and reconciliation tests.
5. Implement preflight, confirmation snapshots, one-shot mutation, stale-SHA
   handling, and authoritative reconciliation; run focused tests; commit and
   push.
6. Add the compact Liquid Glass control and confirmations. Build, launch,
   inspect, and tap deterministic states in the iPhone 17 Pro Simulator;
   repair UI defects; commit and push.
7. Run the proportional final gates once.
8. Deep-review every P3-12 production, test, fixture, and document change.
   Record every material finding below and write a repair plan before editing.
9. Implement review repairs with regressions, rerun affected verification, and
   repeat review until no material finding remains.
10. Complete the P3-12 and Phase 3 checklists, commit, and push.

## Deep-review record

Not started. Findings and any required repair plans will be recorded here
before review-driven production edits.
