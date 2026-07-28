# P3-04 Engineering Plan — Merge Request Discussion Resolution

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Test implementation: complete
- Production implementation: complete
- Verification: pending
- Deep review: in progress — three material findings have committed repair plans

This plan must be committed and pushed before any P3-04 test or production
code is changed.

## Outcome

Eligible users can resolve and reopen resolvable merge-request discussions
from both the ordinary discussion list and inline diff discussion sheets.
Glab optimistically presents the requested state, reconciles the full
authoritative discussion returned by GitLab, and refreshes the merge-request
readiness discussion check.

Issue discussions remain read-only for resolution. GitLab's current public
REST Discussions API documents a whole-thread resolution endpoint for merge
requests, but not for issue discussions.

## Scope decisions and assumptions

- P3-04 changes only the resolved state of an existing merge-request
  discussion. It does not create, edit, delete, move, or bulk-resolve threads.
- The whole-thread endpoint is used. Glab does not resolve one note through
  the separate note-update endpoint.
- A discussion is actionable only when it is a thread rather than an
  `individual_note` and contains a note that GitLab marks `resolvable`.
- The authoritative state comes from the first resolvable note returned in the
  discussion. Glab does not infer resolvability from note type, diff position,
  author, or current merge status.
- Resolved discussions can be reopened. An unresolved discussion can be
  resolved. In-flight and delivery-unknown discussions cannot start another
  mutation until reconciled.
- Outdated and currently positioned diff discussions can be resolved because
  the documented endpoint identifies a thread independently of its diff
  position. A missing or malformed discussion identity remains nonmutating.
- App-level read-only API access disables the action before transport.
  Role-based eligibility remains server-authoritative because Glab does not
  have a reliable complete project-role and authorship capability response.
- A `403` is presented as insufficient permission and rolls back optimistic
  state. Glab does not claim that every OAuth or `api` token can resolve every
  visible thread.
- No automatic retry is allowed for a write. Delivery-unknown results require
  an explicit, uncached reconciliation read before the user can retry.

## Existing-code audit

### Discussion resource and decoding

- `GitLabDiscussion` already has a stable opaque string identity,
  `individualNote`, and the full note array.
- `GitLabDiscussionNote` already defensively decodes `resolvable`, `resolved`,
  `resolved_by`, and `resolved_at`, with computed `isResolvable` and
  `isResolved` values.
- The current UI displays a Resolved badge on each resolved note, but it does
  not expose a thread-level state, resolver metadata, or a mutation control.
- P3-04 should add a small derived thread-resolution projection. It must not
  duplicate or persist discussion data.

### Pagination and shared state

- `GitLabDiscussionsModel` is the existing
  `GitLabPaginatedResourceModel<GitLabDiscussion, String>`.
- It preserves cached first pages, loads later pages, suppresses duplicate
  discussion identities, retains locally reconciled tail items, and increments
  `contentRevision` whenever a discussion is reconciled.
- The model already reconciles a created discussion and a reply. P3-04 needs
  one authoritative-discussion reconciliation method that updates an existing
  identity but never invents a missing paginated item.
- The MR overview and changed-file navigation share this same model. The diff
  index is rebuilt from its discussions and `contentRevision`, so reconciling
  one full discussion will update ordinary, current-line, outdated, and
  unmapped presentations without a second discussion store.

### Existing discussion mutation service

- `GitLabDiscussionMutating` and `LiveGitLabDiscussionService` already own new
  discussion, diff discussion, and reply mutations.
- Successful mutations invalidate only the exact issue or MR discussion-list
  cache entry.
- Mutation errors already expose `GitLabMutationDeliveryCertainty`, and POST
  writes are not automatically retried.
- P3-04 will extend this service with the documented MR-only operation and the
  exact discussion read required to reconcile an uncertain write. It will not
  add a separate networking client or mutation store.

### Optimistic reaction behavior

- `GitLabEmojiReactionsModel` is the closest existing optimistic pattern. It
  overlays pending state on authoritative data, coalesces per identity,
  distinguishes definite rejection from delivery unknown, and requires
  refresh before another uncertain mutation.
- P3-04 should use the same principles, but resolution state is simpler:
  one Boolean desired state per discussion and a full discussion response.
- Reaction pending state is not reused directly; award identities and
  discussion identities have different reconciliation rules.

### Merge-request readiness

- `GitLabMergeRequest` already decodes `blocking_discussions_resolved`.
- `GitLabMergeRequestReadiness` derives its discussion check from that
  authoritative field.
- The detail model loads an exact MR response with the
  `.mergeRequestReadiness` cache policy and refreshes it with `.always`.
- After an authoritative discussion resolution change, P3-04 will reconcile
  the discussion immediately and then refresh the existing MR detail model.
  This refresh updates the readiness field and its exact cached response.
- A readiness refresh failure must not roll back a discussion change that
  GitLab already confirmed. The existing detail refresh error remains the
  recovery surface.

### Current ordinary and inline UI

- `GitLabDiscussionCard` is shared by the ordinary discussion section and
  expanded inline diff discussions.
- Diff sheets receive the same `GitLabDiscussion` values and mutation service,
  but currently only support new comments and replies.
- The resolution control and thread status belong in the shared card so
  ordinary and inline threads cannot diverge.
- Issue screens also use the shared card. They will pass no resolution
  interaction and therefore keep their current static resolved presentation.

## Official GitLab contracts

### Retrieve one merge-request discussion

GitLab's
[Discussions API](https://docs.gitlab.com/api/discussions/#retrieve-a-merge-request-discussion-item)
documents:

`GET /projects/:id/merge_requests/:merge_request_iid/discussions/:discussion_id`

The discussion ID is an opaque string. A successful response is the same
discussion object shape used by the list endpoint.

P3-04 uses this endpoint only to reconcile a delivery-unknown resolution
mutation. It is an uncached read and is never a substitute for normal
discussion pagination.

### Resolve or reopen a merge-request thread

The documented endpoint is:

`PUT /projects/:id/merge_requests/:merge_request_iid/discussions/:discussion_id`

The required `resolved` Boolean is `true` to resolve and `false` to reopen.
A successful request returns `200 OK` and the updated discussion object.

GitLab documents the prerequisite as Developer, Maintainer, or Owner, or the
author of the change being reviewed. Glab treats the response as the final
permission decision.

### Issue discussions

The issue thread-note update endpoint documents `body` editing but does not
document the whole-thread `resolved` operation available for merge requests.
P3-04 therefore sends no issue-resolution request.

### Locked discussions and readiness

GitLab documents that only project members can add, edit, or resolve comments
when an MR discussion is locked. The MR response's
`blocking_discussions_resolved` field is the authoritative readiness input;
Glab does not derive mergeability solely by counting loaded discussion pages.

## Endpoint and service design

### Request construction

Add two endpoint builders:

1. `mergeRequestDiscussion(at:discussionID:)`
   - `GET`
   - read access
   - exact route and opaque discussion path component
   - response `GitLabDiscussion`
2. `setMergeRequestDiscussionResolution(at:discussionID:resolved:)`
   - `PUT`
   - write access
   - the same exact path
   - JSON body `{ "resolved": true|false }`
   - response `GitLabDiscussion`

The existing request builder percent-encodes each path component while
excluding `/`, `?`, `#`, and `%`. Tests must prove that an unusual opaque
discussion ID cannot escape its path segment.

### Service behavior

Extend `GitLabDiscussionMutating` and `LiveGitLabDiscussionService` with:

- an exact MR discussion read for delivery reconciliation; and
- an MR-only `setResolution` operation returning the updated discussion.

The service must:

1. build the typed endpoint;
2. send exactly one non-retried `PUT`;
3. return the decoded full discussion;
4. invalidate the exact MR discussion-list cache after authoritative success;
5. also invalidate that exact cache when write delivery is unknown, because
   GitLab might have accepted the state; and
6. avoid invalidation after a definite rejection before or by GitLab.

No issue resolution method is added. The signature accepts a
`GitLabMergeRequestRoute`, making an issue request unrepresentable.

## Thread-resolution projection

Add a value-semantic projection derived from `GitLabDiscussion` containing:

- the discussion ID;
- whether the discussion is an actionable thread;
- the authoritative resolved Boolean;
- the authoritative resolver, if any; and
- the authoritative resolution date, if any.

Derivation rules:

1. Reject `individual_note` discussions.
2. Find the first note with `resolvable == true`.
3. Use that note's `resolved`, `resolved_by`, and `resolved_at`.
4. If no resolvable note exists, expose no mutation state.
5. Never infer resolution from a Resolved badge on a non-resolvable reply.

Tests must cover empty discussions, individual notes, ordinary threads, diff
threads, multiple replies, missing evolving fields, resolved metadata, and
malformed combinations.

## Resolution model and state machine

Add one `@MainActor @Observable` resolution model owned by an MR detail view.
The same instance is passed to the overview and all changed-file discussion
sheets.

The model is scoped by account and MR route and depends on:

- API access;
- the existing discussion mutator;
- an `isAccountCurrent` closure;
- a current-discussion lookup into the existing paginated model;
- an authoritative discussion reconciliation callback; and
- an async MR-readiness refresh callback.

It stores only transient operation state keyed by discussion ID. It does not
copy the paginated discussion collection.

### Start

1. Receive the currently displayed authoritative discussion.
2. Derive and validate its thread-resolution projection.
3. Reject read-only access, non-MR use, non-resolvable or individual
   discussions, malformed identity, inactive account, or another in-flight or
   uncertain action for the same ID before transport.
4. Record the baseline, desired opposite state, and a monotonically increasing
   generation for that discussion.
5. Present the desired state optimistically with an explicit pending label.
6. Send one typed resolution request.

Different discussion IDs may mutate independently. Repeated taps on the same
discussion are coalesced.

### Authoritative success

Before publishing a returned discussion:

1. confirm the account is still active;
2. confirm its ID exactly matches the target;
3. derive a valid resolvable projection; and
4. confirm its resolved state matches the requested state; and
5. compare the currently loaded target with the operation baseline.

If valid:

- if the currently loaded target changed during the request, perform the exact
  discussion GET and reconcile that newer response instead of overwriting it
  with the original mutation response;
- reconcile the returned discussion into the existing paginated model;
- clear only that discussion's transient operation;
- retain the returned `resolved_by` and `resolved_at` metadata;
- refresh the existing exact MR detail/readiness model; and
- do not roll back the discussion if the separate readiness refresh fails.

A missing paginated discussion is not inserted. The caller refreshes the
collection instead, preventing duplicate ordering or count changes.

### Definite rejection

For app-level read-only access, invalid input, `400`, `401`, `403`, `404`,
`409`, `422`, or another definitely rejected response:

- clear the optimistic state;
- retain the authoritative discussion;
- show an actionable redacted error;
- do not automatically retry; and
- do not alter readiness or unrelated discussions.

Authentication failures continue through the existing account failure path.

### Delivery unknown

For rate limiting, server errors, connectivity, cancellation after the service
call begins, invalid response, decoding, HTTP, or transport failures:

- retain the desired visual state only as explicitly unconfirmed;
- disable another action for that discussion;
- show `Check GitLab`;
- never automatically retry; and
- preserve all other discussion interactions.

`Check GitLab` performs the exact uncached discussion GET:

- If the authoritative state equals the desired state, reconcile it as
  success and refresh readiness.
- If it equals the baseline, roll back and expose an explicit retry.
- If the response identity or resolvability is invalid, keep the action
  uncertain.
- If the check fails, retain the uncertain state and allow another explicit
  check, but not another write.

Cancellation before entering the service is a definite local rejection.
Cancellation after the write begins is delivery unknown.

### Lifecycle, stale results, and account changes

- Each discussion operation has a generation. A late result from an older
  generation is ignored.
- `cancelAll()` invalidates generations when the MR detail disappears.
- A result cannot reconcile after `isAccountCurrent` becomes false.
- A successful first action must finish before resolve-then-reopen can begin.
- If pagination or another local reconciliation changes the target discussion
  during a request, the mutation response is not applied blindly. The exact
  discussion GET supplies the latest authoritative value.
- The account-scoped service may invalidate only its own response cache.

## Reconciliation and cache behavior

Add `reconcileAuthoritativeDiscussion(_:)` to `GitLabDiscussionsModel`:

- replace only a currently loaded matching discussion;
- preserve its position and total count;
- update reconciled tail storage when applicable;
- increment `contentRevision`; and
- return whether the target was present.

That revision updates:

- the overview conversation card;
- current-line diff markers and sheets;
- the all-diff-discussions sheet;
- outdated and unmapped discussion groups; and
- any expanded copy of the same discussion.

Cache rules:

- Invalidate only the exact MR discussion-list key after success or unknown
  delivery.
- Do not clear issue discussions, another MR, work lists, reactions, diff
  payloads, or unrelated accounts.
- Refresh the existing MR detail model after authoritative success so
  `blocking_discussions_resolved` and its exact readiness cache entry update.
- Do not invent readiness from the loaded discussion subset, because
  pagination may omit blocking threads.

## UI and accessibility plan

### Shared thread footer

Extend `GitLabDiscussionCard` with an optional MR resolution interaction.
Below the notes, present a compact thread footer that can contain:

- the existing Reply control;
- a Resolved status with resolver name and relative resolution time when
  GitLab provides them;
- a compact Liquid Glass `Resolve` or `Reopen` button;
- compact progress while mutating; and
- inline rejected, uncertain, check, and retry recovery states.

Use `ViewThatFits` or an adaptive stack so Reply and resolution controls stay
readable at accessibility Dynamic Type. Do not add another floating control or
large permanent card.

### State language

- Unresolved: `Resolve`
- Resolved: `Resolved by <name>` when known, otherwise `Resolved`
- Reopen action: `Reopen`
- Optimistic: `Resolving…` or `Reopening…`
- Unknown: `Resolution not confirmed` or `Reopen not confirmed`
- Permission denial: `GitLab did not allow this thread change`

Do not fabricate the current user as resolver before the server returns.

### Availability

- MR resolvable thread plus read-write API access: enabled.
- MR resolved thread plus read-write API access: Reopen enabled.
- Read-only account: disabled with an explanation.
- Non-resolvable, empty, individual, or issue discussion: no mutation control.
- Outdated diff thread: action remains available when otherwise eligible.
- One pending or uncertain discussion does not disable other discussion IDs.

### Accessibility

Controls must provide:

- at least a 44-by-44-point hit target;
- `Resolve thread` or `Reopen thread` labels;
- Resolved/Unresolved/Pending confirmation values;
- hints describing the GitLab change;
- progress and recovery announcements;
- stable identifiers containing only the opaque discussion ID; and
- no duplicate announcement of resolver metadata on every reply.

Reduce Motion uses immediate state changes. Resolution state must not rely on
color alone, and light/dark/Increase Contrast presentations must remain
legible.

## Tests first

### Endpoint, request, and decoding tests

Write failing tests for:

1. exact discussion GET method, read access, path, and empty body;
2. resolve and reopen PUT methods, write access, exact path, and Boolean JSON
   body;
3. discussion IDs containing reserved path characters;
4. full updated discussion decoding, including resolver and timestamp;
5. read-only access rejection before transport;
6. success plus `400`, `401`, `403`, `404`, `409`, `422`, `429`, `5xx`,
   connectivity, cancellation, invalid response, decoding, and transport
   failures;
7. no automatic retry for either resolution value; and
8. exact cache invalidation on success and unknown delivery only.

### Projection and paginated reconciliation tests

Write failing tests for:

1. unresolved and resolved ordinary discussions;
2. current, outdated, and unmapped diff discussions;
3. empty, individual, system-only, and non-resolvable discussions;
4. first resolvable note selection with multiple replies;
5. absent and present resolver metadata;
6. existing-item replacement without reordering or count change;
7. reconciled tail replacement; and
8. missing identities not being inserted.

### Resolution model tests

Write failing tests for:

1. resolve success and reopen success;
2. optimistic state and authoritative resolver metadata;
3. read-only, issue, individual, and non-resolvable rejection with zero
   transport;
4. already-resolved discussions offering reopen rather than a no-op;
5. rapid repeated taps coalescing to one mutation;
6. independent actions on two discussion IDs;
7. resolve followed by reopen after the first authoritative success;
8. definite failure rollback for all relevant error classes;
9. delivery unknown blocking retry until `Check GitLab`;
10. check proving success, check proving no change, malformed check response,
    and failed check;
11. returned wrong discussion ID, missing resolvability, and wrong resolved
    state;
12. pagination refresh and newer authoritative discussion winning over a stale
    result;
13. cancellation before and during transport, detail disappearance, late
    results, account switching, and the same discussion ID on another account;
14. exact collection reconciliation and content revision; and
15. readiness refresh only after authoritative success.

### Presentation tests

Write failing tests for:

- ordinary and inline cards sharing the same state;
- resolver name and time presentation;
- read-only and permission-denied wording;
- progress, unknown, check, and retry controls;
- stable accessibility labels, values, hints, and identifiers;
- Dynamic Type adaptation and minimum hit targets; and
- issue discussions exposing no resolution action.

## Verification matrix

### Automated

- Focused discussion endpoint, request-builder, service, model, pagination,
  diff-index, readiness, reaction-regression, composer-regression,
  accessibility-presentation, and performance tests.
- The complete normally signed serialized suite on the iOS 26.5 iPhone 17 Pro
  Simulator.
- Release Simulator build and Xcode static analysis.
- `git diff --check`, Info.plist/privacy validation, tracked-file review,
  Release-bundle credential scans, configured-secret scans, and new
  forced-operation/ad-hoc logging scans.

Reuse `/Volumes/hulk/dev/projects/glab/.deriveddata/Glab` for every build,
test, and analysis action.

### Simulator

Use only the iOS 26.5 iPhone 17 Pro Simulator. Do not install on or test a
physical device.

Verify and visually inspect:

- unresolved, resolved, and resolver-metadata ordinary threads;
- current, outdated, and unmapped inline diff threads;
- resolve, reopen, rapid taps, independent threads, rollback, unknown
  delivery, check, explicit retry, and readiness refresh;
- read-only access and simulated insufficient role;
- issue discussions remaining nonmutating;
- pagination and navigation between overview and diff sheets;
- regular and accessibility Dynamic Type;
- VoiceOver labels, values, hints, progress, and focus;
- light, dark, Increase Contrast, Reduce Motion, and Reduce Transparency; and
- long discussions and fast scrolling without duplicated state or visible
  hitching.

### Live mutation safety

`GITLAB_API_TOKEN` remains read-only and may be used only for broader live
read verification.

`DEVOPS_DEMO_TOKEN` may be used only after all deterministic tests pass and
only if read-only inspection proves a notification-safe disposable target:

1. Resolve the exact host, project, MR, discussion, authors, and participants
   without printing credentials or private discussion text.
2. Never change an existing human-authored discussion.
3. Never mention, assign, request review from, or otherwise notify a human.
4. Use only a bot-owned disposable MR and bot-authored disposable discussion.
5. Do not create a commit, push a branch, trigger/retry/cancel a pipeline, or
   alter MR metadata merely to manufacture a live target.
6. Exercise only resolve, reopen, and exact discussion reads.
7. Restore the initial resolution state after verification.
8. Abort live writes if every condition cannot be proven. Deterministic fakes
   and Simulator UI verification are sufficient in that case.
9. Never print, log, commit, screenshot, bundle, fixture, or expose a token in
   a process argument or pasteboard longer than the sign-in operation.

Pipeline failures elsewhere in the project do not block P3-04, but P3-04 must
not intentionally start or interact with a pipeline.

## Ordered implementation

1. Commit and push this plan.
2. Add failing endpoint, request, decoding, and exact invalidation tests.
3. Implement the minimum typed GET/PUT endpoints and service methods.
4. Add failing thread-projection and paginated reconciliation tests.
5. Implement the derived resolution projection and existing-model
   reconciliation.
6. Add failing resolution-model tests for optimistic state, errors,
   delivery certainty, checks, cancellation, accounts, pagination, and
   readiness.
7. Implement the shared account- and MR-scoped resolution model.
8. Add failing presentation/accessibility tests.
9. Wire the shared compact footer into ordinary and inline MR discussions;
   leave issue discussions static.
10. Push small verified commits to `master` after each coherent slice.
11. Run the complete automated, privacy, and Simulator verification matrix.
12. Perform the required deep code review.
13. If anything material is found, commit a repair plan before production
    edits, add regression tests, implement every fix, repeat verification, and
    review again until no material finding remains.
14. Record exact evidence and only then close P3-04 in
    `docs/MVP_PHASE_3.md`.

## Deep-review checklist

Review every P3-04 change for:

- incorrect GitLab endpoint, whole-thread, permission, or response assumptions;
- issue-resolution requests or note-level resolution used accidentally;
- wrong opaque discussion identity or unsafe path encoding;
- invalid resolvability or resolved-state derivation;
- duplicated discussion collections, mutation services, or readiness state;
- optimistic state presented as authoritative;
- missing rollback, unsafe retry, or delivery-unknown loss;
- incorrect resolver metadata or stale result overwriting a newer discussion;
- pagination insertion, ordering, count, or reconciled-tail corruption;
- ordinary and inline discussion copies diverging;
- outdated diff threads becoming unreachable;
- broad or wrong-account cache invalidation;
- stale `blocking_discussions_resolved` readiness state;
- rapid-tap, independent-thread, cancellation, disappearance, and
  account-switch races;
- authentication failure or insufficient-role handling;
- main-actor network or expensive collection work;
- unbounded transient state or retained completed operations;
- accessibility, Dynamic Type, Reduce Motion, contrast, or hit-target defects;
- credential, private comment, user, or project data exposure;
- notification-causing human mentions or unsafe demo-project writes;
- bad code, duplicated code, or code that needs refactoring.

Record every finding in this document.

If anything material is found:

1. Write and commit a repair plan before editing production code.
2. Add regression tests.
3. Implement every repair.
4. Repeat the full relevant automated and Simulator verification.
5. Perform and record another deep review.
6. Continue until no material finding remains.

P3-04 and its checklist in `docs/MVP_PHASE_3.md` may be marked complete only
after exact verification evidence and the final review result are recorded
here.

## Deep-review findings and repair plan

### DR-01 — HTTP 409 is incorrectly treated as delivery unknown

Status: repair planned; production code not yet changed.

The first deep-review pass found that `GitLabClient` maps only HTTP 400 and
422 to `GitLabAPIError.validation`. A GitLab HTTP 409 response therefore
becomes `.http(statusCode: 409)`, which the shared mutation-delivery policy
classifies as `deliveryUnknown`.

That violates this plan's definite-rejection contract for 409 responses. A
discussion-resolution conflict would incorrectly:

- retain the optimistic resolution state;
- require an unnecessary exact `Check GitLab` read;
- invalidate the affected discussion-list cache as though GitLab might have
  accepted the write; and
- prevent an immediate explicit retry after the conflict is addressed.

GitLab's current official REST troubleshooting documentation defines
`409 Conflict` as a server-reported resource conflict. Receipt of that
response makes this write's rejection definite; it is not an ambiguous
transport outcome.

Repair plan, to be committed before production edits:

1. Add a failing core client test proving HTTP 409 maps to a definite
   validation/rejection error.
2. Add discussion-resolution regression coverage proving a 409 rolls back the
   optimistic state and does not refresh readiness.
3. Add service coverage proving a 409 does not invalidate the discussion
   cache.
4. Update the shared HTTP mapping so 409 is a validation rejection. Do not
   broaden the change to unrelated unclassified status codes.
5. Rerun the focused client, discussion endpoint/service/model, cache, and
   presentation suites, then the complete P3-04 gates.
6. Repeat the deep review and record the final result here.

### DR-02 — An enabled resolution control can silently ignore a tap

Status: repair planned; production code not yet changed.

The review also found a state-ownership race after an authoritative resolution
response. `completeAuthoritative` reconciles the returned discussion and clears
its transient resolution state before awaiting the merge-request readiness
refresh. The presentation can therefore render the opposite action as enabled
while the per-discussion operation is still registered in `tasks`.

A tap during that window is silently discarded by the operation guard. A slow
or stalled readiness refresh makes the mismatch visible for longer and violates
the requirement that an enabled control corresponds to an available action.

Repair plan, to be committed before production edits:

1. Add a model regression test with a gated readiness refresh. Prove the
   authoritative discussion is retained, the control remains honestly busy,
   and another mutation cannot start until the refresh finishes.
2. Add presentation coverage for the post-mutation readiness-refresh state,
   including disabled action, progress, authoritative resolved metadata, and
   accessibility wording.
3. Add one explicit resolution phase for the readiness refresh. Preserve the
   authoritative discussion and resolver metadata in this phase; do not keep
   presenting optimistic data after GitLab has confirmed the mutation.
4. Clear the phase only after the readiness refresh returns. Keep the existing
   behavior that a readiness-refresh failure does not roll back the confirmed
   discussion mutation.
5. Rerun the focused model and presentation suites, the complete P3-04 gates,
   and Simulator interaction checks.
6. Repeat the deep review and record the final result here.

### DR-03 — Independent thread changes can race readiness refreshes

Status: repair planned; production code not yet changed.

The second deep-review pass found that successful mutations for two different
discussion IDs can call the injected merge-request readiness refresh
concurrently. That independence is intentional for the writes, but
`GitLabResourceDetailModel` keeps its loaded state visible while refreshing and
does not reject or order another refresh in that state. Two exact MR reads can
therefore complete out of order, allowing an older
`blocking_discussions_resolved` response to overwrite the newer one.

Coalescing the second refresh into the first is also unsafe because the first
read can begin before the second discussion mutation is accepted. P3-04 needs a
trailing exact read after every confirmed write, in mutation-completion order.

Repair plan, to be committed before production edits:

1. Add a failing resolution-model test that completes two independent
   discussion mutations together and proves readiness refreshes never overlap.
2. Gate the first refresh and prove the second refresh starts only after the
   first finishes, rather than being dropped or coalesced.
3. Add the smallest model-owned serial readiness-refresh queue. Keep each
   affected discussion in the explicit `refreshingReadiness` phase until its
   queued refresh finishes.
4. Propagate cancellation into queued refresh work, clear queue ownership on
   disappearance, and prevent an inactive account from publishing late state.
5. Do not change the shared resource-detail loading semantics or serialize the
   independent GitLab discussion writes themselves.
6. Rerun the focused concurrency, cancellation, readiness, and presentation
   suites, then the complete P3-04 gates and Simulator checks.
7. Repeat the deep review and record the final result here.

## Non-goals

- Resolving issue, commit, snippet, epic, work-item, or design discussions.
- Updating an individual note's body or resolved flag.
- Bulk resolve/reopen, resolve-with-reply, pending review comments, moving a
  discussion to an issue, or creating an issue from a thread.
- Creating a merge request or discussion solely for live verification.
- Resolving non-resolvable system activity or individual notes.
- Inferring eligibility from incomplete local role data.
- Inferring readiness from loaded discussion pages.
- A second discussion store, offline mutation queue, background sync,
  automatic write retry, or unbounded operation history.
- Discussion deletion, reaction changes, comment editing, labels, assignees,
  approvals, pipelines, or any later Phase 3 feature.
