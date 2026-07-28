# P3-03 Engineering Plan — Interactive Description Task Lists

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Production implementation: complete; repair pending
- Verification: in progress
- Deep review: in progress; one material finding

This is the required implementation plan for P3-03. It must be committed and
pushed before any P3-03 test or production code is changed.

## Outcome

A permitted user can select a complete or incomplete task marker in an issue
or merge-request description. Glab changes only the exact marker selected,
preserves every other source byte, updates the description through P3-02's
conflict-safe mutation path, and reconciles the authoritative issue or merge
request.

An inapplicable `[~]` task remains visibly inapplicable and read-only. Glab
must never toggle a marker when it cannot prove that the rendered control maps
to that exact marker in the current raw description.

## Scope decisions and assumptions

- P3-03 applies only to issue and merge-request descriptions. Task markers in
  comments remain static; editing comments is not part of this feature.
- Interactive syntax is an ordered or unordered Markdown list item whose
  first content is exactly `[ ]`, `[x]`, or `[X]`. Nested and blockquoted list
  items are supported. `[~]` is indexed and rendered accurately but never
  mutated.
- GitLab 18.9 added native task markers in Markdown table cells. Glab's
  declared self-managed floor is GitLab 15.5 and the current table model does
  not represent a semantic task cell, so table-cell tasks remain static.
- A task-like sequence in ordinary text, an escaped list marker, a fenced or
  indented code block, raw HTML that Glab cannot map safely, or malformed
  Markdown is never interactive.
- Only one task mutation may be active for a resource. A rapid second tap is
  disabled or ignored; Glab does not queue multiple full-description writes.
- A protected P3-02 edit draft already belonging to the resource blocks a
  direct task toggle. Glab explains that the user must finish or discard the
  draft in the editor. It never rewrites, merges, or removes that pre-existing
  draft.
- The server API remains authoritative for resource permissions. App-level
  `.readOnly` access disables the controls before transport. An OAuth or
  personal/project access token with `api` access passes the app-level gate,
  while GitLab may still return `403` or `404`.
- No undocumented GitLab web checkbox endpoint, private GraphQL mutation, or
  automatic textual merge is used.

## Existing-code audit

### Markdown parser and immutable render tree

- `GitLabMarkdownParser` uses Foundation `AttributedString(markdown:)` away
  from the main actor, converts presentation intents into an immutable
  `GitLabMarkdownDocument`, and checks cancellation while building the tree.
- `GitLabMarkdownTreeConverter` already recognizes `[x]`, `[X]`, `[ ]`, and
  `[~]` at the start of the first paragraph in a list item. It removes the
  marker from visible text and stores only `GitLabMarkdownTaskState`.
- The conversion intentionally loses the original source location. List and
  block identity currently uses array offsets, so duplicate task text cannot
  be distinguished for mutation.
- The parser removes HTML comments before Foundation parsing. Any new source
  index must apply equivalent exclusions or fail closed when its inventory
  does not match the rendered task sequence.
- `GitLabMarkdownDocument`, blocks, lists, and items are value-semantic and
  `Sendable`. P3-03 must preserve this immutable output; closures and mutable
  feature state do not belong in the parsed document.

### Renderer and cache

- `GitLabMarkdownRenderer` is an actor. It hashes the exact source UTF-8 bytes,
  coalesces identical renders, cancels unused work, bounds cached document
  count and source cost, and removes an older source variant only after a
  newer render completes.
- A successful description update naturally creates a new content digest.
  The existing renderer can replace the older resource variant without a new
  cache or invalidation subsystem.
- Optimistic task state must be a lightweight UI overlay. It must not mutate a
  cached document or synchronously reparse Markdown on tap.

### Current list UI

- `GitLabMarkdownListView` renders every task marker as a static SF Symbol and
  combines the item into one accessibility label.
- Complete and incomplete markers need accessible button semantics, minimum
  hit targets, checked state, progress/disabled state, and an injected action
  only in editable description contexts.
- `[~]`, comments, unsupported mappings, and read-only contexts remain
  nonmutating while retaining an accurate reading order and explanation.

### Issue and merge-request descriptions

- Both detail screens currently trim leading and trailing whitespace and pass
  the trimmed value to the renderer. A source offset from that value would not
  map to P3-02's exact raw description.
- P3-03 must use trimming only to decide whether the description is visibly
  empty. The Markdown request must receive the exact untrimmed API string.
- Issue and merge-request detail models already reconcile an authoritative
  result. Their loaded projections, Home, Todos, and search are updated
  through the shared P3-02 success callback.

### P3-02 mutation and draft safety

- `GitLabResourceEditing` owns the explicit issue/MR detail reads, description
  `PUT` endpoints, and exact affected-read invalidation.
- `GitLabResourceEditorModel` already owns the required transaction behavior:
  protected draft restoration, exact baseline comparison, direct freshness
  read, stable resource-identity validation, description conflict detection,
  one non-retried `PUT`, durable unknown-delivery state, `Check GitLab`,
  cancellation and account-generation checks, authoritative reconciliation,
  exact cache invalidation, and draft cleanup after success.
- The task-toggle model will compose that P3-02 model as its transaction owner.
  It will not call a second update endpoint or duplicate freshness,
  delivery-certainty, cache, or draft logic.
- Before placing its own desired description into the P3-02 model, it restores
  the protected edit draft. If the restored model is dirty or requires a
  delivery check, the task action stops without changing the draft.
- After a definite preflight or mutation failure, the toggle model clears its
  optimistic state and removes only the clean-baseline draft that this task
  action created. Unknown delivery preserves the P3-02 draft and exposes an
  explicit reconciliation action.

## Official GitLab contracts

### GitLab Flavored Markdown task lists

GitLab's
[Task lists](https://docs.gitlab.com/user/markdown/#task-lists)
documentation applies to Free, Premium, and Ultimate across GitLab.com,
GitLab Self-Managed, and GitLab Dedicated.

- Ordered and unordered list items can be complete (`[x]`), incomplete
  (`[ ]`), or inapplicable (`[~]`).
- Nested task lists are supported.
- Boxes are selectable in issues, merge requests, epics, and comments.
- Selecting an inapplicable task has no effect.

The documentation describes rendered behavior and source syntax, but does not
document a dedicated public REST task-toggle endpoint. P3-03 therefore updates
the containing description through the documented resource update APIs.

Native Markdown task syntax in table cells was introduced in GitLab 18.9.
That newer syntax is outside this feature's list-item interaction scope.

### Issue description update

GitLab's
[Update an issue](https://docs.gitlab.com/api/issues/#update-an-issue)
contract uses:

`PUT /projects/:id/issues/:issue_iid`

`description` is an optional update attribute limited to 1,048,576
characters. The endpoint returns the authoritative updated issue.

### Merge-request description update

GitLab's
[Update a merge request](https://docs.gitlab.com/api/merge_requests/#update-a-merge-request)
contract uses:

`PUT /projects/:id/merge_requests/:merge_request_iid`

`description` is an optional update attribute limited to 1,048,576
characters, at least one non-path update attribute is required, and the
endpoint returns the authoritative updated merge request.

### Permissions and concurrency

GitLab's
[project planning permissions](https://docs.gitlab.com/user/permissions/#project-planning)
document role-dependent issue editing, including narrower author/assignee
conditions for Guest users. Glab does not reproduce this evolving matrix.

Neither description update endpoint documents a revision precondition or
transactional compare-and-swap. P3-03 inherits P3-02's direct preflight and
known-conflict refusal, while accurately retaining the unavoidable race
between that read and GitLab accepting the `PUT`.

## Source identity and byte-preserving rewrite

### Task source identity

Add a small value-semantic `GitLabMarkdownTaskSourceID` containing:

- a SHA-256 digest of the exact source UTF-8 bytes; and
- the UTF-8 byte offset of the opening `[` for the task marker.

The task item separately carries its parsed state. Identity and debug
descriptions contain no task text, surrounding Markdown, project path, user
content, or credential.

Use one source-digest helper for both renderer cache identity and task source
identity so hashing rules cannot diverge.

### Source index

Add a deterministic, cancellation-aware source indexer that scans the exact
original UTF-8 source off the main actor. It records candidates in source
order and recognizes:

- `-`, `*`, and `+` unordered markers;
- CommonMark ordered markers followed by `.` or `)`;
- nested indentation and blockquote container prefixes;
- `[ ]`, `[x]`, `[X]`, and `[~]` immediately after the list marker and its
  required whitespace;
- LF, CRLF, and mixed line endings without normalization.

It excludes HTML comments, fenced code, escaped or malformed list syntax,
inline task-like text, and source that cannot be proven to be an ordinary
list task. Indented-code and raw-HTML ambiguity must fail closed rather than
create a potentially wrong control.

After Foundation builds the render tree, compare the complete ordered sequence
of rendered task states with the indexed source candidates. Attach source
identities only when the sequences match exactly. If count, state, ordering,
or supported-container interpretation differs, retain static task rendering
for that document. Never guess a partial mapping.

This sequence validation makes repeated labels safe: identity comes from the
unique source byte offset, not visible text.

### Rewrite

Add a pure source rewriter that accepts the exact source, source identity,
expected current state, and desired state.

1. Recompute and verify the content digest.
2. Validate the UTF-8 offset and the complete three-byte marker.
3. Re-index or otherwise prove the marker is still a supported task location.
4. Reject `[~]`, a no-op state, a stale digest, an invalid offset, malformed
   UTF-8, or any marker/state mismatch.
5. Replace only the marker's middle ASCII byte:
   - `[ ]` becomes `[x]`;
   - `[x]` or `[X]` becomes `[ ]`.
6. Decode and return the rewritten UTF-8 as a String.

Tests compare the original and result as bytes, allowing only that single
middle-byte difference. Whitespace, indentation, list marker, case outside
the toggled byte, Unicode, links, comments, trailing spaces, line endings, and
all unrelated Markdown remain exact.

## Task-toggle state and mutation flow

Add one `@MainActor @Observable` model per visible issue or merge-request
detail. It owns presentation state for at most one active task and composes a
transient `GitLabResourceEditorModel` for the transaction.

### Start

1. Receive the current authoritative `GitLabResourceEditSnapshot`, selected
   source identity, and parsed current state.
2. Reject read-only access, `[~]`, an already active operation, a stale
   account, or a local source mismatch before transport.
3. Rewrite the exact raw description off the main actor.
4. Construct the P3-02 editor model from that exact snapshot and restore its
   protected draft before changing any value.
5. If a dirty or unknown-delivery draft already exists, leave it byte-for-byte
   untouched, clear the optimistic toggle, and show a "Finish saved draft"
   explanation.
6. Otherwise assign only the rewritten description, retain the exact title,
   and call the existing P3-02 Save transaction.

### Optimistic presentation

- Once the rewrite is validated, show the desired marker state immediately
  for that source identity and display compact progress.
- Keep every other marker unchanged and disable all task actions for that
  resource until the operation resolves.
- Do not alter the cached document. A definite failure clears the overlay;
  authoritative success replaces the resource source and render document.
- Do not add automatic animation; native state updates must remain usable
  with Reduce Motion.

### Success

P3-02 validates the returned target and stable resource ID, invalidates exact
affected reads, invokes the typed authoritative callback, updates the detail
and loaded projections, removes its protected draft, and completes. The
toggle model then clears its transient operation and optimistic overlay.

### Known stale source

- If the selected source digest or marker no longer matches the current detail
  snapshot, send no request, refresh the resource, and explain that the
  description changed.
- If P3-02's direct preflight finds that the server description differs from
  the baseline, send no `PUT`, roll back the optimistic state, remove only the
  draft created for this attempted toggle, refresh, and show the same stale
  explanation.
- A title-only server change is accepted by P3-02's rebase and is not a false
  description conflict.

### Definite failure

Validation, read-only access, draft storage failure, freshness failure,
documented rejection, or known conflict sends zero additional writes. The
toggle rolls back and reports a redacted, actionable failure. A retry is
always a new explicit tap and repeats source validation plus the full
preflight.

### Unknown delivery

- Never automatically retry.
- Preserve the exact P3-02 protected draft and intended description.
- Keep the affected marker visibly pending and disable all task writes.
- Present `Check GitLab`, which uses P3-02's uncached reconciliation read.
- If GitLab contains the intended description, reconcile as success.
- If GitLab still contains the baseline, clear unknown-delivery state and
  offer an explicit retry; do not retry automatically.
- If GitLab contains a third description, preserve the draft, refresh the
  visible resource, and direct the user to the existing editor to review the
  conflict.
- Relaunch or detail reconstruction restores the durable marker through the
  same P3-02 draft contract before another write can occur.

## Refresh, cancellation, and account behavior

- A monotonically increasing toggle generation rejects late rewrite,
  restoration, save, reconciliation, and refresh results.
- Detail disappearance cancels the owned operation. If transport may have
  started, P3-02's marker was persisted before transport and remains delivery
  unknown.
- An account switch destroys the account-scoped view tree and
  `isAccountCurrent` prevents a late result from publishing to the next
  account.
- Refresh during a toggle cannot overwrite authoritative success: P3-02
  invalidation cancels the older exact-key read before it can repopulate
  response state.
- A refreshed description with a different digest creates a new renderer
  request and invalidates old source identities. A tap from an older rendered
  document fails local source validation.
- Protected drafts, task operation state, cache keys, and callbacks remain
  account, host, resource-kind, project, IID, and stable-resource-ID scoped.

## UI and accessibility plan

### Description task controls

- Replace the static marker with a borderless button only when a complete or
  incomplete task has a proven source identity in an issue/MR description.
- Preserve the current 24-point marker column and list alignment while giving
  the control at least a 44-by-44-point hit target without adding a large
  visible bubble.
- Use the existing square/checkmark symbols and orange accent. Do not rely on
  color alone.
- Expose the item text, checked/unchecked value, Button trait, and an action
  hint. Keep nested list reading order unchanged.
- `[~]` remains a static minus-square with the value "Inapplicable" and an
  explanation that it cannot be changed.
- Read-only and unsupported mappings remain static/disabled with an accurate
  accessibility explanation and no transport.
- While one task is active, the selected marker shows compact progress or a
  pending state; other controls explain that another task update is in
  progress.

### Status and recovery

Use a compact inline notice in the Description section for:

- read-only access when interactive tasks are present;
- a protected edit draft that must be finished first;
- stale-description refresh;
- definite save failure;
- delivery unknown with `Check GitLab`;
- reconciliation showing "not changed" with explicit retry; and
- conflict directing the user to the existing editor.

Notices and actions must scale at accessibility Dynamic Type without
obscuring the description. VoiceOver focus should remain near the selected
task or move to the actionable notice. No new floating control or permanent
screen-level chrome is added.

## Cache and reconciliation

- Successful normal and ambiguous-proven updates use
  `GitLabResourceEditorModel.completeSuccess`, so P3-02 remains the only owner
  of exact response-cache invalidation.
- Issue success invalidates exact issue detail, assigned issue reads, the Home
  issue preview, and exact Todo queries. MR success invalidates exact MR
  detail, assigned/review lists, Home MR/review previews, and exact Todo
  queries.
- The typed success callback reconciles the current detail and already loaded
  list, Home, Todo, and global-search projections.
- No response cache is invalidated on source mismatch, read-only denial,
  preflight conflict, definite failure, cancellation before mutation, or
  unresolved unknown delivery.
- The Markdown renderer's exact-source digest creates the new document. Its
  existing bounded replacement policy removes the old resource variant after
  successful parsing.

## Tests first

### Fixtures

Add exact-source fixtures for:

1. simple unordered and ordered complete/incomplete/inapplicable tasks;
2. `-`, `*`, `+`, ordered `.` and `)` markers, and uppercase `[X]`;
3. nested tasks at multiple indentation levels;
4. tasks in one or more blockquotes;
5. duplicate visible labels with different source offsets;
6. Unicode before, inside, and after tasks, including composed/decomposed
   characters and emoji;
7. LF, CRLF, mixed line endings, trailing spaces, and no final newline;
8. comments, fenced and indented code, inline markers, escaped markers,
   table-cell tasks, raw HTML, and malformed task syntax;
9. a very long task line, a document near the description limit, and a large
   document with many tasks.

### Source index and rewrite

Write failing tests proving:

1. every supported rendered task receives the correct source digest, byte
   offset, and state;
2. nested, quoted, repeated, Unicode, and mixed-line-ending tasks retain
   stable identities for the same exact source;
3. `[~]` is indexed but cannot be rewritten;
4. unsupported, ambiguous, mismatched, stale-digest, wrong-offset, wrong-state,
   no-op, and malformed inputs fail without a modified string;
5. complete-to-incomplete and incomplete-to-complete replacement changes
   exactly one expected byte;
6. `[X]` becomes `[ ]`, while unrelated casing is preserved;
7. every unrelated byte, including line endings and trailing whitespace,
   remains identical;
8. an index/render sequence mismatch leaves all tasks static rather than
   attaching a guessed source identity;
9. task identity descriptions and mirrors redact source content.

### Parser, renderer, and cache

Write failing tests proving:

1. immutable documents preserve existing task states and gain source identity
   only for exact safe mappings;
2. the exact untrimmed API description is the render and task source;
3. duplicate labels remain distinct in the UI model;
4. optimistic state does not modify a cached document;
5. a new source digest replaces the old bounded resource variant only after
   the new render completes;
6. comments and existing non-description Markdown remain static and
   behaviorally unchanged.

### Toggle model and P3-02 transaction

Write failing tests for:

1. issue and MR incomplete-to-complete and complete-to-incomplete success;
2. description-only transport with exact title preservation;
3. zero transport for read-only access, `[~]`, source mismatch, malformed
   identity, no-op, or an existing protected edit draft;
4. a title-only server change rebasing successfully;
5. stale descriptions, resource-identity mismatch, refresh during rewrite,
   refresh during preflight, and an old rendered task tapped after refresh;
6. duplicate labels selecting only the tapped source location;
7. rapid repeated taps and taps on two tasks producing at most one mutation;
8. optimistic state, definite-failure rollback, and cleanup of only the draft
   created by the task action;
9. draft storage failure before transport;
10. `400`, `401`, `403`, `404`, `409`, `422`, `429`, `5xx`, connectivity,
    cancellation, invalid response, decoding failure, and delivery certainty;
11. unknown delivery restored after model destruction, check proving success,
    check proving no server change, third-value conflict, failed check, and
    explicit retry;
12. cancellation before and during transport, detail disappearance, late
    results, account switch, and another account with the same project/IID;
13. authoritative detail/list/Home/Todo/search reconciliation and exact cache
    invalidation only after identity-validated success.

### Performance

Run serialized Simulator performance tests for:

- source indexing alone;
- source identity validation and one-byte rewrite;
- Markdown first parse/render;
- warm renderer cache;
- toggle-model preparation without transport; and
- repeated state lookup while scrolling.

Use representative small, 100-KB-plus, and near-1-MiB sources. Establish and
record release/debug budgets after measuring the first test-only indexer
implementation, before production UI wiring. The required invariants are:

- index and rewrite never run on the main actor;
- one tap performs no synchronous Markdown reparse;
- work is linear in source bytes, not task-count multiplied by source size;
- no unbounded source, document, identity, or optimistic-state cache exists;
- the existing Markdown performance budgets do not regress; and
- fast scrolling does not repeatedly rebuild the source index.

## Verification matrix

### Automated

- Focused source-index, rewrite, parser, renderer, cache, toggle-model,
  P3-02 editor/service, detail/projection, draft, authentication, mutation
  certainty, cancellation, and performance tests.
- Complete normally signed, serialized suite on the iOS 26.5 iPhone 17 Pro
  Simulator.
- Release Simulator build and Xcode static analysis.
- `git diff --check`, Info.plist/privacy validation, tracked-file review,
  Release-bundle environment/credential scans, configured-secret scans, and
  new forced-operation/ad-hoc logging scans.

Reuse `/Volumes/hulk/dev/projects/glab/.deriveddata/Glab` for every build,
test, and analysis action.

### Simulator

Use only the iOS 26.5 iPhone 17 Pro Simulator. Do not install on or test a
physical device.

Verify and visually inspect:

- issue and MR simple, nested, blockquoted, repeated-label, Unicode, long, and
  mixed-line-ending task lists;
- complete/incomplete toggles, compact progress, rapid taps, refresh, relaunch,
  rollback, stale explanation, protected-draft block, and unknown-delivery
  recovery;
- `[~]`, comments, malformed/unsupported mappings, and read-only accounts
  remaining nonmutating;
- exact authoritative state after pull-to-refresh and navigation away/back;
- light and dark appearance;
- regular and accessibility Dynamic Type;
- VoiceOver label, value, trait, hint, focus, and list reading order;
- Reduce Motion and Reduce Transparency; and
- fast scrolling through a large task list with no visible hitch or repeated
  formatting loop.

The configured `GITLAB_API_TOKEN` remains read-only and may be used only for
broader live read verification.

The owner explicitly provided `DEVOPS_DEMO_TOKEN` for one demo project with
Developer permissions. Live mutation verification may use it only after all
stubbed tests pass and only under these safeguards:

1. Resolve the exact permitted host and project with read-only requests
   without printing the token or response content that could contain secrets.
2. Never modify an existing human-authored issue or merge request.
3. Create one isolated, unassigned verification issue with no user, group,
   reviewer, or human mention and a neutral task-list description.
4. Do not trigger, retry, cancel, or otherwise interact with a pipeline.
5. Exercise only description task toggles through the app.
6. Restore/record the final description and close the temporary issue after
   verification. Closing is recoverable; do not delete it.
7. If the token, project, or disposable target cannot be identified
   positively, perform no live write and rely on deterministic fakes.
8. Never print, log, commit, screenshot, bundle, or place either token in a
   launch argument, fixture, source file, test result, or process-list-visible
   command.

## Ordered implementation

1. Commit and push this plan.
2. Add the exact-source fixtures and failing task-index/rewrite tests.
3. Implement the minimum source digest, task source identity, index, and pure
   rewrite.
4. Add failing parser/renderer mapping and fallback tests.
5. Attach safe source identities to the immutable render tree without changing
   comment behavior.
6. Add failing task-toggle model tests for P3-02 reuse, drafts, conflicts,
   delivery certainty, cancellation, accounts, reconciliation, and rapid taps.
7. Implement the focused toggle model by composing
   `GitLabResourceEditorModel`.
8. Add the issue/MR description interaction and compact accessible task
   controls. Pass the exact untrimmed description to Markdown.
9. Add and run performance tests, record budgets, and repair any regression
   before broader UI verification.
10. Push small verified commits to `master` after each coherent slice.
11. Run the complete automated and Simulator verification matrix.
12. Perform the required deep review.

## Deep review pass 1 — material finding and repair plan

Date: 2026-07-28

The review reproduced one unsafe source-mapping case:

```markdown
<pre>
- [ ] scanner-only marker
</pre>
-
  [ ] rendered multiline task
```

Foundation treats the raw HTML block as unstructured content and renders the
second list item as the only task. The source scanner currently indexes the
marker inside `<pre>` and does not index the multiline marker. Both ordered
state sequences therefore contain one incomplete task, so sequence equality
alone attaches the raw-HTML marker identity to the visible multiline task. A
tap could rewrite the wrong source byte.

This violates the fail-closed raw-HTML rule, even though ordinary count or
state mismatches already remain static.

### Committed repair plan

1. Add a regression fixture and parser test for the exact false-positive plus
   false-negative combination. Prove that the rendered task receives no
   source identity and the document exposes no mutable task.
2. Add source-index tests for raw HTML before, between, and after otherwise
   supported task lists, including closing tags and HTML-like content inside
   fenced code.
3. Make the source scanner conservatively return no task identities when it
   encounters an unsupported raw HTML tag outside fenced code and masked HTML
   comments. Do not attempt to implement a second HTML parser. Preserve normal
   task mapping for HTML-like content inside fenced code and for comments that
   are already excluded from both source and rendered task inventories.
4. Keep rewrite validation on the same scanner path so a fabricated or stale
   identity cannot bypass the new fail-closed rule.
5. Rerun source-index, rewrite, parser, renderer, toggle-model, P3-02
   transaction, complete-suite, Release, Analyze, privacy, and serialized
   performance gates.
6. Repeat dark/light, Dynamic Type, accessibility, Reduce Motion/Transparency,
   read-only, and permitted demo-project Simulator verification. Confirm raw
   HTML descriptions show only static task markers.
7. Perform and record another full P3-03 review before marking the feature
   complete.

## Deep-review checklist

Review every P3-03 change for:

- bugs and incorrect GitLab task or update assumptions;
- a rendered task mapped to the wrong source marker;
- duplicate-label, nested-list, blockquote, Unicode, or byte-offset mistakes;
- whitespace, indentation, case, line-ending, or unrelated Markdown
  corruption;
- `[~]`, comments, code, HTML, table cells, or malformed syntax becoming
  accidentally interactive;
- duplicated P3-02 endpoint, freshness, conflict, delivery, draft, cache, or
  reconciliation logic;
- a pre-existing edit draft being changed or removed;
- stale source, false or missed conflicts, unsafe retry, or unknown-delivery
  loss;
- optimistic UI diverging from the authoritative response or failing to roll
  back;
- rapid-tap, cancellation, refresh, late-result, disappearance, and
  account-switch races;
- parsing, indexing, hashing, or rewriting on the main actor;
- repeated full-document work, quadratic behavior, unbounded caches, excess
  source copies, or scrolling regressions;
- incorrect state ownership or one model spanning unrelated resources;
- read-only, permission, authentication, accessibility, Dynamic Type, Reduce
  Motion, or Reduce Transparency regressions;
- secret or private source exposure in identity, files, errors, logs,
  screenshots, fixtures, commands, or bundles;
- notification-causing human mentions or unintended demo-project mutations;
- bad code, duplicated code, or code that needs refactoring.

Record every finding in this document.

If anything material is found:

1. Write and commit a repair plan before editing production code.
2. Add regression or performance tests where applicable.
3. Implement every repair.
4. Repeat the full relevant automated and Simulator verification.
5. Perform and record another deep review.
6. Continue until no material finding remains.

P3-03 and its checklist in `docs/MVP_PHASE_3.md` may be marked complete only
after exact verification evidence and the final review result are recorded
here.

## Non-goals

- Editing task markers in comments, discussion notes, epics, tasks/work items,
  milestones, snippets, repository Markdown files, wiki pages, or releases.
- Interactive table-cell task markers introduced in GitLab 18.9.
- Changing `[~]` inapplicable tasks.
- Adding, deleting, reordering, or editing task text.
- Editing title or any metadata as part of a toggle.
- A dedicated/undocumented task-toggle API or private GitLab web endpoint.
- Concurrent or queued full-description writes.
- Automatic textual merge, overwrite-anyway, offline mutation queue,
  background sync, or automatic retry.
- A new Markdown parser, mutable render document, unbounded source index, or
  live reparse on every state change.
- Discussion resolution, issue creation, labels, status, assignees, approvals,
  pipelines, or any later Phase 3 feature.
