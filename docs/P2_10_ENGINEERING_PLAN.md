# P2-10 Engineering Plan — Compact Merge-Request Review Controls

## Status

- Planning: complete
- Implementation: in progress
- Verification: in progress
- Deep review: not started

This document is the required plan for P2-10. Production code must not be
changed for this feature until this plan is committed.

## Outcome

Merge-request details use three compact review affordances:

1. A floating changed-files capsule opens the existing diff viewer and shows
   exact file, addition, and deletion counts when GitLab supplies them.
2. One Activity strip summarizes system-only discussion events. The strip and
   its individual events can be expanded without turning every event into a
   large card.
3. Compact top-trailing comment controls on merge-request and issue details
   open the existing Markdown composer. Read-only accounts can inspect why
   commenting is unavailable.

These controls must reduce occupied space without hiding user comments or
making loading of one optional summary block the merge-request screen.

## Existing-code audit

### Merge-request detail and diffs

- `GitLabMergeRequestDetailView` owns independent detail, approval, and
  discussion models and loads them concurrently.
- `GitLabMergeRequestDetailContent` currently renders a full Changes section
  with a REST `changes_count` sentence and a dedicated glass button.
- `changes_count` is a string, populates asynchronously, and can be capped at
  `"1000+"`. It is useful as a fallback but cannot provide exact additions or
  deletions.
- The existing changed-files destination uses the paginated REST `/diffs`
  endpoint, a head-SHA-aware response-cache key, off-main-actor parsing, and
  lazy UIKit rows. It must remain the only diff-viewer implementation.
- Downloading every `/diffs` page just to derive aggregate counts would add
  unnecessary latency, transfer, decoding, and memory pressure.

### Requests and caching

- `GitLabRequestBuilder` currently anchors every initial request at
  `GitLabHost.apiBaseURL` (`<site-root>/api/v4`).
- GitLab GraphQL uses `<site-root>/api/graphql`, including self-managed
  installations under a relative URL root. Request construction therefore
  needs one explicit GraphQL target; it must not accept an arbitrary URL.
- `GitLabSessionClient` enforces the endpoint's declared read/write
  capability. A GraphQL query is an HTTP POST but requires only read access.
- The response cache deliberately creates keys only for GET endpoints. The
  GraphQL summary POST will not be written to disk or sent with conditional
  GET validators in P2-10. Its observable model retains the result for the
  lifetime of the detail screen, while the REST detail cache supplies an
  immediate fallback file count.
- The generic client does not reactively retry POST after a surprise 401.
  Proactive OAuth refresh still occurs. P2-10 will not weaken that
  duplicate-mutation safety rule for one query.

### Discussions and composer

- `GitLabDiscussionSection` currently renders every system-only discussion as
  the same large card used for user threads.
- System bodies can contain server-generated HTML fragments. The bounded
  Markdown subset intentionally does not interpret arbitrary HTML, so those
  fragments can appear literally and occupy substantial space.
- `GitLabDiscussion.isSystemActivity` already identifies discussions whose
  notes are all system notes. Mixed system/user threads are not classified as
  activity and must remain intact.
- First-page discussion responses are cached and later pages remain in
  memory. Pagination is currently triggered by the final rendered discussion
  card; grouping system activity requires a bottom sentinel based on the last
  unfiltered discussion so all-activity pages can still paginate.
- The section currently owns composer presentation, including new-comment
  and reply targets, reconciliation, drafts, and read-only messaging. P2-10
  moves presentation ownership to each resource-detail boundary and reuses
  the same composer and model reconciliation path.
- Merge-request detail already uses the compact top-trailing action after the
  initial P2-10 implementation. Issue detail still shows the older large
  inline control, so the follow-up must make their presentation consistent
  without introducing a second posting path.

## Official GitLab contracts

- The REST
  [single merge request endpoint](https://docs.gitlab.com/api/merge_requests/#get-single-mr)
  returns `changes_count` as a string. It is asynchronous and capped at
  `"1000+"` for very large changes.
- The paginated REST
  [merge-request diffs endpoint](https://docs.gitlab.com/api/merge_requests/#list-merge-request-diffs)
  returns file diffs and flags, not aggregate additions and deletions.
- GitLab's [GraphQL API](https://docs.gitlab.com/api/graphql/) is served at
  `/api/graphql`, accepts authenticated JSON POST requests, and permits
  queries with `read_api`; mutations require `api`.
- The current
  [GraphQL reference](https://docs.gitlab.com/api/graphql/reference/)
  exposes `Query.mergeRequest(id:)` and
  `MergeRequest.diffStatsSummary`. `DiffStatsSummary` provides `additions`,
  `deletions`, `changes`, and `fileCount`.
- A GraphQL response can return HTTP 200 with a null field and an `errors`
  collection. Missing query data is compatibility unavailability, not a
  decodable zero count.
- Self-managed instances can lag GitLab.com. A missing root field, missing
  `diffStatsSummary`, permission restriction, or null summary must degrade to
  the REST count without disabling changed-file navigation.

## Architecture

Keep the existing SwiftUI Model-View architecture. The feature does not
justify MVVM, MVI, TCA, a coordinator, or an app-wide networking rewrite.

### API target and endpoint

Add a closed `GitLabAPIRequestTarget`:

- `.restV4` uses `GitLabHost.apiBaseURL`.
- `.graphQL` uses a derived `GitLabHost.graphQLURL`.

Existing endpoint factories default to `.restV4`. Only a dedicated GraphQL
factory can select `.graphQL`; callers cannot supply an arbitrary base URL.
Pagination remains REST-only and keeps its exact origin/root validation.

The summary query is static:

```graphql
query GlabMergeRequestDiffSummary($id: MergeRequestID!) {
  mergeRequest(id: $id) {
    diffStatsSummary {
      additions
      deletions
      changes
      fileCount
    }
  }
}
```

The variable is the REST merge request's global database ID represented as
`gid://gitlab/MergeRequest/<id>`. The request body is never described or
logged. Request construction applies the active session's normal OAuth
Bearer or personal-token header and declares `.read` access.

### Diff-summary domain and state

Introduce:

- `GitLabMergeRequestDiffSummary`, an immutable value containing nonnegative
  additions, deletions, changes, and file count.
- `GitLabMergeRequestDiffSummaryAvailability`, either `.available(summary)`
  or `.unavailable`.
- `GitLabMergeRequestDiffSummaryLoading`, an injected read-only dependency.
- A focused `GitLabResourceDetailModel` specialization owned by the floating
  summary link for one MR global ID.

The live loader maps a valid complete summary to `.available`. A successful
GraphQL envelope with missing/null/negative fields maps to `.unavailable`.
HTTP authentication failures remain actionable so `AppSession` can handle
them. Other transport/server/decoding failures stay in the summary model but
only affect the capsule's exact statistics.

The capsule derives presentation in this order:

1. Valid GraphQL summary: exact `N files`, green `+A`, red `−D`.
2. Loading: compact progress plus normalized REST `changes_count` when
   available.
3. Unavailable or failed: normalized REST count, including `"1000+"`.
4. No usable count: `Changed files`.

The entire capsule is one accessible navigation action. It opens the existing
head-SHA-aware changed-files view. If GitLab is still preparing the diff, show
one compact noninteractive preparation status instead.

The summary is loaded concurrently with visible content from its own task and
retried if the MR head SHA changes. It does not delay detail, readiness,
reactions, Markdown, discussion, or navigation.

### Activity presentation

Add a pure nonisolated presentation helper that partitions loaded
discussions:

- System-only discussions are flattened into activity notes while preserving
  GitLab's discussion and note order.
- Empty discussions and mixed system/user discussions remain in the normal
  conversation collection.
- User threads retain their original order and stable IDs.

One Activity strip appears before conversation cards when activity exists.
It starts collapsed and shows the total event count. Expanding it reveals
stable rows; every row starts collapsed and can independently reveal its full
normalized body.

System-note normalization is a small bounded plain-text operation, not a
general HTML or Markdown parser:

- Enforce a maximum source length and output length.
- Remove only tag-shaped fragments, convert common block/list breaks to
  whitespace, decode a small named/numeric entity set, and collapse
  whitespace in linear time.
- Preserve readable literal text for malformed or unmatched markup rather
  than scanning without a bound or dropping the remainder.
- Use a concise fallback such as `Activity details unavailable` for empty
  normalized output.

The existing Markdown renderer remains unchanged for user comments and mixed
threads. A bottom pagination sentinel receives the last unfiltered discussion
so grouping cannot prevent next-page loading.

### Comment presentation

The MR and issue detail boundaries each own
`GitLabDiscussionComposerTarget?` and present the existing
`GitLabDiscussionComposerView`.

- A native top-trailing toolbar button with a compose symbol is the
  new-comment control on both details. iOS 26 supplies the floating toolbar
  Liquid Glass treatment.
- A write-enabled tap selects `.newDiscussion`.
- A read-only tap presents a concise capability explanation; it never opens a
  send-capable composer.
- Reply buttons select `.reply(discussionID:)` through the same owner.
- Success calls one shared `GitLabDiscussionsModel` reconciliation method, so
  new comments and replies keep the existing returned-server-ID behavior.
- Draft storage, explicit sending, ambiguous-failure handling, cache
  invalidation, and mutation endpoints remain exactly those from P2-04.

The shared discussion section no longer renders a resource-level add-comment
control. It still owns discussion content and invokes the injected reply
closure, while each detail screen owns new-comment presentation.

## Liquid Glass and layout

- Custom glass remains limited to interactive floating controls.
- The diff capsule and existing Open in GitLab control share one bottom
  `GlassEffectContainer` and remain separate actions.
- Activity is content, not a glass control; use a compact standard disclosure
  surface.
- The comment action uses the native iOS 26 toolbar glass rather than drawing
  another material layer.
- Counts use monospaced digits, retain sufficient color contrast, and never
  rely on color alone in accessibility labels.
- Layout must fit narrow iPhone widths and accessibility Dynamic Type without
  covering the Home/Todos tab bar or discussion content.

## Follow-up plan — consistent issue comment control

Screenshot review found that issue detail retained the older large inline
comment control after merge-request detail adopted the compact toolbar action.
This follow-up is presentation-only.

Implementation:

1. Move issue composer-target state and sheet presentation from issue detail
   content to the issue detail boundary, matching merge-request ownership.
2. Add the same native top-trailing compose action after issue detail loads.
3. Reuse `GitLabDiscussionComposerLaunchPolicy`: writable accounts open the
   existing composer and read-only accounts receive the same concise
   capability explanation without creating a composer target.
4. Pass one composer-launch closure into discussion content for replies and
   remove the issue-only inline mutation surface.
5. Preserve draft storage, server-ID reconciliation, authentication handling,
   comment endpoints, mutation certainty, and cache invalidation unchanged.

Verification:

- Existing launch-policy and composer tests remain green.
- Simulator inspection proves issue and merge-request details expose the same
  top-trailing action, no inline add-comment button remains, replies still
  target the correct discussion, and read-only taps issue no mutation.
- Include both resource-detail composer paths in the P2-10 deep-review gate.

## Follow-up plan — compact horizontal reaction picker

Screenshot review of the first P2-10 build found that the existing reaction
picker trigger and system `Menu` consume too much space. This follow-up is a
presentation-only refinement; it does not change the Phase 2 reaction API,
cache, optimistic mutation, delivery-certainty, or account-isolation
contracts.

Implementation:

1. Keep `GitLabEmojiReactionsModel` as the single owner of loading, selection,
   pending mutation, failure, and reconciliation state.
2. Replace the padded glass face-symbol trigger with one plain emoji trigger.
   Its visible content has no bubble or label, while its invisible tap target
   remains at least 44 points.
3. Replace the vertical labeled `Menu` with an anchored popover containing one
   horizontal row of the existing bounded common emoji set.
4. Anchor the popover to the trigger's bottom-leading point and prefer a top
   arrow edge, placing it below and toward the left of the comment. Allow the
   system to reposition it only when required to keep the popover on-screen.
5. Render picker choices as emoji only. Preserve accessible names, selected
   and updating values, add/remove hints, stable identifiers, disabled
   pending/uncertain states, and dismiss-before-mutation behavior.
6. Use the native popover material as the only picker surface. Do not add
   nested glass effects around each emoji.

Verification:

- Existing reaction domain/model/endpoint tests must remain green.
- Simulator interaction must prove the trigger opens a horizontal picker,
  every emoji has a stable accessibility action, a selection dismisses the
  popover, and the existing optimistic/error path remains unchanged.
- Inspect dark/light appearance, standard/accessibility Dynamic Type, Reduce
  Transparency, and overlap with the compact activity and bottom controls.
- Include the trigger and popover in the P2-10 deep-review gate.

## Failure and compatibility behavior

| Condition | Presentation |
| --- | --- |
| GraphQL summary succeeds | Exact files, additions, and deletions |
| Summary field/query unsupported | REST count fallback; diff remains openable |
| GraphQL HTTP/server/decoding failure | REST fallback; exact summary can retry after head change/reentry |
| GraphQL authentication failure | REST fallback plus active-account reauthentication handling |
| REST count is empty | `Changed files` |
| Diff head SHA is absent | Compact `GitLab is preparing this diff` status |
| Discussion refresh fails | Retain existing comments/activity and existing retry UI |
| System body is malformed or empty | Bounded readable/fallback activity text |
| Read-only comment tap | Capability explanation; no composer and no request |

No optional summary error becomes a full-screen MR failure.

## Test-first implementation order

1. Request construction tests:
   - GitLab.com and self-managed relative-root GraphQL URLs.
   - Static POST body, global ID variable, JSON headers, read requirement.
   - OAuth/PAT headers and description/body redaction.
   - Existing REST construction and trusted pagination remain unchanged.
2. Summary decoding/loader tests:
   - Valid complete summary.
   - Null merge request, null summary, GraphQL error-only response, missing
     fields, negative fields, unknown fields.
   - Read-only client acceptance.
   - Authentication, forbidden, not-found, server, and decoding behavior.
3. Summary presentation tests:
   - Singular/plural file text, large values, `"1000+"` REST fallback,
     loading, unavailable, failure, and preparing states.
4. Activity tests:
   - Stable partition/order, all-system, mixed thread, empty discussion.
   - HTML lists, breaks, entities, malformed markup, Unicode, empty output,
     source/output bounds, and deterministic preview.
   - Pagination asks with the final unfiltered discussion.
5. Composer ownership tests:
   - Shared reconciliation for returned new discussions and replies.
   - Read-only issue and merge-request controls cannot create a composer
     target.
   - Reply identity remains exact.
6. Implement the smallest vertical slices in the same order and run focused
   tests after each.

New unit tests use Swift Testing. Existing UI automation remains Maestro or
XCUITest as appropriate; it must use stable accessibility identifiers rather
than coordinates whenever possible.

## Performance plan

- One small GraphQL query replaces an all-diff-pages counting strategy.
- Summary loading never runs diff parsing and never blocks the main actor.
- Activity partitioning is linear in loaded discussions and notes.
- Text normalization is linear and capped before allocation; no regex with
  pathological backtracking and no WebView/HTML parser is introduced.
- Activity rows are lazy and keep normalized immutable strings rather than
  reparsing Markdown in SwiftUI `body`.
- Existing large Markdown, long-discussion, diff-collection, and unified-diff
  Release performance suites remain green. Add a long-activity normalization
  fixture and measure it in an optimized build.

Simulator measurements are relative evidence only, not physical-device CPU,
memory, graphics, or thermal fidelity.

## Simulator verification matrix

Use only the configured iPhone 17 Pro Simulator:

- Dark and light appearance.
- Standard and accessibility Dynamic Type.
- Reduce Motion on/off.
- Reduce Transparency on/off.
- MR with exact GraphQL counts.
- GraphQL unavailable/failure fallback.
- MR while diff preparation is incomplete.
- No activity, one activity, many activities, mixed comments/activity, and
  all-activity paginated content.
- Activity strip collapse/expand and independent event expansion.
- Diff capsule tap, file list, file diff, and back navigation.
- Write-enabled deterministic comment and reply composer presentation without
  a live POST.
- Issue and merge-request toolbar action consistency with no inline
  add-comment control.
- Read-only live self-managed account: comment explanation and zero mutation
  on both resource details.
- VoiceOver labels/actions for the three refined controls.
- Rotation and bottom-control/tab-bar nonoverlap.

Capture screenshots for at least dark standard, light standard, accessibility
Dynamic Type, expanded activity, and the diff summary/fallback states. Restore
Simulator accessibility and appearance settings afterward.

## Deep-review gate

After implementation and all first-pass checks:

1. Review every P2-10 production/test/document change and the request,
   session, response-cache, diff, discussion, composer, and navigation
   boundaries it touches.
2. Look specifically for credential/body logging, arbitrary GraphQL URLs,
   incorrect relative-root paths, read/write confusion, accidental POST
   retries, stale stats, duplicate composer paths, discussion loss/reordering,
   pagination starvation, unbounded text work, disclosure identity bugs,
   main-actor work, inaccessible icon-only controls, excessive glass, and
   tab-bar/control overlap.
3. Record material findings here.
4. Write a repair plan before editing.
5. Add regression/performance tests, implement every repair, rerun the full
   verification matrix, and repeat the review.

P2-10 is not complete until the review has no open material finding.

## Explicit non-goals

- Replacing the existing diff viewer or parser.
- Side-by-side iPhone diffs, inline code comments, suggestions, or commit
  browsing.
- Caching arbitrary GraphQL POST bodies in the generic disk response cache.
- A general GraphQL client or generated schema layer.
- A general HTML renderer or expanding the Markdown parser to execute raw
  HTML.
- Editing, deleting, resolving, or reacting to system activity.
- Redesigning issue-detail controls.
- Live posting with the configured read-only self-managed token.
- Physical-device installation, testing, or performance claims.
