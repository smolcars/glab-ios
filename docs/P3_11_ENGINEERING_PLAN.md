# P3-11 Engineering Plan — Safe Pipeline and Job Actions

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Implementation: complete
- Simulator verification: complete
- Deep review: complete

Research date: July 29, 2026.

This plan must be committed and pushed before any P3-11 production or test
code is changed.

## Outcome

A signed-in user with GitLab API write access can:

- retry the failed or canceled jobs in a pipeline;
- retry one failed or canceled ordinary job;
- play one manual ordinary job;
- create a new pipeline for an open merge request;
- cancel an active pipeline; and
- cancel one active ordinary job.

Every action is compact, status-aware, explicitly confirmed, single-flight,
account-scoped, never automatically retried, and reconciled against GitLab's
authoritative response and subsequent reads.

## Existing-code audit

- `GitLabPipelineEndpoints`, `LiveGitLabPipelineLoader`, and the pipeline
  models currently expose read-only MR pipeline history, pipeline details,
  ordinary jobs, trigger jobs, pagination, cache-first refresh, and bounded
  15-second polling while visible content is actively changing.
- `GitLabCIStatus` already preserves unknown status values and recognizes
  GitLab's documented created, waiting, preparing, pending, running,
  canceling, scheduled, manual, success, failed, canceled, and skipped states.
- `GitLabSessionClient` rejects `.write` requests for read-only personal
  access tokens. OAuth and personal tokens with the `api` scope are treated as
  write-capable, but GitLab remains authoritative for project role, protected
  environment, and job-specific permissions.
- `GitLabClient` retries only `GET`; it already sends every `POST` once.
  `GitLabMutationDeliveryCertainty` distinguishes an explicit rejection from
  a response whose delivery is unknown.
- The pipeline response cache is endpoint-keyed and supports targeted
  invalidation. The protected trace store is account- and job-keyed, but needs
  a targeted removal operation so canceling a loaded job cannot later expose
  a stale terminal log.
- The detail and history models already reject stale account publication and
  own polling. P3-11 will extend these models instead of adding a second
  polling loop or a global pipeline coordinator.
- Existing approval, issue, edit, reaction, and discussion mutations provide
  the patterns for write gating, confirmation snapshots, single-flight state,
  uncertain-delivery copy, targeted invalidation, and authoritative
  reconciliation.

## Official GitLab contracts

Primary documentation:

- Pipelines API: <https://docs.gitlab.com/api/pipelines/>
- Jobs API: <https://docs.gitlab.com/api/jobs/>
- Merge requests API:
  <https://docs.gitlab.com/api/merge_requests/#create-merge-request-pipeline>

| Action | Request | Response | Initial eligibility |
| --- | --- | --- | --- |
| Retry pipeline | `POST /projects/:id/pipelines/:pipeline_id/retry` | `GitLabPipeline` | Pipeline is `failed` or `canceled` |
| Cancel pipeline | `POST /projects/:id/pipelines/:pipeline_id/cancel` | `GitLabPipeline` | Pipeline is actively changing |
| Retry job | `POST /projects/:id/jobs/:job_id/retry` | `GitLabPipelineJob` | Ordinary job is `failed` or `canceled` |
| Cancel job | `POST /projects/:id/jobs/:job_id/cancel` | `GitLabPipelineJob` | Ordinary job is actively changing, except `canceling` |
| Play job | `POST /projects/:id/jobs/:job_id/play` | `GitLabPipelineJob` | Ordinary job is `manual` |
| New MR pipeline | `POST /projects/:id/merge_requests/:iid/pipelines` | `GitLabPipeline` | MR is currently open |

Pipeline retry can be a documented no-op when no failed or canceled jobs
exist. Pipeline cancel returns `200` regardless of current state. The client
therefore limits visible actions from its latest state but never claims that
local eligibility guarantees a server-side transition.

All six endpoints require `.write`. Paths use validated positive numeric
project, pipeline, job, and MR identifiers. Requests have no body in this
phase, so they remain compatible with older self-managed versions that support
the endpoints.

GitLab added pipeline `inputs` in 17.10 and made them generally available in
18.1. GitLab added job `job_inputs` in 18.10, and manual jobs also support
custom variable values. P3-11 deliberately sends none of these. It does not
collect, display, persist, log, or screenshot arbitrary CI variables, inputs,
files, or secrets.

Trigger/bridge rows remain navigation-only. The ordinary Jobs API did not
support retrying trigger jobs before GitLab 17.0, and presenting only ordinary
job mutations is the smallest predictable cross-version scope.

## Architecture and state ownership

### Endpoints and service

- Add validated `GitLabJobRoute(projectID:pipelineID:jobID:)`. The pipeline ID
  is not part of the Jobs API path, but keeping it in the action route permits
  exact response validation and cache invalidation even when delivery fails
  before a response arrives.
- Add the six write endpoints beside the existing pipeline read endpoints.
- Add a focused `GitLabPipelineActionServing` protocol and
  `LiveGitLabPipelineActionService`. The live service shares the session
  client with the loader but does not broaden the read-only loader protocol.
- The service sends each mutation once. Confirmed success and
  delivery-unknown failure invalidate only affected reads; explicit rejection
  does not invalidate.
- Response validation rejects a pipeline or job whose project/pipeline
  identity contradicts the requested route. Older responses may omit optional
  nested project fields; absence is accepted, contradiction is not.

### Models

- `GitLabPipelineDetailModel` owns pipeline and job action state for its route.
  `GitLabMergeRequestPipelinesModel` owns new-MR-pipeline state.
- One action operation may be in flight per screen. Rapid duplicate taps and a
  second conflicting action are ignored while confirmation or delivery is
  pending.
- Confirmation captures the target ID, displayed name/reference, and observed
  status. Confirming after account replacement, route replacement, or
  authoritative status change is rejected and requires a fresh action.
- Cancellation of the Swift task stops publication, but is treated as
  delivery-unknown after a `POST` begins. The app never sends the same action
  automatically again.
- Confirmed pipeline responses replace the matching local pipeline. Confirmed
  job responses replace the exact ordinary job or insert a returned retry job
  by its new ID, then rebuild stage projection.
- A successful MR pipeline creation is inserted at the start of pipeline
  history and becomes navigable immediately.
- After a confirmed or uncertain result, perform one authoritative refresh.
  Existing bounded visible polling continues only if the reconciled pipeline
  or job remains actively changing.

### Cache and trace reconciliation

Invalidate only:

- the exact pipeline detail;
- its first ordinary-jobs page;
- its first trigger-jobs page only for pipeline-wide actions;
- the current MR pipeline-history first page when it can change; and
- the exact trace key for a canceled ordinary job.

Canceling a pipeline removes cached traces only for currently loaded ordinary
jobs that were nonterminal when the action began. Retry actions preserve
immutable historical traces because GitLab returns new job IDs. New or
retried job logs start with their own empty trace keys.

Add `remove(for:)` to `GitLabJobTraceStoring` and implement it with the same
ownership and path validation as account-wide removal. No action purges
another account or the entire response cache.

## Delivery certainty and errors

- Explicit `401`, `403`, `404`, validation, or local access rejection means
  rejected: keep the authoritative state, show GitLab's safe mapped error,
  and permit another attempt after state refresh.
- Connectivity, timeout, `5xx`, malformed response, decoding failure, or task
  cancellation after dispatch means delivery unknown: remove stale affected
  cache entries, refresh once, and tell the user to verify GitLab's state
  before trying again.
- Do not include request bodies, response bodies, job logs, variables, token
  values, or URLs containing credentials in user errors or debug
  descriptions.
- Authentication failures continue through `AppSession`'s existing
  account-scoped reauthentication path.

## UI

- Keep controls compact and icon-led. Put available pipeline actions in one
  trailing Liquid Glass toolbar/menu control rather than adding large cards
  or explanatory buttons to the list.
- Put an ordinary job's available action beside that job row in a small
  trailing menu. Trigger jobs keep their existing navigation behavior.
- Do not render disabled actions for impossible statuses. Read-only accounts
  see no write controls; accessibility still explains unavailable access
  where a user reaches a write-only confirmation through stale UI.
- Confirm cancel, retry, play, and create-pipeline actions. Retry, play, and
  create confirmations state that the action can consume CI runner resources.
  Cancel confirmations name the pipeline or job being stopped.
- While one action runs, replace its icon with a compact progress indicator.
  Success reconciles in place. Rejected or uncertain outcomes use concise,
  actionable alerts without optimistic success.
- Every icon has a 44-point hit target, VoiceOver label/hint/value, stable
  focus, Dynamic Type behavior, and deterministic accessibility identifiers.

## Tests

### Endpoint and service tests

- Exact method, `.write` access, path, absent body/query, and decoding for all
  six actions.
- Invalid routes and contradictory response identity.
- Current and older self-managed response shapes with optional fields absent.
- Read-only access rejection before transport.
- `401`, `403`, `404`, conflict/validation, rate limit, `5xx`, connectivity,
  cancellation, malformed response, and decoding failure.
- Exactly one transport attempt for every `POST`.
- Targeted invalidation after confirmed success and delivery-unknown failure,
  and no invalidation after explicit rejection.
- Exact trace removal and cross-account isolation.

### Model tests

- Every allowed and hidden action by documented status plus unknown status.
- Confirmation accept/cancel, stale confirmation, account replacement, and
  route identity.
- Rapid duplicate taps, conflicting actions, task cancellation, rejected
  delivery, unknown delivery, and retry only after reconciliation.
- Authoritative replacement/insertion, new retry job IDs, stage projection,
  pagination retention, MR history insertion, targeted trace removal, and
  bounded polling handoff.
- Auth failure routing and read-only accounts.

### Simulator and quality gates

Use deterministic iPhone 17 Pro fixtures for all states before using the
developer token:

- light/dark appearance, default and accessibility-extra-large text;
- VoiceOver order/labels, Increase Contrast, Reduce Motion, and Reduce
  Transparency;
- confirmations, success, rejection, uncertain delivery, progress, duplicate
  taps, and account replacement;
- each visible/hidden action state without controls covering rows or the
  bottom tab bar.

Then run focused tests, the complete suite once, Release Simulator build,
static analysis, plist/privacy/credential scans, and a final deep review.

Live mutation verification is optional and comes last. If needed, use only
`DEVOPS_DEMO_TOKEN` and its single authorized demo project. Never use the
read-only token for writes, mention or assign a human, modify membership, add
tags, expose secrets, or interact outside that project. A demo pipeline may
fail. Use a clearly identified test pipeline/job, confirm current state before
and after one action, and do not repeat an uncertain action.

## Implementation order

1. Commit and push this plan and the first two P3-11 checklist items.
2. Add failing route, endpoint, write-access, response-validation,
   delivery-certainty, and targeted-invalidation tests.
3. Implement the action service and targeted trace removal; run focused tests;
   commit and push.
4. Add failing pipeline-detail action-state and reconciliation tests.
5. Implement pipeline retry/cancel and ordinary job retry/play/cancel in the
   model; run focused tests; commit and push.
6. Add failing MR-pipeline creation model tests, then implement creation and
   history reconciliation; run focused tests; commit and push.
7. Add compact Liquid Glass controls and confirmations. Build, launch,
   inspect, and tap every deterministic state in the iPhone 17 Pro Simulator;
   repair UI defects; commit and push.
8. Run the proportional final gates once.
9. Deep-review every P3-11 production, test, fixture, and document change.
   Record each material finding and write its repair plan before editing.
10. Add regressions, repair findings, rerun affected gates, and repeat the
    review until no material issue remains.

## Deep-review checklist

Inspect for:

- a mutating endpoint mislabeled `.read` or automatically retried;
- invalid status eligibility, no-op actions presented as success, or missing
  confirmation;
- duplicate taps, overlapping actions, stale confirmation, or uncertain
  delivery offered for immediate retry;
- wrong project/pipeline/job/MR route or mismatched response reconciliation;
- over-broad cache invalidation, stale terminal traces, or cross-account data;
- stale account/route/action publication and polling that outlives visibility;
- variables, inputs, logs, credentials, bodies, or private URLs in errors,
  persistence, screenshots, or debug descriptions;
- trigger jobs incorrectly treated as ordinary jobs;
- oversized/duplicated controls, covered rows, weak accessibility, or
  unnecessary explanatory text;
- bad code, duplicate endpoint/action logic, or code that needs refactoring.

For every material finding: record the bug and impact, write the smallest
repair plan, add a failing regression, implement the repair, rerun the affected
P3-11 gates, and repeat this review.

## Safety checklist

- [x] Existing pipeline/job reads, polling, caches, account scope, mutation
  certainty, write gating, and trace storage were inspected.
- [x] Current official GitLab pipeline, job, and MR-pipeline action contracts
  and version history were researched.
- [x] This plan precedes every P3-11 production and test change.
- [x] Every action requires `.write` and is sent exactly once.
- [x] Arbitrary variables, inputs, files, and secrets are out of scope.
- [x] Valid positive routes and response identity are enforced.
- [x] Confirmation, single-flight state, and stale-account rejection are
  covered by tests.
- [x] Unknown delivery never causes an automatic retry.
- [x] Cache and trace invalidation is targeted and account-scoped.
- [x] Existing bounded polling owns reconciliation after action handoff.
- [x] Deterministic Simulator verification precedes any optional live action.
- [x] No human mention, assignment, membership, tag, or notification action.
- [x] Deep review and every repair plan are recorded before P3-11 is complete.

## Completion

Completed July 29, 2026.

- The seven focused P3-11 endpoint, action-service, action-model, MR creation,
  pipeline-detail, pipeline-history, and trace-store suites pass serially on
  the iPhone 17 Pro Simulator.
- The targeted Simulator flow opened MR pipeline history, confirmed and
  canceled pipeline creation, opened an active pipeline, confirmed and
  canceled pipeline cancellation, expanded an active stage, and confirmed and
  canceled an ordinary-job retry. Stable accessibility identifiers and labels
  were present throughout.
- Dark/default and light/accessibility-extra-large with Increase Contrast were
  visually inspected. The controls remain compact and the large layout remains
  scrollable without covering actions.
- The Release Simulator build and Xcode static analysis pass using the shared
  `.deriveddata/Glab`. The final P3-11 Release build emits no Swift warning.
- Both source and Release app property lists pass validation. No `.env`,
  credential file, debug pipeline fixture, or P3-11 document is present in the
  Release app bundle.
- The physical iPhone, `DEVOPS_DEMO_TOKEN`, and live mutation endpoints were
  not used for P3-11 verification. No person was mentioned, assigned, tagged,
  or notified.
- The review and repair plans are recorded in `docs/P3_11_REVIEW.md`. After
  the four repairs and regressions, the repeat review found no remaining
  material bug, duplication, or necessary refactor.
