# P3-07 Engineering Plan — GitLab Work-Item Status for Issues

Status: complete. Implementation, Simulator verification, safety gates, and
the required repeated deep review are complete.

Research date: July 28, 2026.

## Outcome

On a compatible Premium or Ultimate GitLab instance, Glab will show an issue's
current work-item status and let an eligible write-enabled account select only
statuses allowed by that issue's lifecycle.

Work-item status remains an optional enhancement. Ordinary REST `opened` and
`closed` issue state continues to load and work on Free, older, unlicensed,
disabled, or GraphQL-incompatible instances.

## Assumptions

- The REST issue loaded by Glab is the authoritative starting identity.
- GitLab status is available for issues and tasks, but P3-07 supports issues
  only.
- A status in `DONE` or `CANCELED` closes the work item. `TRIAGE`, `TO_DO`, and
  `IN_PROGRESS` keep or make it open.
- A status update requires both an account credential with write API access
  and GitLab's `updateWorkItem` permission for the exact work item.
- GitLab GraphQL fields involved in this feature are still marked
  experimental in the generated schema. Support must be detected from the
  response, not assumed from a host name or version number.
- The existing REST Close/Reopen action remains available and semantically
  separate from work-item status.

## Official sources

- [Work-item status](https://docs.gitlab.com/user/work_items/status/) defines
  tier, offering, history, lifecycle categories, state interaction, and
  permissions.
- [GraphQL API](https://docs.gitlab.com/api/graphql/) defines authentication,
  authorization, object identifiers, query-null behavior, mutation
  authorization errors, and limits.
- [Generated GraphQL reference](https://docs.gitlab.com/api/graphql/reference/)
  is the source of truth for the current fields and input/output types.
- [GraphQL queries and mutations](https://docs.gitlab.com/api/graphql/getting_started/)
  requires clients to request and handle mutation payload `errors`.
- [Work-item API migration guide](https://docs.gitlab.com/api/graphql/epic_work_items_api_migration_guide/)
  demonstrates opaque work-item global IDs and `workItemUpdate`.
- [GraphQL removed items](https://docs.gitlab.com/api/graphql/removed_items/)
  and [deprecations](https://docs.gitlab.com/update/deprecations/) reinforce
  capability detection for an experimental surface.

The current generated schema was also reconfirmed directly through GitLab.com's
production introspection response. Production introspection is a static schema
and is used only during development, never as an app runtime capability check.

## Current API contract

### Feature and lifecycle

Status is Premium and Ultimate functionality for GitLab.com, Self-Managed, and
Dedicated:

- introduced behind a feature flag in GitLab 18.2;
- generally available in GitLab 18.4;
- reusable lifecycles introduced behind a flag in 18.5 and generally
  available in 18.6;
- up to 30 statuses can belong to one lifecycle.

Categories are:

| GraphQL category | REST/work-item state |
| --- | --- |
| `TRIAGE` | open |
| `TO_DO` | open |
| `IN_PROGRESS` | open |
| `DONE` | closed |
| `CANCELED` | closed |

GitLab allows a status change for Planner, Reporter, Developer, Maintainer, or
Owner roles, and also for an issue author or assignee. Glab will not duplicate
that role logic. It will use the resource's `userPermissions.updateWorkItem`
value and let GitLab authorize the mutation.

### Identity query

The app will not manufacture `gid://gitlab/WorkItem/...` from the REST issue's
integer ID. `WorkItemID` temporarily accepts legacy `IssueID` values, but the
schema explicitly says that compatibility can be removed without notice.

The read path is:

1. Start with the loaded REST issue's positive `project_id` and `iid`.
2. Read `GET /projects/:project_id` and require the same project ID plus a
   non-empty `path_with_namespace`.
3. Query:

   ```graphql
   project(fullPath: $projectPath) {
     fullPath
     workItems(iids: [$iid], first: 2) {
       nodes { ... }
       pageInfo { hasNextPage }
     }
   }
   ```

4. Require the returned project path to match, exactly one node, no additional
   page, the same IID, and work-item type `Issue`.
5. Retain GitLab's returned opaque `WorkItemID` for later mutations.

`workItemsByReference` accepts URL references, but it is not the chosen
identity path. During read-only compatibility research, an authenticated
self-managed instance returned an authorization/not-found GraphQL error for a
REST-readable issue through `workItemsByReference`; querying the same resource
under its resolved project full path returned one work item successfully.
Project path plus IID also follows GitLab's documented identifier guidance.

The `first: 2` limit deliberately detects an invalid multiple-match result.
Allowed statuses themselves are currently a bounded list, not a paginated
connection, so the implementation must not invent an allowed-status pagination
API.

### Status fields

The work-item node will request:

- `id`, `iid`, `state`, `updatedAt`, `lockVersion`, and `webUrl`;
- `userPermissions.updateWorkItem`;
- `workItemType.name`;
- the `WorkItemWidgetStatus.status` widget;
- the `WorkItemWidgetDefinitionStatus.allowedStatuses` definition.

Each status requests GitLab's opaque ID, name, optional description, optional
icon name, optional color, position, and category.

The per-type widget definition is authoritative for allowed transitions. Glab
will not use the root `workItemAllowedStatuses` connection, because that field
returns statuses from all root groups the user belongs to rather than the
exact lifecycle allowed for this issue type.

A supported snapshot requires:

- one validated Issue work item;
- one status widget definition;
- a non-empty, duplicate-free allowed-status list;
- a valid opaque ID, trimmed non-empty name, recognized category, and
  nonnegative position for every allowed status;
- either no current status or a valid current status present in the allowed
  list;
- a recognized `OPEN` or `CLOSED` work-item state consistent with the current
  status category when a current status exists.

Optional description, icon name, and color are display hints only. Glab will
use category-based SF Symbols and semantic colors because GitLab icon names are
not SF Symbol names.

### Update mutation

The mutation uses only returned opaque IDs:

```graphql
mutation GlabUpdateIssueStatus(
  $workItemID: WorkItemID!
  $statusID: WorkItemsStatusesStatusID!
) {
  workItemUpdate(
    input: {
      id: $workItemID
      statusWidget: { status: $statusID }
    }
  ) {
    workItem {
      id
      iid
      state
      updatedAt
      lockVersion
      workItemType { name }
      widgets {
        __typename
        ... on WorkItemWidgetStatus {
          status {
            id
            name
            description
            iconName
            color
            position
            category
          }
        }
      }
    }
    errors
  }
}
```

The status ID input is preferred over the mutually exclusive status-name input
so duplicate names, case folding, and lifecycle changes cannot retarget the
request.

## Existing-code audit

### Reusable foundations

- `GitLabHost.graphQLURL` correctly preserves a self-managed relative root and
  targets `/api/graphql`.
- `GitLabAPIRequest.graphQL` sends an encoded POST with explicit read or write
  access.
- `GitLabSessionClient` applies OAuth or private-token authentication, blocks
  a write request for a read-only account before transport, refreshes expiring
  OAuth credentials, and routes definite authentication failures.
- `GitLabClient` automatically retries only GET requests. A GraphQL mutation
  is therefore not automatically repeated.
- `GitLabMutationDeliveryCertainty` already classifies transport and HTTP
  failures conservatively.
- `GitLabIssueDetailModel.reconcileAuthoritative` and the shell's
  `onResourceEdited` path update the detail, assigned list, Home, search, and
  Todo owners from a complete REST issue.
- P3-06 already owns universal REST label, assignee, and open/closed mutation,
  affected-read invalidation, freshness reads, unknown-delivery recovery, and
  account guards.

### Gaps to add

- Existing GraphQL support decodes only MR diff-summary `data`; it does not
  model top-level GraphQL errors.
- No issue work-item/status domain types or API service exist.
- The issue detail has no independent optional-enhancement model.
- REST issue identity has `project_id` and `iid`, but not project full path.
- A GraphQL status mutation cannot directly construct the complete REST issue
  expected by existing owners.
- P3-06 Close/Reopen must trigger a status refresh because GitLab applies the
  lifecycle's default open or closed status during that REST state change.

P3-07 will add a feature-specific GraphQL envelope rather than prematurely
replacing the app's complete GraphQL handling around one experimental feature.

## Architecture

Retain the app's current Model-View approach.

### Domain

Add focused, nonisolated, `Sendable` types for:

- status category and its expected open/closed state;
- validated allowed status;
- validated issue work-item identity;
- supported status snapshot;
- read availability (`supported`, `unavailable`, or transient failure);
- update intent and authoritative mutation result;
- mutation failure and delivery certainty.

Opaque GraphQL IDs remain strings after strict non-empty validation. Code must
not parse their type names or numeric tails.

### Service

Add `GitLabIssueStatusServing` and `LiveGitLabIssueStatusService`.

The live service owns:

- REST project-ID-to-full-path resolution;
- the GraphQL status query;
- a subsequent status refresh using the already validated project path;
- the GraphQL status mutation;
- feature-specific top-level and payload-error decoding.

The service does not cache GraphQL POST responses on disk. The detail-scoped
model retains the resolved project path and last supported snapshot in memory,
avoiding another project read during status preflight and pull-to-refresh.

The existing resource edit service remains responsible for affected REST cache
invalidation. The existing issue loader performs the uncached authoritative
REST issue read after a successful status mutation.

### Model ownership

Add one `@MainActor @Observable GitLabIssueStatusModel`, owned by
`GitLabIssueDetailView` for the exact account and issue route.

It owns:

- idle/loading/supported/unavailable/transient-failure state;
- the current supported snapshot;
- pending selected status;
- confirmation state for a selection that changes open/closed state;
- mutation, reconciliation, and Check GitLab progress;
- pending unknown-delivery intent;
- a monotonically increasing read generation.

Every result is applied only when:

- the task is not canceled;
- the account remains active;
- the route and validated work-item identity still match;
- the request generation is current.

Rapid status selections are disabled while preflight, mutation,
reconciliation, or delivery check is in progress.

## Read and fallback behavior

Issue detail and discussions start in parallel. Status starts as soon as the
authoritative REST issue supplies its project ID and IID, while discussions
continue loading. It never gates normal issue content.

| Result | Issue behavior | Status behavior |
| --- | --- | --- |
| Valid supported snapshot | Normal | Show compact current status |
| Valid snapshot, no update permission | Normal | Show status read-only |
| Account has only `read_api` | Normal | Show status read-only |
| Missing project/work-item/status fields | Normal | Hide optional status |
| Free/unlicensed/disabled response | Normal | Hide optional status |
| Older schema/top-level GraphQL errors | Normal | Hide optional status; retry on pull refresh |
| Network/server failure before valid status | Normal | Omit control; retry on pull refresh |
| Refresh failure after valid status | Normal | Preserve last status and mark it stale accessibly |
| Authentication failure | Preserve existing content | Route through `AppSession` |

No error text matching or hard-coded version comparison determines support.
The complete validated response is the capability check.

## Ordering and presentation

Allowed statuses are sorted deterministically by:

1. lifecycle category order: Triage, To do, In progress, Done, Canceled;
2. GitLab position within the category;
3. localized case-insensitive status name;
4. opaque ID as the stable final tie-breaker.

The issue header keeps the existing explicit `Opened` or `Closed` REST state.
When supported, it adds one compact status `Menu` beside the existing header
metadata:

- category icon plus the current status name;
- checkmark on the current menu item;
- status names only in the menu;
- no large status card or separate full-screen picker;
- a static label instead of a menu for read-only or unauthorized accounts;
- a small progress indicator while an action is in flight.

Accessibility labels say “Work-item status” so status is never confused with
REST open/closed state. Optional GitLab descriptions become accessibility
hints when useful, not additional always-visible text.

Selecting the current status is a no-op. Selecting a status whose category
changes the current `OPEN`/`CLOSED` state presents a confirmation that names
that effect. A same-state category change proceeds without an extra alert.

## Mutation and reconciliation safety

1. Require write API access, active account, supported snapshot, GitLab
   `updateWorkItem` permission, and an allowed non-current status.
2. Perform a fresh status query using the validated project path and IID.
3. Require the same work-item ID. If lock version, current status, permissions,
   or allowed statuses changed, apply the new snapshot and do not mutate.
4. Reconfirm the selected status remains allowed and any state-change
   confirmation still describes the current transition.
5. Send one `workItemUpdate` POST. Never automatically retry it.
6. Require empty payload `errors`, exact work-item ID and IID, exact selected
   status ID, recognized returned state, a state consistent with the selected
   category, and a lock version strictly greater than the preflight baseline.
7. Invalidate affected issue/list/Home/Todo REST cache keys.
8. Load the complete issue from the REST issue endpoint without cache.
9. Require the same route and REST state consistent with the GraphQL result,
   then reconcile detail and shell owners through the existing callback.
10. Only then announce completion and allow another status mutation.

There is no optimistic status update. A rejected write leaves the prior
snapshot visible.

If GraphQL confirms the write but the REST reconciliation read fails, preserve
the returned new status, block another write, and offer `Check GitLab` until a
complete REST issue can be reconciled. Do not fabricate a partial
`GitLabIssue` from GraphQL.

### GraphQL errors

The feature-specific envelope handles both GitLab modes:

- top-level `errors`;
- mutation payload `errors`.

Read responses with relevant top-level errors or partial/missing required data
become feature unavailability for that load, never a whole-detail failure.

For writes:

- request construction, local access denial, and preflight rejection are
  definitely rejected before a mutation;
- HTTP/session failures use existing mutation-delivery certainty;
- a payload with errors and no work item is rejected under GitLab's
  errors-as-data mutation contract;
- top-level mutation errors, payload errors with a work item, malformed or
  unverifiable success data, and transport ambiguity after dispatch are
  delivery unknown.

An unknown result retains the exact work-item ID, selected status ID, baseline
status ID, and expected state. `Check GitLab` performs a fresh status query:

- desired status present: continue REST reconciliation and complete;
- another authoritative status present: adopt it, clear the pending intent,
  and explain that the requested status is not currently applied;
- unavailable or failed check: retain the pending intent and keep writes
  blocked.

## Interaction with P3-06 state mutation

- REST Close/Reopen remains available even when status is unavailable.
- Work-item status and REST state never share domain names or controls.
- Status mutation disables P3-06 metadata/state mutation until reconciliation
  ends.
- P3-06 metadata/state mutation disables the status menu while it is busy.
- Any successful P3-06 issue mutation refreshes status; this is mandatory for
  Close/Reopen because GitLab applies the lifecycle's default status.
- The complete authoritative REST issue remains the shared reconciliation
  value for all existing owners.

## Test plan

### Endpoint and decoding tests

Write failing tests before implementation for:

- project-ID REST request and identity validation;
- project-path plus IID GraphQL variables;
- `first: 2` connection bound and page-info decoding;
- current status and all five categories;
- allowed statuses from the type definition;
- optional current status;
- empty, duplicate, invalid, and partially decoded status lists;
- zero, one, multiple, and unexpected-next-page work-item results;
- wrong project path, IID, type, and malformed opaque IDs;
- `updateWorkItem` permission;
- exact opaque-ID mutation body;
- success response, payload errors, top-level errors, partial data with errors,
  missing mutation fields, wrong identity/status/state, and nonadvancing lock
  version.

### Service tests

Use deterministic request senders to prove:

- project path is resolved once and reused;
- old schema, unlicensed nulls, and permission-hidden query data become
  unavailable without failing the issue;
- authentication remains distinguishable from capability absence;
- read-only access prevents a write before transport;
- no GraphQL mutation is retried;
- payload rejection and ambiguous delivery are classified conservatively;
- cancellation does not publish late results.

### Model tests

Write failing tests for:

- supported and unavailable instances;
- deterministic status ordering;
- selecting the current status;
- read-only and `updateWorkItem == false`;
- rapid selections and duplicate taps;
- stale preflight lock version/current status/allowed statuses;
- all category transitions, including confirmation only when open/closed state
  changes;
- rejected mutation rollback without optimistic state;
- exact authoritative mutation validation;
- REST reconciliation success and failure;
- unknown delivery plus each Check GitLab outcome;
- refresh after P3-06 state mutation;
- stale read generations, cancellation, and account switching.

### Regression and quality gates

- Run focused GraphQL/status tests.
- Run existing session access, OAuth refresh, issue detail, issue metadata,
  cache invalidation, and shell reconciliation suites.
- Run the complete serialized Simulator suite.
- Build Debug and Release with the reused `.deriveddata/Glab` directory.
- Run Xcode static analysis.
- Lint the packaged privacy manifest.
- Scan tracked source and the Release bundle for configured credential values
  and identifiers without printing secret values.

## Simulator verification

Use only the iPhone 17 Pro Simulator and the configured read-only self-managed
token for live reads. Do not use the physical iPhone.

Verify:

- supported current status and all allowed menu choices;
- read-only status with no enabled mutation;
- deterministic fixtures for supported write UI, confirmation, rejected
  mutation, unknown delivery, and reconciliation;
- unsupported/unlicensed/older-schema fallback with normal Open/Closed UI;
- pull-to-refresh after transient failure;
- compact layout in light and dark appearance;
- Dynamic Type through accessibility sizes;
- VoiceOver labels and hints;
- Reduce Motion, Reduce Transparency, and Increased Contrast.

No live status mutation is required for UI verification. If a later mutation
test is explicitly authorized, it must use only `DEVOPS_DEMO_TOKEN`, only the
single demo project, record and restore the original status, and never mention,
assign, or notify a human.

## Non-goals

- Creating or administering custom statuses or lifecycles.
- Supporting task, epic, objective, or key-result statuses.
- Status filters, issue-board status lists, or bulk status changes.
- Replacing REST issue detail with the work-item GraphQL API.
- Removing or merging the universal REST Close/Reopen control.
- Runtime schema introspection or hard-coded GitLab version gating.
- Persisting GraphQL status responses in the disk response cache.
- Interpreting arbitrary GitLab icon names as SF Symbols.

## Ordered implementation

1. Commit and push this plan with no P3-07 production or test code.
2. Add failing domain, query, envelope, and mutation-construction tests.
3. Implement validated domain types and feature-specific GraphQL endpoints.
4. Add failing service tests, then implement project identity resolution,
   capability read, mutation, and error classification.
5. Add failing model tests, then implement account/cancellation guards,
   preflight, confirmation, delivery certainty, and reconciliation.
6. Add focused presentation tests, then integrate the compact issue-header
   menu and P3-06 state coordination.
7. Run focused tests and Simulator interaction.
8. Run complete quality, privacy, credential, Debug, Release, analysis, and
   test-suite gates.
9. Perform the required deep review below. Record a repair plan before every
   material fix, add regression coverage, implement it, and repeat review and
   verification until clean.
10. Mark P3-07 complete in `docs/MVP_PHASE_3.md` only after all evidence is
    recorded.

## Deep review checklist

After implementation, inspect every P3-07 change for:

- wrong REST-to-work-item identity;
- brittle schema, host, tier, or version assumptions;
- incomplete top-level or payload GraphQL error handling;
- status/state category divergence;
- unallowed or name-targeted mutation;
- duplicate or automatically retried mutation;
- stale lock version, response, account, route, or cancellation races;
- read-only or permission UI that disagrees with transport;
- optimistic or partial REST issue fabrication;
- incomplete cache invalidation or owner reconciliation;
- P3-06 Close/Reopen and status-control conflicts;
- oversized or redundant UI and inaccessible icon-only controls;
- sensitive resource or credential logging;
- duplicated code, bad code, dead code, and code that needs refactoring.

For each material finding:

1. record impact and reproduction;
2. write the repair plan before editing;
3. add a focused regression test;
4. implement the smallest repair;
5. rerun focused and complete verification;
6. repeat the review until no material finding remains.

## Deep review findings

### Finding 1 — Some P3-06 success paths did not refresh status

Impact and reproduction:

- Metadata and REST Close/Reopen success refreshed work-item status, but the
  title/description editor and description-checklist toggle success callbacks
  did not.
- A P3-06 mutation can change the issue revision while a compatible GitLab
  instance independently applies lifecycle behavior. Leaving those callbacks
  unwired could preserve stale status until a manual pull-to-refresh.

Repair plan:

1. Add a detail-scoped status-refresh coordinator with a focused test proving
   that it is a safe no-op before registration and forwards each later
   authoritative issue exactly once.
2. Register the P3-07 model before its initial load.
3. Route checklist, title/description, and metadata/state success callbacks
   through the same coordinator after the complete REST issue is accepted.
4. Rerun status, editor, checklist, and metadata model suites, then repeat the
   integration review.

Repair:

- Added one detail-scoped coordinator, registered it with the status model
  before the model's initial read, and routed checklist, title/description,
  metadata, and state success callbacks through it.
- The coordinator regression test and the focused status, editor, checklist,
  and metadata model suites pass.

Status: repaired; integration review repeated with no remaining instance of
this gap.

### Finding 2 — Status descriptions were not available to assistive technology

Impact and reproduction:

- The GraphQL decoder retained each optional GitLab status description, but
  `GitLabIssueStatusPresentation` and the status menu used only the status
  name.
- VoiceOver therefore announced the current status and each allowed choice
  without any server-provided lifecycle guidance. This contradicted the
  planned behavior that useful descriptions become accessibility hints while
  staying out of the compact visible layout.

Repair plan:

1. Add a focused presentation expectation proving a trimmed GitLab description
   becomes an optional accessibility hint and a missing description stays nil.
2. Apply that hint to the compact current-status element and each allowed menu
   choice, combining it with the existing interaction/read-only hint without
   adding visible text.
3. Rerun the presentation/status suites and repeat the accessibility review in
   the iPhone 17 Pro Simulator.

Repair:

- `GitLabIssueStatusPresentation` now exposes the validated optional
  description as an accessibility hint.
- The compact current-status element combines that server guidance with its
  interaction or read-only hint, and each allowed menu choice exposes its own
  description without adding visible text.
- Focused presentation/status tests and the repeated accessibility Simulator
  review pass.

Status: repaired; accessibility review repeated with no remaining description
loss.

### Finding 3 — Issue metadata broke into narrow columns at accessibility sizes

Impact and reproduction:

- In the iPhone 17 Pro Simulator at
  `accessibility-extra-extra-large`, the issue header's outer
  `ViewThatFits` correctly moved work-item status below the metadata, but the
  nested Opened/comments `HStack` remained horizontal.
- The two labels were compressed into narrow columns and wrapped individual
  words across several lines, making the header difficult to scan and the
  status control harder to reach.

Repair plan:

1. Make the existing issue metadata group use a compact horizontal layout at
   standard sizes and a leading vertical layout at accessibility Dynamic Type
   sizes.
2. Keep the same labels, ordering, and status control; do not add a card,
   duplicate state, or more visible text.
3. Use the deterministic supported-status harness as the focused regression
   test at `accessibility-extra-extra-large`, tap the status menu, and confirm
   all allowed choices remain reachable.
4. Rerun the focused status suites and repeat light/dark, contrast, and
   accessibility review.

Repair:

- The existing Opened/Closed and comments metadata remains horizontal at
  standard sizes and switches to a leading vertical group at accessibility
  Dynamic Type sizes.
- At `accessibility-extra-extra-large`, both labels render as complete rows,
  the compact status control remains reachable, and all five deterministic
  menu choices remain tappable.

Status: repaired; Dynamic Type, contrast, light, and dark review repeated with
no remaining metadata compression.

### Finding 4 — A stale state-change confirmation could retain wrong wording

Impact and reproduction:

- Selecting a status that closes or reopens an issue presents a confirmation,
  but pull-to-refresh remains available while that confirmation is visible.
- If GitLab changes the issue to the target open/closed state before the user
  confirms, the stored confirmation no longer describes the current
  transition. The later mutation preflight protects the write baseline, but
  the app could still proceed from a confirmation whose “close” or “reopen”
  wording had become false.
- This violates the mutation plan's requirement to reconfirm that a
  state-changing selection still has the described effect.

Repair plan:

1. Add a model regression test that presents a close confirmation, refreshes
   to an already-closed supported snapshot, confirms the stale alert, and
   proves no preflight or mutation is sent.
2. Before starting mutation preflight, recompute the selected status's
   resulting state from the current snapshot and reject a confirmation that no
   longer represents an open/closed transition.
3. Preserve the refreshed authoritative snapshot, surface the existing stale
   message, rerun focused status tests, and repeat the mutation-race review.

Repair:

- `confirmSelection()` now recomputes the selected status's resulting state
  against the current supported snapshot before preflight.
- A refreshed status, allowed-status list, current status, or open/closed state
  that invalidates the stored transition clears the confirmation, retains the
  authoritative snapshot, reports stale state, and sends no mutation.
- The regression failed before the guard and passes afterward. The repeated
  mutation-race review found no other stale confirmation path.

Status: repaired.

## Verification evidence

Completed July 29, 2026:

- Focused endpoint, service, model, presentation, and refresh-coordinator
  verification passed 49 tests with zero failures.
- The status/session/access/OAuth/cache/resource-edit/issue-detail/Home/Todos
  regression bundle passed 154 tests. The additional session-client cache
  suite passed 13 tests.
- The complete serialized iPhone 17 Pro Simulator suite passed 872 of 872
  tests with zero failures or skips.
- Debug and Release Simulator builds succeeded using the shared
  `.deriveddata/Glab` directory. Release Xcode static analysis completed with
  no diagnostics.
- A deterministic iPhone 17 Pro harness verified supported status, all five
  status choices, close confirmation, read-only access, server permission
  denial, unsupported fallback, rejected mutation, unknown delivery,
  reconciliation recovery, light and dark appearance,
  `accessibility-extra-extra-large`, Increased Contrast, Reduce Motion, and
  Reduce Transparency. The temporary harness and flows were removed after
  inspection.
- The configured self-managed host did not respond during the final live
  read-only check. No live mutation was attempted; supported and unsupported
  behavior was verified with deterministic fixtures instead.
- The existing cold-first-presentation issue-creation Maestro smoke passed on
  the clean Debug app after P3-07 integration.
- Source and packaged privacy manifests passed `plutil`. Configured
  `GITLAB_API_TOKEN` and `DEVOPS_DEMO_TOKEN` values were absent from tracked
  files and the Release bundle. Sensitive environment-variable identifiers
  were absent from the Release executable. No secret value was printed.
- `git diff --check` passed. The production diff contains no added forced
  casts, forced tries, fatal errors, debug prints, TODOs, or FIXMEs. SwiftLint
  is unavailable in this workspace; Swift compiler diagnostics and Xcode
  static analysis were clean.
- The required deep review was repeated after all four documented repairs. No
  remaining material P3-07 bug, duplication, dead path, safety violation, or
  refactor need was found.
