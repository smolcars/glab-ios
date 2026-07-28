# P2-08 Engineering Plan — Merge Request Readiness

Last updated: 2026-07-28

Status: complete; implementation, verification, and deep-review repairs passed.

Glab has not shipped, so internal response and presentation models may change
without migration. The feature is read-only. Verification will use an iPhone
17 Pro Simulator and the configured self-managed read-only account; no live
mutation is authorized.

## Outcome

The merge-request detail screen gives a compact, accessible answer to:

- Is GitLab currently able to merge this request?
- Is the head pipeline passing, running, failed, absent, or unknown?
- Are required approvals satisfied?
- Is the merge request a draft?
- Are there merge conflicts?
- Are blocking discussions resolved?

The summary must never infer “ready” from missing fields or an unknown status.
Partial or unavailable data remains visible without replacing the already
loaded merge-request detail with a full-screen failure.

## Source of truth

The plan is based on GitLab's official documentation reviewed on 2026-07-28:

- [Merge requests API](https://docs.gitlab.com/api/merge_requests/)
- [Merge request approvals API](https://docs.gitlab.com/api/merge_request_approvals/)
- [Pipelines API](https://docs.gitlab.com/api/pipelines/)
- [Discussions API](https://docs.gitlab.com/api/discussions/)
- [REST API deprecations](https://docs.gitlab.com/api/rest/deprecations/)

Relevant contracts:

- `GET /projects/:id/merge_requests/:merge_request_iid` exposes
  `detailed_merge_status`, `has_conflicts`, `blocking_discussions_resolved`,
  `draft`, and `head_pipeline`.
- GitLab explicitly says to use `detailed_merge_status` instead of the
  deprecated `merge_status`. Mergeability is computed asynchronously, so
  `checking`, `unchecked`, `preparing`, and `approvals_syncing` are pending
  states rather than failures.
- `has_conflicts` depends on GitLab's asynchronous merge-status calculation.
  A `true` value or the `conflict` detailed status is blocking; absent or
  premature data must not be treated as conflict-free.
- `head_pipeline` is the preferred pipeline object because it contains more
  information than the legacy `pipeline` field. GitLab omits it when the
  current user cannot view pipelines. A missing object can also mean the merge
  request has no pipeline, so absence is neutral and explicitly presented
  rather than treated as a request failure.
- `GET /projects/:id/merge_requests/:merge_request_iid/approvals` is
  authenticated and available on Free, Premium, and Ultimate. The
  `/approval_state` endpoint is Premium/Ultimate and is not required for this
  slice.
- Approval semantics differ between Community and Enterprise editions.
  `approvals_required == 0` means no approval is required even if Community
  Edition reports `approved == false`; otherwise `approved` and
  `approvals_left` determine the summary.
- `blocking_discussions_resolved` is the merge-request-level answer for
  blocking threads. The UI does not scan every paginated discussion merely to
  derive readiness.

The configured self-managed instance was sampled read-only on 2026-07-28. A
representative merge request returned a non-draft state, an unresolved-
discussion merge status, no conflict, unresolved blocking discussions, a
running head pipeline, and a successful approvals response with the
requirements satisfied. No token, host, project path, user, pipeline ID,
comment body, or commit SHA is recorded.

## Existing implementation audit

- MR detail and discussion loading already start concurrently and retain
  cached content when refresh fails.
- `GitLabMergeRequest` already decodes draft compatibility and exact diff
  revision fields, but not readiness, conflict, blocking-discussion, or head-
  pipeline fields.
- The existing detail response is cached by account and request URL through
  `GitLabSessionClient`; no new persistence layer is needed.
- `GitLabResourceDetailModel` already provides cache-first events, retained
  refresh failures, cancellation restoration, and authentication propagation.
- The detail view receives one account-bound live loader. Account switching
  rebuilds the signed-in feature hierarchy, so readiness models should use
  that same loader rather than own credentials or a global client.
- The paginated discussion model already displays unresolved threads. The
  readiness summary should use the MR-level blocking result and keep the
  existing discussion section as the detailed destination.
- There is no pipeline, approval, or readiness domain model and no readiness
  UI to reuse.

## Architecture

Keep the existing SwiftUI Model-View architecture:

1. Extend the MR response with optional, defensive readiness fields and a
   minimal head-pipeline response.
2. Add one immutable readiness derivation value that maps raw GitLab strings
   into stable presentation states.
3. Add one approval response and availability value.
4. Add a narrow approval-loading protocol implemented by
   `LiveGitLabMergeRequestLoader`.
5. Reuse `GitLabResourceDetailModel` for cached approval state.
6. Derive the final summary from the currently loaded MR plus approval model
   state. Do not duplicate the MR detail or discussion loaders.

No coordinator, app-wide store, pipeline-list model, background task, or
separate cache database is warranted.

## API and decoding contracts

### Merge request

Decode as optional:

- `detailed_merge_status: String?`
- `has_conflicts: Bool?`
- `blocking_discussions_resolved: Bool?`
- `head_pipeline: GitLabMergeRequestHeadPipeline?`

The head-pipeline response contains only:

- stable numeric `id`
- raw `status`
- optional `web_url`

Unknown fields and unknown status strings remain decodable. Pipeline web URLs
must pass the existing safe web-URL validation before becoming a Link.

### Approvals

Add:

`GET /projects/:project_id/merge_requests/:merge_request_iid/approvals`

Decode only:

- `approved: Bool?`
- `approvals_required: Int?`
- `approvals_left: Int?`
- `approved_by` as a minimal array sufficient to expose the approver count

The stable availability value is:

- `.available(summary)`
- `.unavailable`

HTTP 403 and 404 map to `.unavailable` after the MR itself has loaded. They do
not show a network-error row. Authentication, connectivity, rate-limit,
decoding, and server errors remain typed errors. A cached prior value stays
visible when a refresh fails.

## Readiness derivation

Use explicit stable states:

- `.satisfied`
- `.blocked`
- `.pending`
- `.notRequired`
- `.unavailable`
- `.unknown`

Each row owns a short title and explanation, but the domain values do not own
SwiftUI colors or views.

### Overall state

- `.ready` only when `detailed_merge_status == "mergeable"` and no decoded
  component explicitly contradicts it.
- `.pending` for transient GitLab states such as `checking`, `unchecked`,
  `preparing`, `approvals_syncing`, and `ci_still_running`.
- `.blocked` for documented non-transient blockers, including conflicts,
  draft status, unresolved discussions, required approvals, failed required
  CI, rebase, requested changes, status checks, security policies, locks,
  missing associations, merge time, or a closed/non-open MR.
- `.unknown` for an absent or unrecognized detailed status. Preserve the raw
  status only in a bounded diagnostic title; do not log it.

An explicit decoded conflict, draft, unresolved discussion, missing approval,
or failed pipeline overrides a nominal `mergeable` status to prevent a false
ready result from inconsistent or stale partial responses.

### Pipeline

- `success` is satisfied.
- `created`, `waiting_for_resource`, `preparing`, `pending`, `running`, and
  `scheduled` are pending.
- `failed`, `canceled`, and `canceling` are blocked.
- `skipped` is satisfied but titled “Skipped”.
- `manual` is pending and titled “Manual action”.
- absent is `.notRequired` with “No visible pipeline”.
- unknown strings are `.unknown`.

### Approvals

- `approvals_required == 0` is `.notRequired`.
- `approved == true` or `approvals_left == 0` with a positive requirement is
  satisfied.
- a positive `approvals_left` is blocked and preserves the remaining count.
- 403/404 is unavailable.
- absent or contradictory fields are unknown.

### Draft, conflicts, and discussions

- Use `draft`, then legacy `work_in_progress`; if both are absent, draft state
  is unknown rather than silently false.
- `has_conflicts == true` or detailed status `conflict` is blocked.
- `blocking_discussions_resolved == false` or detailed status
  `discussions_not_resolved` is blocked.
- Missing fields are unknown unless the detailed status supplies the matching
  authoritative blocker.

## State, loading, caching, and cancellation

- Start MR detail, approvals, and discussions concurrently.
- `head_pipeline`, conflicts, draft, discussions, and detailed status arrive
  in the existing MR request. Do not request the pipelines list.
- Cache both MR detail and approvals by the existing account-scoped response
  cache key with a new 60-second-fresh/24-hour-maximum readiness policy.
- Opening a recently viewed MR can publish cached values immediately and
  revalidate stale data. Pull to refresh always revalidates MR, approvals, and
  discussions concurrently.
- Retain loaded MR and approval values on refresh failure and show a compact
  inline refresh error for the affected source.
- Cancellation restores prior model state. The active account owns the client
  and cache key, and account switching reconstructs the view/model tree.
- Do not automatically poll transient statuses in Phase 2. Explicit refresh
  and normal cache revalidation are sufficient for the first slice.

## UI and accessibility

Place a compact “Merge readiness” section directly after the MR header:

- one overall status row
- pipeline
- approvals
- conflicts
- discussions
- draft/review state

Use existing grouped surfaces and Liquid Glass controls where interactive.
Avoid six independent large cards. Each row has a distinct symbol plus text,
so color is never the only status channel.

- A valid head-pipeline URL makes the pipeline row a Link.
- The existing discussion section remains the detailed destination for
  unresolved threads.
- Approval count and remaining requirements are visible without requiring a
  paid approval-rules endpoint.
- Loading and approval-unavailable states occupy stable compact rows.
- Dynamic Type may wrap rows vertically; do not force one-line labels.
- VoiceOver labels include the check name, state, and explanation.

## Failure behavior

- Initial MR failure keeps the existing full-screen retry state.
- Initial approval connectivity/server/decode failure leaves the MR visible
  and shows “Approvals unavailable” with a compact retry path.
- A retained approval refresh failure keeps the prior approval result visible
  and shows a small refresh warning.
- 403/404 approvals are capability unavailable, not retry errors.
- 401 or refresh-token failures participate in existing account-scoped
  reauthentication.
- Unknown future detailed statuses or pipeline statuses display as unknown and
  prevent a ready verdict.

## Test plan

Write failures before implementation for:

1. MR decoding of detailed status, conflict, blocking discussions, pipeline,
   absent fields, unknown strings, and safe pipeline URL handling.
2. Approval endpoint path/access and response decoding, including Community
   Edition zero-requirement behavior.
3. Approval loader cache policy, cache-first events, 403/404 availability,
   retained refresh errors, cancellation, authentication, and account-bound
   reconstruction.
4. Overall derivation for mergeable, every transient category, representative
   blockers, absent status, and an unknown future status.
5. Pipeline success/running/failed/canceled/skipped/manual/missing/unknown.
6. Approval approved/pending/not-required/unavailable/unknown.
7. Draft, conflict, and discussion states with missing and contradictory data.
8. A stale or inconsistent `mergeable` response never overrides an explicit
   component blocker.
9. Concurrent detail/approval/discussion startup and refresh without a serial
   request waterfall.
10. Accessibility strings and stable row identity.

Use Swift Testing and protocol fakes. No live write test is permitted.

## Simulator verification

On an iPhone 17 Pro Simulator:

1. Inspect deterministic fixtures for ready, pending, blocked, missing
   pipeline, unavailable approvals, partial failure, and unknown future
   status.
2. Use the configured self-managed read-only account to inspect a real running
   pipeline, satisfied approvals, no conflict, and unresolved discussions.
3. Tap the pipeline Link only if it remains within the read-only system-browser
   flow; never trigger pipeline or approval mutations.
4. Pull to refresh and verify stable cached content, compact partial errors,
   and no duplicate requests or visible jumping.
5. Check dark/light appearance, standard and accessibility Dynamic Type,
   Reduce Motion, VoiceOver labels, and rapid back/navigation cancellation.
6. Capture and inspect screenshots, then restore settings, shut down every
   simulator, and quit Simulator.

## Implementation sequence

Keep `master` buildable with small pushed commits:

1. Response, endpoint, and readiness-domain contracts with failing tests.
2. Cached approval loader/model and partial-failure tests.
3. Concurrent detail integration and compact readiness UI.
4. Simulator verification, documentation, and deep-review repairs.

Do not stage or modify the owner's existing Xcode signing/configuration change.

## Non-goals

- Approve, unapprove, merge, retry, cancel, or run a pipeline.
- Paid per-rule approval details.
- Pipeline job lists, logs, artifacts, test reports, or security findings.
- Formal requested-change details.
- Background polling or push updates.
- Reimplementing GitLab mergeability rules locally.
- Counting unresolved threads by loading every discussion page.
- Cross-account readiness aggregation.

## Deep-review gate

After implementation and simulator verification:

1. Review every P2-08 diff for false-ready states, status fallthrough,
   Community/Enterprise approval assumptions, tier/version handling, request
   waterfalls, cache/account leakage, stale-value replacement, cancellation,
   unsafe links, duplicate loading/derivation, inaccessible color-only state,
   and unnecessary abstraction.
2. Record concrete findings below.
3. If anything material is found, write a repair plan before production edits.
4. Add regression tests, implement all repairs, repeat focused/full tests,
   static analysis, live read-only Simulator checks, and the final review.

### Findings

1. **Material — retained refresh failures could leave an optimistic ready
   verdict.** `GitLabResourceDetailModel` correctly retains cached MR and
   approval values when revalidation fails, but
   `GitLabMergeRequestReadiness` only received the retained values. If those
   values were mergeable and approved, the overall state could remain “Ready
   to merge” even though the latest MR or approval refresh failed. The existing
   inline errors disclosed the failure, but the optimistic summary still
   violated the feature's false-ready invariant.
2. **Fixed during Simulator verification — a section identifier masked every
   row identifier.** Applying `mergeRequests.readiness` to the containing
   section propagated that identifier to descendants, so the stable overall,
   pipeline, and approval identifiers were not exposed to accessibility
   automation. Removing only the redundant container identifier preserved the
   VoiceOver labels and exposed every row identity.
3. **Fixed during Simulator verification — the floating GitLab link obscured
   content at maximum Dynamic Type.** The compact action inherited the maximum
   accessibility text size and expanded over the readiness rows. Capping only
   that floating control at the first accessibility size retained its
   VoiceOver label and touch target while leaving all readiness content fully
   uncapped and scrollable.

The review found no additional material request waterfall, GitLab tier
assumption, account/cache leakage, unsafe pipeline link, mutation exposure,
duplicate state derivation, or color-only status issue. The MR, approval, and
discussion loads share one structured-concurrency group; response cache keys
remain account-scoped; 403/404 approvals remain capability-unavailable; and
unknown future statuses prevent a ready verdict.

### Repair plan

1. Add a regression test proving retained MR or approval refresh failures
   cannot produce `.ready`, while last-known component rows remain visible.
2. Add one refresh-failure input to the immutable readiness derivation. Preserve
   conservative blocked/pending/unknown results, but downgrade an otherwise
   ready result to unknown.
3. Feed the existing MR and approval `refreshError` state into the derivation;
   do not add another loader, cache, coordinator, or persistence layer.
4. Repeat focused tests, the complete suite, static analysis, cache/account
   isolation checks, and the live self-managed read-only Simulator refresh
   flow.

Repair status: complete. The regression test preserves last-known rows while
downgrading only an otherwise optimistic ready result. The reviewed production
build then passed the complete verification gate below.

## Final verification

Completed on 2026-07-28 using only the iPhone 17 Pro Simulator running iOS
26.5 and the configured self-managed read-only account:

- Focused endpoint, decoding, readiness, approval-loader/model, cache-policy,
  unknown-status, and stale-refresh regression tests passed.
- The complete Debug suite passed: 501 tests, representing 688 parameterized
  test cases, with zero failures, expected failures, or skips.
- Six existing Release performance tests for the surrounding markdown,
  discussion, and diff detail surfaces passed with testability enabled only
  for the test action.
- Xcode static analysis passed.
- Existing multi-account switching, active-account race, cache invalidation,
  request coalescing, variant isolation, and retained revalidation tests passed
  as part of the complete suite.
- Live read-only navigation showed the expected blocked summary for a real MR:
  passed head pipeline, two approvals remaining, no conflicts, resolved
  blocking discussions, and a non-draft review state.
- The pipeline glass Link opened the expected self-managed GitLab browser
  destination. Safari requested its independent GitLab login; no credential
  was entered and no mutation was attempted.
- Pull to refresh preserved the summary without an approval error.
- Dark and light appearance, standard and maximum accessibility Dynamic Type,
  Reduce Motion, stable accessibility row identifiers, scrolling, and the
  compact floating GitLab control passed visual and interaction checks.
- The final reviewed source was rebuilt, installed on the Simulator, and both
  the navigation and refresh flows passed again.
