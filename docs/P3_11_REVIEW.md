# P3-11 Deep Review and Repair Plan

Review date: July 29, 2026.

Scope: every production, test, fixture, and document change from the P3-11
engineering plan through the compact pipeline-action UI.

## Material findings

### P3-11-R1 — Pipeline cancellation can retain stale job traces

Impact: a confirmed pipeline cancellation, or a cancellation whose delivery is
unknown, invalidates pipeline API reads but leaves locally stored traces for
loaded nonterminal jobs. A later job-log visit can therefore start from content
captured before cancellation.

Repair plan:

1. Capture the IDs of loaded nonterminal ordinary jobs in the pipeline-cancel
   confirmation snapshot.
2. On confirmed cancellation and delivery-unknown cancellation, remove only
   those account- and project-scoped trace keys.
3. Preserve traces for terminal jobs, retries, plays, and explicitly rejected
   cancellations.
4. Add focused model regressions for success, unknown delivery, rejection, and
   cross-job isolation.

Status: planned.

### P3-11-R2 — Job actions invalidate unrelated trigger-job caches

Impact: retrying, canceling, or playing one ordinary job invalidates both
ordinary-job reads and trigger/bridge reads. This is broader than required and
causes avoidable child-pipeline network work.

Repair plan:

1. Split pipeline-wide invalidation from ordinary-job invalidation.
2. Pipeline retry/cancel continues to invalidate pipeline, ordinary jobs, and
   both trigger-job variants.
3. Ordinary-job retry/cancel/play invalidates only pipeline detail and ordinary
   jobs.
4. Update service tests to assert exact cache keys for both action classes.

Status: planned.

### P3-11-R3 — A convenience initializer assumes every MR is open

Impact: the unused short initializer for pipeline history supplies
`isMergeRequestOpen == true`. A future caller could accidentally expose
pipeline creation for a closed or merged MR.

Repair plan:

1. Remove the initializer rather than preserve an unsafe default.
2. Keep every production and fixture call site explicit about API access,
   account currency, and current MR state.
3. Rebuild the affected screens to ensure no implicit caller remains.

Status: planned.

## Review areas with no material finding

- All six mutations are `POST` requests requiring `.write`; the shared client
  does not automatically retry them.
- Positive route validation and response identity checks remain scoped to the
  requested account, project, pipeline, job, or MR where the GitLab response
  exposes that identity.
- Confirmations, single-flight state, stale status checks, account replacement,
  delivery certainty, and authentication routing are present.
- Trigger/bridge rows remain read-only navigation and are not sent through
  ordinary-job mutation endpoints.
- UI controls are icon-led, status-gated, compact, and have named 44-point
  targets and stable accessibility identifiers.
- No CI variables, inputs, logs, tokens, request bodies, human mentions,
  membership changes, or notification-producing actions were added.

## Verification after repairs

- Run only the focused action-model, action-service, pipeline-detail, pipeline
  history, endpoint, and trace-store tests.
- Build the Debug simulator target in the shared `.deriveddata/Glab`.
- Re-run the focused iPhone 17 Pro confirmation and compact-layout fixture.
- Run a Release simulator build and static analysis once at P3-11 closure.
- Repeat this review against the repaired diff; P3-11 remains open until no
  material finding remains.
