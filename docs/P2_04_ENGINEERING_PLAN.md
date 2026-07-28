# P2-04 engineering plan: post comments and threaded replies

Last updated: 2026-07-28

Status: planned; implementation has not started.

Glab has never shipped. Breaking internal APIs and local draft formats are
acceptable when they make this feature smaller, safer, or easier to test. No
migration layer is required for draft data because no prior draft store
exists.

## Outcome

A write-enabled account can:

- add a new overview discussion to an issue or merge request;
- reply to an existing non-system discussion;
- see an explicit sending state;
- cancel an in-flight request without losing the draft;
- intentionally retry after a failure; and
- see the server-confirmed discussion or note reconciled into the loaded
  discussion list.

A `read_api` account can continue reading discussions and sees a concise,
non-pressuring explanation that commenting requires GitLab API write access.

## Success criteria

1. Empty or whitespace-only bodies never reach the network.
2. At most one POST is in flight for a composer.
3. No failed or cancelled POST is retried automatically.
4. A draft is saved before its POST begins and removed only after a successful
   server response is decoded.
5. Draft identity includes the account, issue or merge request, and optional
   discussion ID; one account can never restore another account's draft.
6. New discussion and reply POSTs require `.write`.
7. A successful mutation invalidates only the affected resource's cached
   first discussion page and reconciles the returned server identity in
   memory.
8. Read-only presentation, new-comment composition, reply composition,
   sending, cancellation, failure, retry, dismissal, and success are exercised
   with deterministic services in an iPhone 17 Pro Simulator.
9. No live mutation is sent with the configured self-managed read-only token.

## Inspected current state

- `GitLabDiscussionResource` already unifies issue and merge-request routes.
- `GitLabDiscussionEndpoints` and `LiveGitLabDiscussionLoader` currently
  implement paginated reads only.
- `GitLabDiscussionsModel` specializes the shared paginated model, which
  already prevents overlapping reads and preserves loaded content on failure.
- Only an initial discussions GET is cached. Later pages are memory-only.
- `GitLabSessionClient` rejects `.write` before transport for a read-only
  session and never automatically retries a POST.
- The Todo feature provides the existing mutation precedent: capability is
  checked in presentation state, the endpoint still declares `.write`, errors
  remain typed, and successful mutations invalidate relevant GET caches.
- OAuth sessions are classified as read/write. Personal access-token metadata
  distinguishes `api` from read-only `read_api`.
- `GitLabAPIError` already distinguishes validation, authentication,
  authorization, not-found, rate-limit, server, connectivity, cancellation,
  invalid-response, decoding, and transport failures.
- `AppSession` owns the credential store and account-partitioned response
  cache, and purges an account's cached responses when that account is
  removed.
- There is no draft store or production fixture mode.
- Issue and merge-request details each own a discussions model but share the
  discussion view.

## GitLab API contracts

Use the Discussions API for both new comments and replies:

| Resource | Operation | Endpoint | Response |
| --- | --- | --- | --- |
| Issue | New discussion | `POST /projects/:id/issues/:issue_iid/discussions` | `201` discussion |
| Issue | Reply | `POST /projects/:id/issues/:issue_iid/discussions/:discussion_id/notes` | `201` note |
| Merge request | New discussion | `POST /projects/:id/merge_requests/:merge_request_iid/discussions` | `201` discussion |
| Merge request | Reply | `POST /projects/:id/merge_requests/:merge_request_iid/discussions/:discussion_id/notes` | `201` note |

Each request has one required string `body`. Send it as a JSON payload with
`Content-Type: application/json`, which GitLab's REST API supports for POST
payloads. Preserve the user's body except for rejecting it when trimming
whitespace and newlines produces an empty string. Do not invent an undocumented
client-side maximum length.

GitLab does not allow adding a reply to a system note and returns `400`.
Glab will therefore omit reply controls for discussions whose visible notes
are all system activity. The service still exposes the normal typed validation
failure if server state changes between display and submission.

The first P2-04 slice creates overview discussions only. Merge-request diff
positions, internal notes, resolution state, quick actions, and editing or
deleting notes remain out of scope.

The `api` scope provides complete read/write API access. The `read_api` scope
is read-only. Capability is checked both before presenting a composer and by
the request's `.write` requirement.

Sources:

- [GitLab Discussions API](https://docs.gitlab.com/api/discussions/)
- [GitLab REST request payloads](https://docs.gitlab.com/api/rest/#request-payload)
- [GitLab access-token scopes](https://docs.gitlab.com/security/tokens/access_token_scopes/)
- [GitLab comments and threads](https://docs.gitlab.com/user/discussions/)

## Architecture

Retain the current Model-View architecture. A focused composer has enough
state to justify one observable model, but not a feature-wide MVVM, MVI, TCA,
coordinator, or repository layer.

```text
Issue/MR discussion section
  -> GitLabDiscussionComposerView (sheet)
  -> GitLabDiscussionComposerModel (@MainActor)
     -> GitLabDiscussionMutating
        -> LiveGitLabDiscussionService
        -> GitLabDiscussionEndpoints
        -> account-bound GitLabSessionClient
     -> GitLabDiscussionDraftStoring
        -> FileGitLabDiscussionDraftStore (actor)
  -> GitLabDiscussionsModel reconciliation
```

`LiveGitLabDiscussionService` will conform to both the existing read protocol
and a new mutation protocol. Issue and merge-request paths continue to switch
in exactly one endpoint builder.

The detail screen creates composer state only when presenting a sheet. The
sheet receives:

- account ID and API capability;
- discussion resource;
- target: a new discussion or a reply with a server discussion ID;
- the shared mutation service and draft store; and
- success closures that reconcile the returned value into the existing
  discussions model.

The composer must not own or duplicate the discussions list.

## Draft ownership and storage

Define a value key containing:

- `GitLabAccountID`;
- resource kind (`issue` or `mergeRequest`);
- numeric project ID;
- numeric issue or merge-request IID; and
- optional server discussion ID.

The key is Codable and Hashable but redacts its description. A new-comment
draft and each reply draft are independent.

`GitLabDiscussionDraft` contains the body and a monotonic revision. The
revision prevents an older delayed persistence task from overwriting newer
text. The composer debounces ordinary typing, but explicitly flushes the
latest body before sending or intentional dismissal.

The production store is an actor and writes one binary property-list record
per key under Application Support:

- account and draft filenames are SHA-256 hashes of non-secret identity
  values rather than readable host, resource, or discussion strings;
- writes are atomic;
- the directory and files use complete iOS file protection because drafts may
  contain confidential project information;
- corrupt, unknown-version, or empty records are removed and treated as no
  draft;
- explicitly removing or signing out an account removes that account's entire
  draft directory; an automatic expired-session removal retains drafts so a
  later sign-in to the same account can recover them; and
- draft bodies, hosts, usernames, project references, and tokens are never
  logged.

Storage failures retain the in-memory body and show a compact warning that the
draft could not be saved locally. A storage failure does not silently begin a
POST: the user must be told that the current draft cannot be protected before
sending.

The store does not use `UserDefaults`, Keychain, the response cache, or a
database. Draft text is not a credential, and the tiny account-partitioned
file store is faster and simpler than adding a persistence framework.

## Composer state and duplicate prevention

The model owns these orthogonal values:

- body and draft revision;
- whether the stored draft has been restored;
- draft persistence warning;
- request state: idle, sending, or failed;
- failure certainty: rejected or delivery unknown; and
- whether the latest successful result has been handed back.

`send()` follows this order:

1. Require write capability, a nonempty trimmed body, restored draft state,
   and no in-flight POST.
2. Persist the exact latest body and await that write.
3. Enter sending state and issue one POST.
4. On a decoded `201` result, reconcile the real server object.
5. Remove the draft only after GitLab's decoded success has been handed to
   reconciliation.
6. Dismiss the sheet after the draft removal completes.

A synchronous `isSending` guard prevents duplicate taps from creating
multiple requests. The send button is disabled during the request.

The sheet disables interactive dismissal while sending. Its toolbar action
changes from `Cancel` to `Cancel Sending`. Cancelling stops the current task
but keeps the sheet open so the user can see the delivery-unknown explanation.
Once the request settles, dismissal flushes the preserved draft.

The model never creates optimistic note or discussion IDs. Success uses only
the IDs returned by GitLab.

## Failure and retry policy

No POST is automatically retried by the client, service, model, view, or
refresh path.

Classify failures for presentation:

- **Rejected**: local empty body, read-only capability, GitLab validation,
  forbidden, or not found. GitLab did not provide a created object. Preserve
  the draft and let the user edit or explicitly try again where sensible.
- **Delivery unknown**: connectivity, cancellation after send begins,
  transport, server `5xx`, rate-limit, invalid response, or decoding failure.
  The server might have accepted the comment even though Glab did not receive
  a usable response. Preserve the draft, warn that retrying may duplicate the
  comment, and require an explicit `Try Again`.
- **Authentication failure**: preserve the draft and expose the existing
  reauthentication path. Automatic expired-session removal must retain draft
  files; explicit account removal and sign-out must purge them.

The failure card shows the error, whether delivery is uncertain, and an
explicit retry action. Editing the body clears a rejected validation message
but must not make an uncertain-delivery retry happen automatically.

## Reconciliation and cache invalidation

After GitLab confirms a mutation:

1. `LiveGitLabDiscussionService` invalidates only
   `GitLabDiscussionEndpoints.discussions(for: resource)`. That is the only
   persisted discussion page; later pages are not cached.
2. For a new discussion, append or replace by the returned discussion string
   ID while preserving server-backed identity.
3. For a reply, find the target discussion, append or replace by returned note
   integer ID, and replace that discussion value in the visible model.
4. Increment the model content revision so lazy presentation updates.

The shared paginated model will receive one narrow internal reconciliation
method that replaces an item by identity or appends a missing item and can
adjust a known total count. The discussion specialization owns reply
reconstruction. This avoids a second discussions model and avoids duplicating
pagination logic.

If a reply's target disappeared during an unusual concurrent refresh, do not
invent a container. The mutation remains successful, the draft is cleared,
and an explicit discussions refresh reconciles the server state.

Do not automatically refresh the issue or merge request detail. Its comment
count can update on the next ordinary refresh; P2-04 invalidates only the
discussion data it changed.

## UI and accessibility

The existing `Discussion` section gains:

- a compact `Add comment` action above the discussion list for write-enabled
  accounts;
- one `Reply` action at the bottom of each non-system discussion;
- a read-only capability callout in place of mutation actions; and
- no reply action for all-system activity.

The composer is a navigation sheet with:

- `New comment` or `Reply` title;
- a multiline native editor with visible label and placeholder;
- remaining body preserved through failure and dismissal;
- `Cancel`, `Cancel Sending`, and `Post` or `Reply` actions;
- visible sending progress;
- local validation and draft-storage warnings;
- a rejected or delivery-unknown failure card with explicit retry; and
- Dynamic Type, VoiceOver labels, minimum tap targets, keyboard dismissal,
  and stable accessibility identifiers.

Do not add a Markdown preview in P2-04. Rendering the posted server response
through the existing discussion Markdown view provides the final result
without doubling composer work.

## Isolation and cancellation

- Endpoint, body, result, draft key, draft value, and error types are immutable
  and `Sendable`.
- Network and file services are actors or nonisolated Sendable values.
- The composer and discussions models remain `@MainActor`.
- The SwiftUI sheet owns the send task and cancels it on `Cancel Sending` or
  disappearance.
- Draft persistence tasks are retained, cancelled when superseded, and guarded
  by revision in the store.
- `AppSession` owns the shared draft store so explicit account removal can
  purge it. Its automatic expired-session path removes credentials and the
  account index without purging drafts.
- No detached task, manual lock, global mutable singleton, or cross-account
  model is introduced.

## Test-first implementation slices

### Slice 1: endpoints and domain validation

Write failing Swift Testing coverage for:

- issue and merge-request new-discussion POST paths;
- issue and merge-request reply paths with opaque discussion IDs;
- `.write` requirement;
- JSON body and request headers;
- created discussion and created note decoding; and
- whitespace-only local validation.

### Slice 2: draft storage

Write failing coverage for:

- account/resource/target key separation;
- new-comment and per-discussion reply separation;
- atomic round-trip persistence;
- newer revisions winning over delayed older revisions;
- corrupt and unsupported records being discarded;
- exact-draft removal and account-wide removal;
- redacted descriptions and hashed paths;
- complete file-protection attributes where the test platform exposes them;
  and
- storage failures preserving the in-memory body.

### Slice 3: mutation service and reconciliation

Write failing coverage for:

- new discussion success and targeted cache invalidation;
- reply success and targeted cache invalidation;
- no invalidation on failure or cancellation;
- returned discussion append/replace without duplicate IDs;
- returned note append/replace without duplicate IDs;
- missing reply target handling; and
- known total-count adjustment only for a newly inserted discussion.

### Slice 4: composer model

Write failing coverage for:

- draft restore before editing;
- empty and whitespace-only bodies;
- read-only capability;
- draft flush before network;
- successful reconciliation and draft clearing;
- server validation failure with preserved draft;
- duplicate send taps;
- cancellation with preserved draft;
- connectivity, transport, decoding, rate-limit, and server failures marked as
  delivery unknown;
- no automatic retry after any failure;
- explicit retry sending exactly one additional POST; and
- dismissal flushing the latest revision.

### Slice 5: UI and integration

Add focused presentation tests for labels and capability copy where practical.
Build the complete app and use deterministic in-memory services on the iPhone
17 Pro Simulator to inspect:

- write-enabled new-comment and reply sheets;
- restored drafts;
- keyboard and multiline editing;
- disabled empty send action;
- duplicate-tap prevention and sending progress;
- cancellation, rejected failure, delivery-unknown warning, and explicit
  retry;
- success reconciliation;
- read-only explanation;
- no reply control on system activity;
- dark and light appearance;
- portrait layout and large Dynamic Type; and
- VoiceOver identifiers/labels through accessibility inspection.

Production must not gain a hidden fixture mode solely for manual testing.
Use a test host, SwiftUI preview/test harness, or temporary untracked
Simulator-only harness and remove it after verification.

The configured self-managed token may be used only for read-only checks:

- load a real issue and merge request discussion;
- confirm the account is classified `read_api`; and
- confirm the production UI never enables a mutation.

Do not send a live comment, reply, reaction, or other mutation.

## Verification

Run:

1. endpoint, draft-store, service, reconciliation, and composer-model tests;
2. all discussion and API/session regression tests;
3. the complete signed test suite;
4. Release performance gates to ensure discussion reconciliation does not
   regress P2-03 rendering budgets;
5. Xcode static analysis;
6. a production build for the resolved iPhone 17 Pro Simulator;
7. the deterministic Simulator UI matrix; and
8. a privacy scan for configured tokens, OAuth secrets, raw authorization,
   draft bodies, private host values, logging, `UserDefaults` draft writes,
   readable draft paths, and accidental fixture code.

After verification, shut down every Simulator and close Simulator.app.

## Mandatory deep review

Before marking P2-04 complete, review every added or changed line for:

- duplicate issue and merge-request mutation paths;
- accidental automatic POST retries;
- more than one in-flight request;
- draft loss on send, failure, cancellation, dismissal, or relaunch;
- stale revision overwrites;
- cross-account, cross-resource, or cross-discussion draft leakage;
- removing a draft before a decoded server success;
- fake or unstable local identities;
- duplicate reconciliation;
- wrong or overly broad cache invalidation;
- replies offered for system activity;
- authentication failures hidden from `AppSession`;
- confidential text in logs, filenames, defaults, screenshots, or fixtures;
- retained tasks or cancellation bugs;
- actor-isolation or Sendable violations;
- duplicated state or unnecessary abstraction; and
- code that needs material refactoring.

Record findings in this document. If anything material is found, write a
repair plan here before editing, add regression tests, implement every fix,
repeat focused and full verification, and review the repaired code again.

## Non-goals

- Markdown composer preview or toolbar.
- Editing or deleting notes.
- Internal/admin-only notes.
- Resolving or reopening threads.
- Merge-request diff-position comments.
- Emoji reactions (P2-05).
- Push notifications or background posting.
- Offline send queues, automatic retry, or scheduled drafts.
- Attachment upload.
- Mention, user, issue, or quick-action autocomplete.
- Server-side draft sync.
- Live writes with the configured read-only account.

## Planned implementation order

1. Add failing endpoint/body tests, then implement shared create/reply
   endpoints.
2. Add failing draft tests, then implement the actor-backed in-memory and
   protected file stores and account purge integration.
3. Add failing mutation/cache tests, then extend the live discussion service.
4. Add failing reconciliation tests, then add the narrow generic item
   reconciliation hook and discussion-specific reply merge.
5. Add failing composer tests, then implement validation, persistence, send,
   cancellation, failure certainty, retry, and success behavior.
6. Add the shared composer/read-only/reply UI to issue and merge-request
   details.
7. Run focused checks and inspect deterministic Simulator states.
8. Run the full suite, analyzer, performance and privacy checks.
9. Perform the mandatory deep review, plan and fix findings, rerun all
   relevant verification, update the Phase 2 checklist, commit, and push.
