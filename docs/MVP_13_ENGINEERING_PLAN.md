# MVP-13 engineering plan: Todo routing and completion

Last updated: 2026-07-27

Status: complete. The implementation, regression suite, static analysis,
privacy scan, and iPhone 17 Pro interaction pass satisfy the gates below.

## Outcome

Make Todo rows useful without broadening the MVP beyond its two focused
actions:

- issue and merge-request Todos open the existing native details;
- every other target opens its validated GitLab `target_url`;
- a pending Todo can be marked done;
- all pending Todos can be marked done after confirmation.

Personal access tokens with only `read_api` remain fully usable for browsing.
Every API request must declare whether it requires read or write access, and a
read-only session must reject a write before credential refresh, URL
construction, or transport.

## Assumptions and official API contract

- `POST /todos/:id/mark_as_done` marks one pending Todo done and returns the
  completed Todo object.
- `POST /todos/mark_as_done` marks all pending Todos done and returns an empty
  `204` response.
- Both completion endpoints are write requests.
- GitLab's `api` token scope grants read and write API access. `read_api`
  grants read-only API access.
- Glab OAuth already requests `api`, so established OAuth sessions are
  read/write. Personal-token metadata remains the source of the read-only
  distinction.
- The list response supplies `target.project_id` and `target.iid` for issue
  and merge-request targets. A native route uses those values, with
  `project.id` as the project fallback.
- If an issue or merge-request Todo lacks a complete native route, a valid
  `target_url` is the fallback. All other target types use only a validated
  `target_url`.
- URLs with a non-HTTPS scheme, no host, embedded credentials, or another
  unsafe shape stay noninteractive.
- Completion is user initiated. A failed or cancelled write rolls back its
  optimistic local change. A later refresh remains the server-authoritative
  reconciliation path if delivery was ambiguous.
- The app does not add undo, Todo creation, background mutation, or persistence
  of optimistic state in this phase.

Sources:

- [GitLab To-Do List API](https://docs.gitlab.com/api/todos/)
- [GitLab access token scopes](https://docs.gitlab.com/security/tokens/access_token_scopes/)
- [GitLab REST API authentication](https://docs.gitlab.com/api/rest/authentication/)

## Architecture

Keep the existing Model-View and injected-loader boundaries.

### Request capability gate

- Add a small `GitLabAPIRequestAccess` value with `read` and `write`.
- Require every `GitLabAPIRequest` factory call to spell
  `requires: .read` or `requires: .write`; do not infer access from HTTP
  method.
- A next-page request is structurally read-only and exposes `.read` through
  `GitLabAPIPageRequest`.
- `GitLabSessionClient` checks the page/request requirement against the
  current session before OAuth refresh or transport.
- A rejected write returns a distinct, user-meaningful
  `GitLabSessionClientError.insufficientAccess` and does not require
  reauthentication.
- `GitLabRequestBuilder` remains responsible only for safe URL construction
  and authentication headers. Sign-in validation can continue using the raw
  client before a stored session exists.

This is a compile-time declaration at every endpoint and a runtime
defense-in-depth gate at the authenticated session boundary.

### Todo endpoints and service seams

- Keep `GitLabTodoLoading` read-only.
- Add a separate `GitLabTodoMutating` protocol for `markDone(id:)` and
  `markAllDone()`.
- Let the live Todo service implement both protocols with the shared session
  client.
- Add explicit write endpoints:
  - `GitLabAPIRequest<GitLabTodo>` for one Todo;
  - `GitLabAPIRequest<GitLabEmptyResponse>` for all pending Todos.

Separating the read and write protocols lets tests and UI dependencies state
which authority they use without creating a new service layer.

### Routing

- Add a hashable `GitLabTodoNativeRoute` with issue and merge-request cases.
- Derive a native route only from a matching target type and complete
  project/IID identity.
- `TodosView` receives the existing issue and merge-request loaders from the
  signed-in shell and registers their existing native detail destinations.
- A row uses:
  1. a native navigation link when `nativeRoute` exists;
  2. a system `Link` when only `safeTargetURL` exists;
  3. static row content when neither route is safe.
- Completion remains a separate trailing control so opening a row never
  triggers a write.

### Optimistic completion state

`TodosModel` owns mutation state while the generic pagination engine remains
unchanged:

- IDs being or already marked done are overlaid on every cached pending query,
  so the same Todo cannot reappear when filters change.
- A single tap immediately hides that row and decrements a reliable pending
  badge. Duplicate taps for the ID are ignored.
- On success, the returned done Todo is retained as a small overlay for an
  already-loaded done query and the done query is marked for refresh.
- On failure, only the optimistic change introduced by that attempt is rolled
  back and an actionable failure context is exposed.
- Mark-all snapshots the currently cached pending IDs, hides them immediately,
  and presents a zero badge while in flight. Failure restores only that
  operation's snapshot; success keeps pending caches hidden and makes the next
  done selection refresh from GitLab.
- A refresh may run while a mutation is in flight. The overlay stays
  authoritative until the mutation resolves, so a refresh cannot flash the
  pending row back into the list.
- Cancellation rolls back without presenting an error. Authentication
  failures continue through the existing `AppSession` handling.

The model receives `GitLabAPIAccess`, exposes `canComplete`, and still relies
on the session-client gate. The first controls are therefore disabled for a
read-only session, but an accidental call also cannot reach transport.

## Test-first implementation order

### 1. Declare and enforce request access

Write failing tests for:

- every existing read endpoint declaring `.read`;
- both Todo completion endpoints declaring `.write`;
- a read-only session successfully sending a read request;
- the same session rejecting a write before transport;
- an OAuth/read-write session sending a write;
- pagination remaining read-only;
- the new insufficient-access error description and reauthentication
  classification.

Then add the access declaration to the request type, update all endpoint and
authentication call sites, and enforce it in `GitLabSessionClient`.

This gate must be green and committed before adding the live mutation loader
or an enabled completion control.

### 2. Add Todo destinations

Write failing tests for:

- issue route derivation;
- merge-request route derivation;
- project-ID fallback;
- safe web routing for every non-native target category;
- safe web fallback for an incomplete issue/MR route;
- nil routing for missing or unsafe URLs.

Then add only the route presentation values and connect the existing native
detail loaders to `TodosView`.

### 3. Add mutation endpoints and model state

Write failing tests for:

- exact single and mark-all paths, methods, response types, and write
  requirements;
- successful single completion and the returned done overlay;
- immediate row removal and badge decrement before the response;
- single failure rollback and retry context;
- duplicate taps;
- successful mark-all and empty `204` decoding;
- mark-all confirmation state, optimistic empty state, and failure rollback;
- filter changes and a refresh while a mutation is in flight;
- read-only model capability;
- cancellation and authentication-failure propagation.

Then implement the write service and the minimum mutation state in
`TodosModel`.

### 4. Build completion UI

- Keep route interaction on the row's main content.
- Show a trailing mark-done control only for pending rows.
- Show progress for the affected row and prevent duplicate input.
- Add a pending-only toolbar action for mark-all with explicit confirmation.
- Keep single and mark-all controls visible but disabled for `read_api`.
- Show a compact read-only explanation that `api` permission is required.
- Present mutation failures next to retained content with retry and an
  accessible announcement.
- Preserve the existing filters, refresh, pagination, empty states, and tab
  badge behavior.

## Verification gates

1. Request capability tests prove unsupported writes never reach transport.
2. Endpoint, routing, and mutation-model suites pass independently.
3. The configured read-only session can browse and route but exposes disabled
   completion controls; no mutation request is sent during that pass.
4. Write behavior is exercised with deterministic protocol fakes. A real
   mutation is not sent with the user's read-only token.
5. Row routing, disabled read-only controls, single/all success, confirmation,
   rollback, refresh, filters, and navigation are tapped on iPhone 17 Pro.
6. Populated, in-flight, failure, empty, confirmation, and read-only states are
   visually inspected in light and dark appearance.
7. The complete signed unit-test suite passes on iPhone 17 Pro, iOS 26.5.
8. Xcode static analysis, property-list validation, and secret/logging scans
   are clean.
9. The implementation is committed and pushed to `master` in small, passing
   increments.
