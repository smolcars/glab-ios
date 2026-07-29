# P3-13 Engineering Plan — Trigger and Open Child Pipelines

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Implementation: pending
- Simulator verification: pending
- Deep review: pending
- Final quality gates: pending

Research date: July 29, 2026.

This plan must be committed and pushed before any P3-13 production or test
code is changed.

## Outcome

A signed-in user with GitLab API write access can:

- run a manual trigger job from any pipeline detail screen;
- see that bridge reconcile from manual to its authoritative server state;
- open the downstream pipeline natively as soon as GitLab returns its project
  and pipeline identity; and
- repeat the same flow for nested child pipelines.

The action remains compact, explicitly confirmed, account-scoped,
single-flight, submitted once, and reconciled against GitLab. The app never
creates an unrelated project pipeline as a substitute for playing the
configured trigger job.

## Existing-Code Audit

- Pipeline detail already loads ordinary jobs and trigger jobs independently.
  It prefers
  `GET /projects/:id/pipelines/:pipeline_id/trigger_jobs` and falls back to
  legacy `/bridges` only after a documented `404`.
- `GitLabPipelineTriggerJob` already decodes bridge identity, status, parent
  pipeline, optional downstream pipeline, user, timing, and validated web URL.
- A trigger row already becomes a native `NavigationLink` when the response
  contains positive downstream project and pipeline IDs. Because the
  destination is another `GitLabPipelineDetailView`, navigation is already
  recursive.
- A trigger row without complete downstream identity is currently read-only.
  If GitLab returns a downstream object with only a safe web URL, the row can
  offer that URL instead of inventing a native route.
- `GitLabPipelineActionModel` owns status-aware confirmations, account and
  write-access gates, single-flight delivery, stale-state rejection,
  uncertain-delivery handling, and post-action refresh for ordinary jobs and
  pipelines.
- `LiveGitLabPipelineActionService.playJob` currently decodes only
  `GitLabPipelineJob`. GitLab returns a bridge representation when the same
  Play endpoint targets a trigger job, so reusing that response type would be
  incorrect.
- Pipeline detail already polls while the parent pipeline, an ordinary job, or
  a trigger job has an actively changing status. No second general polling
  loop is needed.
- The pipeline response cache is endpoint-keyed. Trigger mutations must
  invalidate the parent pipeline and both preferred and legacy trigger-job
  reads without purging other projects or accounts.

## Official GitLab Contracts

Primary documentation and implementation references:

- Jobs API: <https://docs.gitlab.com/api/jobs/>
- Downstream pipelines:
  <https://docs.gitlab.com/ci/pipelines/downstream_pipelines/>
- Current GitLab Jobs API implementation:
  <https://gitlab.com/gitlab-org/gitlab/-/blob/master/lib/api/ci/jobs.rb>

### Read trigger jobs

GitLab 19.2 and newer:

`GET /projects/:id/pipelines/:pipeline_id/trigger_jobs`

Compatibility route:

`GET /projects/:id/pipelines/:pipeline_id/bridges`

The existing loader already owns this capability selection and it remains
unchanged.

### Play a manual trigger job

`POST /projects/:id/jobs/:job_id/play`

The documented Play endpoint accepts a job in `manual` status. GitLab's
current API implementation resolves either a build or a bridge, verifies
`play_job`, verifies the job is still playable, and returns
`Entities::Ci::Bridge` for a bridge.

No body is sent in P3-13. Job variables and job inputs are deliberately
excluded because they add secret handling, validation, and self-managed
version compatibility beyond this feature.

### Compatibility and authority

- Older self-managed GitLab releases have reported `404` for manual bridge
  Play. The app does not invent a fallback endpoint or create a standalone
  pipeline, because either could bypass the trigger job's configured include,
  variables, permissions, strategy, and upstream relationship.
- A `400`, `403`, `404`, or other explicit server rejection is shown as a
  scoped action error. A `404` is not permanently cached as an
  instance-wide capability because permissions and bridge configuration can
  also produce job-specific failures.
- GitLab remains authoritative for project membership, protected
  environments, deployment ordering, bridge playability, and whether the
  downstream pipeline can be created.
- A canceled request or transport loss after dispatch has unknown delivery.
  The POST is never automatically retried.

## Deliberate Scope

### Included

- Manual trigger jobs whose current status is exactly `manual`.
- The existing compact Play icon in the trigger row.
- A confirmation that names the trigger and warns that it can start CI or
  deployment work.
- Authoritative bridge response reconciliation.
- Immediate refresh of the parent pipeline and trigger-job list.
- Existing bounded visible polling while the bridge remains active.
- Native downstream navigation when both downstream project and pipeline IDs
  are present.
- Safe GitLab web navigation when native identity is incomplete but a
  validated downstream URL exists.
- The same behavior at every recursively opened child-pipeline level.

### Excluded

- Automatically navigating away after a trigger succeeds.
- Guessing a missing downstream project ID from a URL or assuming every
  downstream pipeline belongs to the parent project.
- Trigger variables, job inputs, secrets, or protected variable display.
- Retrying a completed bridge to recreate its downstream pipeline.
- Canceling a bridge directly.
- Trigger tokens, pipeline schedules, CI configuration editing, or arbitrary
  standalone pipeline creation.
- Background polling after the pipeline detail screen is no longer visible.

The row remains in place after Play. When GitLab supplies complete downstream
identity, it changes naturally from an action row into a tappable child
pipeline row. This avoids surprising navigation and lets the user see whether
the trigger was accepted.

## Architecture and State Ownership

Keep the existing SwiftUI MV boundaries. This feature does not justify a new
coordinator, reducer, or pipeline action framework.

### Models

- Add a distinct `playTriggerJob` action kind rather than pretending a bridge
  is an ordinary job.
- Extend the action model with:
  - a current-trigger-jobs projection;
  - status-aware trigger action eligibility;
  - trigger-specific confirmation creation and stale validation; and
  - a trigger reconciliation closure.
- Confirmation captures the bridge ID, displayed name, parent route, and
  observed `manual` status.
- `GitLabPipelineDetailModel` remains the source of loaded trigger rows and
  adds one focused `reconcileActionTriggerJob` operation.
- The paginated trigger resource replaces the matching bridge by ID and
  reprojects stages. It does not discard loaded pages or insert a duplicate.

### Endpoint and service

- Add a typed `playTriggerJob` endpoint using the same
  `/projects/:id/jobs/:job_id/play` path but decoding
  `GitLabPipelineTriggerJob`.
- Add `playTriggerJob(at:)` to `GitLabPipelineActionServing`.
- Validate that:
  - the returned bridge ID matches the requested bridge ID;
  - a returned parent pipeline ID matches the open pipeline;
  - a returned parent project ID, when present, matches the open project; and
  - downstream identity is accepted only as optional response data and never
    substituted for parent identity.
- On confirmed success or unknown delivery, invalidate only:
  - the exact parent pipeline response;
  - the preferred first trigger-jobs response; and
  - the legacy first bridges response.
- Immediate model reconciliation updates the matching bridge anywhere in the
  loaded pages. The existing retained-tail refresh behavior remains intact.
- Do not invalidate ordinary job traces because a trigger job has no ordinary
  runner trace in this flow.

### Mutation flow

1. The row exposes Play only for a current manual trigger, a current account,
   and write-capable credentials.
2. Tapping Play creates one confirmation snapshot.
3. Confirming rechecks account, route, bridge ID, status, and current action.
4. The service sends one POST.
5. A valid bridge response replaces the matching trigger row.
6. The detail model performs one authoritative refresh.
7. Existing visible polling continues only while server state is actively
   changing.
8. Once valid downstream identity appears, tapping the row opens the child
   pipeline using the existing detail screen.

If the bridge becomes terminal without downstream identity, polling stops and
the row remains honest about the returned state. The app offers a validated
GitLab link when available rather than spinning indefinitely.

## UI and Accessibility

- Reuse the small trailing Liquid Glass Play button used by ordinary manual
  jobs. Do not add another card, banner, or text-heavy action.
- Use the existing child-pipeline status icon and metadata. The button gets:
  - label: `Run child pipeline, <trigger name>`;
  - hint: `Shows a confirmation before starting this child pipeline`; and
  - stable identifier:
    `pipelines.detail.triggerJob.<id>.action.playTriggerJob`.
- Confirmation title: `Run child pipeline?`
- Confirmation body names the trigger and states that it can consume CI
  resources or begin a deployment.
- Disable pipeline and job actions while another action on the screen is in
  flight.
- Preserve a minimum 44-point hit target, Dynamic Type, VoiceOver order,
  Increase Contrast, Reduce Motion, and dark/light appearance.
- Do not auto-push the child screen after mutation. The row becomes a
  navigation target when authoritative identity arrives.

## Error and Reconciliation Behavior

- Explicit rejection: keep current content and show GitLab's sanitized error.
- Stale manual status: do not dispatch; refresh and ask the user to review the
  new state.
- Unknown delivery: invalidate and refresh, explain that GitLab might have
  received the trigger, and never send it again automatically.
- Account replacement or navigation away: cancel publication into the old
  screen and never reconcile into another account.
- Missing downstream project ID: retain safe web navigation only.
- Malformed or contradictory response: reject it, invalidate affected reads,
  and refresh without constructing a route.
- Protected-environment or deployment-order rejection remains a server
  decision; the app does not infer permission from token scope.

## Test Plan

Write focused failing tests before production changes.

### Endpoint and decoding

- Play uses POST, `.write`, and the exact encoded project and bridge IDs.
- A current bridge Play response decodes with and without a downstream
  pipeline.
- Current `/trigger_jobs` and legacy `/bridges` response shapes remain
  supported.
- Missing optional project ID, timestamps, user, and web URL do not corrupt
  the bridge.
- Invalid IDs, contradictory parent identity, malformed downstream identity,
  and unknown statuses are handled without guessing.

### Service

- Success returns and validates a bridge, not an ordinary job.
- Success invalidates the parent and both trigger-job endpoint variants.
- Explicit rejection does not retry.
- Unknown delivery invalidates and refreshes but sends only once.
- Authentication and read-only failures remain distinguishable.
- Another account, project, pipeline, or bridge cannot receive reconciliation.

### Model and projection

- Only a manual trigger exposes `playTriggerJob`.
- Read-only, replaced-account, stale, active, and terminal triggers do not
  expose Play.
- Rapid taps and conflicting ordinary/trigger actions remain single-flight.
- Alert dismissal ordering preserves the displayed confirmation snapshot.
- A successful bridge response replaces the row without duplication.
- A response with downstream identity makes the row natively navigable.
- A response without downstream identity remains non-navigable and is
  refreshed.
- Nested child pipeline detail exposes the same manual trigger behavior.
- Pagination, loaded tails, stage ordering, search, and ordinary job actions
  remain intact.

### UI and live verification

- Verify manual, pending, running, success, failed, unsupported, permission
  denied, unknown-delivery, missing-identity, nested-child, offline-cache, and
  account-switch states in the iPhone 17 Pro Simulator.
- Tap through confirmation cancellation and confirmed Play.
- Verify the row becomes navigation without layout jumps or a second action
  card.
- Use only the developer-scoped demo project for one live manual bridge Play.
  Treat any jobs or deployments it starts as a real mutation and require an
  explicit confirmation tap. Do not tag or notify people.

## Verification Gates

- Focused trigger-job endpoint, decoding, service, action-model, pagination,
  projection, and navigation tests.
- Existing pipeline detail and ordinary job action suites.
- Release Simulator build and direct visual/tap inspection.
- Xcode static analysis and diff check.
- Credential, token, URL, and privacy scan.
- No physical-device testing unless the user explicitly requests an install.

## Implementation Sequence

1. Add failing bridge Play endpoint, decoder, invalidation, and service tests.
2. Add failing action-model and trigger reconciliation tests.
3. Implement the typed bridge mutation and focused model seams.
4. Add the compact trigger-row Play control and recursive navigation proof.
5. Run focused verification and inspect the Simulator.
6. Perform the required deep review and repair loop.
7. Run final quality gates, update both documents, and push small commits.

## Required Deep Review

After implementation, review every P3-13 change for:

- bridge/build response-type confusion;
- unsupported self-managed assumptions;
- wrong parent or downstream project identity;
- accidental standalone pipeline creation;
- duplicate or lost trigger rows across pagination;
- repeated POST delivery or action races;
- stale confirmation or account publication;
- over-broad cache invalidation;
- unbounded polling or navigation loops;
- permission and protected-environment assumptions;
- secrets, variables, tokens, or private URLs in logs;
- duplicated action logic; and
- code that needs refactoring.

Record every material finding in this document. If anything is found, write a
repair plan before editing, add a regression test, fix it, rerun the focused
and final verification gates, and repeat the deep review until no material
finding remains.

## Success Criteria

P3-13 is complete only when:

- a manual trigger job can be played exactly once after confirmation;
- the authoritative bridge state replaces the existing row;
- a valid downstream pipeline can be opened natively;
- nested child pipelines use the same flow;
- unsupported or denied instances fail honestly without a fallback mutation;
- ordinary pipeline and job actions remain unchanged;
- the complete verification and deep-review gates pass; and
- the implementation and review status are committed and pushed.
