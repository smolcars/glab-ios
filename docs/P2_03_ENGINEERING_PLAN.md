# P2-03 engineering plan: issue and merge-request discussions

Last updated: 2026-07-28

Status: complete.
Glab has never shipped, so breaking internal model, loader, cache-key, and
view APIs are acceptable when they produce a simpler or safer implementation.

## Outcome

Show paginated issue and merge-request discussions in their native detail
screens. Preserve top-level discussion and nested reply identity, distinguish
system activity and internal notes, render every visible note body through the
P2-02 native Markdown pipeline, and retain useful cached or already-loaded
content when refresh or pagination fails.

P2-03 is read-only. Creating comments, replies, reactions, resolving threads,
and editing notes remain separate Phase 2 work.

## Inspected current state

- Issue and merge-request detail screens already share the generic
  `GitLabResourceDetailModel` but have separate resource loaders and views.
- No discussion, note, thread, or system-note model exists.
- Both detail screens use one vertical `ScrollView`. Discussion presentation
  must join that scroll and must not add a nested vertical `List` or
  `ScrollView`.
- `GitLabPaginatedResourceModel` already provides first/next-page loading,
  stable identity-based duplicate suppression, cache-first revalidation,
  retained refresh failures, pagination retry, cancellation restoration, and
  authentication-failure exposure.
- `GitLabSessionClient` caches only an initial GET request. Server-provided
  next-page URLs are followed exactly and remain memory-only, which directly
  matches the P2-03 cache requirement.
- The shared response cache is account-partitioned, protected with iOS file
  protection, globally bounded to 25 MiB, and removed for an account when that
  account is removed.
- P2-02 provides an asynchronous native Markdown parser, bounded parsed
  document and image caches, safe relative links, and lazy block views.
- The P2-02 parsed-document resource identity currently distinguishes only an
  issue description from a merge-request description. Reusing that identity
  for multiple notes would make each note evict the others, so P2-03 must add
  note-level Markdown resource identity.
- The signed-in shell owns one account-bound API client and destroys the
  feature tree on account switching. A discussion loader can share that
  client while still receiving an explicit resource identity for every call.

## GitLab API contracts

Use the Discussions API rather than flattening threads through the Notes API:

- issue discussions:
  `GET /projects/:id/issues/:issue_iid/discussions`;
- merge-request discussions:
  `GET /projects/:id/merge_requests/:merge_request_iid/discussions`.

Both return an array of discussions. A discussion has a stable string `id`,
an `individual_note` flag, and an ordered `notes` array. Each note has an
integer `id`, body, author, created and updated timestamps, system flag,
noteable metadata, and optional resolvable state. Merge-request notes may have
type `DiscussionNote`, `DiffNote`, or `null`, with optional diff position and
resolution data. Unknown note types and unknown JSON fields must decode
without failing the whole page.

`internal` and legacy `confidential` note flags are decoded when present.
They affect presentation only; GitLab remains responsible for authorization
and does not return notes the current account cannot see.

List endpoints are paginated and return 20 discussions by default. Request
`per_page=20`, preserve server ordering, and follow the exact HTTPS
`Link: rel="next"` URL. Do not construct page numbers or depend on `X-Total`,
because GitLab.com can omit pagination totals.

A redacted read-only sample from the configured self-managed GitLab instance
confirmed:

- issue and merge-request responses use the documented discussion envelope;
- current issue data included individual system notes;
- current merge-request data included both system and user notes;
- note responses include evolving fields such as `commands_changes`,
  `internal`, `confidential`, `imported`, and `imported_from`;
- a forced five-item page returned both `Link: rel="next"` and
  `X-Next-Page`;
- the sampled first-note timestamps were ascending, but the app will preserve
  server order rather than treating that observation as an API guarantee.

Sources:

- [GitLab Discussions API](https://docs.gitlab.com/api/discussions/)
- [GitLab REST pagination](https://docs.gitlab.com/api/rest/#pagination)
- [GitLab Notes API](https://docs.gitlab.com/api/notes/)
- [GitLab comments and threads](https://docs.gitlab.com/user/discussions/)

## Architecture

Keep the current Model-View architecture. The feature has straightforward
paginated state and does not justify MVVM, MVI, or a new package.

```text
Issue/MR detail view
  -> GitLabDiscussionsModel
     (specialized GitLabPaginatedResourceModel)
  -> GitLabDiscussionLoading
  -> LiveGitLabDiscussionLoader
  -> GitLabDiscussionEndpoints
  -> account-bound GitLabSessionClient
```

Add one shared domain and service path:

- `GitLabDiscussionResource`: issue route or merge-request route;
- `GitLabDiscussion`: string discussion ID, individual-note flag, ordered
  notes;
- `GitLabDiscussionNote`: integer note ID, raw optional type, body, author,
  timestamps, system/internal/resolution flags, and optional position summary;
- `GitLabDiscussionPosition`: only the file and line fields required to
  identify a code discussion in P2-03;
- `GitLabDiscussionEndpoints`: switches once on resource kind to build either
  documented endpoint;
- `LiveGitLabDiscussionLoader`: loads both resource kinds through one
  paginated client;
- `GitLabDiscussionsModel`: specializes the generic pagination model with
  discussion ID as stable identity.

The issue and merge-request detail screens each own a discussion model
initialized from their route. Their initial detail and discussion GETs run
concurrently with structured concurrency. The two screens share the same
discussion section view and do not duplicate loading or pagination
orchestration.

No forwarding-only view model or repository abstraction is added.

## Model identity and defensive decoding

- Top-level `ForEach` identity is the server discussion string ID.
- Reply identity is the server note integer ID.
- A repeated discussion on a later page is suppressed by discussion ID.
- First-page refresh replaces the loaded page using the same identities, so
  unchanged visible rows remain stable.
- Note `type` remains a raw optional string with computed known categories.
  A new server type renders as a normal note instead of failing decoding.
- New or irrelevant JSON fields are ignored by `Decodable`.
- Optional evolving flags default conservatively in computed presentation:
  absent `system`, `internal`, `confidential`, `resolvable`, or `resolved`
  behaves as false.
- An empty discussion notes array stays representable and produces a readable
  fallback instead of crashing.
- Server order is preserved within both the page and each discussion.

## Pagination, caching, and offline behavior

Add a `.discussions` response policy:

- fresh for 60 seconds;
- stale fallback retained for up to 24 hours;
- first page persisted through the existing account-partitioned response
  cache;
- later pages loaded from exact server links and held only by the view model.

On initial load:

1. Publish a fresh cached first page and stop, or publish a stale cached first
   page immediately and revalidate it.
2. Replace it with the network first page when revalidation succeeds.
3. If revalidation fails, retain cached discussions and show an inline
   recovery state.

On an explicit refresh, keep all visible discussions until the network first
page succeeds. On failure, retain them and show the error. On a next-page
failure, retain every loaded page and offer a pagination retry. A connectivity
failure with no cache uses the existing offline recovery presentation.

Never persist parsed Markdown, images, tokens, usernames, or a second
discussion representation.

## Markdown integration

Rename the description-specific Markdown view to a content-neutral native
Markdown view with presentation text for descriptions or comments.

Extend `GitLabMarkdownResourceID` with issue-note and merge-request-note cases
containing the note ID. Description cases remain distinct. This prevents
different comments on the same resource from evicting each other from the
parsed-document cache while preserving account and resource isolation.

Every nonempty user, reply, system, and diff-note body uses:

- the current account ID;
- issue or merge-request route plus note ID;
- the exact note body;
- the resource's validated web URL for safe relative links;
- the note's `updated_at` value as the SwiftUI task revision.

Empty note bodies show an explicit fallback. The existing image origin,
credential, byte, dimension, and memory limits continue to apply.

## UI and accessibility

Add one `Discussion` section after existing resource metadata:

- keep the existing detail `ScrollView` and change its vertical content to a
  `LazyVStack`;
- render one discussion card per server discussion and one stable row per
  reply;
- show author avatar, display name, username, relative time, edited state, and
  Internal/Code discussion/Resolved status where applicable;
- visually inset replies with a subtle leading rule without adding a nested
  vertical scroll;
- render system activity as a compact, lower-emphasis row that remains fully
  visible and readable;
- identify diff notes by path and old/new line when the server supplies a
  position, but leave navigation into a diff for P2-07;
- trigger pagination only when the last loaded discussion appears;
- use lightweight skeletons for initial loading and small inline recovery
  cards for retained refresh and next-page failures;
- show a friendly empty state when no discussions exist.

Long discussion presentation uses native `LazyVStack`, not `List`, HTML, or a
WebView. P2-02 measured a small Markdown parse at well under 1 ms in an
optimized Simulator build, but eagerly parsing hundreds of notes would still
create unnecessary work. A lazy row starts Markdown work only when the note
becomes visible.

Accessibility:

- discussion and note rows keep author, time, and status semantics available;
- system activity is labeled as activity;
- reply position in a thread is announced;
- Internal, code-discussion, resolved, loading, empty, error, and pagination
  states have explicit labels or identifiers;
- Markdown headings, links, code, tables, images, and task state retain P2-02
  semantics;
- Dynamic Type may expand cards vertically without truncating note content.

## Isolation and cancellation

- `GitLabDiscussion`, note, resource, and page values are immutable and
  `Sendable`.
- Endpoint construction and live loading are nonisolated; network calls use
  `@concurrent` loader methods.
- The observable pagination model remains `@MainActor`.
- Detail and discussion initial work uses `async let`, preserving task
  priority and view-disappearance cancellation.
- SwiftUI `.task` owns initial and pagination work. No detached task or manual
  lock is introduced.
- The generic model prevents overlapping initial, refresh, and next-page
  requests and restores prior failure state on cancellation.
- Account switching destroys the account-bound loader and model. Raw and
  parsed cache keys also include the account identity, so late results cannot
  cross accounts.

## Test-first implementation slices

### Slice 1: domain decoding and endpoints

First write failing Swift Testing coverage for:

- issue and merge-request endpoint paths, read access, and `per_page=20`;
- a multi-note thread with stable discussion/note identities;
- individual comments and system notes;
- `DiscussionNote`, `DiffNote`, `null`, and unknown note types;
- optional internal/confidential/resolution/position fields;
- unknown JSON fields, empty page, and an empty notes array;
- malformed required identity, author, body, or timestamp fields failing
  predictably rather than inventing identity.

Then implement the smallest immutable domain and endpoint types. Run focused
tests and commit the buildable slice.

### Slice 2: shared loader and paginated model

First write failing tests for:

- issue and merge-request first-page requests;
- exact next-page URL forwarding;
- `.discussions` cache policy and cache-first event forwarding;
- first/next-page success, empty state, stable duplicate suppression, and
  nested replies;
- stale cache retained after refresh failure;
- loaded pages retained after explicit refresh or next-page failure;
- retry and cancellation restoring prior visible state;
- authentication failures remaining observable.

Then implement the one shared loader and specialized generic model. Run
focused tests and commit.

### Slice 3: note-level Markdown identity

First add a regression test proving two different notes on the same issue or
merge request coexist in the parsed-document cache. Add presentation-model
tests proving a changed `updated_at` or body cannot publish stale output.

Then add note resource identities and make the native Markdown view
content-neutral. Run P2-02 and P2-03 focused suites and commit.

### Slice 4: shared lazy discussion UI

Wire one discussion model into both detail routes. Load resource and
discussions concurrently. Add shared loading, empty, retained-error,
pagination, system activity, user thread, reply, internal, resolved, and
diff-note views.

Build and inspect issue and merge-request details on the iPhone 17 Pro
Simulator in light/dark appearance and default/accessibility Dynamic Type.
Exercise initial load, scrolling, pagination, pull-to-refresh, retry, rapid
back navigation, and cached relaunch. Commit the slice.

### Slice 5: performance, deep review, and completion

Create deterministic fixtures for:

- empty discussions;
- one discussion with nested replies and every status;
- 20 mixed first-page discussions;
- 200 mixed discussions with Markdown, system activity, and long replies.

Measure decoding, first-page model publication, duplicate merge, warm cache
publication, visible Markdown work, scrolling, and bounded cache behavior.
Initial Simulator regression budgets:

- decode 20 discussions below 10 ms p95;
- decode 200 discussions below 75 ms p95;
- first-page model publication below 5 ms p95;
- duplicate merge of 200 discussions below 10 ms p95;
- no Markdown parsing until a note row appears;
- responsive continuous scrolling without repeated parsing of unchanged
  visible notes;
- response, parsed-document, and image caches remain within existing bounds.

Run focused tests, the complete suite, static analysis, a source/cache privacy
scan, and the Simulator UI matrix.

Then deeply review all P2-03 code for endpoint drift, unsafe decoding,
duplicate issue/MR paths, unstable identities, lost replies, page-boundary
duplicates, stale-cache races, refresh/pagination overlap, late cancellation,
cross-account content, eager Markdown parsing, excessive row work, hidden
system notes, and unnecessary abstraction. Record material findings and a
repair plan before editing, add regression tests, implement every fix, repeat
verification, and only then mark P2-03 complete.

## Non-goals

- Creating, editing, deleting, or replying to a note.
- Resolving or reopening a thread.
- Emoji reactions.
- Navigating a diff note to a code line.
- Showing a full diff or syntax-highlighted suggestion preview.
- Downloading note attachments outside Markdown's bounded image path.
- Filtering or changing discussion sort order.
- Loading all pages eagerly to calculate an exact total.
- Persisting later pages, parsed notes, or decoded images.
- Exact GitLab web activity-event parity for resource events that the
  Discussions API does not return.

## Verification record

- Verified the documented issue and merge-request discussion envelopes,
  evolving note fields, system/user notes, and exact next-page links against
  redacted read-only responses from the configured self-managed instance.
- Focused discussion domain, endpoint, loader, pagination, cache, Markdown,
  detail, session, and performance suites pass.
- Debug and optimized Release performance gates pass for 20- and
  200-discussion decoding, first-page and warm-cache publication, duplicate
  merging, and lazy Markdown parsing.
- The complete signed test suite passes on the iPhone 17 Pro Simulator with
  test parallelization disabled. A parallel run caused only the pre-existing
  Markdown micro-benchmark to exceed its contention-sensitive budget; that
  benchmark passed both in isolation and in the complete serial rerun.
- `xcodebuild analyze` completes without findings.
- The tracked-source scan found no configured token, OAuth secret, or private
  self-managed host value. Discussion response keys and Markdown document
  keys remain account scoped, and the existing bounded caches are reused.
- Live read-only issue and merge-request discussions were exercised on the
  iPhone 17 Pro Simulator. Verification covered user Markdown, system
  activity, long scrolling, pull-to-refresh, rapid enter/back navigation, and
  cached relaunch in dark appearance at the default content size. Light
  appearance and accessibility-extra-large Dynamic Type were also inspected;
  discussion cards expanded without clipping.
- Deterministic tests cover empty pages, empty note arrays, stale-cache and
  failed-refresh retention, pagination, next-page failure/retry, duplicate
  suppression, cancellation, internal notes, resolved notes, and diff notes
  that are not all available simultaneously in the live read-only account.

## Deep-review findings and repair plan

Review performed after the complete domain, loader, cache, pagination,
Markdown, UI, and performance implementation.

Material findings:

1. Issue and merge-request detail screens observe discussion authentication
   failures with `onChange`, then inspect the same failure again after initial
   load and refresh. The duplicated routing can request account invalidation
   twice for one failure and makes the two detail implementations easier to
   drift.
2. The note presentation derives `Edited` only from differing `created_at` and
   `updated_at` values. GitLab system activity may have differing timestamps
   without representing an edited user comment, so the current header can
   misleadingly show `Edited • Activity`.

Repair plan, recorded before editing:

1. Give each detail view one combined authentication-failure value that
   prefers its resource-detail failure and otherwise uses the discussion
   failure. Observe that value once, covering initial load, refresh, and
   pagination. Remove both redundant post-operation checks.
2. Add a note-presentation regression assertion that an updated user note may
   show the edited status while system activity never does. Implement the
   smallest computed presentation property and use it in the shared note
   header.
3. Run the discussion, detail, Markdown, session, and performance suites;
   repeat static analysis and the Simulator interaction checks; then review
   the repaired diff once more.

No material endpoint drift, unsafe next-page construction, lost reply
identity, stale-cache overwrite, cross-account cache key, eager Markdown
parsing, unbounded discussion-specific cache, or duplicated issue/MR service
path was found. The existing shared pagination and Markdown components remain
the appropriate abstractions.

Both repairs were implemented and re-reviewed. The focused suites, complete
serial suite, Release performance gates, analyzer, privacy scan, and Simulator
interaction pass all succeeded afterward. No material P2-03 findings remain.
