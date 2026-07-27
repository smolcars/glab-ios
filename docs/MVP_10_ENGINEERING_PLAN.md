# MVP-10 engineering plan: merge requests

Last updated: 2026-07-27

## Outcome

Add read-only, paginated assigned and review-requested merge-request lists plus
a native merge-request detail screen. Both Home shortcuts must route to the
correct list mode, and each row must navigate by project ID plus merge-request
IID.

This phase does not add approvals, discussions, diffs, pipelines, merges, or
any other write action.

## Assumptions and API contract

- The instance is already represented by an authenticated
  `GitLabSessionClient`; MVP-10 adds no authentication behavior.
- Assigned work uses:
  `GET /merge_requests?scope=assigned_to_me&state=opened`.
- Review requests use:
  `GET /merge_requests?scope=reviews_for_me&state=opened`.
- Both initial lists request `order_by=updated_at`, `sort=desc`, and
  `per_page=20`.
- The loader follows GitLab's response `Link` URL for later pages instead of
  constructing page numbers.
- A detail uses
  `GET /projects/:id/merge_requests/:merge_request_iid`.
- Route identity is `(project_id, iid)`, not the globally unique response
  `id`.
- The current response `draft` field is the primary draft signal. Decode the
  documented legacy `work_in_progress` field only as a compatibility fallback
  when `draft` is absent.
- API-provided `web_url` values are exposed only when they are HTTPS,
  host-bearing, and contain no URL credentials.
- List merge-status fields can be stale unless GitLab performs an expensive
  recheck. Glab will not request a recheck and will not decode, infer, or
  present mergeability in this read-only MVP screen.

Sources:

- [GitLab Merge Requests API](https://docs.gitlab.com/api/merge_requests/)
- [GitLab REST pagination](https://docs.gitlab.com/api/rest/#pagination)

## Architecture

Keep the existing SwiftUI Model-View shape:

- `GitLabMergeRequestListMode` owns the assigned/review scope, title, and empty
  copy.
- `GitLabMergeRequest` and small nested response types decode only fields
  needed by the MVP UI.
- `GitLabMergeRequestEndpoints` builds the two list requests and project detail
  request.
- `GitLabMergeRequestLoading` is the test seam; the live loader delegates to
  `GitLabPaginatedSessionRequestSending`.
- One `MergeRequestsModel` instance owns one fixed list mode, pagination,
  refresh, filtering, de-duplication, and recoverable error state.
- `GitLabMergeRequestDetailModel` owns detail loading and retry state.
- `MergeRequestsView` creates its mode-specific model and routes to
  `GitLabMergeRequestDetailView`.
- `HomeView` maps both existing merge-request shortcuts to the new view.

Reuse the existing user-summary normalization, compact relative-time
formatter, Markdown description formatter, loading/empty/retry states, and
GitLab label styling. Extract a shared helper only where MVP-10 would otherwise
duplicate an existing correctness or presentation rule.

## Test-first implementation order

### 1. Response types and endpoints

Write failing tests for:

- assigned and review-request query construction;
- project ID plus IID detail routes;
- decoding draft and non-draft responses;
- the legacy `work_in_progress` fallback;
- empty descriptions, labels, assignees, reviewers, and absent optional
  timestamps;
- state presentation for opened, closed, merged, locked, and unknown values;
- rejection of unsafe web URLs.

Then add only the response fields and endpoint builders needed to pass them.

### 2. Loader and list state

Write failing tests for:

- passing the fixed list mode into the initial request;
- following the server-provided next-page URL;
- de-duplicating by project ID plus IID;
- local filtering over title, full reference, labels, branches, author,
  assignees, and reviewers;
- refresh replacement and preservation with a visible retry state on failure;
- incremental failure without removing loaded rows;
- cancellation and authentication-failure propagation.

Then implement the loader and list model.

### 3. Detail state

Write failing tests for:

- initial detail load and retry;
- cancellation restoring the previous state;
- authentication-failure propagation.

Then implement the detail model.

### 4. UI and Home routing

Build:

- separate “Assigned Merge Requests” and “Review Requests” list titles;
- dense rows with full reference, draft/state, title, labels, author,
  assignees/reviewers, source-to-target branches, comment count, and compact
  update time;
- search, pull to refresh, pagination, empty states, retained-content refresh
  failures, and retryable incremental failures;
- a read-only detail with description, state/draft, branches, author,
  assignees, reviewers, labels, comment count, and created/updated/closed/merged
  timestamps when supplied;
- a prominent validated “Open in GitLab” link;
- Home routing for both merge-request shortcuts.

## Verification gates

1. Focused endpoint/decoding tests pass.
2. Focused loader/list/detail model tests pass.
3. The complete signed unit-test suite passes on iPhone 17 Pro, iOS 26.5.
4. Xcode static analysis reports no code findings.
5. With the existing read-only simulator session, both Home shortcuts load the
   correct live list mode; representative rows and details are tapped and
   scrolled.
6. Assigned and review-requested list, empty/error states available from the
   live account, and a merge-request detail are visually inspected in light
   and dark appearance.
7. The implementation is committed to `master` in small, passing increments.
