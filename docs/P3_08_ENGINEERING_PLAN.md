# P3-08 Engineering Plan — Merge Request Approvals

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Models and endpoints: complete
- Live approval service: complete
- Approve/unapprove state machine: complete
- Rule-add state machine: complete
- Rule-add slice review: complete
- Detailed approval-state ownership: complete
- Compact approval UI and member picker: complete
- Test implementation: in progress
- Production implementation: complete
- Simulator verification: in progress
- Deep review: not started

Research date: July 29, 2026.

This is the required implementation plan for P3-08. It must be committed and
pushed before any P3-08 test or production code is changed.

## Outcome

A user can open a compact approval section on a merge request and see:

- everyone who has approved, including an approval time when GitLab provides
  one;
- detailed approval rules and progress when the instance and tier expose
  them;
- who has approved each rule and who is eligible to approve it;
- whether the current account has approved the current revision.

A write-enabled account can approve the exact merge-request revision currently
shown or remove only its own approval. A sufficiently privileged account can
deliberately add one active project member to one existing editable regular
merge-request rule when Glab can prove the replacement request preserves every
visible existing direct user, group, rule name, and required approval count.

The existing merge-request detail, discussion, diff, and readiness content
must remain available if detailed approval APIs are unsupported or fail.

## Scope decisions and non-goals

- P3-08 manages merge-request approvals only. It does not merge a merge
  request.
- The existing all-tier `GET .../approvals` response remains the sole source
  for the global approving-user list and the readiness approval check.
- Detailed rule state is an independent optional enhancement loaded from
  `GET .../approval_state`. Its failure cannot replace or fail the basic
  approval summary or merge-request detail.
- P3-08 can add one direct user to an existing regular MR-level rule. It does
  not create a rule, delete a rule, remove a user or group, rename a rule,
  change its required count, or edit project- or group-level rules.
- P3-08 never edits `code_owner`, `report_approver`, `any_approver`, or an
  unknown future rule type.
- P3-08 never calls `reset_approvals`. GitLab documents that mutation for bot
  users; ordinary human users receive `401`.
- Glab does not collect, transmit, or store `approval_password`. If a project
  requires reauthentication, the app explains that approval must be completed
  in GitLab and retains the native Open in GitLab action.
- Reviewers remain P3-06 review-request recipients. They are not relabeled,
  inferred, or mutated as approval-rule approvers.
- The feature uses the documented REST endpoints. Existing GraphQL support is
  limited to diff summaries and work-item statuses; P3-08 adds no GraphQL
  query or mutation.
- Routine verification uses deterministic services and the iPhone 17 Pro
  Simulator. It must not approve, unapprove, or alter rules on a live project.
  Configured GitLab credentials may be used only for nonmutating reads.
- P3-08 does not tag, assign, mention, or notify any human.

## Official GitLab sources

- [Merge request approvals API](https://docs.gitlab.com/api/merge_request_approvals/)
  defines the basic approval response, detailed approval state, approve and
  unapprove mutations, SHA conflict behavior, and MR-level rule contracts.
- [Merge request approvals](https://docs.gitlab.com/user/project/merge_requests/approvals/)
  defines Free versus Premium/Ultimate behavior, eligibility, required rules,
  and approval reset behavior.
- [Merge request approval rules](https://docs.gitlab.com/user/project/merge_requests/approvals/rules/)
  defines rule concepts and permissions.
- [Project members API](https://docs.gitlab.com/api/project_members/)
  defines the effective project-member search reused for the add-approver
  picker.
- [Merge requests API](https://docs.gitlab.com/api/merge_requests/) defines
  the authoritative merge-request detail and `detailed_merge_status` values.

GitLab's documentation is the source of truth. Tests use documented response
fixtures rather than assumptions from one GitLab installation.

## API contract

### Basic approval summary — all tiers

`GET /projects/:id/merge_requests/:merge_request_iid/approvals`

This endpoint is authenticated and available on Free, Premium, and Ultimate.
The existing loader already:

- uses read access;
- maps `403` and `404` to an unavailable capability without failing MR detail;
- cache-revalidates the response under `.mergeRequestReadiness`;
- exposes `approved`, `approvals_required`, `approvals_left`, and
  `approved_by`.

P3-08 adds optional `approved_at` decoding to each `approved_by` entry. A
missing timestamp or malformed optional user entry must not discard the
remaining summary.

Edition semantics must remain explicit:

- Enterprise Edition, including an unlicensed installation, reports
  `approved == true` when configured rules are satisfied. With no applicable
  rule it can be true with an empty `approved_by`.
- Community Edition reports `approved == true` only after at least one user
  approves.
- Therefore `approved` is not used to infer that the current user approved.
  Current-user state is determined only by user ID membership in
  `approved_by`.

### Detailed approval rules — Premium and Ultimate

`GET /projects/:id/merge_requests/:merge_request_iid/approval_state`

The response can include:

- `approval_rules_overwritten`;
- zero or more rules;
- rule identity, name, and `rule_type`;
- `eligible_approvers`;
- `approvals_required`;
- direct `users` and `groups`;
- `contains_hidden_groups`;
- rule-scoped `approved_by`;
- `source_rule`;
- `approved` and `overridden`.

Detailed state is modeled defensively. Fields needed only for presentation can
be absent without losing the entire response. Fields needed for mutation stay
optional in the decoded model so missing data cannot be confused with a
genuine empty list.

The detailed loader maps only `403` and `404` to `.unavailable`. Authentication,
server, decoding, rate-limit, connectivity, and cancellation errors remain
actionable errors. A Free or incompatible instance therefore keeps the basic
summary while omitting rule UI.

Rule-scoped `approved_by` contains only approvals matching that rule. It must
not replace the global `/approvals` list, which can include approvals that do
not satisfy a rule.

### Exact MR-level rule read

`GET /projects/:id/merge_requests/:merge_request_iid/approval_rules/:rule_id`

This uncached endpoint is mandatory immediately before any rule update and
when reconciling an uncertain rule update. A rule is editable only when this
fresh response proves:

- the positive rule ID matches the selected rule;
- the normalized type is exactly `regular`;
- the name is present and nonempty;
- `approvals_required` is present and nonnegative;
- the complete direct `users` and `groups` arrays are present;
- every direct member and group has a positive stable ID;
- `contains_hidden_groups` is explicitly `false`;
- the active account and MR route are unchanged.

`source_rule` and `overridden` are displayed when helpful but do not by
themselves make a regular MR-level rule unsafe to update. The confirmation
copy explains that adding a direct approver can override the rule for this
merge request only.

### Approve the current revision

`POST /projects/:id/merge_requests/:merge_request_iid/approve`

The JSON body contains the exact current `sha`. The authenticated user must be
eligible. GitLab returns `409` if the supplied SHA is stale.

Before sending:

1. Capture the nonempty head SHA from the merge request currently rendered.
2. Require write API access, an active account, an open MR, no mutation in
   flight, and no unresolved delivery.
3. Load an uncached authoritative MR.
4. Require matching route and the same nonempty head SHA.
5. Reject `checking` and `approvals_syncing` detailed merge statuses.
6. Load a fresh basic approval summary and adopt it before deciding whether
   the current user still needs to approve.
7. Recheck account identity and cancellation.
8. Send one approve request with the fresh SHA.

The official automation guidance also discusses waiting for a non-null diff
`patch_id_sha`. This app performs a deliberate human action on an already
rendered MR rather than create-and-immediately-approve automation. P3-08 does
not poll or sleep for patch IDs. It instead blocks GitLab's documented
approval-syncing states, submits the exact fresh SHA, and requires
authoritative post-mutation reconciliation.

### Remove the current user's approval

`POST /projects/:id/merge_requests/:merge_request_iid/unapprove`

GitLab's endpoint removes only the authenticated user's approval and does not
accept a SHA. Glab still performs the same fresh-MR, same-head, open-state,
sync-state, account, and fresh-summary checks before sending. This prevents a
tap on an old screen from silently acting on a newly pushed revision.

### Add one direct user to an existing rule

`PUT /projects/:id/merge_requests/:merge_request_iid/approval_rules/:rule_id`

GitLab documents replacement semantics: direct approvers and groups omitted
from `user_ids`, `group_ids`, or `usernames` are removed. The request must
therefore include:

- the exact fresh rule name;
- the exact fresh `approvals_required`;
- every unique fresh direct user ID plus the one selected member ID;
- every unique fresh group ID;
- `remove_hidden_groups: false`.

The app must never build this body from `/approval_state`, cached data, visible
eligible approvers, or the originally tapped row. It uses only the uncached
exact-rule response.

The response is accepted only if it retains the same identity, name, regular
type, required count, every prior direct user, every prior group, and the new
user. A fresh exact-rule read and detailed-state refresh remain authoritative.

### Project member picker

`GET /projects/:id/members/all?query=...&per_page=20`

P3-08 reuses the existing account-scoped, project-scoped, paginated effective
member response and `GitLabProjectMember`, including avatar URL. It shows only
active members and never searches the instance-wide user directory or changes
project membership.

Members already present as a direct user or already eligible through the
selected rule are not offered as an addition. GitLab remains authoritative
for the user's permission to modify the rule.

## Existing-code audit

### Existing basic approval state

- `GitLabMergeRequestApprovalSummary` and
  `GitLabMergeRequestApprovalAvailability` already model the basic all-tier
  response.
- `LiveGitLabMergeRequestLoader` already conforms to
  `GitLabMergeRequestApprovalLoading`, handles optional capability errors, and
  cache-revalidates basic approval state.
- `GitLabMergeRequestApprovalModel` is the existing generic resource detail
  model. It retains cached content when a refresh fails and exposes
  authentication failures.
- `GitLabMergeRequestReadiness` derives its compact approval check from that
  same model.

P3-08 keeps these owners. It does not create a second global approval summary
or a second readiness derivation.

### Merge-request identity and freshness

- `GitLabMergeRequestRoute` contains the numeric project ID and MR IID.
- `GitLabMergeRequest.diffHeadSHA` prefers `diff_refs.head_sha` and safely
  falls back to `sha`.
- `GitLabMergeRequest.detailedMergeStatus` exposes GitLab's current readiness
  state.
- `GitLabResourceDetailModel.reconcileAuthoritative` can replace the loaded MR
  without discarding the rest of the detail view.
- `GitLabAccountID` contains host and user ID. `SignedInShellView` is keyed by
  account ID, while explicit account-current checks protect late async work.

### Mutation and cache behavior

- `GitLabSessionClient` enforces request access before transport.
- Non-GET requests are not cache-coalesced or automatically retried.
- `GitLabMutationDeliveryCertainty` treats local access, authentication,
  permission, not-found, and validation failures as rejected; network, server,
  rate-limit, decoding, transport, cancellation, and unexpected HTTP failures
  are delivery-unknown.
- Existing edit features use uncached preflight reads, generation checks,
  authoritative reconciliation, and explicit Check GitLab states.
- Cache keys include the account and complete request URL. Targeted
  invalidation can remove MR detail, basic approval, detailed approval, and
  exact-rule entries without affecting another account.

### Reviewer boundary

- `GitLabMergeRequest.reviewers` is already displayed and edited through the
  merge-request update endpoint's `reviewer_ids`.
- Existing picker copy says reviewers are separate from approval-rule
  approvers.
- P3-08 must preserve this wording and never use reviewers as a substitute for
  `eligible_approvers`, rule `users`, or global `approved_by`.

### Member and avatar reuse

- `GitLabProjectMember` contains ID, name, username, active state, avatar URL,
  web URL, and access level.
- The shared member row already renders `GitLabUserAvatar` with a fallback.
- The approval picker can reuse that presentation and paging behavior rather
  than inventing another user or image loader.

## Architecture

### Data types

Add focused value types beside merge-request approval code:

- `GitLabMergeRequestApproval.approvedAt`;
- `GitLabMergeRequestApprovalDetails`;
- `GitLabMergeRequestApprovalRule`;
- `GitLabMergeRequestApprovalRuleGroup`;
- an optional source-rule identity;
- `GitLabMergeRequestApprovalDetailsAvailability`;
- a small rule presentation projection.

Rule model fields that gate mutation remain optional. Presentation projections
normalize and de-duplicate user IDs without changing the decoded source.

### Endpoint ownership

Extend `GitLabMergeRequestEndpoints` with:

- `approvalDetails`;
- `approvalRule`;
- `approve`;
- `unapprove`;
- `updateApprovalRule`.

Bodies are private, typed, `Encodable`, and deterministic. Endpoint tests
assert method, access requirement, path, and exact JSON content.

### Service ownership

Add one focused `GitLabMergeRequestApprovalServing` protocol and
`LiveGitLabMergeRequestApprovalService`. It owns:

- uncached MR and basic-summary reads used by mutation preflight;
- detailed-state loading with cache events and capability fallback;
- exact-rule reads;
- project-member pages;
- approve, unapprove, and update-rule writes;
- targeted cache invalidation.

The existing loader continues to own only the basic summary used by readiness.
Both share the same account-scoped `GitLabSessionClient`.

### Model ownership

Add one `@MainActor @Observable`
`GitLabMergeRequestApprovalManagementModel`. It owns:

- detailed-rule load state and refresh errors;
- operation phase and user-facing failure;
- a pending approve/unapprove confirmation;
- delivery-unknown intent;
- selected rule and paginated member-picker state;
- operation generations and cancellation;
- callbacks that reconcile the existing MR detail and basic approval model.

It does not copy the current MR or basic summary into another long-lived
authoritative store. The view supplies closures to the existing models.
Detailed rules remain model-owned because no other feature currently owns
them.

Only one approval or rule mutation can be in flight. Rapid taps are ignored
while busy or while delivery certainty is unresolved.

### UI ownership

Add a compact, collapsed-by-default approval section near readiness:

- the collapsed row shows a concise status, approving-user avatars, and an
  expand chevron;
- the expanded content shows the global Approved list, rule rows, and one
  compact approve/unapprove action;
- each rule shows the rule state (`Approved`, `Pending`, or `Not required`),
  progress, approved people, and eligible people;
- an editable regular rule exposes a compact add-person action;
- unavailable detailed rules do not create an error card when the basic
  summary is valid;
- an actionable refresh error uses an inline retry without replacing content.

Liquid Glass is used for compact interactive controls where the current design
system supports it. Static state labels are not unnecessarily rendered as
large glass buttons.

The add-approver picker uses avatars, names, and usernames. Confirmation
identifies the selected person and rule and states that all existing
membership and the required count are preserved.

## Presentation rules

### Global approval list

- De-duplicate valid approving users by user ID while preserving response
  order.
- Show `Approved` and the timestamp when present.
- Never derive global approval membership from a rule.
- If `approved_by` is empty, say `No approvals yet`, even when Enterprise
  Edition reports all zero-rule requirements satisfied.

### Per-rule state and math

- A positive `approvals_required` and authoritative `approved == true` is
  satisfied.
- Authoritative `approved == false` is pending even if an incomplete or
  inconsistent member list would suggest otherwise.
- If `approved` is absent, derive only when both a nonnegative required count
  and the rule-scoped approved list are available.
- Required count zero is `Not required`.
- Remaining count is clamped to zero and uses unique rule-scoped approving
  user IDs.
- People present in `approved_by` are labeled `Approved`.
- Other valid `eligible_approvers` are labeled `Eligible`, not individually
  `Pending`.
- `Pending` describes the rule requirement, because a rule can require fewer
  approvals than its eligible population.
- Duplicate people inside a rule are removed by ID. A person may legitimately
  appear in multiple rules; progress stays rule-scoped.
- An approving user absent from `eligible_approvers` remains visible as
  approved.
- Hidden groups produce a compact note and lock editing. They do not invent
  hidden people or alter visible progress.
- Missing fields show a conservative unavailable/unknown presentation and
  never unlock editing.

## Approval and unapproval state machine

### Definite path

1. Capture action, rendered route, rendered head SHA, and account ID.
2. Confirm the destructive or externally visible action.
3. Validate API access and current account.
4. Load the fresh MR and basic summary concurrently only where ordering does
   not weaken the head check.
5. Reconcile both existing models.
6. Require the same route, open state, same nonempty head SHA, and stable
   approval-sync state.
7. Re-evaluate whether the current user is already approved.
8. Send exactly one write.
9. Invalidate affected cached reads.
10. Load fresh MR, basic summary, and optional detailed state.
11. Require the same account and route before publishing.
12. Reconcile MR and summary. Approve succeeds only if the same head remains
    and the current user appears globally approved. Unapprove succeeds only if
    the same head remains and the current user is absent.

No optimistic approval is displayed. The operation is short, externally
visible, and reset-prone; authoritative state is simpler and safer.

### Rejected path

- Read-only access is rejected before transport.
- `403` is a permission or eligibility denial.
- `409` is stale revision; refresh and require another deliberate action.
- Other `400` or `422` validation failures are shown without automatic retry.
- An approve `401` can indicate project reauthentication requirements. The
  approval action offers Open in GitLab and does not by itself invalidate the
  account. A failing authenticated read remains the signal for session
  reauthentication.
- Cancellation before the write returns to idle. Cancellation reported by
  the write transport is delivery-unknown.

### Delivery-unknown path

No write is automatically retried. The pending intent stores only:

- account and route;
- action;
- expected head SHA;
- current user ID.

Check GitLab performs uncached MR and basic-summary reads:

- approve is confirmed if the same head remains and the current user is
  present;
- unapprove is confirmed if the same head remains and the current user is
  absent;
- the opposite result on the same head permits a new deliberate attempt;
- a changed head becomes stale and never retries the old intent;
- a failed check preserves the delivery-unknown state.

## Rule-add state machine

1. Select one displayed rule and load its exact uncached form.
2. Fail closed unless every editability invariant is proven.
3. Load/search active project members.
4. Exclude existing direct and already eligible users.
5. Select one person and present an explicit confirmation.
6. Reload the exact rule immediately before writing.
7. Revalidate rule identity, type, hidden membership, full arrays, account,
   and route.
8. Build a complete replacement payload from that second fresh rule only.
9. Send one update.
10. Validate the response preserves all prior membership and adds the selected
    user.
11. Invalidate exact-rule, detailed-state, basic-summary, and MR-detail cache
    entries.
12. Reload exact rule, detailed state, basic summary, and MR detail; reconcile
    existing owners.

On delivery unknown, Check GitLab reloads the exact rule. The operation is
confirmed only if the selected user is present and every baseline user, group,
name, and required count remains preserved. If the user is absent and the
baseline is intact, a fresh deliberate retry is allowed. Any other difference
is stale and requires reloading the rule before another change.

## Cache and refresh plan

- Basic `/approvals` and detailed `/approval_state` use
  `.mergeRequestReadiness`.
- Exact-rule preflight and delivery checks bypass cached reads.
- Project-member paging stays uncached, matching existing metadata pickers.
- After any approval mutation, invalidate:
  - exact merge-request detail;
  - basic `/approvals`;
  - detailed `/approval_state`.
- After a rule update, also invalidate the exact rule.
- Approval changes do not change reviewer assignment, discussion pages, diff
  pages, Todos, or work-list membership, so those caches are not broadly
  invalidated.
- A failed detailed refresh retains the last detailed content and exposes an
  inline retry.
- A failed basic refresh retains its existing cached summary and readiness
  presentation.

## Test plan

All new unit tests use Swift Testing. Async tests use deterministic protocols,
actors, continuations, and generation checks rather than sleeps.

### Decoding and presentation

Write failing tests before implementation for:

- global approving users and ISO-8601 `approved_at`;
- missing timestamps and partial basic responses;
- zero rules;
- one and multiple detailed rules;
- overlapping eligible users across rules;
- duplicate users within one rule;
- satisfied, pending, zero-required, and unknown rule states;
- authoritative rule state taking precedence over inconsistent counts;
- approved users outside the eligible list;
- hidden groups and missing hidden-group flags;
- omitted direct users or groups remaining distinguishable from empty arrays;
- unknown rule types;
- unavailable detailed state;
- partial detailed responses;
- Enterprise zero-rule and Community Edition approval semantics;
- reviewers remaining distinct from approvers.

### Endpoints and service

Write failing tests for:

- detailed-state and exact-rule GET paths and read access;
- approve POST body containing the exact SHA and write access;
- unapprove POST path, empty body, and write access;
- replacement rule JSON preserving all users, groups, name, and required count;
- `remove_hidden_groups == false`;
- member search query and pagination;
- detailed `403` and `404` capability fallback;
- actionable authentication, server, decoding, and connectivity errors;
- targeted invalidation after each mutation;
- no mutation retry in the client/service.

### Approval model

Write failing tests for:

- approve with the rendered and freshly verified head SHA;
- a fresh preflight head change causing no write;
- GitLab `409` stale-SHA rejection;
- blocking `checking` and `approvals_syncing`;
- authoritative approval reset after a new commit;
- unapproving only when the current user is approved;
- duplicate/rapid taps sending one write;
- read-only access sending no write;
- inactive account before and after the request;
- permission and eligibility denial;
- cancellation before write and delivery-unknown cancellation during write;
- ambiguous delivery and Check GitLab confirmation;
- ambiguous delivery and safe retry availability;
- failed reconciliation retaining a checkable state;
- current-user ID, route, and head validation;
- MR, basic summary, and detailed-state reconciliation;
- detailed failure preserving the MR and basic summary;
- approval reauthentication guidance without automatic account invalidation.

### Rule-add model

Write failing tests for:

- editable existing regular rule;
- code-owner, report-approver, any-approver, and unknown rules locked;
- hidden groups true or missing locked;
- missing users/groups/name/count locked;
- complete fresh replacement body;
- every existing user/group/count preserved;
- second fresh rule changing before confirmation causing no write;
- selected member already direct or eligible causing no write;
- rapid taps and cancellation;
- permission and read-only failure;
- authoritative response omitting a prior member being rejected;
- unknown delivery reconciled as applied, unapplied, or stale;
- member search paging and account/project generation isolation.

### UI and accessibility

Use deterministic UI fixtures in the iPhone 17 Pro Simulator for:

- Free/basic approval state;
- Premium detailed rules;
- approve and unapprove confirmations;
- pending, success, rejected, stale, and delivery-unknown states;
- editable, system, hidden, and partial rules;
- add-approver picker with avatars and fallback avatars;
- reviewer versus approver wording;
- dark and light appearance;
- default and accessibility Dynamic Type;
- VoiceOver labels, values, hints, ordering, and minimum hit targets;
- compact collapsed and expanded layouts;
- pull-to-refresh and inline retry;
- long names, rule names, and several rules.

## Implementation sequence

1. Commit and push this plan.
2. Add failing decoding, presentation, and endpoint tests.
3. Implement value types and endpoints; run focused tests; commit and push.
4. Add failing service tests.
5. Implement the live service and targeted invalidation; run focused tests;
   commit and push.
6. Add failing approval/unapproval state-machine tests.
7. Implement guarded actions and reconciliation; run focused tests; commit and
   push.
8. Add failing rule-edit and member-picker tests.
9. Implement fail-closed rule addition; run focused tests; commit and push.
10. Implement compact UI and accessibility; build and inspect/tap it in the
    iPhone 17 Pro Simulator; commit and push.
11. Run focused tests, the complete serialized suite, Debug and Release
    Simulator builds, static analysis, privacy validation, and credential
    scans.
12. Perform the required deep review. Record findings and a repair plan here
    before editing material issues, add regression tests, fix all findings,
    repeat verification and review, then close P3-08 in `MVP_PHASE_3.md`.

## Safety checklist

- [ ] No P3-08 production code before this plan is committed and pushed.
- [ ] No live approve, unapprove, rule update, or human notification.
- [ ] Every write requires `.canWrite` and the same active account.
- [ ] Approve always sends the exact fresh head SHA.
- [ ] No automatic write retry.
- [ ] Delivery-unknown state requires explicit reconciliation.
- [ ] No optimistic approval or rule membership.
- [ ] Only an exact fresh `regular` rule with explicitly visible membership is
  editable.
- [ ] Hidden, system-generated, incomplete, and unknown rules are locked.
- [ ] Replacement payload includes every fresh visible direct user and group.
- [ ] Reviewers and approvers remain separate in API and UI.
- [ ] Unsupported detailed rules never fail basic approvals or MR detail.
- [ ] Simulator only; reuse `.deriveddata/Glab`.
- [ ] Deep review and any repair plan are recorded before P3-08 is marked
  complete.

## Deep-review record

The final whole-feature review has not started. The completed rule-add
state-machine slice received an incremental review on July 29, 2026:

1. Finding: canceling the add-approver picker while an exact-rule or member
   request was in flight advanced the response generation but could leave
   `isLoadingRule` or `isLoadingMembers` stuck because the superseded task
   correctly refused to publish.
   - Repair plan: synchronously clear both loading flags when canceling,
     preserve the generation invalidation, and add a continuation-gated
     regression test proving the late response publishes no state.
   - Status: fixed and verified by
     `cancelsInFlightPickerLoading`.
2. Finding: a successful retry of member loading cleared the inline error
   value but retained the equivalent feature failure, so recovered UI could
   continue presenting an obsolete error.
   - Repair plan: clear only the matching member-options failure after a
     successful first or next page, and leave unrelated failures intact.
   - Status: fixed and covered by the focused rule-management suite.
3. Finding: approval confirmation and rule-add selection could be represented
   at the same time through direct model calls, creating unnecessary
   overlapping UI state.
   - Repair plan: make both flows mutually exclusive at their model entry
     points and provide a confirmation-only cancel operation that preserves
     the member picker.
   - Status: fixed and verified by
     `cancelsOnlyRuleConfirmation` plus the existing rapid-action tests.

The compact UI slice was inspected and tapped on the iPhone 17 Pro Simulator
in dark and light appearances at default and accessibility-extra-large Dynamic
Type. The collapsed summary, expanded premium rules, approval confirmation,
locked code-owner rule, member picker, fallback avatars, and member search all
remained reachable without overlap. The accessibility-size run required the UI
test to scroll to offscreen actions, as expected for content that reflows
vertically. The remaining deterministic state variants and final VoiceOver
audit are part of the in-progress simulator verification rather than treated
as complete.

The final review will inspect every P3-08 change for:

- duplicated basic approval/readiness state;
- incorrect Community versus Enterprise semantics;
- incorrect rule progress or user de-duplication;
- reviewer/approver confusion;
- omitted replacement members or groups;
- hidden-group or system-rule editing;
- stale-SHA approval;
- approval reset races;
- optimistic rollback errors;
- read-only, permission, tier, or reauthentication mistakes;
- automatic mutation retries;
- unresolved delivery ambiguity;
- cross-account, cancellation, and generation races;
- cache invalidation gaps;
- inaccessible or oversized UI;
- unnecessary abstraction or duplicated code.

Every material finding must be added below with a repair plan before its fix.
The final repeated review must find no remaining material issue.
