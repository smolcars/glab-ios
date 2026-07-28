# P3-02 Engineering Plan — Edit Titles and Descriptions

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Production implementation: in progress
- Verification: not started
- Deep review: not started

This is the required implementation plan for P3-02. It must be committed and
pushed before any P3-02 test or production code is changed.

## Outcome

A user can edit an issue or merge-request title and raw GitLab Flavored
Markdown description, preview the description with Glab's existing renderer,
recover an account- and resource-scoped local draft, and safely reconcile the
authoritative response.

Glab must refuse a save when a field the user edited is already known to have
changed on GitLab. It must never claim stronger concurrency protection than
the documented GitLab APIs provide.

## Scope decisions and assumptions

- P3-02 edits only `title` and `description`.
- Issue and merge-request update endpoints, request bodies, returned resource
  types, and cache invalidation remain explicit even though the editor
  presentation and state machine are shared.
- Raw Markdown is the source of truth. The editor initializes from the
  untrimmed API description, persists it verbatim, and sends it verbatim.
  Display-only trimming in the current detail views is not an edit baseline.
- GitLab documents a maximum issue and merge-request description length of
  1,048,576 characters. Glab enforces that documented boundary before
  transport. GitLab does not document a title-length maximum for these update
  endpoints, so Glab will reject only an empty or whitespace-only title and
  will leave all other title validation to GitLab.
- An OAuth or personal access token with `api` access passes the app-level
  write gate. Resource-specific roles and authorship cannot be inferred
  reliably from the existing detail responses, so GitLab remains
  authoritative for `403` and `404`.
- A read-only account may open the local editor, recover a draft, and preview
  Markdown, but Save remains disabled with an accurate explanation. This
  keeps all network mutation disabled while allowing the editor UI to be
  verified with the configured read-only Simulator account.

## Existing-code audit

### Detail resources and state ownership

- `GitLabIssue` and `GitLabMergeRequest` already decode the complete title,
  optional description, `updated_at`, project ID, IID, and stable route needed
  for an edit baseline.
- Both detail screens use
  `GitLabResourceDetailModel<Resource, Route>`. It preserves cached content
  during revalidation but currently has no public authoritative-mutation
  reconciliation method.
- The signed-in shell is recreated with
  `.id(GitLabAccountID(session: session))`. Switching accounts therefore
  destroys the old feature tree and its client. P3-02 still needs generation
  checks and cancellation handling so an old editor cannot publish a late
  result before destruction completes.
- `GitLabPaginatedResourceModel.reconcileItem` already replaces an item by
  stable identity. It can update assigned issue and merge-request lists
  without introducing another list-state owner.
- Home, Todos, and global search retain their own loaded projections. Small,
  typed reconciliation methods are needed so a successful edit does not leave
  a title or description visibly stale in an already loaded screen.

### Request, authentication, and mutation behavior

- P3-01 added typed JSON `PUT` requests that always require `.write`.
- `GitLabClient` retries only `GET`; `PUT` receives one transport attempt.
- Reactive OAuth refresh after `401` is restricted to `GET`. Proactive refresh
  may happen before the sole write attempt when a token is already expired.
- `GitLabMutationDeliveryCertainty` distinguishes definite rejection from a
  response where the write might already have reached GitLab. P3-02 must
  preserve the draft and require a direct reconciliation read after an
  ambiguous result.

### Response cache

- The issue detail uses the `workItemDetail` cache policy. Merge-request
  detail uses the `mergeRequestReadiness` policy.
- Persistent cache keys are account-scoped and exist only for exact `GET`
  requests. `invalidateCachedResponse` also cancels an older in-flight read
  for the same key, preventing stale repopulation.
- Known cached projections affected by title or description changes are:
  - the exact issue or merge-request detail;
  - assigned issue or merge-request lists;
  - Home assigned-issue, assigned-MR, and review-request previews;
  - every exact Todo state/type query because Todo targets embed resource
    titles and descriptions.
- Global search currently bypasses the response cache. Its loaded in-memory
  results still need authoritative reconciliation.

### Markdown

- `GitLabMarkdownRenderer` parses off the main actor, coalesces identical
  renders, keys documents by account/resource/content digest, removes an older
  resource variant, and bounds both entry count and source cost.
- The editor preview must reuse this renderer. It must not add a second parser,
  parse on every keystroke, or render while the Edit tab is selected.
- A preview request uses the same account and resource identity as the detail
  description and the exact draft source. The existing digest makes a changed
  draft a distinct render while bounding old variants.

### Draft storage and account lifecycle

- Discussion drafts already demonstrate revisioned, account/resource-scoped,
  hashed file names, atomic writes, complete file protection, redacted
  descriptions, debounced persistence, and account-removal cleanup.
- Discussion draft records contain only a comment body and cannot represent an
  edit baseline or an intentionally empty description. P3-02 needs a separate
  typed edit-draft contract rather than overloading comment semantics.
- `AppSession` preserves discussion drafts when authentication expires but
  removes them when the user intentionally removes an account. Edit drafts
  must follow the same lifecycle.
- Shared protected-file mechanics may be extracted only if otherwise copied
  literally between the two stores. The public discussion-draft behavior must
  remain unchanged.

### Current UI

- Issue and merge-request detail screens already share a native trailing
  `ToolbarItemGroup` containing the GitLab link and new-comment action. The
  edit action belongs in this same Liquid Glass toolbar group.
- The editor should be one native SwiftUI sheet with title, Edit/Preview
  selection, raw Markdown `TextEditor`, validation/read-only/conflict states,
  and explicit Save/Cancel actions.
- Dirty interactive dismissal must not silently lose text. Save, conflict
  checks, and draft flushing must have visible progress and disabled duplicate
  actions.

## Official GitLab contracts

### Update issue

GitLab's
[Update an issue](https://docs.gitlab.com/api/issues/#update-an-issue)
contract is:

`PUT /projects/:id/issues/:issue_iid`

- At least one update parameter is required.
- `title` and `description` are optional update attributes.
- The description is limited to 1,048,576 characters.
- The response is the authoritative updated issue.
- The Issues API is documented for Free, Premium, and Ultimate on GitLab.com,
  GitLab Self-Managed, and GitLab Dedicated.

The
[issue permissions documentation](https://docs.gitlab.com/user/project/issues/managing_issues/#edit-an-issue)
states that Planner, Reporter, Developer, Maintainer, and Owner can edit, and
the author or assignee can also edit under the documented conditions. Glab
does not duplicate this evolving authorization matrix.

### Update merge request

GitLab's
[Update a merge request](https://docs.gitlab.com/api/merge_requests/#update-a-merge-request)
contract is:

`PUT /projects/:id/merge_requests/:merge_request_iid`

- At least one non-path attribute is required.
- `title` and `description` are optional update attributes.
- The description is limited to 1,048,576 characters.
- The response is the authoritative updated merge request.
- The Merge Requests API is documented for Free, Premium, and Ultimate on
  GitLab.com, GitLab Self-Managed, and GitLab Dedicated.

### Concurrency limitation

Neither update endpoint documents a revision parameter, `If-Match`, ETag
precondition, or `If-Unmodified-Since` behavior for `PUT`. GitLab's general
REST documentation mentions `If-Unmodified-Since` only as an example for
resource deletion, not for issue or merge-request editing.

Therefore P3-02 will use a best-effort direct freshness read immediately before
the update, but there remains an unavoidable race if another client changes
the same field between that read and GitLab processing the `PUT`. The UI and
documentation must not claim transactional compare-and-swap protection.

## State and type design

### Edit identity and snapshots

Add focused, value-semantic edit types:

- `GitLabResourceEditTarget`: issue route or merge-request route.
- `GitLabResourceEditSnapshot`: target, stable numeric GitLab resource ID,
  exact title, exact description normalized only from API `nil` to editor
  `""`, and `updatedAt`.
- `GitLabResourceEditChanges`: optional changed title and optional changed
  description. `nil` means omit that field; `""` means explicitly clear the
  description.
- `GitLabResourceEditResult`: authoritative `GitLabIssue` or
  `GitLabMergeRequest`.

Descriptions and debug descriptions for edit targets, snapshots, drafts,
errors, and cache/draft keys must redact title and Markdown content.

### Explicit endpoints and service

Add separate endpoint factories:

- `GitLabIssueEndpoints.update(at:changes:)`
- `GitLabMergeRequestEndpoints.update(at:changes:)`

Each factory builds a typed JSON `PUT` and decodes its own authoritative
resource type. Endpoint tests freeze path, method, write access, omitted
unchanged fields, explicit empty description, Unicode, and maximum-boundary
payloads.

Add a focused `GitLabResourceEditing` service used only by this feature:

- `loadLatest(target)` performs the exact detail `GET` through `send`, never
  `loadResponse`, so no cached value can satisfy the preflight.
- `update(target, changes)` switches to the explicit issue or MR endpoint,
  returns the typed authoritative result, then invalidates only the known
  exact affected reads.
- No write is sent when `changes` is empty.
- The service owns no UI state and does not become a generic CRUD repository.

### Editor model

One `@MainActor @Observable` editor model owns one edit session:

- account ID, target, baseline snapshot, title, description, selected
  Edit/Preview mode, and local revision;
- draft restore/persistence state;
- validation, freshness, conflict, save, ambiguous-delivery, and success
  state;
- a monotonically increasing operation generation plus one active task owner;
- injected editor service, draft store, API access, and authoritative-success
  callback.

The issue and MR detail views construct this shared model from their exact
loaded resource and reconcile the result back into the typed detail model.

## Draft contract

Add `GitLabResourceEditDraftStoring` with an in-memory test implementation and
a protected file implementation.

### Key

The key includes:

- canonical account identity (host and numeric user ID);
- resource kind;
- project ID;
- issue or merge-request IID.

Keys and file names must not contain credentials, titles, Markdown, project
paths, or other response content. On-disk account and resource identifiers are
length-prefixed before hashing, following the established draft-store pattern.

### Record

The versioned draft record contains only:

- target identity;
- baseline stable numeric GitLab resource ID, title, description, and
  `updatedAt`;
- current title and description;
- monotonic local revision.

It contains no access token, refresh token, authorization header, user object,
comments, diff, or unrelated response data.

### Persistence rules

- Restore completes before Save can run.
- Text changes persist after a short debounce on the store actor, not the main
  actor. Cancel and view disappearance flush the newest revision.
- An older delayed write cannot overwrite a newer revision.
- Returning both fields exactly to the baseline removes the draft.
- An intentionally empty description remains representable when the title or
  description differs from baseline.
- Save first flushes the current draft. A storage failure prevents the network
  mutation and remains visible.
- A successful authoritative reconciliation removes the draft. If cleanup
  fails, reopening detects that the stored desired content already equals the
  current server baseline and safely discards the stale record.
- Intentional account removal deletes its edit drafts. Authentication expiry
  preserves them for sign-in recovery, matching discussion drafts.
- Corrupt, wrong-version, wrong-key, oversized, or unreadable records are not
  treated as valid drafts and never expose their content in errors or logs.
- Glab has not shipped, so the first development-only draft schema is not a
  compatibility contract. Adding the stable resource ID intentionally makes
  an older local development draft fail decoding and be discarded instead of
  adding speculative migration code.

## Validation and freshness algorithm

### Local validation

Before any network request:

1. Reject a title whose whitespace-trimmed value is empty, but do not alter the
   submitted title.
2. Reject a description over 1,048,576 Swift `Character` values.
3. Compute changes against the exact baseline.
4. If neither field changed, perform no request and remove an obsolete draft.
5. Flush the current draft before continuing.

The potentially linear description-length check runs only for validation, not
on every keystroke. Preview parsing remains off the main actor.

### Three-way preflight

Immediately before every `PUT`, load the latest full resource directly:

1. Confirm account, resource kind, project ID, IID, and stable global resource
   ID still match the edit target.
2. Compare latest `updatedAt`, title, and description with the baseline.
3. For each locally changed field:
   - if the latest value still equals the baseline, it is eligible to update;
   - if the latest value differs, enter conflict state and send no `PUT`.
4. For each locally untouched field:
   - accept the latest value into the baseline and editor, preserving the
     other person's change;
   - omit that field from the `PUT`.
5. An `updatedAt` change by itself, or a change only to an untouched field,
   rebases the baseline and does not create a false title/description
   conflict.
6. Recompute changes after rebasing and send only fields still changed.

A failed or canceled freshness read sends no mutation and preserves the
draft. The user may retry the freshness check.

### Conflict behavior

A conflict shows that GitLab changed a field also edited locally. It preserves
the local draft and disables Save. The user can:

- keep the draft and leave or continue copying/editing it; or
- explicitly discard local changes and load the latest authoritative title
  and description.

P3-02 will not provide an unreviewed "overwrite anyway" action or attempt an
automatic textual Markdown merge.

## Mutation and delivery certainty

- A `PUT` receives one transport attempt and no reactive OAuth replay.
- A definite rejection (`400`, `401`, `403`, `404`, `422`, local validation,
  read-only access, or freshness conflict) preserves the draft and can be
  retried only where the recovery is meaningful.
- `409`, `429`, `5xx`, connectivity loss, cancellation during transport,
  invalid response, decoding failure, and transport failure are handled
  conservatively as delivery unknown unless the shared error model already
  proves otherwise.
- After delivery becomes unknown, the normal Save action is disabled. The UI
  offers "Check GitLab", which performs an uncached detail `GET`:
  - if every locally changed field equals the intended value, treat the latest
    resource as authoritative success, reconcile it, and remove the draft;
  - if every locally changed field still equals the prior baseline, rebase and
    allow a new explicit Save, which repeats the full preflight;
  - otherwise enter conflict state and preserve the draft.
- An authentication failure uses the existing account-scoped session recovery.
  The edit draft survives forced reauthentication.
- Cancellation, account switching, or a superseding operation invalidates the
  operation generation. A late response cannot update the current editor,
  detail model, list projection, draft, or another account.

## Authoritative reconciliation

After a normal successful `PUT` or a successful delivery-unknown check:

1. Verify task cancellation, operation generation, account ID, target, and
   result identity.
2. Reconcile the returned full resource into
   `GitLabResourceDetailModel`, clearing stale refresh metadata.
3. Publish the same authoritative result through a small callback to already
   loaded projections:
   - assigned issues or the active assigned/review MR list via
     `reconcileItem`;
   - Home work previews;
   - every loaded Todo model whose target matches;
   - loaded global-search issue or MR results.
4. Invalidate the exact persistent reads listed below.
5. Replace the editor baseline with the authoritative snapshot.
6. Remove the draft and dismiss only after the main-actor reconciliation has
   completed.

The reconciliation callback passes a typed result and owns no storage. It is
not an app-wide resource repository.

### Exact cache invalidation

On issue success:

- exact issue detail;
- assigned issue list;
- Home assigned-issue preview;
- all six exact Todo state/type queries.

On merge-request success:

- exact merge-request detail;
- assigned and review-requested MR lists;
- Home assigned-MR and review-request previews;
- all six exact Todo state/type queries.

No cache is invalidated on validation, freshness failure, conflict,
read-only denial, cancellation, or failed/unknown mutation delivery. A
delivery-unknown reconciliation read that proves success performs the same
success invalidation.

Search uses no response cache. Approval, discussion, reaction, diff, project,
and unrelated account caches are not affected by title/description updates.

## UI plan

### Entry

- Add a labeled Edit toolbar action to the existing top-trailing native
  `ToolbarItemGroup` for both issue and MR detail.
- Keep Open in GitLab, Edit, and Add Comment in one native horizontal Liquid
  Glass group.
- The Edit accessibility hint distinguishes local draft/preview access from
  the ability to save.

### Editor

Use one native sheet and `NavigationStack`:

- title `TextField`;
- Edit/Preview segmented selection;
- raw Markdown `TextEditor` shown only in Edit mode;
- existing `GitLabMarkdownContentView` shown only in Preview mode;
- read-only, restoring-draft, saving, freshness-checking, conflict,
  validation, storage, definite-rejection, and delivery-unknown notices;
- Cancel and Save toolbar actions with stable accessibility identifiers;
- explicit discard confirmation for a dirty draft;
- keyboard dismissal, focus, and selection behavior that do not rewrite text.

Save is disabled while the draft is restoring, when unchanged or invalid,
for read-only access, during an operation, after delivery unknown until
reconciled, and during a conflict.

Preview is demand-driven and uses the current exact draft. Empty descriptions
show an empty-preview message instead of invoking the renderer.

### Accessibility and adaptive UI

- Labeled controls and error states must remain understandable without icon
  shape or color.
- Preserve logical VoiceOver order: title, mode selection, editor/preview,
  state notice, actions.
- Support accessibility Dynamic Type without clipping toolbar actions or
  hiding Save/Cancel.
- Announce save progress, conflict, failure, and success changes.
- Respect Reduce Motion for any editor/preview transition and Reduce
  Transparency for glass surfaces.

## Tests first

Before production implementation, add failing Swift Testing coverage for:

### Endpoint and decoding

1. Issue and MR update paths, `PUT`, mandatory write access, JSON content type,
   and OAuth/personal-token redaction.
2. Title-only, description-only, combined, explicit empty-description,
   Unicode, exactly 1,048,576-character, and over-limit input.
3. Omission of unchanged fields and prevention of an empty update.
4. Authoritative issue and MR decoding, including empty descriptions and
   changed `updated_at`.
5. Malformed response plus `400`, `401`, `403`, `404`, `409`, `422`, `429`,
   `5xx`, connectivity, cancellation, invalid-response, decoding, and
   transport failures.
6. Exactly one `PUT` attempt and no retry/backoff/reactive OAuth replay for
   ambiguous failures.

### Draft store

1. Account, host, resource-kind, project, and IID isolation.
2. Exact raw Unicode/Markdown/whitespace/empty-description round trips.
3. Monotonic revision protection against delayed older writes.
4. Returning to baseline removes the draft.
5. Corrupt, wrong-version, wrong-key, oversized, and storage-failure handling.
6. Redacted descriptions, hashed names, atomic replacement, complete file
   protection, intentional-account-removal cleanup, and authentication-expiry
   preservation.

### Editor model

1. Draft restoration before Save, local edits during a delayed restore, and
   failed draft persistence blocking transport.
2. Empty title, unchanged submission, exact maximum description, over-limit
   description, Unicode, and raw Markdown preservation.
3. Fresh baseline, updated-time-only rebase, untouched-title change,
   untouched-description change, locally edited title conflict, locally
   edited description conflict, both-field conflict, and result identity
   mismatch.
4. Successful authoritative reconciliation and draft removal.
5. Definite failures preserving an immediately retryable draft.
6. Delivery-unknown outcomes where the follow-up read proves success, proves
   no change, finds a conflict, fails, or is canceled.
7. Rapid duplicate Save taps, Cancel, view destruction, late preflight, late
   mutation, account switch, and superseding-operation stale-result rejection.
8. Read-only editing/preview with zero mutation calls.

### Projection and cache reconciliation

1. Detail, assigned list, Home, Todo, and global-search projection replacement
   by exact account/resource identity.
2. No insertion into projections where the resource was not already loaded.
3. Exact success invalidation sets for issue and MR.
4. No invalidation on failure, cancellation, conflict, or delivery unknown
   before success is proven.
5. An older in-flight exact-key read cannot repopulate invalidated content.
6. Reconciliation for account A cannot change account B.

### Markdown and performance

1. Preview uses the existing renderer and exact source.
2. Switching back to Edit does not parse again without a content change.
3. Existing Markdown parser/render performance fixtures remain within their
   budgets.
4. Draft serialization, validation, and preview of representative long and
   maximum-boundary content do not synchronously parse on the main actor or
   create an unbounded render cache.

## Verification matrix

### Automated

- Focused endpoint, service, draft, editor-model, detail-model, projection,
  cache, authentication, mutation-certainty, and Markdown tests.
- Complete normally signed, serialized test suite on the iOS 26.5 iPhone 17
  Pro Simulator.
- Existing Markdown performance fixtures run serially on the matching iOS
  26.5 runtime.
- Release Simulator build.
- Xcode static analyzer.
- `git diff --check`, privacy manifest and Info.plist validation, credential
  scans, configured-secret scans, forbidden logging/forced-cast/forced-try
  scans, and tracked-file review.

All builds and tests reuse
`/Volumes/hulk/dev/projects/glab/.deriveddata/Glab`. Temporary isolated build
data is allowed only to diagnose a proven cache/tooling problem and must be
deleted immediately afterward.

### Simulator

Use only the configured self-managed read-only account on the iOS 26.5
iPhone 17 Pro Simulator. Do not install on or test the owner's physical
device, and do not perform a live GitLab mutation.

Verify and visually inspect:

- issue and MR Edit entry in the shared toolbar group;
- exact initial title/Markdown, editing, preview, cancel, draft persistence,
  restored draft, explicit discard, and unchanged state;
- read-only explanation and disabled Save with zero network mutation;
- empty, short, long, Unicode, table, task-list, code-block, link, and image
  Markdown previews;
- keyboard interaction and scrolling;
- loading, storage failure, validation, freshness failure, conflict,
  permission, delivery-unknown, and success presentations using deterministic
  model/view fixtures where live mutation is prohibited;
- light and dark appearance;
- regular and accessibility Dynamic Type;
- VoiceOver labels/order;
- Reduce Motion and Reduce Transparency.

Tap through Home, assigned issue/MR lists, Todos, global search, deep links,
details, comments, reactions, and diff entry after the change to detect
integration regressions.

## Ordered implementation

1. Commit and push this plan.
2. Add failing endpoint and validation tests.
3. Implement the explicit issue and MR `PUT` endpoint bodies.
4. Add failing edit-draft store tests.
5. Implement the minimum account/resource-scoped protected draft store and
   AppSession lifecycle integration.
6. Add failing editor-model freshness, conflict, delivery, cancellation,
   account, and reconciliation tests.
7. Implement the shared edit value types, service, and model.
8. Add failing detail/list/Home/Todo/search reconciliation and cache
   invalidation tests.
9. Implement authoritative projection reconciliation without a shared state
   repository.
10. Add the shared editor UI and both detail toolbar entries.
11. Run focused tests after each slice and push small verified commits to
    `master`.
12. Run the full automated and Simulator verification matrix.
13. Perform the required deep review.

## Deep-review checklist

Review every P3-02 change for:

- bugs and incorrect GitLab endpoint assumptions;
- accidental empty or over-broad updates;
- raw Markdown, Unicode, whitespace, or empty-description corruption;
- false-negative conflicts, false-positive conflicts, or unacknowledged
  preflight/`PUT` race claims;
- unsafe retry after ambiguous delivery;
- lost, cross-account, cross-host, cross-resource, or stale drafts;
- authoritative-response identity mistakes;
- stale detail/list/Home/Todo/search state or over-broad cache invalidation;
- duplicated issue/MR endpoint, editor, validation, persistence, or
  reconciliation logic;
- incorrect state ownership or a feature-spanning state repository;
- main-actor parsing, length counting on every keystroke, unbounded caching,
  or unnecessary full-document copies;
- late-response, cancellation, duplicate-submit, account-switching, and
  draft-write races;
- secret exposure in files, keys, descriptions, errors, logs, screenshots, or
  fixtures;
- read-only, permission, authentication, accessibility, Dynamic Type, Reduce
  Motion, or Reduce Transparency regressions;
- bad code or code that needs refactoring.

Record every finding in this document.

If anything material is found:

1. Write and commit a repair plan before editing production code.
2. Add regression or performance tests where applicable.
3. Implement every repair.
4. Repeat the full relevant automated and Simulator verification.
5. Perform and record a second deep review.
6. Continue until no material finding remains.

P3-02 and its checklist in `docs/MVP_PHASE_3.md` may be marked complete only
after the review record and exact verification evidence are recorded here.

## Non-goals

- Editing labels, assignees, reviewers, milestones, status, state, or any
  field other than title and description.
- Creating issues or merge requests.
- Interactive task-list toggles; P3-03 must reuse this mutation path.
- Discussion resolution; P3-04 owns it.
- Server-side Markdown rendering, a new parser, or live preview on every
  keystroke.
- Automatic Markdown merge, generic diff3, or an "overwrite anyway" shortcut.
- A generic CRUD repository, app-wide normalized resource database, offline
  mutation queue, background sync engine, or automatic write retry.
- Live writes with the configured read-only token or any physical-device test.
