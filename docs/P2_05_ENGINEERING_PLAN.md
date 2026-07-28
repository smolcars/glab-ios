# P2-05 Engineering Plan — Emoji Reactions

Last updated: 2026-07-28

Status: planned; implementation has not started.

Glab has not shipped. Breaking internal APIs, model initializers, and local
cache formats are acceptable when they make this feature smaller, safer, or
easier to test. This milestone will not send reaction mutations to the
configured self-managed account because its token is read-only.

## Outcome

A signed-in user can:

- View emoji reactions on an issue, merge request, or individual discussion
  note.
- See grouped counts without losing the individual server award IDs needed for
  removal.
- Add a reaction from a deliberately small common-emoji picker when the
  session has write access.
- Remove their own reaction by selecting its group again.
- Continue viewing reactions in a read-only session.
- See optimistic feedback immediately, with exact rollback and a safe recovery
  path if GitLab rejects the mutation or delivery is uncertain.

## Source of truth

The implementation is based on GitLab's official documentation, reviewed on
2026-07-28:

- [Emoji reactions API](https://docs.gitlab.com/api/emoji_reactions/)
- [Emoji reactions user documentation](https://docs.gitlab.com/user/emoji_reactions/)
- [GitLab quick actions](https://docs.gitlab.com/user/project/quick_actions/)

Important API facts:

- GitLab calls a resource that accepts reactions an `awardable`.
- Resource collection paths are:
  - `GET|POST /projects/:id/issues/:issue_iid/award_emoji`
  - `GET|POST /projects/:id/merge_requests/:merge_request_iid/award_emoji`
- Note collection paths insert `notes/:note_id` before `award_emoji`.
- `POST` requires a `name` query parameter without surrounding colons and
  returns the created award, including its server ID.
- `DELETE` appends `/:award_id`. Only an administrator or the award author can
  delete it.
- A list response contains individual awards. Grouping is a client
  presentation concern.
- GitLab.com, Self-Managed, and Dedicated all support these endpoints.
- GitLab supports custom emoji, but custom-emoji discovery is outside this
  first slice.

The note-delete example URL in the current API documentation omits
`notes/:note_id`, while the documented endpoint signature immediately above
it includes those components. Glab will follow the endpoint signature, which
is also consistent with the list, retrieve, and add note-reaction endpoints.

## Existing architecture audit

Relevant existing behavior:

- `GitLabAccountID` contains the normalized host and current user ID. It is the
  correct account-isolation and current-user identity source.
- `GitLabDiscussionResource` already distinguishes issue and merge-request
  routes without duplicating project and IID fields.
- `GitLabDiscussionNote` retains the server note ID needed by note reaction
  paths.
- `GitLabAPIRequest` supports `GET` and `POST`, but not `DELETE`.
- Automatic transport retries and reactive OAuth refresh retries are already
  limited to `GET`. Adding `DELETE` must preserve that invariant.
- `GitLabSessionClient` keys cached reads by account and complete request URL.
- Discussion reads use stale-while-revalidate caching and lazy pagination.
- Comment POSTs invalidate only the affected discussion collection after a
  decoded success.
- Todo mutations have a larger optimistic overlay because a single mutation
  affects multiple filtered lists. Reactions need a smaller target-local
  overlay and should not reuse the Todo model.
- Issue and merge-request detail screens already own resource identity,
  current account identity, API capability, and the shared session client.
- Discussion notes are lazily rendered in stable server-ID order.

## Decisions

### Awardable identity

Add a single hashable `GitLabEmojiAwardable` value:

- `resource: GitLabDiscussionResource`
- `noteID: Int?`

`noteID == nil` identifies the issue or merge request itself. A non-nil note ID
identifies that note within the resource. Construction will expose named
resource and note factories so invalid or ambiguous call sites do not spread.

The complete account identity is not part of this value. Models and caches are
already scoped to a session client and `GitLabAccountID`; mixing it into an API
route would duplicate responsibility.

### Individual award model

Add `GitLabEmojiAward` with:

- Server `id`
- Canonical GitLab `name`
- Awarding `GitLabAPIUser`
- `createdAt` and `updatedAt`
- `awardableID` and `awardableType`

The decoder will not collapse awards. The server ID remains the identity used
for `DELETE`.

### Grouped presentation

Derive `GitLabEmojiReactionGroup` values from individual awards:

- Canonical name
- Display glyph or a safe `:name:` fallback
- Total count
- Current user's exact award IDs
- Stable ordering based on first server appearance, with picker-only
  optimistic additions appended

Grouping will be a pure, nonisolated function with direct unit coverage.
Duplicate awards from the current user are tolerated rather than crashing or
silently losing IDs.

### Common picker

The first picker is intentionally bounded to common, stable GitLab names:

- `thumbsup` — 👍
- `thumbsdown` — 👎
- `heart` — ❤️
- `tada` — 🎉
- `eyes` — 👀
- `rocket` — 🚀

The API and GitLab user documentation explicitly establish names without
colons, including `thumbsup`, `heart`, `tada`, and `rocket`. Existing awards
with other standard or custom names remain visible through a text fallback.
Browsing the complete GitLab emoji catalog and fetching custom-emoji artwork
are deferred.

### HTTP DELETE

Extend `GitLabHTTPMethod` and `GitLabAPIRequest` with a bodyless `DELETE`
factory. This is a breaking internal addition with no compatibility shim.

Verification must prove:

- Request construction emits `DELETE`.
- It includes no body or `Content-Type`.
- It still requires write access.
- The transport does not automatically retry it.
- A reactive OAuth `401` does not replay it.
- A proactive refresh for a token known to be expired can still occur before
  the first attempt.

### Loading and cache behavior

Add a target-local reaction service and observable model.

- Request up to 100 awards per page.
- Follow trusted GitLab next-page links so grouped counts remain exact when
  more than 100 awards exist.
- Cache the first page for 60 seconds with the existing 24-hour stale ceiling.
- Publish cached groups immediately and revalidate using the existing
  stale-while-revalidate path.
- Load a resource reaction bar with its detail screen.
- Load note reactions only when the note reaction bar appears. Do not eagerly
  issue a reaction request for every note in every loaded discussion page.
- Coalescing and account isolation come from the existing session client cache
  and read coalescer.
- Empty reaction state is valid content and must not show a permanent spinner.
- A failed reaction read must not hide the issue, merge request, note body, or
  previously cached reactions.

The service invalidates only the affected awardable's first-page reaction
cache after a decoded mutation success. It does not invalidate the issue,
merge request, discussion, or unrelated note caches.

### Optimistic mutation

The model keeps confirmed server awards separate from temporary overlays:

- Pending add: add one visual count and mark the group as selected without
  inventing a server ID.
- Successful add: replace the overlay with the decoded server award.
- Pending remove: hide the selected exact current-user award ID.
- Successful remove: delete that exact award from confirmed state.
- Rejected add/remove: remove the overlay, restoring the exact prior state.

One mutation per emoji name per awardable may be in flight. A repeated tap on
that name is coalesced. Different names may proceed independently because
their overlays and rollback snapshots do not overlap.

If malformed server state contains multiple current-user awards with the same
name, a toggle removes one exact award at a time. The group remains selected
while another current-user award remains, preserving truthful state.

### Delivery uncertainty

The existing comment-specific delivery-certainty classification would become
duplicate logic. Before reaction mutation work, promote it to a small shared
core mutation certainty value used by comments and reactions.

- Local request construction, insufficient access, refresh failure, 401, 403,
  404, and 400/422 mean the operation was rejected.
- Rate limits, 5xx, unknown HTTP responses, connectivity loss, cancellation,
  invalid response, decode failure, and transport failure mean delivery is
  unknown.

Both categories remove the optimistic overlay and restore the last confirmed
state. For delivery-unknown failure, the same emoji action is blocked until a
forced reaction refresh resolves actual server state. Glab must not blindly
repeat an add or delete whose first delivery may have succeeded.

There is no automatic mutation retry. Authentication failures continue through
the existing `AppSession` recovery path.

### Read-only behavior

`read_api` sessions:

- Load and display all reaction groups.
- Do not show an enabled picker.
- Do not make group chips interactive.
- Expose a concise accessibility explanation that reaction changes require the
  `api` scope.

The UI will not pressure the user to broaden access.

### UI composition

Create one compact reusable reaction bar for resource and note targets:

- Horizontally wrapping or scrolling grouped reaction chips.
- Selected styling when the current user has an award in the group.
- A compact add-reaction control using Liquid Glass because it is interactive.
- No glass treatment on static chips or content.
- A bounded picker presented with a lightweight menu or popover.
- A subtle inline retry affordance for read failures.
- A concise failure message for mutation rollback.
- Progress shown inside the affected chip/control rather than with a screen-
  level spinner.

Issue and merge-request reactions sit beneath the detail header. Note reactions
sit after rendered Markdown inside the existing note card. System activity
does not show an add control.

Accessibility requirements:

- Each group announces emoji name, count, and whether the current user reacted.
- Interactive groups announce whether activation adds or removes the reaction.
- Pending groups announce that an update is in progress.
- The picker control has a stable label, hint, and identifier.
- Count changes are visible to VoiceOver through the updated group value.
- Controls remain usable with accessibility Dynamic Type and Reduce
  Transparency.

## Planned implementation sequence

1. Add tests for shared delivery certainty, bodyless `DELETE`, and no automatic
   or reactive retry of `DELETE`.
2. Implement the small request-layer and shared-certainty changes.
3. Add awardable, individual award, picker item, and grouped presentation
   models with decoding and grouping tests.
4. Add issue, merge-request, issue-note, and merge-request-note endpoint tests
   for list, add, and exact-ID delete.
5. Implement the live loading/mutation service with pagination, targeted cache
   invalidation, and tests.
6. Write model tests for cached/network publication, current-user selection,
   optimistic add/remove, exact rollback, repeated taps, cancellation,
   delivery-unknown refresh gating, read-only behavior, authentication failure,
   and distinct accounts.
7. Implement the observable model until those tests pass.
8. Add the reusable reaction bar to resource headers and non-system discussion
   notes.
9. Run focused tests and commit each coherent layer to `master`.
10. Build and inspect deterministic issue, merge-request, note, read-only,
    loading, empty, failed, pending, rollback, dark/light, large Dynamic Type,
    and Reduce Transparency states in an iPhone 17 Pro Simulator.
11. Re-run the production build with the configured read-only self-managed
    account. Confirm reactions load and no mutation control can send a request.
12. Run the complete test suite, isolated performance suites where necessary,
    static analysis, privacy/logging scans, and an account-isolation audit.
13. Perform the required deep review, record findings below, write a repair
    plan before any material repair, fix every finding, and repeat affected
    verification.

## Test matrix

### Request layer

- Bodyless `DELETE` construction
- Write capability enforcement
- No generic retry for `POST` or `DELETE`
- No reactive OAuth replay for `POST` or `DELETE`
- Proactive expired-token refresh before a first mutation attempt

### Domain and endpoints

- Decode standard and custom-named awards
- Preserve every server award ID
- Group identical names
- Identify all current-user award IDs
- Stable ordering and fallback labels
- Issue resource paths
- Merge-request resource paths
- Issue-note paths
- Merge-request-note paths
- Add query encoding without colons
- Delete exact award ID
- Pagination metadata

### Loading and cache

- Empty result
- Cached-first publication
- Network revalidation
- Multi-page append without duplication
- Stale cache retained after refresh failure
- Initial and retry failures
- Cancellation
- Only affected target invalidated after success
- No invalidation after failure
- Separate account cache keys

### Mutation model

- Read-only guard never calls the mutator
- Optimistic add and decoded reconciliation
- Optimistic exact-ID removal
- Rejected add rollback
- Rejected remove rollback
- Delivery-unknown rollback and forced-refresh gate
- Repeated same-name tap coalescing
- Independent different-name mutations
- Duplicate current-user server awards
- Authentication failure propagation
- Cancellation
- Account switching creates isolated state

### UI and Simulator

- Issue resource reactions
- Merge-request resource reactions
- Issue-note reactions
- Merge-request-note reactions
- Unknown/custom-name fallback
- Empty and loading states without persistent spinners
- Add picker and selected group
- Pending add/remove
- Rejected rollback
- Delivery-unknown recovery
- Read-only display
- System activity without mutation control
- Rapid taps
- Light and dark appearance
- Accessibility Dynamic Type
- VoiceOver labels/identifiers
- Reduce Transparency

## Success criteria

- Individual award IDs survive decoding, grouping, optimistic updates, and
  reconciliation.
- Issue, merge-request, and note endpoints match GitLab documentation.
- No mutation is issued without write capability.
- The first tap updates immediately and a repeated in-flight tap cannot create
  drift or duplicate requests.
- Every failed optimistic mutation restores the exact confirmed state.
- Delivery-unknown mutations are not blindly repeated.
- Only the affected reaction cache is invalidated after success.
- Reactions remain visible and non-interactive for a read-only account.
- No note-reaction N+1 burst is triggered for off-screen discussion content.
- Simulator inspection shows no clipping, stuck progress, unreadable fallback,
  broken sheet/menu, or inaccessible control.
- Focused tests, the complete functional suite, static analysis, and the
  required deep review pass.

## Deep review checklist

Complete after implementation:

- [ ] Endpoint and HTTP method correctness
- [ ] Exact award ID preservation and deletion
- [ ] Group count and current-user-state correctness
- [ ] Optimistic overlay and rollback correctness
- [ ] Duplicate tap and concurrent-name safety
- [ ] Delivery-unknown replay safety
- [ ] Pagination and cache invalidation scope
- [ ] Account and host isolation
- [ ] Read-only and authentication behavior
- [ ] Task cancellation and retained-task safety
- [ ] Accessibility and Dynamic Type
- [ ] Confidential logging and privacy
- [ ] Duplicate code and unnecessary abstraction
- [ ] Static analysis and complete test results

### Findings

Pending implementation.

### Repair plan

Pending review findings. If any material issue is found, write its concrete
repair steps and regression test here before editing production code.

## Non-goals

- Full searchable emoji catalog
- Custom-emoji discovery, upload, or image rendering
- Reactions on snippets, epics, commits, wikis, tasks, or objectives
- Displaying the complete list of users behind a reaction group
- Administrator deletion of another user's award
- Offline mutation queues
- Background mutation retries
- Push or webhook-driven reaction updates
- Live mutations with the configured read-only token
