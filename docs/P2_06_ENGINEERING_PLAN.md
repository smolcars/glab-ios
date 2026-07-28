# P2-06 Engineering Plan — Performant Merge Request Diff Viewer

Last updated: 2026-07-28

Status: planned; production implementation has not started.

Glab has not shipped. Breaking internal APIs, model initializers, and cache
formats are acceptable when they make the viewer smaller, safer, or measurably
faster. This milestone is read-only. It will use only an iPhone 17 Pro
Simulator and the configured self-managed `read_api` token for live
verification.

## Outcome

A signed-in user can:

- Open a Changed Files screen from a merge request.
- Browse the changed-file list page by page.
- Open and render one file at a time without parsing every file in the merge
  request.
- Read old/new line numbers, additions, deletions, context, hunk headers, and
  missing-newline markers in a fixed-width presentation.
- Scroll long lines horizontally, jump between hunks, and select code where
  practical.
- Understand added, deleted, renamed, generated, collapsed, too-large, and
  otherwise unavailable file states.
- Return quickly to a recently parsed file without accepting stale content
  from a previous account or head SHA.

## Source of truth

The plan is based on GitLab's official documentation, reviewed on 2026-07-28:

- [Merge requests API](https://docs.gitlab.com/api/merge_requests/)
- [REST API pagination](https://docs.gitlab.com/api/rest/#pagination)
- [REST API deprecations](https://docs.gitlab.com/api/rest/deprecations/)
- [Diff limits administration](https://docs.gitlab.com/administration/diff_limits/)
- [Changes in merge requests](https://docs.gitlab.com/user/project/merge_requests/changes/)
- [Merge request diff versions](https://docs.gitlab.com/user/project/merge_requests/versions/)

Important API facts:

- The supported endpoint is
  `GET /projects/:id/merge_requests/:merge_request_iid/diffs`.
- The older `/changes` endpoint was deprecated in GitLab 15.7 and is scheduled
  for removal in API v5. Glab will not call it.
- `/diffs` is offset-paginated. `per_page` may be at most 100, and GitLab says
  clients should follow returned pagination links rather than synthesize later
  URLs.
- Each item can contain `old_path`, `new_path`, old/new modes, `diff`,
  `new_file`, `renamed_file`, `deleted_file`, `generated_file`, `collapsed`,
  and `too_large`.
- `generated_file` became generally available in GitLab 16.11.
- `collapsed` and `too_large` were introduced in GitLab 18.4. Older
  self-managed responses can legitimately omit them.
- A collapsed diff was excluded but might be expanded by GitLab. A too-large
  diff was excluded and cannot be retrieved through the ordinary viewer.
- The endpoint is subject to instance diff limits. Self-managed defaults
  include a 200 KB total patch limit, 1,000 files, and 50,000 changed lines;
  administrators can raise these limits.
- A single merge-request response exposes `sha` and latest `diff_refs`.
  `diff_refs.head_sha` identifies the latest MR diff head. New merge requests
  can have empty `diff_refs` and `changes_count` while GitLab prepares them.
- `changes_count` is a string and may be capped as `"1000+"`.

The current self-managed instance was sampled through the read-only token on
2026-07-28. It reports GitLab 18.11.3-ee. A recent accessible merge request
returned a populated `sha`, `diff_refs`, four paginated `/diffs` file objects,
and all documented status flags. No source text, credential, project name, or
request header is recorded in this document.

## Existing architecture audit

Relevant current behavior:

- `GitLabMergeRequestRoute` already provides stable project ID and MR IID.
- `GitLabMergeRequest` does not yet decode `sha`, `diff_refs`, or
  `changes_count`.
- `GitLabMergeRequestDetailView` owns the detail and discussion models and is
  reached from both Home and Todos inside an existing `NavigationStack`.
- The detail body uses `ScrollView` plus `LazyVStack`; there is no diff route
  or UIKit bridge.
- `GitLabPaginatedResourceModel` already provides cached-first publication,
  trusted next-page loading, deduplication, cancellation-safe state, retry, and
  retained content after refresh failure.
- `GitLabSessionClient` caches GET responses by account and normalized request
  URL, coalesces identical reads, and trusts only same-host HTTPS pagination
  links.
- `FileGitLabResponseCache` has a global 25 MiB LRU capacity, hashes filenames,
  isolates account directories, and applies file protection.
- The first page of a new diff list can reuse that response cache. Later
  pagination pages currently remain network-only.
- The Markdown renderer demonstrates a bounded actor-owned LRU, in-flight
  request sharing, per-waiter cancellation, stale-variant removal, and an
  off-main parser seam.
- The app builds in Swift 6 with complete strict concurrency, approachable
  concurrency, and default MainActor isolation. CPU-heavy parsing therefore
  needs an explicit nonisolated `@concurrent` boundary.
- New SwiftUI controls can use Liquid Glass, but static code rows and status
  badges should remain ordinary content.

## Architecture decision

Keep the app's existing MV architecture:

- Immutable, `Sendable` API and parsed domain values.
- A small read-only service for `/diffs`.
- A MainActor observable paginated file-list model.
- A stateless off-main parser.
- A bounded actor-owned parsed-document cache/renderer.
- SwiftUI views that express model state and own navigation-local models.

MVI, TCA, and a new coordinator do not solve a pressure present in this slice.
A UIKit bridge is a rendering implementation detail, not a new feature
architecture. It will be introduced only if measured SwiftUI behavior misses
the budgets below.

## API and revision identity

### Merge request revision

Extend the MR contract with optional:

- `sha`
- `diffRefs.baseSHA`
- `diffRefs.startSHA`
- `diffRefs.headSHA`
- `changesCount`

Expose one normalized `diffHeadSHA`:

1. Trim whitespace from `diff_refs.head_sha` and use it when non-empty.
2. Otherwise trim and use `sha`.
3. Otherwise return `nil`.

An absent head SHA means GitLab is still preparing changes or did not supply
the revision. The app will show a preparing/unavailable state and will not
create a revisionless parsed-cache entry.

### Diff list endpoint

Add a read-only endpoint with:

- Exact route components under `/diffs`.
- `per_page=20`.
- No use of `/changes`, `/raw_diffs`, or `access_raw_diffs`.

Twenty files bounds decoded source retained by each page and matches GitLab's
documented default. The first slice does not require `unidiff=true`: the
default file patch contains hunk headers and line prefixes needed by the
viewer, while omitting the optional parameter improves compatibility with
older self-managed versions. The parser fixtures still accept complete
unified file headers so the parser is not tied to one server representation.

The first page uses stale-while-revalidate caching for 60 seconds with the
existing 24-hour stale ceiling. The service follows only the trusted next URL
returned by the client.

### Head-aware raw response cache

The `/diffs` request URL does not include the head SHA, so URL-only caching can
return a fresh but obsolete first page after a push.

Add one local-only optional cache variant to `GitLabAPIRequest`:

- It participates in `GitLabResponseCacheKey`.
- It is never serialized into the URL, headers, body, logs, or description.
- Diff first-page requests use the normalized head SHA as the variant.
- Existing requests keep `nil`, preserving their current cache identity.

This is a deliberately small breaking request-layer change. Tests must prove
that equal URLs with different variants do not collide and that no variant is
sent to GitLab.

## Raw file model

Add `GitLabMergeRequestDiffFile` preserving:

- Old and new paths.
- Optional old and new modes.
- Raw patch text.
- Added, renamed, deleted, generated, collapsed, and too-large flags.

Compatibility decoding:

- Paths remain required because a pathless file cannot be identified or
  presented honestly.
- Patch text defaults to an empty string if omitted.
- All flags default to `false` when absent.
- Optional newer fields must not make an older self-managed response fail.

Stable file identity is `(oldPath, newPath)`, not array position. A rename
therefore remains distinguishable from a modified file and from another path.

Derived presentation states:

- Added
- Deleted
- Renamed
- Modified
- Generated as an additional badge

Derived availability is evaluated in this order:

1. `too_large`
2. `collapsed`
3. Empty patch returned by GitLab
4. Available text patch

An empty patch is described as “GitLab did not return a text diff.” The client
must not guess that every empty patch is binary.

## Parsed diff model

Parse into immutable values:

- `GitLabParsedDiffDocument`
  - flattened render items
  - hunk summaries
  - line count
  - estimated cache cost
  - maximum rendered line length
- `GitLabDiffHunk`
  - stable ordinal
  - original header text
  - old/new start and count
  - flattened item index for navigation
- `GitLabDiffLine`
  - stable ordinal
  - kind
  - old line number, when applicable
  - new line number, when applicable
  - display text without the diff prefix
- `GitLabDiffRenderItem`
  - hunk header
  - context
  - addition
  - deletion
  - no-newline marker
  - file metadata

The flattened representation lets either SwiftUI or `UICollectionView`
address one item by integer index without scanning all hunks for every visible
row. Old/new paths remain owned by the raw file and parsed-cache key, avoiding
duplicating them on every line.

### Line-number rules

For a valid hunk:

- Context consumes one old and one new line.
- Deletion consumes only an old line.
- Addition consumes only a new line.
- `\ No newline at end of file` consumes neither.
- File headers and other recognized metadata consume neither.

Single-line ranges without an explicit count have count 1. Zero-count ranges
are valid for pure additions/deletions.

### Malformed input

The parser must never crash or index beyond a string:

- CRLF and LF are accepted.
- Missing final newlines are accepted.
- Unknown pre-hunk metadata is preserved as metadata.
- A line beginning with `@@` that does not match a valid hunk header produces
  a typed malformed-hunk error with its one-based source line.
- Content after a valid hunk that has an unknown prefix is preserved as
  metadata rather than assigned false line numbers.
- Range-count mismatches do not crash or silently renumber later hunks; each
  valid next hunk resets counters from its own header.

The UI presents a parser failure with the reason, an Open in GitLab action, and
no attempt to render the raw patch as one enormous `Text`.

## Parser isolation and cancellation

`GitLabUnifiedDiffParser` is a nonisolated stateless value with an
`@concurrent async` parse entry point.

- Parsing never runs on MainActor.
- All outputs are immutable and `Sendable`.
- The loop checks cancellation before work and at least every 256 source
  lines.
- No `Task.detached`, semaphore, GCD queue, unsafe Sendable conformance, or
  shared mutable parser state is needed.
- Cancellation throws `CancellationError` and is not converted into a user
  failure.

Leaving a file cancels the SwiftUI `.task`. The renderer removes that waiter;
if no other viewer is awaiting the same parse, it cancels the underlying
parse task.

## Parsed-document cache

Create an actor-owned in-memory renderer/cache patterned after the proven
Markdown renderer, but with diff-specific identity and cost.

Cache key:

- `GitLabAccountID`
- Project ID
- MR IID
- Head SHA
- Old path
- New path
- Parser version
- Source digest as a final corruption/staleness guard

The key and its descriptions are redacted.

Bounds:

- Maximum 8 parsed files.
- Maximum 16 MiB estimated cost across entries.
- Estimate includes UTF-8 source bytes, rendered text bytes, and fixed
  per-item overhead.
- An individual document over the total cost limit is returned but not cached.
- LRU eviction runs after every insertion until both limits hold.

Behavior:

- Identical concurrent parses share one task.
- Cancelling one waiter does not cancel work still needed by another.
- When a newer head for the same account/MR/path is stored, stale-head variants
  for that path are removed immediately instead of waiting for LRU eviction.
- Account identity is part of every lookup and stale-removal comparison.
- The parsed cache remains memory-only. Private source persistence continues
  to use the existing protected, bounded raw response cache rather than a
  second on-disk format.

## Loading and navigation

Add a Changes entry inside MR details. It should not fetch diffs merely because
the MR detail appeared.

Navigation:

1. MR detail
2. Changed Files screen
3. One selected file screen

Changed Files:

- Loads the first 20 files on appearance.
- Publishes a cached first page before network revalidation.
- Loads the next page only when the last loaded row becomes visible.
- Retains loaded rows after refresh or next-page failure.
- Shows total count from reliable pagination metadata when available, falling
  back to the MR `changes_count` string.
- Refresh uses the same head SHA and forces the first page.
- A new MR head recreates the changed-files state and uses a different raw and
  parsed cache identity.

File selection passes one raw file to the file viewer. Only that file is
parsed. Pagination, refresh, or navigation must never eagerly parse all loaded
files.

## UI plan

### MR detail entry

Add a compact Changes section after Branches:

- File/change count when available.
- “View changed files” navigation action.
- Preparing text when no head SHA is available.
- Stable accessibility identifier.

The navigation action may use an interactive Liquid Glass treatment. Static
count/status text should not.

### Changed Files screen

Use a native list with:

- Leading file-status symbol and color.
- Truncating but selectable full path.
- Old path shown for renames.
- Generated, collapsed, and too-large badges.
- Clear loading, empty, cached-refresh, retry, and next-page retry states.
- Stable row identifiers based on a privacy-safe digest/ordinal rather than
  embedding private repository paths in logs or UI-test identifiers.

### File screen

Header:

- New path and old path for a rename.
- Added/deleted/renamed/generated status.
- File progress, such as “2 of 18,” when known.
- Previous/next file controls where the loaded page provides neighbors.
- Hunk menu/jump control when more than one hunk exists.

Body:

- Fixed-width code font that still scales with Dynamic Type.
- Old and new line-number gutters.
- Distinct but restrained addition, deletion, context, metadata, and hunk
  styling in light and dark appearance.
- Horizontal access to long lines without wrapping code.
- Text selection where it does not destroy scrolling behavior.
- VoiceOver label per visible line including kind and available old/new line
  numbers.
- Hunk headers exposed as accessibility headings.

Interactive toolbar and hunk controls can use Liquid Glass. Code lines, file
headers, and status badges remain ordinary content for contrast and
performance.

### Unavailable files

For collapsed, too-large, empty, or parse-failed files:

- Explain exactly what GitLab returned.
- Do not fetch `/raw_diffs` for the entire MR.
- Do not attempt the deprecated `/changes` endpoint.
- Offer the existing compact Open in GitLab control pointed to the MR changes
  page.

## SwiftUI-first virtualization decision

The first renderer will use SwiftUI with a two-axis scroll surface and
`LazyVStack`, one flattened item per row. It must not construct one
`AttributedString`, one giant `Text`, or one view containing all source text.

The parser records maximum line length so the code surface can establish a
stable horizontal width instead of changing as new lazy rows appear.

Profile this implementation in the iPhone 17 Pro Simulator with 1k, 10k, and
50k-line fixtures. Replace only the line surface with a focused
`UIViewRepresentable` backed by `UICollectionView` when any of these remain
true after one small SwiftUI optimization pass:

- 50k-line first interactive render exceeds 500 ms.
- A deterministic 10-second scroll has a hitch-time ratio above 5%.
- Any single scroll hitch exceeds 250 ms.
- The 50k-line screen increases resident memory by more than 100 MiB over the
  file-list screen.
- Rapid back navigation leaves parsing or view work alive.

The UIKit fallback would retain the same immutable document, model, cache,
navigation, colors, accessibility strings, and tests. It would own only cell
reuse, shared horizontal offset, hunk scrolling, and selection.

## Performance budgets

Measure optimized builds on the iPhone 17 Pro Simulator. Record median and p95
for parser/cache tests and Instruments results for UI traces.

Parser p95:

- Approximately 1,000 changed lines: under 10 ms.
- Approximately 10,000 changed lines: under 50 ms.
- Approximately 50,000 changed lines: under 200 ms.
- Warm parsed-cache lookup: under 2 ms.

State/UI:

- Publishing a decoded 20-file first page: under 10 ms.
- First interactive 10k-line file: under 250 ms.
- First interactive 50k-line file: under 500 ms.
- 50k-line incremental resident memory: at most 100 MiB.
- Deterministic scroll hitch-time ratio: at most 5%, with no hitch over 250 ms.

Use `ContinuousClock` for parser/model tests and Instruments' SwiftUI,
Animation Hitches, and Allocations templates for the simulator surface.
Performance tests run in isolation. Debug-build numbers are diagnostic;
optimized-build numbers determine the gate.

### Renderer profiling method

Keep the benchmark entirely in the test target. Host the production
`GitLabDiffCollectionView` in a real `UIWindow` with deterministic generated
documents; do not add a benchmark route or fixture source to the app.

- Measure parse start through the first non-empty visible-cell layout for 10k
  and 50k documents, reporting median and p95.
- Measure resident memory immediately before parsing the first 50k document
  and after its visible collection layout.
- Sweep the 50k collection for 600 frames over 10 seconds at a fast inertial
  rate of four rows per frame, recording layout work, over-budget time, and
  the largest frame. Traversing all 50,000 rows in 10 seconds is intentionally
  excluded because it would replace roughly 83 rows per frame rather than
  model a user scroll.
- Run the harness alone in an optimized build on the iPhone 17 Pro Simulator
  and cross-check the run with Animation Hitches and Allocations traces.

## Fixtures

Keep small correctness fixtures readable and generate large fixtures
deterministically in tests.

Correctness coverage:

- Ordinary context/add/delete hunks.
- Multiple hunks.
- Single-line and explicit-count ranges.
- Pure additions and deletions with zero-count ranges.
- Missing final newline markers.
- Added, deleted, and renamed file metadata.
- Binary/empty diff.
- Generated, collapsed, and too-large flags.
- CRLF.
- Unicode, combining characters, emoji, tabs, and bidirectional-safe plain
  display.
- Very long lines.
- Malformed hunk headers and unknown metadata.

Generated performance fixtures:

- Approximately 1,000 changed lines.
- Approximately 10,000 changed lines.
- Approximately 50,000 changed lines.

Generators must be deterministic, bounded, and excluded from production.

## Test plan

### MR and endpoint contract

- Decode optional `sha`, `diff_refs`, and string `changes_count`.
- Normalize head SHA and handle empty preparation fields.
- Decode complete current diff fields.
- Decode pre-16.11/pre-18.4 responses with missing newer flags.
- Preserve rename paths and modes.
- Exact `/diffs` request path, read access, and `per_page=20`.
- Trusted next-page request.
- Different local head variants produce different cache keys without changing
  the outgoing URL.

### Parser

- Correct line kinds and old/new counters.
- Multiple hunks reset counters.
- Zero and omitted range counts.
- File metadata and default fragment formats.
- CRLF, missing final newline, marker lines, Unicode, tabs, and long lines.
- Malformed hunk typed failure.
- Unknown input never crashes.
- Cancellation before and during a large parse.
- No MainActor parser execution.

### Parsed cache

- Exact account/MR/head/path/parser-version/source identity.
- Same-key coalescing.
- One cancelled waiter does not cancel another.
- Last waiter cancellation stops parsing.
- New head removes the stale path variant.
- Different accounts and different paths remain isolated.
- Count-bound LRU.
- Cost-bound LRU.
- Oversize documents are returned but not cached.

### Loading model

- Cached first-page publication and network replacement.
- Pagination append and deduplication.
- Empty, initial failure, retry, retained refresh failure, and next-page
  failure.
- New head constructs isolated state.
- Only selected file is sent to the parser.
- Leaving or changing selected file cancels obsolete parse publication.
- Authentication failure propagation.

### UI and simulator

- MR preparing state and Changes entry.
- Empty and multi-page file lists.
- Every file status and unavailable state.
- Ordinary, multiple-hunk, Unicode, long-line, 1k, 10k, and 50k viewers.
- Horizontal and vertical scrolling.
- Hunk jump.
- Text selection.
- Rapid file switching and back navigation.
- Cache-warm reopen.
- Light/dark appearance.
- Standard and accessibility Dynamic Type.
- Reduce Motion and Reduce Transparency.
- VoiceOver labels/identifiers.
- Live self-managed read-only MR with no write request.

## Implementation sequence and commits

1. Commit this plan and mark only the audit/plan todos complete.
2. Add MR revision and raw diff decoding/endpoint tests.
3. Implement the API contract and head-aware raw cache identity; run focused
   request/cache tests; commit and push.
4. Add correctness and generated performance fixtures.
5. Add failing parser, cancellation, and performance tests.
6. Implement the immutable parser off MainActor until correctness and parser
   budgets pass; commit and push.
7. Add failing parsed-cache/coalescing/LRU/head-invalidation tests.
8. Implement the bounded renderer/cache; commit and push.
9. Add file-list and selected-file observable model tests.
10. Implement models and service integration; commit and push.
11. Read the Liquid Glass and iOS Simulator guidance before UI work.
12. Implement the MR entry, changed-file list, and SwiftUI-first virtualized
    file viewer.
13. Build and inspect every deterministic UI state in the iPhone 17 Pro
    Simulator. Tap, scroll, select, jump hunks, switch files, and navigate back.
14. Record optimized SwiftUI, Animation Hitches, and Allocations measurements.
15. If a threshold fails after one bounded optimization pass, write the
    measured reason below before replacing only the line surface with UIKit.
16. Verify the normal app against the configured self-managed read-only
    account. Do not use or install on a physical iPhone.
17. Run focused tests, isolated performance suites, the complete functional
    suite, static analysis, privacy/cache scans, and account/head isolation
    audits.
18. Perform the required deep review. Record findings and write a repair plan
    before any material fix.
19. Fix every finding, repeat affected tests/traces/UI verification, close the
    Phase 2 checklist, commit, push, and shut down all simulators.

## Success criteria

- No deprecated `/changes` call exists.
- Current and older compatible self-managed diff objects decode without losing
  server status.
- Raw and parsed cache entries cannot cross account or head SHA.
- Only the selected file is parsed, and parsing never blocks MainActor.
- Cancellation stops obsolete work and prevents stale publication.
- Line kinds and old/new numbers are correct for every fixture.
- Parsed-cache count and cost never exceed explicit limits.
- Collapsed, too-large, and empty files show honest fallback instead of a
  spinner or unsafe full-MR fetch.
- The chosen renderer meets every recorded performance and memory budget.
- Light/dark, Dynamic Type, long-line, accessibility, and navigation checks
  pass in the iPhone 17 Pro Simulator.
- The live read-only self-managed flow loads without a write request.
- Focused tests, performance gates, the complete suite, static analysis, and
  the required deep review pass.

## Deep review checklist

Complete after implementation:

- [ ] `/diffs` endpoint, pagination, and optional-field compatibility
- [ ] MR/head revision ownership and stale-head invalidation
- [ ] Old/new path and line-number correctness
- [ ] Malformed input and unavailable-state honesty
- [ ] Off-main parsing and cancellation propagation
- [ ] Parsed-cache identity, coalescing, bounds, and LRU behavior
- [ ] No eager all-file parsing or giant text construction
- [ ] SwiftUI/UIKit virtualization and horizontal scrolling
- [ ] Hunk navigation and rapid-navigation cleanup
- [ ] Account, host, MR, head, and path isolation
- [ ] Accessibility, Dynamic Type, appearance, and reduced-effects settings
- [ ] Confidential source, URL, credential, and cache-key privacy
- [ ] Duplicate parsing/rendering logic and unnecessary abstraction
- [ ] Static analysis, complete tests, performance, memory, and hitch results

### Renderer decision evidence

The first implementation used one SwiftUI `LazyVStack` line surface. Parsing,
ordinary rendering, vertical scrolling, and horizontal scrolling worked on
the iPhone 17 Pro Simulator with live read-only data. A 14,380-character,
two-hunk self-managed patch exposed a functional threshold failure: selecting
the second hunk resolved the correct parser `renderItemIndex`, but SwiftUI's
lazy two-axis scroll APIs only revealed the distant target near the bottom or
ignored its exact anchor. One bounded pass tried an explicitly top-aligned
two-axis container, fixed/scaled row heights, `ScrollViewReader`,
`scrollPosition`, and exact calculated anchors. None reliably aligned the
distant hunk at the top.

P2-06 therefore uses the planned focused UIKit fallback for only the code-line
surface. Navigation, loading, selection, errors, unavailable states, and
toolbars remain SwiftUI. The fallback must use reusable collection cells,
constant-time layout attributes, exact indexed hunk scrolling, shared
horizontal access, selectable visible code text, and Dynamic Type-aware fixed
row heights.

The UIKit pass was then verified against the same live read-only fixture on
the iPhone 17 Pro Simulator. Hunk 2 aligned at the top of the viewport,
horizontal and vertical scrolling remained interactive, unavailable files
retained their honest fallback, and file switches reset stale hunk state.
Dark, light, and accessibility-extra-large inspections retained readable line
numbers and code. Focused diff/API/model/cache tests pass.

Isolated optimized results on the iPhone 17 Pro Simulator:

- Parser p95: 1k `0.497 ms`, 10k `5.173 ms`, 50k `27.226 ms`.
- Warm parsed-cache p95: `0.114 ms`.
- Parse-to-visible renderer: 10k median `80.240 ms`, p95 `82.350 ms`;
  50k median `94.792 ms`, p95 `96.058 ms`.
- 50k incremental resident memory: `4.219 MiB`.
- 600-frame/10-second scroll: layout-work p95 `4.924 ms`, hitch-time
  ratio `0%`, maximum frame `16.667 ms`.

The iOS 26.5 Simulator reported that the Animation Hitches template is not
supported on this platform. Allocations attached to both the optimized test
host and the persistent live app, but `xctrace` hung while finalizing and
produced no valid export after the bounded capture. These tool limitations are
recorded rather than treated as passing traces; the optimized display-link
frame gate and direct resident-memory measurement above are the reproducible
simulator evidence.

### Findings

- The first UIKit pass keyed the parse task and retained collection document
  only by old/new path. If the same navigation stayed alive across an account,
  merge request, or head revision change, the visible cells could retain the
  prior revision.
- A normal collection content height prevents a hunk near the end of a patch
  from aligning to the viewport top. The live two-hunk fixture reproduced this
  by clamping hunk 2 below earlier lines.
- Row height and font respected Dynamic Type, but the first UIKit pass kept
  default-size gutter and content-width estimates. Large accessibility sizes
  could therefore clip line numbers or long code horizontally.
- The selected-file task identity includes account, merge request, head, and
  path, but not the patch revision. A stale cached first page can therefore be
  replaced by corrected network text for the same file without retriggering
  parsing, leaving the cached document visible until the user navigates away.
- The parser records Swift grapheme count as the maximum rendered line length.
  Tabs advance multiple columns and wide Unicode glyphs commonly occupy two,
  so the collection content width can under-allocate valid source and clip it
  with no remaining horizontal scroll range.

### Repair plan

1. Introduce one privacy-safe document identity containing account, merge
   request route, head SHA, and path pair. Use it for the SwiftUI parse task and
   retained UIKit document replacement.
2. Give the custom layout one viewport of trailing scroll allowance so every
   row, including the last hunk, can align at the top without rendering spacer
   cells.
3. Unit-test document-identity isolation, rebuild, and repeat the live exact
   hunk, file-switch, unavailable-state, and two-axis scroll checks.
4. Derive gutters and content width from the same scaled row metric as the
   font, while retaining the documented width cap for pathological lines.
5. Add a regression proving that two payloads with the same account, route,
   head, and path but different patch text have distinct document identities.
   Precompute a privacy-safe patch digest while constructing the diff file and
   include it in the selected-file task and collection identity.
6. Replace the ambiguous maximum-line-length metric with an estimated rendered
   column count calculated off MainActor. Add parser and layout tests covering
   tab stops, combining marks, and wide Unicode before using it to size the
   horizontal content surface.
7. Run the focused model/parser/renderer suites first, then repeat the live
   cache-warm file selection, Unicode/long-line, hunk-jump, and two-axis
   simulator checks before closing the findings.

## Non-goals

- Side-by-side diff mode
- Syntax highlighting
- Full file contents outside changed hunks
- Fetching more context around a hunk
- Whitespace-ignore preferences
- Marking files as viewed
- Diff version selection
- Commit-by-commit diffs
- Inline discussions or line comments, which belong to P2-07
- Suggestions, approvals, merge actions, or any write operation
- Bypassing GitLab diff limits with `/raw_diffs`
- The deprecated `/changes` endpoint
- Offline persistence of parsed documents
- Physical-device installation or testing
