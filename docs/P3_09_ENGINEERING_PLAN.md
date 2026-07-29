# P3-09 Engineering Plan — Browse Merge-Request Pipelines and Jobs

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Models and endpoints: not started
- Live read service: not started
- Pipeline history model: not started
- Pipeline detail and job model: not started
- Native UI and navigation: not started
- Simulator verification: not started
- Deep review: not started

Research date: July 29, 2026.

This is the required implementation plan for P3-09. It must be committed and
pushed before any P3-09 production or test code is changed.

## Outcome

A user can open a compact native Pipelines destination from any merge-request
detail screen. The destination shows the merge request's paginated pipeline
history without replacing or blocking the existing merge-request detail.

Opening a pipeline shows authoritative pipeline metadata and a paginated,
stage-oriented list of ordinary jobs. Trigger jobs and their downstream
pipeline summaries are included when the self-managed GitLab version supports
the documented endpoint or its documented legacy route.

Active visible content refreshes at a bounded interval and stops when the
screen disappears, the scene becomes inactive, the pipeline becomes terminal,
the account changes, or the task is canceled. Cached terminal pipeline content
remains useful offline longer than active content.

P3-09 is entirely read-only. It does not retry, play, cancel, trigger, erase,
or otherwise mutate a pipeline or job.

## Scope decisions and non-goals

- P3-09 begins only after P3-08 and adds only pipeline and job browsing.
- The merge-request pipeline history uses the documented merge-request
  pipeline endpoint. It does not approximate the history from the current
  `head_pipeline`.
- The pipeline screen retrieves the selected pipeline by project and pipeline
  ID, then loads ordinary jobs with `include_retried=true`.
- Trigger jobs are an independently failing enhancement. GitLab 19.2 added
  `/trigger_jobs` and deprecated `/bridges`; Glab tries `/trigger_jobs` first
  and falls back to `/bridges` only after a documented `404`.
- A trigger-job failure never removes ordinary jobs or pipeline metadata.
- Downstream pipeline summaries are displayed when returned. Glab opens a
  downstream pipeline natively only when the response provides a valid
  positive downstream project ID and pipeline ID. Otherwise it offers only a
  validated GitLab web destination.
- The documented REST job response does not identify the exact parent of a
  retried job. `include_retried=true` exposes earlier attempts but does not
  provide a reliable lineage field. Glab preserves every returned attempt in
  server order and may label duplicate stage-and-name entries as earlier
  attempts, but it does not claim one job is the exact retry parent of another.
- P3-09 does not fetch job traces. P3-10 owns the bounded log viewer.
- P3-09 does not fetch test reports or download artifacts. Those remain
  P3-S02.
- P3-09 does not implement pipeline or job mutations. Retry, play, trigger,
  and cancel belong to P3-11 and require separate confirmation and delivery
  certainty.
- Every P3-09 request is `GET` with `.read` access. Mutation delivery
  certainty, confirmation, optimistic rollback, and cache invalidation are
  therefore intentionally absent. P3-11 must add those concerns before it
  adds any pipeline or job write.
- P3-09 does not add a project-wide pipelines tab, pipeline search, filters,
  variables, schedules, or deployment views.
- P3-09 does not rewrite the app architecture, the shared cache, or the
  existing merge-request detail model.
- Routine verification uses deterministic fixtures and the iPhone 17 Pro
  Simulator. The configured self-managed read-only token may be used for live
  reads only. The physical iPhone is out of scope.

## Official GitLab sources

- [Merge requests API](https://docs.gitlab.com/api/merge_requests/#list-merge-request-pipelines)
  defines `GET /projects/:id/merge_requests/:merge_request_iid/pipelines` and
  its offset pagination.
- [Pipelines API](https://docs.gitlab.com/api/pipelines/) defines pipeline
  list statuses and `GET /projects/:id/pipelines/:pipeline_id`, including
  detailed status, timing, user, and archived fields.
- [Jobs API](https://docs.gitlab.com/api/jobs/#list-all-jobs-by-pipeline)
  defines `GET /projects/:id/pipelines/:pipeline_id/jobs`, pagination,
  descending job-ID order, `include_retried`, job statuses, timing, runner,
  artifact, and user fields.
- [Trigger jobs API](https://docs.gitlab.com/api/jobs/#list-all-trigger-jobs-by-pipeline)
  defines `/trigger_jobs`, the deprecated `/bridges` route, the GitLab 19.2
  transition, and downstream-pipeline summaries.
- [REST pagination](https://docs.gitlab.com/api/rest/#pagination) requires
  clients to follow the response `Link` URL instead of manufacturing the next
  page. Some total-count headers can be absent on GitLab.com.

All selected endpoints are documented for Free, Premium, and Ultimate on
GitLab.com, GitLab Self-Managed, and GitLab Dedicated. Private project data
still depends on the authenticated user's project and pipeline visibility.
Tests use documented response shapes rather than observations from one GitLab
instance.

## Current implementation audit

### Merge-request pipeline summary

- `GitLabMergeRequest` decodes a minimal `head_pipeline` containing an ID,
  status, and web URL.
- `GitLabMergeRequestReadiness` maps that current head status into a compact
  merge-readiness check and already preserves unknown future values.
- `GitLabMergeRequestReadinessView` currently opens the pipeline web URL. It
  has no native pipeline-history action and does not own pipeline state.
- The P3-09 control will reuse that compact readiness row. It will replace
  only the pipeline row's external arrow with a native navigation action.
  Other readiness checks and their behavior remain unchanged.

### Pagination and cache

- `GitLabPaginatedResourceModel` already owns first-page, refresh, next-page,
  de-duplication, retained-content failure, cache event, and untrusted repeated
  next-page behavior.
- Its current refresh behavior replaces all loaded pages with page one. P3-09
  needs an opt-in first-page reconciliation mode that places refreshed
  first-page values first, retains already loaded unique tail IDs, and then
  safely refollows server next links. Existing pagers retain their current
  replacement behavior by default.
- `GitLabAPIResponse` parses the documented `Link` header and optional
  `X-Total`; missing totals are already supported.
- `GitLabRequestBuilder` accepts next-page URLs only when they retain HTTPS,
  the configured host and port, the API base path, no credentials or fragment,
  and no dot segments.
- `GitLabSessionClient` decodes off the main actor, coalesces reads, performs
  conditional revalidation, and keys cached responses by account plus
  normalized request URL and optional variant.
- `FileGitLabResponseCache` is account-partitioned, size-bounded, protected on
  disk, and LRU-pruned. P3-09 extends its policy catalog rather than adding a
  second cache.

### Detail and navigation ownership

- The signed-in shell is recreated with `.id(GitLabAccountID)` when the active
  account changes. Its client and response-cache identity are account scoped.
- `GitLabMergeRequestDetailView` owns merge-request, approvals, discussions,
  editing, and diff dependencies. Its detail model must not gain pipeline job
  pages or a polling task.
- Existing native detail destinations are created from immutable project/IID
  routes and injected services. P3-09 follows the same pattern with immutable
  pipeline routes and independently created feature models.
- Home, Todo, assigned-MR, review-request, search, and deep-link entry points
  all converge on the same merge-request detail view. Injecting one pipeline
  reader there covers every current entry point without parallel behavior.

### Status and formatting

- Pipeline readiness has a private status-to-presentation mapping, but no
  shared CI status type exists.
- P3-09 introduces one lossless CI status value and one shared presentation
  mapping for pipeline and job screens. Readiness can adopt that mapping only
  where behavior remains identical; P3-09 must not create two new competing
  status tables.
- Existing relative-date and user-avatar components can be reused. Duration
  and queued-duration formatting need small deterministic helpers with
  nonnegative validation.

## API contracts

### Merge-request pipeline history

`GET /projects/:project_id/merge_requests/:merge_request_iid/pipelines`

Initial query:

- `per_page=20`

Contract:

- every request requires `.read`;
- project ID and merge-request IID come only from the validated native route;
- the first response page can omit timestamps, user, name, detailed status,
  project ID, IID, and web URL;
- pipeline ID, SHA, ref, and raw status are required for a usable row;
- positive pipeline IDs are the stable page identity;
- invalid required data fails the page and retains already rendered content;
- optional malformed metadata is treated as absent when it can be decoded
  independently;
- next pages follow only the validated server `Link` URL;
- when a server repeats a pipeline ID across pages, the first occurrence in
  the current server order wins and no second row is produced;
- missing `X-Total` means the count is unknown, not zero.

The API documents offset pagination for this endpoint. Glab does not request
undocumented keyset parameters.

### Pipeline detail

`GET /projects/:project_id/pipelines/:pipeline_id`

Contract:

- every request requires `.read`;
- both path IDs must be positive;
- the returned pipeline ID must match the route;
- a returned positive `project_id`, when present, must match the route;
- required identity/status data is decoded losslessly;
- optional name, IID, source, ref, SHAs, dates, durations, coverage,
  YAML error, user, detailed status, archive flag, and web URL tolerate
  omission;
- negative duration or queued-duration values are ignored;
- URLs are exposed only through `GitLabWebURL.validated`;
- an unfamiliar raw status remains visible as Unknown and is not treated as
  terminal success.

The documentation mentions pagination parameters on this single-resource
endpoint, but Glab sends none because the response is not a collection.

### Ordinary pipeline jobs

`GET /projects/:project_id/pipelines/:pipeline_id/jobs`

Initial query:

- `include_retried=true`
- `per_page=50`

Contract:

- every request requires `.read`;
- pages preserve GitLab's documented descending job-ID order;
- positive job ID, nonempty name, nonempty stage, and raw status are required;
- optional source, ref, failure reason, dates, durations, coverage, user,
  runner, runner manager, tags, artifacts, archive flag, allow-failure flag,
  and web URL tolerate omission;
- a returned nested pipeline ID or project ID, when present, must match the
  selected route;
- negative durations, sizes, and IDs are ignored or reject only the affected
  optional projection;
- pagination follows only the validated response `Link`;
- when a server repeats a job ID across pages, the first occurrence in the
  current server order wins and no second row is produced;
- a page failure retains prior pages and exposes a scoped retry.

Fifty items balances round trips with decode and rendering cost. The model
remains genuinely paginated and does not eagerly load all remaining pages.

### Trigger jobs and child pipelines

Preferred endpoint on GitLab 19.2 and newer:

`GET /projects/:project_id/pipelines/:pipeline_id/trigger_jobs?per_page=50`

Compatibility fallback:

`GET /projects/:project_id/pipelines/:pipeline_id/bridges?per_page=50`

Contract:

- the preferred endpoint is attempted first;
- only `404 Not Found` selects the legacy endpoint for that pipeline model;
- `401`, `403`, rate limits, server errors, cancellation, and decoding errors
  do not silently fall back;
- trigger-job loading, failure, pagination, and retry remain independent from
  ordinary jobs;
- the selected endpoint is remembered for the lifetime of the pipeline detail
  model to avoid repeating a guaranteed `404`;
- trigger jobs share status, stage, timing, user, and allow-failure
  presentation with ordinary jobs;
- downstream ID, project ID, SHA, ref, status, timestamps, and URL are all
  optional;
- native downstream navigation requires both positive IDs; otherwise only a
  validated web URL is offered;
- a `403` or failure leaves the trigger-job section unavailable while
  ordinary stages remain usable.

P3-09 does not use the project pipeline list with `source=parent_pipeline` to
guess an MR's child-pipeline relationship.

## Immutable model design

P3-09 adds value types under `Features/Pipelines`:

- `GitLabPipelineRoute`
  - `projectID`
  - `pipelineID`
- `GitLabCIStatus`
  - preserves the normalized raw string;
  - exposes a known semantic kind;
  - exposes `isActivelyChanging` and `isTerminal`;
  - treats unknown values as unknown and non-successful;
- `GitLabPipeline`
  - identity, optional IID/name/project ID, SHA/ref/source/status;
  - optional created/updated/started/finished/committed dates;
  - optional duration, queued duration, coverage, archive state, YAML error;
  - optional validated web URL, user, and detailed status;
- `GitLabPipelineDetailedStatus`
  - optional text, label, group, tooltip, detail availability, and path;
  - server text is presentation metadata, never a control or API path;
- `GitLabPipelineUser`
  - positive ID plus optional username, name, avatar URL, and web URL;
  - maps to the existing avatar summary when identity is valid;
- `GitLabPipelineJob`
  - identity, name, stage, status, allow-failure, optional failure reason;
  - optional timing, runner, user, tags, artifact summary, ref, and web URL;
- `GitLabPipelineTriggerJob`
  - trigger-job identity and job metadata plus an optional downstream
    pipeline;
- `GitLabPipelineStage`
  - stable stage name and ordered ordinary/trigger job rows;
  - computed status counts and active-state summary;
- `GitLabPipelineRunner`
  - positive ID and optional description, name, type, online/paused/shared
    state, platform, architecture, and status;
- `GitLabPipelineArtifactSummary`
  - immutable validated artifact entries, nonnegative aggregate size, and
    archive availability without downloading data.

All API models are `Decodable`, `Equatable`, and `Sendable`. Unknown fields are
ignored. Unknown status strings are retained. Required identity fields fail
closed. Optional nested objects use defensive decoding so one malformed avatar,
runner, detailed-status field, or artifact does not discard otherwise usable
pipeline or job content.

No model contains credentials, authorization headers, cache file paths,
`URLRequest`, mutable UI state, or closures.

## Architecture and state ownership

P3-09 stays in the current SwiftUI Model-View architecture.

### Service boundary

`GitLabPipelineLoading` is a `Sendable` read-only protocol with methods for:

- MR pipeline first and next pages;
- pipeline detail events;
- ordinary job first and next pages;
- trigger-job first and next pages with explicit preferred/legacy capability.

`LiveGitLabPipelineLoader` owns only endpoint execution, response validation,
cache policy selection, compatibility fallback, and response-to-page mapping.
It uses the existing account-scoped `GitLabPaginatedSessionRequestSending`.

The pipeline loader is constructed once in `SignedInShellView` from the same
session client and passed independently to merge-request destinations. It is
not added to the issue loader, approval service, discussion service, or MR
detail model.

### Pipeline history model

`GitLabMergeRequestPipelinesModel` is `@MainActor @Observable` and owns:

- the immutable account ID and MR route;
- one composed `GitLabPaginatedResourceModel<GitLabPipeline, Int>`;
- a structured visible polling loop;
- an injected account-current check and poll waiter;
- authentication failure forwarding.

It does not own merge-request detail, jobs, a navigation path, or global
account state.

The model wraps loader responses with account and route validation before
publishing them. A response from a canceled task or inactive account becomes a
cancellation result and cannot update visible state.

### Pipeline detail model

`GitLabPipelineDetailModel` is `@MainActor @Observable` and owns:

- the immutable account ID and pipeline route;
- authoritative pipeline detail state;
- one ordinary-job pager;
- one independently failing trigger-job pager;
- the selected trigger-job endpoint capability;
- immutable, precomputed stage projections;
- one structured visible polling loop;
- refresh and authentication failure projections.

It does not own the MR model, approval model, merge-request readiness, job-log
content, or mutation state.

Stage projection runs away from the main actor whenever a page revision
changes, then publishes only if the account, route, and projection generation
are still current.

### Navigation ownership

`GitLabMergeRequestDetailView` owns only whether its pipeline-history
destination is presented. Creating that destination creates a fresh pipeline
history model. Selecting a pipeline creates a fresh pipeline detail model.

Popping a detail screen cancels its structured `.task` work. Switching
accounts destroys the signed-in shell, loader, navigation tree, and all
pipeline models. No P3-09 model is stored in `AppSession`.

## Pagination, ordering, and retry-attempt presentation

- Pipeline history retains GitLab's server order.
- Ordinary and trigger pages retain server order and de-duplicate by positive
  ID.
- Stage order is the first appearance of each normalized nonempty stage in the
  combined server sequence.
- Rows within a stage retain their respective endpoint's server order.
- Ordinary jobs appear before trigger jobs only when both endpoints provide
  rows for the same stage and the API provides no common cross-endpoint order.
  The UI identifies trigger jobs explicitly.
- Loading another page recomputes a stable immutable stage projection without
  mutating the already decoded API values.
- A refresh replaces authoritative first-page values and reconciles IDs already
  loaded from later pages. It must not duplicate jobs or collapse an expanded
  long list merely because polling refreshed page one.
- This uses the shared pager's new opt-in retained-tail refresh mode. Existing
  pagers continue to replace content on refresh.
- `include_retried=true` preserves earlier attempts. Rows with the same
  normalized stage and exact job name can be grouped visually as attempts in
  descending server ID order.
- Because the REST response lacks a documented retry-parent field, Glab uses
  neutral labels such as “latest run” and “earlier run”; it never says “retried
  from job #X” or hides a duplicate as if lineage were proven.
- Next-page loading is driven by the last visible row, uses one in-flight
  request, and exposes a scoped retry after failure.

## Polling behavior

Polling is a structured async operation, not a detached or global timer.

- Default interval: 15 seconds.
- A clock/wait closure is injected so tests advance polling without real
  sleeps.
- Pipeline history polls only while its screen is visible, the scene is
  active, the account is current, and at least one currently loaded pipeline
  has an actively changing status.
- Pipeline detail polls only while its screen is visible, the scene is active,
  the account is current, and the pipeline or any loaded job/trigger job has
  an actively changing status.
- Active statuses are documented nonterminal work states: `created`,
  `waiting_for_resource`, `preparing`, `waiting_for_callback`, `pending`,
  `running`, `canceling`, and `scheduled`.
- `manual` is not continuously polled because it can wait indefinitely for a
  user action. Pull to refresh remains available.
- Each tick refreshes pipeline metadata and authoritative first pages. It
  reconciles refreshed IDs into loaded content instead of dropping later
  pages.
- A polling refresh never starts while the same scope is already loading.
- Polling stops after terminal transition, `Task` cancellation, navigation
  disappearance, inactive/background scene, or account switch.
- A poll failure retains content, exposes a compact refresh error, and waits
  for the next bounded tick. It does not enter a tight retry loop.
- `401` ends polling and forwards authentication failure to `AppSession`.
- Rate-limit responses use the existing read retry policy only; P3-09 adds no
  independent retry loop.

## Cache design

P3-09 extends `GitLabResponseCachePolicy` with:

- `pipelineActive`
  - fresh for 15 seconds;
  - usable stale for 1 hour;
- `pipelineCompleted`
  - fresh for 5 minutes;
  - usable stale for 24 hours.

The MR pipeline-history endpoint always uses the active policy because new
pipelines can appear even when every currently loaded item is terminal.

Pipeline detail, ordinary jobs, and trigger jobs select the policy from the
best known selected-pipeline status:

- active or unknown status uses `pipelineActive`;
- a documented terminal status uses `pipelineCompleted`.

The cache stores raw responses independently of policy. A detail model opened
from an active summary uses the active policy for its lifetime; once history
observes that pipeline as terminal, the next detail presentation uses the
completed policy over the same cached response. This avoids mutable
cross-actor cache-policy state while still retaining completed content longer.
Explicit pull-to-refresh and polling use `.always` to conditionally revalidate
even fresh cache data.

Existing cache keys already include:

- account host and user ID;
- project and pipeline or MR path;
- query items, including `include_retried` and `per_page`;
- exact validated next-page URL.

Preferred trigger jobs and legacy bridges have different path keys. No cache
entry or model crosses accounts. P3-09 does not cache stage projections,
credentials, logs, or arbitrary web responses.

## Failure, cancellation, and stale-result behavior

- Initial pipeline-history failure shows retry without affecting the MR detail.
- Empty history is an explicit “No pipelines” state, not a blank screen.
- Refresh failure retains pipeline rows.
- Next-page failure retains prior pages and retries only that page.
- Pipeline-detail failure leaves the history screen intact.
- Ordinary-job initial failure retains pipeline metadata and has its own retry.
- Trigger-job failure retains pipeline metadata and ordinary jobs.
- Cached content remains visible during failed revalidation and is labeled by
  existing cache state where user-facing copy is useful.
- Every long-running load checks task cancellation before publication.
- Each model validates the account, fixed route, and generation after every
  await before publishing.
- A response for another project, pipeline, MR, account, or superseded
  generation is rejected.
- Repeated next-page URLs fail closed through the shared pager.
- Untrusted next-page URLs fail before an authenticated request can be sent.
- Unknown status, source, runner state, artifact type, and optional detailed
  status remain displayable without enabling behavior.
- `401` is forwarded to the existing account-scoped authentication handler.
- `403` and `404` are scoped to the pipeline or trigger-job surface; they do
  not sign the user out or fail unrelated MR content.

## UI and accessibility plan

### MR entry point

- The existing compact Merge readiness card remains collapsed by default.
- Its Pipeline row uses one native trailing arrow/button to open Pipelines.
- The control remains available when there is no current head pipeline because
  older MR pipeline history can still exist.
- The button has a 44-point hit target, “View merge request pipelines” label,
  and an accessibility hint describing native navigation.
- Other readiness rows retain their current behavior.

### Pipeline history

- Navigation title: “Pipelines”.
- Lazy native `List` with compact rows rather than nested cards.
- Each row shows one status icon, pipeline IID or ID, optional name, ref,
  short SHA, and concise relative timing when available.
- Status is never color-only; icon and readable text are exposed together to
  accessibility.
- Pull to refresh and incremental pagination use existing state components.
- Loading, empty, failure, retained-refresh failure, next-page failure,
  offline-cache, and unknown-status states have stable accessibility
  identifiers.

### Pipeline detail

- Navigation title: “Pipeline #…”.
- A compact metadata header shows status, ref, short SHA, source, trigger user,
  duration, queue time, and timing only when present.
- A compact top-right GitLab icon opens the validated pipeline web URL.
- Jobs appear in stage sections. Sections can collapse to reduce screen real
  estate while preserving status summaries.
- A job row shows status icon/text, name, duration, allow-failure state,
  manual state, and latest/earlier-run wording when applicable.
- Trigger-job rows use a distinct child-pipeline icon and show downstream
  status/ref when available.
- P3-09 job rows do not pretend to open logs; P3-10 will add that navigation.
- Lists remain lazy and do not embed independently scrolling text views.

### Required UI verification

Use the iPhone 17 Pro Simulator and inspect/tap:

- dark and light appearance;
- default and accessibility-extra-large Dynamic Type;
- VoiceOver labels/hints/order;
- Increase Contrast;
- Reduce Motion;
- Reduce Transparency;
- empty, one pipeline, long paginated history;
- active, success, failed, canceled, skipped, manual, scheduled, and unknown
  pipeline status;
- single and many stages;
- long job names, missing dates/user/runner, artifacts, allowed failure;
- earlier attempts, trigger jobs, and downstream pipeline summary;
- cached/offline content and first/refresh/next-page partial failures;
- navigation back to an intact MR;
- polling cancellation on pop/background and account replacement.

The UI follows the current compact pattern: combine related controls, avoid
explanatory text where icon plus accessibility copy is sufficient, and use
Liquid Glass only for compact interactive controls rather than every content
surface.

## Test plan

All new core tests use Swift Testing. UI automation stays in Maestro.

### Endpoint and request tests

- MR pipeline path, IDs, read access, and `per_page=20`;
- pipeline-detail path and read access;
- jobs path, `include_retried=true`, and `per_page=50`;
- preferred trigger-jobs and legacy bridges paths;
- positive route validation;
- percent encoding and no credential leakage;
- trusted, cross-host, HTTP, user-info, fragment, path-escape, repeated, and
  malformed next-page URLs.

### Decoding tests

- minimal MR pipeline summary;
- full pipeline detail and detailed status;
- missing every optional pipeline field;
- known and unknown pipeline statuses;
- optional valid/malformed user and URL data;
- ordinary job with timing, runner, runner manager, allow failure, tags, and
  artifacts;
- missing optional job data;
- all documented job statuses and unknown status;
- trigger job and downstream pipeline;
- missing downstream project ID;
- negative IDs, durations, and artifact sizes;
- malformed required pipeline/job data;
- `include_retried` pages containing same-name attempts.

### Service and cache tests

- first and next pipeline pages;
- first and next job pages;
- pagination metadata propagation;
- active versus completed cache policies;
- cache-first and conditional revalidation events;
- trigger-jobs success;
- `404`-only legacy bridges fallback;
- no fallback on `401`, `403`, server, decoding, or cancellation failures;
- remembered trigger endpoint capability;
- route/response mismatch rejection;
- independently retained ordinary and trigger-job failures.

### Pipeline history model tests

- first-page loading, empty, error, retry, and cached content;
- pagination, de-duplication, and repeated next page;
- refresh preserves content on failure;
- active-to-terminal polling transition;
- no polling for terminal/manual-only content;
- visible and active-scene gating;
- cancellation on navigation;
- no publication after account switch;
- stale generation rejection;
- authentication failure forwarding.

### Pipeline detail model tests

- parallel independent pipeline, ordinary-job, and trigger-job loading;
- pipeline-only success when jobs fail;
- ordinary jobs retained when triggers fail;
- long pagination and no repeated/lost jobs;
- stable stage and row ordering;
- later-page preservation during first-page poll refresh;
- stage regrouping after running-to-terminal updates;
- allowed-failure/manual/earlier-attempt projections;
- trigger and downstream projections;
- bounded polling and no overlapping refresh;
- cancellation, stale generation, account switch, and authentication failure;
- unknown-status fail-closed behavior.

### Performance tests

Deterministic fixtures cover at least:

- 1,000 pipeline summaries across pages;
- 5,000 ordinary and trigger job rows across many stages;
- repeated stage projection after a first-page status refresh;
- pagination de-duplication with overlapping IDs.

Budgets are measured after a warm-up and kept generous enough for shared
Simulator contention. JSON decoding and stage projection must remain off the
main actor. UI tests verify scrollability and stable row identity rather than
claiming Simulator frame timing proves device performance.

### Regression and full gates

- new pipeline endpoint/model/presentation suites;
- existing `GitLabPaginatedResourceModelTests`;
- cache key, cache policy, response metadata, request construction, and
  session-client cache suites;
- MR decoding and readiness suites;
- Home, Todo, MR list/detail, account switch, and deep-link suites affected by
  dependency plumbing;
- complete serialized Simulator test suite;
- Debug and Release Simulator builds using `.deriveddata/Glab`;
- Release static analysis;
- `git diff --check`;
- property-list validation;
- forced operation, credential identifier, tracked-secret, and Release bundle
  scans.

## Live-read and Simulator safety

- Do not use the physical iPhone.
- Reuse `.deriveddata/Glab`; do not create per-run Derived Data directories.
- Deterministic fixtures are the primary UI proof.
- The configured `GITLAB_API_TOKEN` may be used only for self-managed read
  verification in Simulator.
- Never print, log, screenshot, commit, bundle, or copy token values.
- Do not use `DEVOPS_DEMO_TOKEN` for P3-09 because no live mutation is needed.
- Do not retry, play, cancel, trigger, erase, mention, assign, tag, or notify
  anyone.
- A live read failure does not justify a mutation, permission change, broad
  project crawl, or undocumented endpoint.
- Shut down all Simulators and remove generated screenshots/videos after the
  final inspection.

## Deep-review checklist

After implementation and verification, inspect every P3-09 production, test,
fixture, and document change for:

- duplicate pagination, cache, URL trust, or status mapping;
- required fields made optional in a way that invents identity;
- optional fields made required in a way that rejects useful data;
- lost or repeated pipeline/job IDs;
- false retry-parent claims;
- unstable stage or row ordering;
- first-page polling that drops loaded later pages;
- unbounded, background, terminal, or overlapping polling;
- polling that continues after pop, scene deactivation, cancellation, or
  account switch;
- stale account, route, or generation results;
- cache-key collisions or the wrong active/completed policy;
- trigger-jobs fallback on errors other than `404`;
- trigger-job failure breaking ordinary jobs;
- main-actor decode or large stage projection;
- eager loading, eager rendering, or over-fetching;
- invalid or untrusted browser destinations;
- authentication or credential leakage;
- MR detail/navigation ownership mistakes;
- oversized controls, duplicate text, inaccessible status, or compact-layout
  regressions;
- bad code, duplicated code, unused paths, or code needing refactoring.

Record every material finding in this document. Before fixing one:

1. describe the bug and impact;
2. write the smallest repair plan;
3. add a failing regression or performance test where applicable;
4. implement the repair;
5. rerun the complete P3-09 verification;
6. repeat this review until no material finding remains.

P3-09 and its MVP checklist cannot be marked complete before that repeated
review and exact verification evidence are recorded here.

## Implementation order

1. Commit and push this plan and the two planning checklist updates without
   production or test code.
2. Add failing immutable-model, status, endpoint, and decoding tests.
3. Implement the minimum model and endpoint contracts; run focused tests;
   commit and push.
4. Add failing live-service, cache-policy, pagination, and trigger fallback
   tests.
5. Implement the read service and cache behavior; run focused tests; commit
   and push.
6. Add failing history/detail model tests for ordering, retained pages,
   polling, cancellation, stale results, and account switching.
7. Implement independent observable models and off-main stage projection; run
   focused tests; commit and push.
8. Add native compact navigation and pipeline/job screens.
9. Build, launch, inspect, and tap every changed state in the iPhone 17 Pro
   Simulator; repair UI defects; commit and push.
10. Run all focused and full quality gates plus privacy scans.
11. Perform and record the deep review. Write a repair plan before changing
    any material finding, add tests, repair it, repeat verification and review.
12. Only then check off P3-09 in `docs/MVP_PHASE_3.md`, record exact evidence,
    commit, and push.

## Safety checklist

- [x] Existing pipeline/readiness, pagination, cache, navigation, account, and
  route ownership were inspected before planning.
- [x] Current official GitLab API documentation was researched.
- [x] This plan precedes every P3-09 production and test change.
- [ ] Every endpoint is read-only and requires `.read`.
- [ ] No live mutation, human mention, assignment, tag, or notification.
- [ ] No automatic mutation or independent network retry path.
- [ ] Pagination follows only validated GitLab `Link` URLs.
- [ ] Polling is visible-only, bounded, structured, and cancelable.
- [ ] Terminal and manual-only content does not poll indefinitely.
- [ ] Account, project, MR, pipeline, query, and page cache identity is
  isolated.
- [ ] Completed content uses a longer cache policy than active content.
- [ ] Trigger-job failure cannot fail ordinary jobs or pipeline metadata.
- [ ] Unknown statuses remain visible and fail closed.
- [ ] Stage projection and decoding remain off the main actor.
- [ ] Simulator only; `.deriveddata/Glab` reused; generated artifacts removed.
- [ ] Deep review and any repair plan are recorded before P3-09 is marked
  complete.
