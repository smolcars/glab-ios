# P3-01 Engineering Plan — Shared Mutation Foundation

## Status

- Planning: complete
- Implementation: complete
- Verification: complete after repair
- Deep review: complete; one material finding was planned, repaired, verified,
  and reviewed again

This document is the required plan for P3-01. Production code must not be
changed for this item until this plan is committed.

## Outcome

Later Phase 3 features can construct and send typed GitLab `PUT` requests
without weakening the app's existing write-access, authentication,
cancellation, account-isolation, retry, delivery-certainty, or cache
guarantees.

P3-01 adds shared transport capability only. It does not add a Phase 3 feature
endpoint, state owner, or user interface.

## Existing-code audit

### Request construction and transport

- `GitLabAPIRequest` supports typed `GET`, `POST`, GraphQL `POST`, and
  `DELETE` requests. `PUT` is the only HTTP method required by the planned
  Phase 3 resource edits that is missing.
- Typed `POST` bodies use `JSONEncoder` with ISO 8601 dates and sorted keys.
  `GitLabRequestBuilder` adds `Content-Type: application/json` only when a
  body exists and applies OAuth bearer or personal-token authentication after
  URL construction succeeds.
- `GitLabClient` checks cancellation immediately before request construction,
  immediately before transport, and immediately after transport. Only `GET`
  requests are eligible for automatic transient-failure retries.
- Response handling already provides typed empty-body and JSON decoding plus
  validation, authentication, authorization, not-found, rate-limit, server,
  connectivity, cancellation, invalid-response, decoding, and transport error
  categories.

### Session authorization and token refresh

- Every request declares `.read` or `.write` access.
  `GitLabSessionClient.ensureAccess` rejects `.write` requests from a
  `read_api` personal-token session before request construction or transport.
- OAuth and personal-token authorization are both applied by the shared
  request builder, so `PUT` must not introduce a separate credential path.
- Proactive OAuth refresh can occur before any request when an access token is
  already expired. Reactive refresh-and-retry after a `401` is restricted to
  reads. A `PUT` that reaches GitLab must therefore never be repeated
  automatically.
- `AppSession.synchronizeRefreshedSession` accepts a refreshed credential only
  when the callback still belongs to the active account. The signed-in shell is
  recreated with active-account identity, so feature state and its session
  client are not reused across accounts.

### Mutation behavior

- Todo, discussion, and reaction mutations already use typed `POST` and
  `DELETE`, return authoritative response objects where GitLab provides them,
  and explicitly invalidate the corresponding account-scoped read endpoint
  after success.
- `GitLabMutationDeliveryCertainty` already separates definitely rejected
  requests from failures where GitLab might have accepted the write. P3-01
  does not need a new mutation error hierarchy.
- A canceled caller cannot receive a late successful value because
  `GitLabClient` rechecks task cancellation after transport returns. Later
  feature models still remain responsible for generation or identity checks
  before applying an authoritative mutation response to UI state.

### Response caching

- Only `.get` requests have response-cache keys. A `PUT` will never be read
  from or written to the response cache.
- `GitLabSessionRequestSending.invalidateCachedResponse` is the existing
  endpoint-scoped, account-scoped invalidation seam. It also cancels an older
  in-flight exact-key read so that the obsolete response cannot repopulate the
  entry.
- The authoritative-response reconciliation seam is the typed value returned
  by `send`. Feature services return that value to their feature-specific state
  owner, then invalidate only the reads affected by the successful write.
  P3-01 will preserve this explicit pattern instead of introducing a generic
  mutation store.

## Official GitLab contracts

- GitLab's
  [REST request requirements](https://docs.gitlab.com/api/rest/#request-requirements)
  state that `PUT` and `POST` requests usually send a payload body and support
  JSON with `Content-Type: application/json`.
- [Update an issue](https://docs.gitlab.com/api/issues/#update-an-issue) is
  `PUT /projects/:id/issues/:issue_iid`, requires at least one update
  parameter, and accepts fields including title, description, labels,
  assignees, and `state_event`.
- [Update a merge request](https://docs.gitlab.com/api/merge_requests/#update-a-merge-request)
  is `PUT /projects/:id/merge_requests/:merge_request_iid`, requires at least
  one update attribute, and accepts fields including title, description,
  labels, assignees, reviewers, and `state_event`.
- [Resolve a merge request thread](https://docs.gitlab.com/api/discussions/#resolve-a-merge-request-thread)
  is `PUT /projects/:id/merge_requests/:merge_request_iid/discussions/:discussion_id`
  with required `resolved` boolean input. GitLab documents a query-parameter
  example, so the shared request must support bodyless `PUT` plus query items
  as well as JSON-body `PUT`.

## Exact implementation

### HTTP additions

1. Add only `put = "PUT"` to `GitLabHTTPMethod`.
2. Add a typed bodyless `GitLabAPIRequest.put` factory accepting path
   components and query items. The factory always requires `.write`; callers
   cannot weaken that access requirement.
3. Add a typed JSON-body `GitLabAPIRequest.put` factory accepting the same
   fields plus an `Encodable & Sendable` body. This factory also always
   requires `.write`.
4. Share the existing ISO 8601, sorted-key JSON-body encoding between `POST`
   and `PUT` if this avoids literal duplication without changing GraphQL or
   public behavior.

No caller may pass raw authorization headers, a raw URL, or an arbitrary body
content type through these factories.

### Authorization, retries, and cancellation

- A `PUT` endpoint must declare `.write`; the shared session access check then
  rejects read-only credentials before transport.
- OAuth uses `Authorization: Bearer …`; personal tokens use
  `PRIVATE-TOKEN: …`. Request and error descriptions must not expose either
  credential or JSON body text.
- `PUT` is not eligible for the `GET` retry policy.
- A transport timeout, lost connection, `429`, `5xx`, cancellation, or other
  ambiguous result is returned after the single attempted write and classified
  by the existing delivery-certainty model.
- Pre-cancelled requests never reach transport. A task canceled while a
  non-cooperative transport is in flight must discard the late response as
  `.cancelled`.
- Proactive OAuth refresh remains allowed before the first transport attempt.
  A `PUT` is not reactively retried after `401`.

### Invalidation and reconciliation seams

No new generic mutation state owner will be added.

- `GitLabSessionRequestSending.send` remains the typed authoritative-response
  seam.
- `invalidateCachedResponse` remains the exact read-invalidation seam.
- Tests will freeze that non-GET requests do not receive cache keys and that
  exact invalidation cannot be undone by an older in-flight read.
- Each later feature plan must identify which successful response replaces
  local state and which read endpoints it invalidates.

## Tests first

Before production implementation, add failing Swift Testing coverage for:

1. Bodyless `PUT` construction with query encoding and no content type.
2. JSON `PUT` construction with sorted JSON, ISO 8601 dates, and JSON content
   type.
3. OAuth and personal-token authorization on `PUT`, including descriptions
   that exclude credential and body secrets.
4. `read_api` rejection before transport and successful `api` write access.
5. Representative object and empty success decoding.
6. Validation (`400`/`422`), authentication (`401`), authorization (`403`),
   not-found (`404`), rate-limit (`429`), server (`5xx`), connectivity,
   cancellation, invalid-response, decoding, and transport failures.
7. A transient or ambiguous `PUT` failure performs exactly one transport
   attempt and no backoff.
8. Pre-cancellation performs zero attempts; cancellation during a
   non-cooperative in-flight request prevents its late success from reaching
   the caller.
9. Existing stale-account refresh-callback protection, exact cache
   invalidation, and POST/DELETE no-retry tests remain passing.

Tests will use injected transports, sleepers, and in-memory stores. P3-01 will
not call a live GitLab mutation endpoint.

## Migration impact

- Existing endpoints and service call sites require no migration.
- Adding an enum case is source-compatible within this app.
- `POST`, GraphQL, and `DELETE` request bytes, headers, authorization, error
  mapping, and retry behavior must remain unchanged.
- Later Phase 3 feature endpoints may opt into `PUT` one at a time through
  their own reviewed plans.

## Non-goals

- `PATCH` or other speculative HTTP methods.
- A generic CRUD repository, mutation queue, offline write queue, or automatic
  conflict resolver.
- Automatic retry of any write.
- Optimistic UI or feature-specific rollback behavior.
- Issue, merge-request, discussion, approval, assignment, or pipeline
  mutations.
- UI changes or physical-device testing.

## Ordered execution and verification

1. Commit this plan before production code.
2. Add the failing request, access, failure, retry, cancellation, redaction,
   cache, and account-isolation regressions.
3. Implement the minimum `PUT` request factories and shared body encoding.
4. Run focused core API and account-session tests.
5. Run the complete test suite.
6. Build Release for the iPhone 17 Pro Simulator.
7. Run Xcode static analysis plus credential, privacy, and forbidden-pattern
   scans.
8. Launch the unchanged app in the iPhone 17 Pro Simulator and smoke-test
   sign-in/Home navigation to detect integration regressions.
9. Perform the required deep review of every P3-01 change.

## Deep-review record

### First review

The first review covered:

- request/body duplication and encoding drift,
- access checks and credential redaction,
- accidental write retries or reactive refresh retries,
- failure-to-certainty classification,
- cache pollution or invalidation races,
- canceled-owner and stale-account response races,
- unnecessary abstractions or feature logic,
- POST/DELETE regressions.

#### Finding 1 — `PUT` can be mislabeled as read access

Material safety issue:

Both new `put(requires:path:query:)` factories accept a caller-selected
`GitLabAPIRequestAccess`. A future endpoint can therefore compile with
`requires: .read`, causing `GitLabSessionClient.ensureAccess` to permit a
mutating `PUT` for a `read_api` personal-token session.

Every `PUT` endpoint in the Phase 3 source contracts mutates GitLab state.
Caller-selectable access is unnecessary and makes the write-access guarantee
dependent on endpoint-author discipline.

Repair plan, written before the repair:

1. Remove the access parameter from both `PUT` factories and always construct
   them with `.write`.
2. Update the new tests and keep an explicit assertion that a constructed
   `PUT` requires write access.
3. Keep the session-client regression proving a `read_api` session rejects
   that request before transport and an `api` session sends it exactly once.
4. Do not change `POST`, GraphQL, or `DELETE`; their existing access contracts
   predate P3-01 and are outside this surgical repair.
5. Rerun focused request/client/access/OAuth tests, the complete signed and
   serialized suite, Release Simulator build, analyzer, scans, and Simulator
   smoke flow.
6. Repeat the deep review after the repair.

No other material correctness, retry, cancellation, delivery-certainty,
cache, account-isolation, credential-leakage, duplication, or refactoring
finding is open from the first review.

### Repair

The repair removed the caller-selected access argument from both typed `PUT`
factories and hard-coded `.write`. All call sites now use the smaller API, and
the request-construction test still asserts the resulting access requirement.

### Second review

The post-repair review repeated the first review's full scope and confirmed:

- every typed `PUT` is write-scoped by construction and a `read_api` session
  rejects it before transport;
- only `GET` is cacheable, coalesced, automatically retried, or reactively
  replayed after an OAuth `401`;
- proactive refresh happens before the sole `PUT` transport attempt, so an
  expired OAuth token does not cause a duplicate write;
- cancellation is checked before transport and after a non-cooperative
  transport returns, preventing a late response from reaching feature state;
- authoritative typed responses, exact account-scoped cache invalidation, and
  mutation delivery certainty remain the existing reconciliation seams;
- JSON encoding is shared only by REST `POST` and `PUT`, with no duplicate
  request path or speculative mutation abstraction;
- request descriptions, errors, and production logging do not expose
  authorization values or JSON bodies.

No material bug, bad code, duplicated logic, incorrect state ownership,
security or privacy issue, concurrency or cancellation race, or needed
refactor remains open after the repair.

## Pre-repair verification record

- The request/client/access/OAuth/cache/account focused suites passed. One
  existing cache-coalescing case failed under broad parallel contention and
  passed immediately in isolation; it also passed in the final full suite.
- The complete normally signed, serialized iOS 26.5 Simulator suite passed
  with 581 tests in 96 suites. Disabling signing was rejected as an invalid
  verification setup because the data-protection Keychain tests correctly
  require simulator app entitlements.
- The four contention-sensitive performance suites passed serially on the
  iOS 26.5 iPhone 17 Pro Simulator. A parallel run's parser timings were
  discarded because unrelated suites competed for the same Simulator.
- The Release iPhone 17 Pro Simulator build and Xcode static analyzer passed.
- Tracked-production-source scans found no configured GitLab token, hosted
  OAuth secret, forced cast, forced try, production request logging, shared
  `URLSession`, or `UserDefaults` use in the changed request code.
- `PrivacyInfo.xcprivacy` and the app Info.plist passed `plutil` validation.
- The Release app was installed only on the iOS 26.5 iPhone 17 Pro Simulator.
  The saved read-only self-managed account loaded Home, Todos, and Assigned
  Issues; back navigation returned to Home. The final settled screenshot was
  visually intact and the read-only access notice remained visible.

## Post-repair verification record

- The focused request-construction, client, session-access, mutation-certainty,
  cache, OAuth-refresh, and multiple-account suites passed with 89 tests.
- The complete normally signed, serialized iOS 26.5 Simulator suite passed
  with 581 tests in 96 suites. This includes the four performance suites and
  the entitlement-dependent Keychain tests.
- The Release iPhone 17 Pro Simulator build and Xcode static analyzer passed.
- `git diff --check` passed. Changed-code scans found no forced try, forced
  cast, fatal error, production request logging, configured credential, or
  hosted OAuth secret. `PrivacyInfo.xcprivacy` and the app Info.plist passed
  `plutil` validation.
- The post-repair Release app was installed only on the iOS 26.5 iPhone 17 Pro
  Simulator. The automated smoke flow opened Todos, returned Home, opened
  Assigned Issues, navigated back, and found Assigned Merge Requests. The
  settled Home screen was visually inspected and remained correctly laid out
  with the saved read-only self-managed account.
