# P2-07 Engineering Plan — Inline Diff Discussions

Last updated: 2026-07-28

Status: planned; implementation has not started.

Glab has not shipped. Breaking internal APIs, draft identifiers, model
initializers, and cache formats are acceptable when they make positional
comments safer or the implementation smaller. Verification will use only an
iPhone 17 Pro Simulator. Live requests will use the configured self-managed
read-only token; POST behavior will be verified with deterministic transports,
not against a real account.

## Outcome

A user can:

- See a compact marker on every loaded diff line that has a discussion.
- Open current threads without expanding every comment inside the scrolling
  code surface.
- Find outdated or otherwise unmapped diff threads instead of having them
  silently disappear.
- Read Markdown comments and emoji reactions using the existing shared
  components.
- Reply to an existing thread and, with write access, start a discussion on an
  exact added, deleted, or context line.
- Keep a line-specific draft through dismissal, validation failure,
  cancellation, or an ambiguous network result.

Glab must never attach or POST a comment to a guessed line or diff version.

## Source of truth

The plan is based on GitLab's official documentation, reviewed on 2026-07-28:

- [Discussions API](https://docs.gitlab.com/api/discussions/)
- [Merge requests API](https://docs.gitlab.com/api/merge_requests/)
- [Merge request diff versions](https://docs.gitlab.com/user/project/merge_requests/versions/)

Important API facts:

- Existing threads are read with
  `GET /projects/:id/merge_requests/:merge_request_iid/discussions`.
- A positional note includes `base_sha`, `start_sha`, `head_sha`,
  `position_type`, `old_path`, `new_path`, and applicable old/new line
  numbers.
- A text-position POST requires the three version SHAs, both paths, and
  `position_type=text`.
- An added line sends only `new_line`; a deleted line sends only `old_line`;
  a context line sends both.
- A new positional thread is created with
  `POST /projects/:id/merge_requests/:merge_request_iid/discussions`.
- A reply remains
  `POST /projects/:id/merge_requests/:merge_request_iid/discussions/:discussion_id/notes`
  and does not repeat the position.
- GitLab documents retrieving the latest diff version before creating a
  positional discussion. `GET .../versions` is ordered newest first and
  exposes `base_commit_sha`, `start_commit_sha`, and `head_commit_sha`.
- Incorrect or obsolete position parameters can be rejected by GitLab.

The self-managed instance was sampled through the read-only token on
2026-07-28. The sampled merge request returned complete MR diff refs, a latest
version whose three SHAs matched those refs, 75 discussions, four positional
threads, and ten positioned notes. Every positioned note included the complete
SHA triplet and `position_type=text`. No token, host, path, comment body, or
commit SHA is recorded.

## Existing architecture audit

- MR detail already owns one `GitLabDiscussionsModel`, mutator, reaction
  service, API access value, account identity, and app session. The diff route
  should receive these dependencies rather than create a parallel discussion
  stack.
- `GitLabDiscussionPosition` currently decodes paths and lines but drops
  position type and all three SHAs.
- The discussion endpoint and service support non-positional creation and
  replies, but not version lookup or positional creation.
- The shared composer already provides target-specific drafts, pre-POST draft
  flushing, read-only rejection, cancellation handling, server-result
  reconciliation, and no automatic retry after delivery-unknown failures.
- Draft keys distinguish a general comment from a reply but cannot distinguish
  two new line comments.
- Shared discussion cards already render Markdown, replies, resolved state,
  diff context, and emoji reactions. Their useful subviews are private.
- The shared paginated model publishes a cached first page and loads later
  pages safely, but it has no explicit “load every remaining page” operation.
- The P2-06 viewer has immutable parsed lines with old/new numbers, stable
  file path-pair identity, exact account/MR/head cache identity, and a
  fixed-height virtualized `UICollectionView`.
- Visible diff cells currently receive only a render item. There is no
  per-line marker state or selection callback.
- MR responses already decode `diff_refs`, which usually provide the exact
  latest triplet. The versions endpoint is still required immediately before a
  write because the MR screen can become stale after a push.

## Architecture decision

Keep the existing MV architecture:

- Immutable, `Hashable`, `Sendable` version and line-position values.
- One O(1) discussion index derived from the shared discussion model.
- The existing MainActor discussion and composer models.
- One small version loader added to the existing discussion service.
- UIKit remains responsible only for virtualized code rows and taps; SwiftUI
  owns thread presentation and composition.

No coordinator, MVI store, TCA dependency, second discussion service, or
diff-only Markdown/reaction implementation is warranted.

## Exact version and line identity

### Diff version

Add `GitLabMergeRequestDiffVersionIdentity` containing:

- `baseSHA`
- `startSHA`
- `headSHA`

All values are normalized as nonempty strings at the API boundary. The value
is redacted in descriptions and is never logged.

Add a version response model for `/versions` with:

- server version ID
- `base_commit_sha`
- `start_commit_sha`
- `head_commit_sha`
- optional state

The current MR `diff_refs` maps to the same identity type. A head SHA alone is
not sufficient for a write.

### Line position

Add `GitLabDiffLinePosition` containing:

- exact diff version
- old path
- new path
- old line, when applicable
- new line, when applicable

Mapping rules:

| Diff row | `old_line` | `new_line` |
| --- | --- | --- |
| Addition | omitted | required |
| Deletion | required | omitted |
| Context | required | required |

Both paths are always retained, including for renamed files. Paths are not
duplicated onto parsed lines; the file view combines its selected file with a
visible `GitLabDiffLine` to create the identity in O(1).

A line position is valid only when:

- all three version SHAs are present;
- both paths are nonempty;
- its old/new line combination matches one of the three rules above; and
- line numbers are positive.

Invalid or partial positions remain decodable for forward compatibility but
cannot be indexed or posted.

## Existing discussion classification

Extend `GitLabDiscussionPosition` to decode:

- the three SHAs;
- `position_type`;
- existing paths and line numbers.

Use the root positioned note as the thread position. Replies may repeat the
position, but they do not create additional markers.

Build `GitLabDiffDiscussionIndex` once for a discussion content revision:

- `[GitLabDiffLinePosition: [GitLabDiscussion]]` for exact current positions;
- an ordered collection of outdated positional discussions;
- an ordered collection of current-version positions that cannot map to the
  loaded diff contract.

Construction is O(number of discussions). A visible row performs one
dictionary lookup. No cell may scan the discussion collection.

Classification:

- **Current**: the position's complete version identity equals the file
  viewer's exact version.
- **Outdated**: the position has a complete different version identity.
- **Unmapped**: the version is current but the position is partial, non-text,
  malformed, or references a line/path not present in loaded content.
- **Non-positional**: remains in the ordinary MR discussion section and is not
  shown as an inline marker.

Outdated and unmapped positional threads remain reachable from a compact
“Other diff discussions” control. They must never be attached to a nearby or
same-numbered line by guesswork.

## Pagination and ownership

Pass the existing MR `GitLabDiscussionsModel` through the changed-file and
file views.

Add a cancellation-aware `loadAllRemainingPages()` operation to the generic
paginated model:

- it loads the current trusted `nextPageURL` sequentially;
- it stops at `nil`, failure, cancellation, or a repeated next URL;
- it preserves all already-loaded items and existing failure semantics;
- it never fabricates page numbers or URLs.

The file screen starts this operation after its first render so an existing
marker can appear quickly from cached/loaded content while remaining pages
arrive. The index is rebuilt only when `contentRevision` or exact version
changes, not on scroll.

## Positional creation and stale-version safety

Add a positional composer target carrying `GitLabDiffLinePosition`.

Before a positional POST, the live service:

1. Loads the newest MR diff version from `/versions?per_page=1`.
2. Checks cancellation.
3. Requires its exact base/start/head identity to equal the composer's
   position identity.
4. Throws a typed `staleDiffVersion` rejection when they differ.
5. Encodes the nested `position` object and sends the discussion POST only
   after equality succeeds.

The client cannot make the check and POST atomic with a concurrent Git push.
GitLab remains the final validator; a server validation response is surfaced
as a rejected mutation. Glab will not automatically retry with a new position
because the same line number in another version may represent different code.

The general-comment and reply paths stay unchanged.

## Draft identity and reconciliation

Replace the draft key's optional `discussionID` with a target discriminator:

- general MR/issue comment;
- reply with discussion ID;
- positional comment with exact version, paths, and old/new line numbers.

This is an intentional breaking local format change. No migration or fallback
lookup will be added because no released build owns the prior format. File
storage continues hashing the complete identifier and using complete file
protection; model descriptions remain redacted.

On successful positional creation:

- reconcile the server `GitLabDiscussion` into the existing shared model;
- increment its existing content revision;
- rebuild the index from that revision;
- update only cells whose marker count changed;
- dismiss the composer and delete only that positional draft.

Replies use the current reconciliation path. Rejected, cancelled, and
delivery-unknown failures preserve the draft. A delivery-unknown result
continues to disable automatic resubmission until the user edits.

## UI plan

### Code surface

Keep the fixed-height virtualized rows introduced by P2-06.

- Add a compact orange bubble/count marker inside the line-number gutter.
- A row tap opens its current thread sheet when threads exist.
- With write access, the row also exposes an accessible “Comment on line”
  action.
- With read-only access, existing markers and threads remain readable but no
  mutation control is shown.
- Marker state and callbacks are passed to the coordinator and cell without
  retaining SwiftUI views or creating one hosting controller per row.

### Thread presentation

SwiftUI presents a sheet for a selected line:

- file and old/new line context;
- one collapsed summary per thread;
- expansion creates the shared discussion card lazily;
- shared Markdown, reaction, reply, draft, and composer behavior;
- current/outdated state stated in text and accessibility labels.

Expose the existing discussion card at internal scope and parameterize only
the small presentation differences needed here. Do not copy its note,
Markdown, or reaction body.

The file header shows a compact control when outdated or unmapped positional
threads exist. Its sheet uses the same collapsed thread component and clearly
labels why each thread is not attached to the current code.

Use Liquid Glass only for interactive marker/thread/composer controls where it
improves hierarchy. Code backgrounds, diff colors, and status text remain
ordinary content.

## Performance requirements

Correctness gates:

- Index construction is linear in discussion/note count.
- Visible line lookup is expected O(1).
- Scrolling does not decode API models, rebuild the index, render Markdown, or
  load reactions.
- Collapsed threads do not create Markdown or reaction requests.

Measure with:

- 50,000 diff lines;
- at least 500 inline threads distributed across the document;
- multiple discussions on one line;
- current, outdated, and unmapped positions;
- 600 deterministic scroll frames.

Budgets on the existing simulator test harness:

- p95 synthetic scroll-work time remains below 8 ms;
- no frame exceeds the harness's 16.67 ms budget;
- marker lookup performs no discussion scans;
- index rebuild p95 remains below 20 ms for 2,000 discussions;
- incremental marker reconciliation does not reload the entire document.

## Test plan

### Domain and decoding

- Complete and partial position decoding.
- Added, deleted, and context line identities.
- Renamed old/new path identity.
- Invalid zero/negative line and partial SHA rejection.
- Current, outdated, unmapped, non-text, reply, and non-positional
  classification.
- Multiple threads per line and root-position selection.
- Account, route, version, and path isolation.

### Endpoints and services

- Exact `/versions?per_page=1` request.
- Nested positional JSON for added/deleted/context lines.
- Exact old/new paths for renamed files.
- Latest-version match sends one POST.
- Changed base, start, or head SHA sends no POST and returns
  `staleDiffVersion`.
- Empty version response, decoding failure, server validation, authentication,
  connectivity, cancellation before version response, and cancellation before
  POST.
- No cache invalidation after failure/cancellation; discussion cache
  invalidation only after a successful POST.

### Models, drafts, and pagination

- Positional target restores only its own draft.
- Two lines, two versions, two accounts, and a general comment do not collide.
- Read-only target never invokes version lookup or POST.
- Successful create reconciles before deleting the exact draft.
- Rejected and delivery-unknown results preserve drafts and certainty.
- Replies remain position-free and reconcile into the selected thread.
- Load-all pagination termination, deduplication, failure retention, repeated
  next-URL defense, and cancellation.

### UI and accessibility

- Marker count/configuration and cell reuse reset.
- Selection callback receives the exact line identity.
- Current/outdated labels and read-only mutation absence.
- Collapsed threads do not instantiate Markdown/reaction work.
- Large Dynamic Type, VoiceOver labels, dark/light appearance, Reduce Motion,
  rapid navigation, and a simulated version change.

## Simulator and live verification

Use only an iPhone 17 Pro Simulator:

1. Build and run a deterministic write-capable fixture for added, deleted,
   context, renamed, multiple-thread, outdated, and stale-version states.
2. Tap markers, expand/collapse threads, open the shared composer, preserve
   drafts, post through the stub transport, and test replies/reactions.
3. Run read-only mode and verify no line-comment, reply, or reaction mutation
   control is available.
4. Use the self-managed read-only token to display real existing positional
   threads across paginated discussions. Do not invoke any live write.
5. Exercise rapid file changes/back navigation, Dynamic Type, light/dark
   appearance, and Reduce Motion.
6. Capture screenshots and inspect layout rather than relying only on
   automation assertions.

Shut down all simulators and quit Simulator after verification.

## Implementation sequence

Each implementation slice gets a focused test-first commit pushed to
`master`:

1. Exact version, position, decoding, endpoint, and draft identities.
2. Version validation and positional mutation service.
3. Load-all pagination and O(1) discussion index.
4. Virtualized line markers and thread presentation.
5. Shared composer/reply/reaction integration and reconciliation.
6. Performance harness, simulator verification, documentation, and review
   repairs.

Do not stage or modify the user's existing Xcode project signing/configuration
change.

## Non-goals

- Viewing an entire historical diff version.
- Multi-line range comments.
- Suggested code changes.
- Resolving/unresolving discussions.
- Editing or deleting notes.
- Draft-review batching or submitting a formal review.
- Live POST verification with the read-only token.
- Migration of pre-release draft files or internal model schemas.

## Deep-review gate

After implementation and simulator verification:

1. Review every P2-07 diff for wrong-SHA writes, off-by-one mapping, renamed
   paths, hidden outdated threads, pagination termination, main-actor work,
   cancellation, draft collisions, mutation certainty, account/version
   isolation, eager Markdown/reaction work, cell reuse, unbounded state,
   duplicate components, and unnecessary abstraction.
2. Record concrete findings below.
3. If anything material is found, write a repair plan before editing.
4. Add regression/performance tests, implement every repair, rerun focused and
   full tests plus static analysis, repeat simulator checks, and review again.

### Findings

Pending implementation.

### Repair plan

Pending review findings.
