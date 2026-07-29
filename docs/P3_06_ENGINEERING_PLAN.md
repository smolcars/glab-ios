# P3-06 Engineering Plan — Edit Metadata and Open/Closed State

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Test implementation: complete
- Production implementation: complete
- Verification: complete
- Deep review: complete

This plan must be committed and pushed before any P3-06 test or production
code is changed.

## Outcome

A permitted user can manage existing issue and merge-request labels, explicitly
confirm creation and assignment of a new project label, change assignees,
change merge-request reviewers, and close or reopen an issue or merge request.

Every successful mutation is reconciled from GitLab's authoritative returned
resource. Replacement-based people fields are rebased on an uncached preflight
read so a stale local picker does not silently remove a newer server assignee
or reviewer.

## Scope decisions and non-goals

- P3-06 edits only labels, assignees, merge-request reviewers, and the
  documented `close` or `reopen` state event.
- P3-06 does not edit milestones, due dates, confidentiality, weights,
  iterations, issue types, work-item status, reviewer status, approval rules,
  eligible approvers, approvals, merge state, draft state, or project
  membership.
- Reviewers are review-request recipients. They are not approval-rule
  approvers. P3-06 does not call the merge-request approval-rules API.
- Existing project and ancestor-group labels can be assigned. Archived labels
  remain visible only where needed to explain an existing assignment and
  cannot be newly assigned.
- Existing effective project members can be assigned or selected as
  reviewers. P3-06 never searches the instance-wide user directory and never
  adds a user to a project.
- Glab cannot determine every project, protected-branch, authorship, or custom
  role permission from the existing resource responses. App-level API access
  prevents a known read-only write; GitLab remains authoritative for
  project-specific permission denial.
- There is no persistent draft for metadata selections. Dirty interactive
  dismissal requires confirmation, and an in-flight or delivery-unknown
  mutation cannot be dismissed normally. This avoids introducing a second
  durable draft format for short-lived selections not required by the phase
  checklist.
- No automatic mutation retry, best-effort retry, or truncating fallback is
  allowed. A failed multi-assignee request is never retried automatically as a
  single-assignee request.

## Existing-code audit

### Architecture and state ownership

- The app uses small `@MainActor @Observable` feature models with injected
  `Sendable` services. P3-06 remains in that Model-View architecture.
- `GitLabResourceDetailModel.reconcileAuthoritative` can replace a loaded
  issue or merge request with a full authoritative response and clear stale
  refresh metadata.
- The signed-in shell is recreated for `GitLabAccountID`, but P3-06 still
  needs account checks, operation generations, cancellation, and response
  identity checks so a late result cannot affect another account.
- A single focused metadata/state editor model is sufficient. P3-06 does not
  justify a coordinator, MVI reducer, app-wide resource repository, or
  extending the title/description editor with unrelated picker state.

### Current issue and merge-request resources

- `GitLabIssue` already decodes stable ID, project ID, IID, labels, assignees,
  state, `updatedAt`, and the fields required to keep detail, list, Home,
  search, and Todo projections authoritative.
- `GitLabMergeRequest` decodes the same identity and mutation fields plus
  reviewers and merged/locked states.
- Both full detail responses include complete assignee arrays; merge requests
  include complete reviewer arrays. These full resources are the only
  replacement baselines.
- Current list rows and detail People/Labels sections already render the
  resulting fields. They need authoritative reconciliation, not a parallel
  display model.

### Existing metadata loaders

- P3-05 added account-scoped, project-scoped, paginated label and effective
  project-member reads:
  - `GET /projects/:id/labels`
  - `GET /projects/:id/members/all`
- `GitLabProjectLabel` and `GitLabProjectMember` already contain the identity,
  name, color, active state, avatar, and access level needed by P3-06.
- The current creation pickers search only loaded items. The official label
  endpoint supports `search`, and the effective-member endpoint supports
  `query`. P3-06 will extend the shared loader contract with an optional
  server query while preserving P3-05's `nil` query behavior.
- Search is debounced, paginated, scoped to one account and project, and
  generation checked. It never loads every page merely to satisfy a query.
- Current resource assignees or reviewers remain visible and removable even
  when they are not present on the currently loaded member page.

### Existing update and delivery-safety paths

- P3-02 has explicit issue/MR `PUT` endpoints, a direct uncached freshness
  read, one-attempt mutations, mutation-delivery classification, authoritative
  response checks, bounded cache invalidation, and loaded-owner
  reconciliation.
- `GitLabClient` retries only `GET`. It does not retry a `PUT` or replay one
  reactively after an authentication failure.
- `GitLabMutationDeliveryCertainty` treats validation, authentication,
  permission, not-found, and app-level access denial as definite rejection.
  Rate limiting, server errors, connectivity, cancellation during transport,
  invalid responses, and decoding failures remain delivery unknown.
- P3-06 reuses these transport and invalidation guarantees, but it does not
  reuse the title/description editor model. Metadata uses delta and
  replacement rebase rules that are different from text-field conflicts.

### Loaded owners and caches

- Already loaded authoritative resources can be reconciled into detail,
  assigned issues, the active assigned/review-request MR list, Home previews,
  Todo targets, and global search.
- The generic paginated model can replace an item but cannot yet remove one
  that no longer belongs in an open/assigned/review-request list. P3-06 needs
  a tested identity-based removal operation.
- Closing a resource or removing the current user from an assignee/reviewer
  set can change list membership. Immediate bounded removal plus a refresh
  after cache invalidation prevents a stale row without guessing the next
  server item.
- The existing resource-edit service already invalidates exact detail,
  assigned/review-request list, Home, and Todo reads. P3-06 will reuse one
  shared invalidation implementation rather than duplicate that matrix.
- Search has no persistent response cache and is reconciled only in memory.
  Project label cache invalidation is additionally required after a confirmed
  new label is created through `add_labels`.

### Current UI

- Issue and MR detail screens share one native top-trailing Liquid Glass group
  with Open in GitLab, Edit, and Add Comment.
- Adding another permanent toolbar icon would make the group wider. The
  existing pencil becomes one compact Edit menu with:
  - Title & description
  - Labels & people
  - Close or Reopen, when the current state supports that transition
- The metadata sheet uses compact summary rows that navigate to native label,
  assignee, and reviewer pickers. It avoids large cards, repeated explanatory
  text, or separate buttons for every field.
- The close/reopen action always uses a confirmation dialog and remains
  separate from Save in the metadata sheet.

## Official GitLab contracts

Research was completed against the current official GitLab REST documentation
on 2026-07-28.

### Update issue

[Update an issue](https://docs.gitlab.com/api/issues/#update-an-issue):

`PUT /projects/:id/issues/:issue_iid`

- `add_labels` adds comma-separated labels and creates/assigns a missing
  project label.
- `remove_labels` removes comma-separated labels.
- `labels` replaces the complete label set; `""` removes all labels. Missing
  names are created as project labels.
- `assignee_ids` replaces assignees; an empty value unassigns everyone.
- The endpoint also documents `assignee_id` as an accepted update parameter.
- `state_event` accepts `close` or `reopen`.
- At least one update field is required.
- The response is the authoritative updated issue.

### Update merge request

[Update a merge request](https://docs.gitlab.com/api/merge_requests/#update-a-merge-request):

`PUT /projects/:id/merge_requests/:merge_request_iid`

- `add_labels`, `remove_labels`, and `labels` have the same additive,
  subtractive, and complete-replacement behavior as issues.
- `assignee_id` and `assignee_ids` replace assignees; `0` or an empty value
  unassigns everyone.
- `reviewer_ids` replaces the complete reviewer list; `0` or an empty value
  removes all reviewers.
- `state_event` accepts `close` or `reopen`.
- At least one non-path field is required.
- The response is the authoritative updated merge request.

### Project labels and members

- [List project labels](https://docs.gitlab.com/api/labels/#list-all-project-labels)
  is paginated, includes ancestor-group labels by default, and accepts
  `search`.
- [List all project members](https://docs.gitlab.com/api/project_members/#list-all-members-of-a-project)
  is paginated, returns effective inherited and invited membership, and
  accepts `query`. Duplicate memberships are collapsed to the highest
  effective access level.
- The member `state=active` request filter is Premium/Ultimate only. Glab
  therefore keeps the all-tier request and filters decoded inactive members
  locally, including the already repaired all-inactive-page pagination case.

### Reviewers versus approvers

- `reviewer_ids` on the merge-request update endpoint changes the merge
  request's reviewers and review requests.
- [Merge request approvals](https://docs.gitlab.com/api/merge_request_approvals/)
  use separate approval and approval-rule endpoints. Eligible approvers and
  required approval rules are not changed by `reviewer_ids`.
- Every P3-06 label, hint, confirmation, and accessibility value says
  “Reviewer” or “Review request”; none says “Approver” for this mutation.

### Tier and permission behavior

- The issue create API explicitly distinguishes single-assignee Free behavior
  from multi-assignee Premium/Ultimate behavior. Update installations can
  also reject unsupported multiple assignments.
- For one selected assignee, Glab sends the documented singular
  `assignee_id`. For zero assignees it sends `assignee_ids: []`. For multiple
  assignees it sends the complete `assignee_ids` array.
- A multiple-assignee rejection preserves the selection and explains that the
  instance or project may allow only one. Glab never silently drops people or
  retries a different body.
- GitLab remains authoritative for role and project-specific permission
  checks. The UI must not claim that write-scoped credentials guarantee the
  operation is allowed.

## Data and endpoint design

### Target and snapshots

Add focused value types:

- `GitLabResourceMetadataTarget`: issue route or merge-request route.
- `GitLabResourceMetadataSnapshot`: target, stable global resource ID,
  `updatedAt`, exact label names, assignee users, optional reviewer users, and
  normalized resource state.
- `GitLabResourceMetadataIntent`: explicit label additions/removals,
  assignee additions/removals, reviewer additions/removals, and no state
  event.
- `GitLabResourceStateEvent`: `close` or `reopen`.
- `GitLabResourceMetadataResult`: reuse the existing typed authoritative
  issue/MR result unless review proves the current name creates semantic
  confusion at call sites.

Descriptions and debug descriptions redact label names, user names, project
identity, and resource content.

### Endpoint bodies

Keep explicit issue and merge-request endpoint factories. The metadata body
encodes only fields intentionally supplied:

- `add_labels: String?`
- `remove_labels: String?`
- `labels: String?` for an explicitly requested complete replacement
- `assignee_id: Int?`
- `assignee_ids: [Int]?`, including `[]`
- `reviewer_ids: [Int]?`, including `[]`, on merge requests only
- `state_event: String?`

Endpoint tests freeze omission versus an explicit empty value, sorted-key JSON,
Unicode, spaces, emoji, scoped labels, punctuation, duplicate normalization,
and exact path/write access. Invalid target-field combinations fail before a
request is built.

The UI uses additive/removal label semantics. Complete label replacement is a
documented endpoint capability with dedicated tests, but is not used to
overwrite a stale picker snapshot.

### Shared project metadata loading

Extract the label/member page requirements from
`GitLabIssueCreationServing` into a small `GitLabProjectMetadataLoading`
protocol. `GitLabIssueCreationServing` inherits it, preserving the existing
live service and P3-05 callers.

The methods accept an optional normalized search query and a trusted next-page
URL. Initial pages continue through the account-scoped response cache; next
pages continue through trusted GitLab pagination URLs.

P3-06's model creates query-scoped label/member pagers. A changed query:

1. cancels the old debounce/load task;
2. increments a generation;
3. waits for the injected debounce;
4. creates a new first-page request for the same project and account;
5. rejects late events whose query or generation is stale.

Selected server users and labels are represented separately from the current
page and remain removable during search or pagination.

## Selection and preflight semantics

### Labels

The model records explicit user intent relative to the opening authoritative
resource:

- selected absent baseline label → add intent;
- deselected baseline label → remove intent;
- returning a label to baseline removes that intent.

Immediately before saving, the service performs an uncached detail read:

- additions already present become no-ops;
- removals already absent become no-ops;
- unrelated labels added or removed on GitLab are preserved;
- only the remaining `add_labels` and `remove_labels` deltas are sent.

### Explicit new-label creation

Typing does not create a label. If trimmed text does not match an existing
loaded or server-searched label, the picker exposes a distinct
`Create “…”` action.

That action opens a confirmation explaining that GitLab will create a project
label and assign it to this resource. Only confirmation marks the name as an
approved new-label addition. Canceling, dismissing, or changing the search
does not create or select it.

The final update sends a confirmed name through `add_labels`, using GitLab's
documented create-and-assign behavior. A definite rejection leaves the
confirmation and selection intact. A confirmed success invalidates the
project label first-page cache.

### Assignees and reviewers

`assignee_ids` and `reviewer_ids` are full replacement arrays. User intent is
stored as added and removed IDs rather than one stale final array.

At save:

1. load the latest full resource directly;
2. validate its target and stable global ID;
3. start from its current full assignee/reviewer IDs;
4. apply only the user's additions and removals;
5. submit the resulting complete replacement array.

This preserves a server member added after the sheet opened unless the user
explicitly removed that same member. Empty arrays are sent only when the
rebased intended set is empty.

Inactive, blocked, or invalid IDs cannot be newly selected. A currently
assigned user who is no longer returned by membership remains visible and can
be removed, but cannot be newly restored without an active member result.

### Close and reopen

- Only opened resources offer Close.
- Only closed resources offer Reopen.
- Merged, locked, and unknown merge-request states offer neither action.
- The confirmation names the exact transition and explains that list
  membership can change.
- The service performs an uncached detail read before `state_event`.
- If GitLab already reports the intended state, the latest resource is
  reconciled as success without sending a redundant `PUT`.
- If the latest state changed to an incompatible state, no mutation is sent
  and the current server state replaces the stale detail.

## Mutation state machine and safety

One `@MainActor @Observable` model owns:

- account and resource target;
- authoritative baseline and picker intent;
- query-scoped metadata pagers;
- dirty, loading, saving, checking, rejection, conflict, and
  delivery-unknown presentation state;
- one active task and monotonically increasing operation generation;
- injected API access, metadata loader, mutation service, account-current
  check, and authoritative-success callback.

### Save flow

1. Reject duplicate submission, read-only access, empty changes, stale
   account, or invalid selection locally.
2. Capture immutable intent and operation generation.
3. Directly load the latest full resource without cached response delivery.
4. Verify target, route, stable global ID, and account generation.
5. Rebase label deltas and people replacement arrays on that resource.
6. If rebasing produces no work, reconcile the latest resource and close
   without a `PUT`.
7. Store the exact intended post-update predicate in memory before transport.
8. Send exactly one typed `PUT`.
9. Verify the returned resource identity and intended fields.
10. Invalidate bounded reads, reconcile loaded owners, and dismiss.

No task performs an automatic write retry. Cancellation before transport is a
definite local cancellation. Cancellation after transport begins is treated
as delivery unknown.

### Definite rejection

Validation, read-only access, authentication, permission, not-found, and
documented validation failures:

- preserve all selections;
- send no automatic follow-up mutation;
- allow correction and another explicit Save only when safe;
- route authentication failures through the account-scoped session handler.

### Delivery unknown

After rate limiting, server failure, connectivity loss, transport
cancellation, invalid response, or decoding failure:

- keep the sheet/state action active;
- disable Save and normal dismissal;
- show Check GitLab;
- never automatically repeat the mutation.

Check GitLab performs an uncached detail `GET`:

- if the intended label predicates, exact people arrays, and/or state match,
  treat the read as authoritative success;
- if every affected field still matches the preflight baseline, clear the
  unknown state and require another explicit Save;
- otherwise rebase untouched remote changes, surface a conflict for affected
  fields, and preserve the user's intent for review.

## Authoritative reconciliation and cache behavior

After confirmed success:

1. verify cancellation, generation, account, target, and stable resource ID;
2. reconcile the returned full resource into the detail model;
3. update or remove it from already loaded assigned/review-request lists based
   on open state and the current account user ID;
4. reconcile matching Todo targets and loaded global-search results;
5. update a matching Home preview immediately where still eligible;
6. invalidate exact detail, list, Home, and Todo cache entries;
7. schedule bounded refreshes for list/Home owners whose membership may have
   changed;
8. invalidate the project label cache only after a confirmed new-label
   creation;
9. refresh merge readiness only if the returned MR fields make its existing
   summary stale.

No cached JSON is edited in place. Unrelated project, diff, discussion,
reaction, pipeline, approval-rule, and account caches are untouched.

For a delivery-unknown mutation, affected exact reads are invalidated before
the reconciliation read so a stale cached value cannot be treated as proof.

## UI and accessibility

### Compact detail entry

The existing pencil remains one icon in the shared Liquid Glass toolbar pill,
but becomes an Edit menu. It does not add another top-level icon.

Menu actions use concise visible labels and complete accessibility hints:

- Title & description
- Labels & people
- Close issue / Reopen issue, or Close merge request / Reopen merge request

Open in GitLab and Add Comment remain in the same horizontal toolbar group.

### Metadata sheet

Use a native `NavigationStack` sheet:

- compact label summary row;
- compact assignee summary row;
- an MR-only reviewer summary row explicitly described as review requests;
- concise read-only, error, and delivery-check notices;
- Cancel and Save toolbar actions.

Each summary opens a searchable paginated list. Rows use avatar/label color,
name, concise secondary identity, checkmark selection, selected accessibility
value, and a 44-point hit target. Selected items remain available at the top
when a search page does not contain them.

Dirty Cancel requires confirmation. Interactive dismissal is disabled while
dirty, saving, or delivery unknown. Read-only accounts can inspect the sheet
and metadata, but Save sends zero mutations and clearly explains why.

### Close/reopen confirmation

The menu action presents a native confirmation dialog. The destructive style
is used only for Close; Reopen is a normal action. Progress, definite
rejection, authentication, incompatible state, and delivery-unknown checking
remain visible without adding a large permanent card to detail content.

### Adaptive and assistive behavior

- VoiceOver distinguishes labels, assignees, reviewers, and approvers.
- Icon-only toolbar actions have labels and hints.
- Dynamic Type can wrap summaries without clipping Save/Cancel.
- Search, selection, confirmation, and mutation statuses are announced.
- Dark/light appearance, Reduce Transparency, and Reduce Motion preserve
  legibility and do not rely on color alone.
- Liquid Glass remains on controls and navigation surfaces, not static
  metadata content.

## Test plan

### Endpoint tests

Write failing tests before implementation for:

- issue and MR `add_labels` and `remove_labels`;
- complete label replacement and explicit empty replacement;
- exact Unicode, spaces, emoji, scoped-label, quote, slash, and ampersand JSON;
- singular assignee, multi-assignee, and explicit empty `assignee_ids`;
- MR `reviewer_ids`, including explicit empty arrays;
- issue and MR `state_event` close/reopen;
- omission of unrelated fields and invalid target-field combinations;
- write access, exact method/path, response decoding, permission/validation
  errors, cancellation, rate limiting, and delivery certainty.

### Metadata loader tests

Cover:

- label and member initial pages, next pages, totals, cache behavior, and
  trusted pagination;
- normalized server `search`/`query`;
- rapid query changes and stale response rejection;
- account/project isolation;
- inactive raw-tail and all-inactive-page continuation;
- selected-current users not present in loaded membership pages;
- partial failure and retry without discarding the other picker.

### Model and service tests

Cover:

- additive/removal label intent;
- typing without confirmation creates nothing;
- explicit new-label confirmation and cancellation;
- preflight preserving unrelated server labels;
- people replacement preserving a newer server user;
- explicitly removing a newer/current user;
- unassigning everyone and clearing all reviewers;
- single versus multiple assignee body selection;
- reviewers never changing approval rules;
- no-op rebase sending no `PUT`;
- close/reopen confirmation and already-completed state;
- merged/locked/unknown MR transition rejection;
- read-only and permission denial;
- duplicate-tap prevention;
- stale result identity and route;
- cancellation before and after transport;
- delivery-unknown check success, unchanged baseline, and conflict;
- account switching and late response rejection;
- exact invalidation and project-label-cache behavior.

### Owner reconciliation tests

Cover:

- detail authoritative replacement;
- loaded list replacement when still eligible;
- loaded list removal after close, unassignment, or reviewer removal;
- Home preview update/removal and bounded refresh;
- Todo target replacement;
- global-search label/state replacement;
- no cross-account or unrelated-owner mutation.

### Presentation tests

Cover:

- compact edit-menu actions by resource/state;
- distinct reviewer and approver wording;
- explicit Create Label confirmation;
- close versus reopen roles and copy;
- read-only, definite rejection, multi-assignee rejection, incompatible state,
  delivery unknown, and Check GitLab actions;
- accessibility labels, hints, selected values, and state announcements.

## Simulator and live-data safety

Use the reusable `.deriveddata/Glab` directory and the iPhone 17 Pro Simulator.
Do not use the physical iPhone for development testing.

Routine verification uses deterministic mutation stubs and the configured
self-managed read-only token for live metadata reads. It sends no production
write mutation.

If a live write smoke test becomes necessary:

- announce it before sending;
- use only the project scoped by `DEVOPS_DEMO_TOKEN`;
- use an isolated test issue or merge request;
- never assign, review-request, mention, or tag a human;
- use only an explicitly identified bot account if a people mutation is
  required;
- never alter approval rules;
- restore the original labels, people, and state after verification;
- treat every restore mutation with the same one-attempt and delivery-unknown
  safety rules.

Simulator interaction must verify:

- compact edit menu on issue and MR detail;
- label, assignee, and reviewer search/pagination;
- explicit new-label confirmation;
- dirty dismissal and read-only behavior;
- close/reopen confirmation and deterministic mutation states;
- light/dark appearance;
- regular and accessibility Dynamic Type;
- VoiceOver reviewer-versus-approver wording;
- Reduce Transparency and Reduce Motion;
- no regressions in scrolling, comments, reactions, diffs, readiness, Home,
  Todos, search, and account switching.

Tap every visible P3-06 action and capture normal plus accessibility
screenshots. Shut down the Simulator when verification completes.

## Final quality gates

At P3-06 close:

1. run focused endpoint, loader, service, model, owner, and presentation tests;
2. run the complete serialized test suite on the iPhone 17 Pro Simulator;
3. build Release for the Simulator with `.deriveddata/Glab`;
4. run Xcode static analysis;
5. validate the privacy manifest and bundled resources;
6. scan tracked files and the Release bundle for credential values and
   credential identifiers;
7. scan production code for forced crashes/casts/tries, debug output,
   accidental content logging, and unfinished markers;
8. inspect the complete production diff and record exact results here.

## Deep-review checklist

After implementation and verification, review every P3-06 change for:

- incorrect GitLab field or tier assumptions;
- empty, over-broad, or duplicate mutations;
- accidental project-label creation from typed text;
- stale label replacement or lost concurrent label changes;
- lost assignees or reviewers from stale full arrays;
- reviewer/approver wording or API confusion;
- unsafe singular/multiple-assignee fallback;
- invalid close/reopen transitions;
- automatic retry or unsafe delivery-unknown recovery;
- stale detail/list/Home/Todo/search state;
- incorrect list-membership removal or cache over-invalidation;
- account/project/resource leakage;
- task ownership, cancellation, reentrancy, or late-response races;
- unbounded metadata loading or stale search results;
- duplicated issue/MR endpoint, picker, service, mutation, or reconciliation
  logic;
- oversized UI, redundant text, ungrouped actions, inaccessible icon-only
  controls, or unnecessary Liquid Glass;
- sensitive labels, users, project/resource identities, or credentials in
  logs, descriptions, file names, screenshots, or tests;
- bad code, unnecessary abstractions, dead code, and code that needs
  refactoring.

Record every material finding below before editing a repair. For each finding:

1. describe impact and reproduction;
2. write the smallest repair plan;
3. add a regression test;
4. implement the repair;
5. rerun focused and complete verification;
6. repeat the review until no material finding remains.

## Deep-review findings

### Review pass 1 — repair required

The first complete production review on 2026-07-28 found the following
material issues before P3-06 could be closed:

1. **Partial and stale metadata loads.** The initial label/member load
   discarded both results when either request failed. Search failures did not
   reject stale query generations, and an older next-page response could merge
   into a newer search. Repeated last-row appearance could also start the same
   page more than once.
   - Impact: a healthy picker could disappear because the other endpoint
     failed, or labels/people from a prior query could appear in the current
     query.
   - Repair plan: test independent initial-page success, stale success/failure
     rejection, and duplicate pagination; add query generations and
     per-resource in-flight page guards while preserving the successful
     picker.

2. **A cancelled or superseded preflight could still write.** After the fresh
   detail read, the mutation path did not re-check task cancellation or active
   account identity before sending `PUT`.
   - Impact: dismissing/switching accounts during preflight could allow an
     unwanted mutation.
   - Repair plan: add cancellation and account-switch regression tests, then
     require both checks immediately before mutation transport.

3. **Incompatible fresh state was not rejected.** An opened MR could become
   merged or locked after the editor opened, but a stale Close action would
   still submit `state_event=close`.
   - Impact: Glab could send a transition that its own UI no longer permits.
   - Repair plan: test fresh incompatible states, reconcile the authoritative
     resource without a `PUT`, and report that the requested transition was
     not applied.

4. **Authoritative no-op/conflict reconciliation was incomplete.** A
   preflight that showed the requested change was already applied invalidated
   all affected caches unnecessarily. Delivery checks and incompatible-state
   results updated only the editor baseline, leaving detail/list owners stale.
   - Impact: avoidable cache churn and stale visible owners.
   - Repair plan: separate mutation success from read-only authoritative
     reconciliation, invoke owner reconciliation for both, and invalidate
     cached reads only after a confirmed mutation.

5. **Current-user seed eligibility was too permissive.** Detail users were
   synthesized as active project members. A current assignee/reviewer missing
   from the active membership result could be removed and then re-added.
   Conflict reconciliation also did not merge newly authoritative users into
   the picker.
   - Impact: an inactive or no-longer-assignable user could be restored, or a
     newly observed server user could remain unidentifiable in the picker.
   - Repair plan: test remove-only seed behavior, track IDs confirmed active
     by project membership pages, and merge authoritative seed users after
     reconciliation.

6. **Confirmed new labels did not refresh project label metadata.** The model
   did not distinguish a confirmed Create Label action from selecting an
   existing label, and the service invalidated resource/list caches only.
   The create action could also be offered for a differently-cased selected
   label absent from the loaded page.
   - Impact: a new project label could remain absent from later pickers, and
     duplicate-looking creation could be offered.
   - Repair plan: test explicit-new-label cache invalidation, track confirmed
     names, invalidate the project label first page only after confirmed
     mutation success, and compare loaded plus selected names before offering
     Create.

7. **Query-owned lists did not remove ineligible resources.** Close,
   unassignment, or reviewer removal replaced rows in assigned/review lists
   and Home previews even when the resource no longer matched the server
   query.
   - Impact: closed or no-longer-assigned work remained visibly stale until a
     refresh.
   - Repair plan: add generic tested remove-if-present reconciliation, apply
     state/current-user eligibility in assigned issue and MR owners, remove
     ineligible Home previews, and trigger one bounded Home refresh only when
     a displayed preview is removed.

8. **The required model and owner regression matrix was incomplete.** The
   initial focused model tests covered core rebase and delivery uncertainty
   but not the races and owner transitions above.
   - Impact: the documented P3-06 safety guarantees were not frozen against
     regression.
   - Repair plan: add focused tests for every finding before its production
     repair, then run the full quality gates and repeat this review.

### Review pass 2 — additional repair required

The post-repair review repeated the full P3-06 checklist on 2026-07-28. The
complete serialized suite passed before this review with 818 tests in 114
suites, but that run does not close P3-06 because the review found these
additional material issues:

9. **Some late read results could still cross an account or cancellation
   boundary.** The fresh-detail path checked the active account immediately
   before `PUT`, but its already-applied and incompatible-state branches could
   reconcile without the same post-read guard. `Check GitLab` had the same
   gap.
   - Impact: a canceled task or inactive account could update a lingering
     detail/list owner from a late `GET`, even though no write would be sent.
   - Repair plan: gate every post-read branch on cancellation and the exact
     active account before validation or reconciliation. Add gated-service
     regressions for both preflight and delivery-check reads.

10. **An unverifiable response after a sent `PUT` did not enter
    delivery-unknown recovery.** A wrong resource identity or authoritative
    response that did not contain the intended fields produced
    `invalidAuthoritativeResponse` without retaining the pending intent.
    - Impact: Save became available again even though GitLab might already
      have accepted the mutation, allowing an unsafe repeated write.
    - Repair plan: add wrong-identity and intent-mismatch response tests, retain
      the exact intent, classify the result as delivery unknown, and require
      an uncached Check GitLab read before another write.

11. **Loaded merge-request lists were reconciled only from their own
    navigation path.** Each `MergeRequestsView` privately owned its model, so
    editing an MR from Todos, search, a deep link, or the other list could
    leave an already-loaded assigned/review-request list stale. Removing an
    resource also did not refresh a list to fill the vacated row.
    - Impact: a closed, unassigned, or no-longer-reviewed MR could remain in a
      preserved tab stack, or a removed row could leave an incomplete first
      page until manual refresh.
    - Repair plan: promote the two account-scoped MR list models alongside the
      existing assigned-issue owner, inject them into their views, reconcile
      all three from the shell, and schedule a bounded refresh only when an
      already-loaded row was removed. Reuse the existing tested eligibility
      and removal functions.

12. **Metadata presentation repeated the first-open sheet race.** Issue and MR
    details independently set an optional editor model and a Boolean sheet
    flag. Direct close/reopen also kept a hidden editor model before
    confirmation and did not route a definite authentication failure through
    session recovery unless the sheet was subsequently shown.
    - Impact: the first metadata sheet presentation could be blank, and an
      authentication failure from a direct state action could remain a local
      alert instead of recovering the account.
    - Repair plan: make the optional model the single sheet item, create the
      state model only after confirmation, and explicitly pass direct-action
      authentication failures to `AppSession`. Re-run cold first-presentation
      issue and MR flows.

13. **A fully selected label page had no pagination control.** Selected labels
    are rendered in a separate section and removed from the project-label
    rows. If every label on the current page was selected, no row remained to
    trigger the next-page task.
    - Impact: an existing label on page two could be unreachable.
    - Repair plan: expose whether a trusted next label page exists and show an
      explicit one-page-at-a-time Load More control only when filtering leaves
      no row trigger. Add a model regression using an all-selected first page.

14. **Remove-only member state and compact summaries were not fully honest.**
    A current assignee/reviewer not confirmed by active project membership
    could be removed but then remained a visually enabled no-op button.
    Summaries could also show a known name followed by the total count as if it
    were an additional selection.
    - Impact: tapping could silently do nothing, VoiceOver announced a normal
      unselected control, and the compact summary could double-count.
    - Repair plan: expose tested selection eligibility, disable and explain an
      unavailable unselected seed row while keeping removal enabled, and fall
      back to one total-count summary when any selected identity is unknown.

15. **Tracked smoke flows contained private live resource titles, and state
    confirmation omitted list-membership impact.** The scripts selected live
    issue/MR rows by internal titles. Close confirmation only said the resource
    would close on GitLab.
    - Impact: repository history disclosed unnecessary company work text, and
      users were not warned that closing can remove the item from their work
      lists as required by this plan.
    - Repair plan: select the first matching row through generic accessibility
      identifier patterns, verify the revised flows, and add compact
      assigned/review-list impact text to close/reopen confirmation.

## Ordered implementation

1. Commit and push this plan without P3-06 test or production changes.
2. Add failing issue/MR endpoint and metadata-body tests.
3. Implement explicit typed metadata/state update bodies.
4. Add failing shared project metadata search/pagination tests.
5. Extract and extend the P3-05 metadata loader contract with no behavior
   regression.
6. Add failing service and model tests for rebase, confirmation, delivery,
   cancellation, account, and authoritative-response behavior.
7. Implement the focused service and observable model.
8. Add failing list/Home/Todo/search reconciliation tests and implement
   bounded reconciliation/removal/refresh.
9. Add presentation tests, then implement the compact Edit menu, metadata
   sheet, pickers, and close/reopen confirmation.
10. Run focused tests and one complete Simulator interaction pass.
11. Run all final quality gates.
12. Perform and record the deep review, plan and repair every material
    finding, rerun verification, and repeat review until clean.
13. Mark P3-06 complete only after all checklist evidence is recorded.

## Review pass 2 repair evidence

- Every fresh-detail and delivery-check result is now rejected after
  cancellation or an account change before it can validate, reconcile, or
  mutate an owner.
- A sent mutation whose returned identity or intended fields cannot be
  verified retains its exact pending intent and enters delivery-unknown
  recovery. It cannot be sent again until an uncached Check GitLab read
  reconciles the result.
- Assigned-issue, assigned-MR, and review-request MR owners are account-scoped
  shell state. Authoritative edits from Home, Todos, search, or deep links
  reconcile all already-loaded owners and remove resources that no longer
  satisfy their server query.
- Metadata sheets use their optional editor model as the single presentation
  identity. Direct close/reopen creates a separate state owner only after
  confirmation and routes definite authentication failures through the
  account session handler.
- Label pagination retains an explicit Load More path when every label on a
  page is selected. Remove-only member rows are disabled after removal with
  an accurate accessibility explanation, while selected remove actions remain
  available.
- Compact people summaries no longer double-count unresolved identities.
  Tracked Maestro flows use generic row identifiers rather than private live
  resource titles, and close/reopen confirmation explains assigned and review
  list membership impact.
- Regression tests cover late preflight and delivery-check reads, wrong or
  mismatched mutation responses, all-selected label pages, remove-only member
  eligibility, and the repaired owner transitions.

## Final verification evidence

- The final focused endpoint, metadata-loader, service, editor-model,
  paginated-owner, assigned-issue, assigned-MR, review-request, and Home model
  bundle passed 94 tests with zero failures.
- The final serialized app suite passed 823 tests with zero failures on the
  iOS 26.5 iPhone 17 Pro Simulator. Xcode reported 34.725 seconds for the test
  operation.
- Debug and Release iPhone Simulator builds succeeded using the reusable
  `.deriveddata/Glab` directory. Xcode Release static analysis also succeeded.
- The cold first-presentation issue-composer flow passed. The issue and MR
  P3-06 flows passed in dark appearance at regular Dynamic Type and in light
  appearance at accessibility Dynamic Type. Their captured UI was visually
  inspected for clipping, layout, avatars, search, picker selection, disabled
  read-only state, and reviewer-versus-approver wording.
- The issue flow also passed with Increase Contrast, Reduce Motion, and Reduce
  Transparency enabled. The accessibility hierarchy exposed the explicit
  “Reviewers are separate from approval-rule approvers” wording. Simulator
  settings were restored afterward.
- Read-only live verification navigated metadata and member APIs only. No live
  mutation, issue creation, state transition, label creation, assignment,
  review request, human mention, notification, or pipeline action was sent.
- `Configuration/Glab-Info.plist`, the source privacy manifest, and both
  bundled Release copies passed `plutil` validation. The privacy manifest is
  present in the Release app.
- Configured token values are absent from tracked files and the Release
  bundle. Token variable identifiers are absent from the Release executable.
  Generated UI screenshots containing live names were moved to Trash and were
  never staged.
- `git diff --check` passed. The complete P3-06 production diff contains no
  forced try, forced cast, fatal error, precondition failure, debug print,
  dump, TODO, or FIXME addition.

## Final repeat-review result

The required repeat review covered all 18 P3-06 production files, the complete
test diff, and the tracked Simulator flows after the second repair pass. It
rechecked official endpoint fields, label creation, singular and replacement
assignee semantics, reviewer-versus-approver boundaries, preflight rebasing,
delivery certainty, cancellation, account isolation, bounded cache
invalidation, detail/list/Home/Todo/search reconciliation, pagination,
presentation ownership, read-only behavior, accessibility, privacy, and
unnecessary abstraction.

All 15 recorded material findings are repaired. The final repeat review found
no remaining material bug, bad code, duplicated logic, privacy issue, or
refactoring requirement. P3-06 is complete.
