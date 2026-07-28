# P2-01 engineering plan: multiple GitLab accounts

Last updated: 2026-07-28

Status: planned before implementation. The current single-session
implementation has been inspected. Glab has never shipped, and the owner
explicitly authorized breaking persistence changes, so this feature will
replace the old `current-session` Keychain format instead of migrating it.

## Outcome

Allow a user to add, switch, and remove GitLab.com and self-managed accounts
without signing out of the others:

- identify an account by canonical GitLab host and GitLab user ID;
- store each account's OAuth or personal-access-token session independently in
  Keychain;
- keep only a non-secret account index and active-account identifier in
  `UserDefaults`;
- rebuild the complete signed-in feature hierarchy when the active account
  changes;
- prevent credentials, cached responses, authentication failures, refreshed
  credentials, and late in-flight results from affecting a different account;
- preserve the existing GitLab.com OAuth, self-managed OAuth, and personal
  access-token entry points when adding an account.

## Inspected current state

- `GlabApp` creates one `AppSession`, one fixed
  `KeychainGitLabCredentialStore`, and one shared file response cache.
- `KeychainGitLabCredentialStore` reads and writes one generic-password item
  whose account is `current-session`.
- `AppSession` restores, establishes, invalidates, and deletes one
  `GitLabStoredSession`. Signing out deletes that item and purges that
  session's response-cache partition.
- `SignedInShellView` constructs one `GitLabSessionClient` and all feature
  models from the active session. SwiftUI currently has no explicit identity
  forcing those `@State` models to be discarded when a different session
  replaces it.
- `GitLabSessionClient` and the response cache already derive cache identity
  from canonical `GitLabHost` plus GitLab user ID. This boundary should be
  reused, not replaced.
- OAuth refresh conditionally replaces the expected stored session, which is
  the right race-safety shape but currently targets the single fixed item.
- Feature views report authentication failures to `AppSession` without the
  account that produced them. A late failure from a removed feature tree could
  therefore invalidate whichever account is active later.
- The Account sheet shows only the active profile and a destructive Sign Out
  action. The existing signed-out OAuth scene already contains GitLab.com,
  self-managed, and personal-token flows and can be reused for Add Account.
- There is no draft store yet. P2-04 will key drafts by the account identity
  introduced here. There is no existing draft data to migrate or isolate in
  P2-01.

## Architecture decision

Keep the existing SwiftUI Model-View architecture. `AppSession` remains the
single main-actor owner of app-level account inventory, active-account state,
and transitions. Do not add a second app store, coordinator, reducer
framework, or parallel client composition layer.

```text
GlabApp
  -> AppSession (@MainActor)
     -> GitLabAccountIndexStoring (non-secret UserDefaults data)
     -> GitLabCredentialStore (one Keychain item per account)
     -> GitLabResponseCaching (already partitioned per account)
  -> AppRootView
     -> SignedInShellView.id(activeAccountID)
        -> account-bound GitLabSessionClient and feature models
```

### Account identity

Add immutable `GitLabAccountID`, composed of:

- normalized `GitLabHost`;
- authenticated GitLab numeric user ID.

Usernames are presentation only and never identity. The same username on two
hosts is two accounts; a renamed username on the same host and user ID remains
the same account. Descriptions and debug descriptions must remain redacted.

The Keychain account attribute will use a deterministic SHA-256 digest of the
account identity rather than exposing a private hostname in metadata.
Credentials and tokens are never part of identity, hashing, logs, defaults,
or cache keys.

### Non-secret account index

Add a bounded-shape, versioned `GitLabAccountIndex` containing:

- ordered account summaries derived from the validated session's host, user,
  credential kind, and API access;
- an optional active `GitLabAccountID`;
- a storage format version.

The index contains no access token, refresh token, OAuth authorization code,
client secret, or personal-access-token value. It is encoded as one data value
in `UserDefaults`. Decode or structural validation failure is surfaced as
corrupt local account metadata; it is not silently interpreted as an empty
account list.

No legacy migration will be implemented. On the first build with this format,
the obsolete fixed `current-session` item is ignored. The test Simulator will
sign in again using the configured read-only self-managed credential. This is
an intentional pre-release breaking change authorized by the owner.

### Credential storage

Change `GitLabCredentialStore` to account-addressed operations:

- load a session for an exact `GitLabAccountID`;
- save a session under the identity derived from that session;
- conditionally replace only the exact expected session for OAuth rotation;
- delete only an exact account.

The in-memory implementation stores a dictionary and remains the primary test
double. The Keychain implementation keeps
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, data-protection Keychain use,
non-synchronizing items, ISO-8601 date encoding, and redacted diagnostics.

### `AppSession` state ownership

`AppSession` publishes:

- the existing restoration/signed-out/signed-in/failure state;
- ordered non-secret account summaries;
- the active account ID;
- an optional account-scoped authentication notice.

Operations:

1. `restore()` loads and validates the index, then loads only the selected
   Keychain session. Missing active credentials are removed from the index and
   the next valid account is selected. An expired OAuth session is kept only
   when it has a refresh token.
2. `establish(_:)` saves or replaces that account's credential, upserts its
   summary, makes it active, and publishes the new session only after both
   persistence steps succeed.
3. `switchAccount(to:)` loads the exact stored session, validates it, persists
   the active ID, and then publishes it.
4. `removeAccount(_:)` requires a UI confirmation, removes only that
   credential and cache partition, removes the summary, and activates the next
   available account or signs out.
5. Authentication invalidation removes only the account that produced the
   terminal authentication error. A stale error from a non-active account is
   ignored by the active UI.
6. OAuth refresh synchronization accepts only the currently active account's
   exact host/user/application configuration; the credential store's
   conditional replacement targets that account's Keychain item.

Main-actor methods that suspend are reentrant. Account transitions will carry
a monotonically changing transition token and verify it after each suspension
before publishing state. The most recently requested switch wins; an older
load cannot overwrite it.

### Feature-tree reconstruction and cancellation

`AppRootView` will apply the active `GitLabAccountID` as the explicit identity
of `SignedInShellView`. Switching accounts therefore destroys the old
navigation stacks and `@State` feature models, and SwiftUI cancels their
`.task` work.

Every feature-tree authentication callback will carry its captured
`GitLabAccountID`. `AppSession` will reject a late refresh or authentication
failure when that identity is no longer active. This is the correctness
boundary even if an underlying network request does not observe cancellation
immediately.

The app will not retain navigation paths, selected filters, Todo optimistic
mutations, or model objects across an account switch. Future drafts will be
keyed by this same account ID.

## API contracts

P2-01 adds no new GitLab endpoint. Authentication continues to validate a
session through authenticated `GET /user`, whose numeric `id` and current
username/name/avatar form the validated local account identity and summary.

GitLab documents Authorization Code with PKCE as the recommended mobile/public
client flow. It does not require a client secret in the app. Refresh replaces
both the prior access and refresh token, so the exact account's Keychain item
must be atomically conditionally replaced. Personal tokens continue to use
`read_api` for read-only access or `api` for read/write access.

Sources:

- [GitLab OAuth 2.0 and PKCE](https://docs.gitlab.com/api/oauth2/)
- [GitLab Users API: retrieve the current user](https://docs.gitlab.com/api/users/#retrieve-the-current-user)
- [GitLab REST API authentication](https://docs.gitlab.com/api/rest/authentication/)
- [GitLab access-token scopes](https://docs.gitlab.com/security/tokens/access_token_scopes/)

## Failure and recovery behavior

- Index decode/encode failures show the existing recoverable local-storage
  failure state without deleting Keychain credentials.
- A missing Keychain record removes only its stale summary and tries the next
  indexed account.
- Adding an account writes its credential before publishing it. If the index
  update fails, the new credential is deleted; when replacing an existing
  account, its prior credential is restored.
- Switching persists the active ID before publishing the new session. Failure
  leaves the prior account active.
- Removing an account updates the index and deletes its credential as one
  compensated operation. Any failed persistence step restores the prior index
  where possible and reports the error; the UI must not claim removal
  succeeded.
- Cache purge failure is non-fatal because cache removal is best-effort and the
  cache is already unreadable from another account identity.
- Terminal authentication failure removes only its owning account. If another
  account exists, the app activates it and presents an account notice; if not,
  the normal sign-in scene presents the notice.
- Cancellation is not shown as an error and never changes the active account.

## Test-first implementation slices

### Slice 1: identity and storage

Write failing Swift Testing coverage for:

- canonical host plus user-ID identity;
- identical usernames on different hosts;
- versioned index round-trip, active-account restoration, duplicate rejection,
  and corrupt data;
- saving and loading two in-memory sessions;
- saving and loading two Keychain sessions;
- conditional OAuth replacement of only one account;
- deleting one account without altering the other;
- descriptions, defaults, and Keychain metadata not containing credentials.

Then implement the identity, summary, index store, and account-addressed
credential stores. Run focused storage tests and commit this buildable slice.

### Slice 2: session transitions and isolation

Write failing tests for:

- restoring the indexed active account;
- adding a second account and making it active;
- switching and persisting the selection across a new `AppSession`;
- removing active and inactive accounts independently;
- missing/corrupt/expired active records;
- the latest of two gated switches winning;
- a stale account's late authentication failure and OAuth refresh being
  rejected;
- terminal failure removing only its owner;
- purging only the removed account's response cache.

Then update `AppSession`, refresh storage, and active-account callback
boundaries. Run focused session, OAuth refresh, cache, and sign-in tests and
commit this slice.

### Slice 3: account UI and feature reconstruction

Write focused presentation/state tests where logic can be expressed without
rendering. Then:

- key the signed-in root by active account ID;
- add an Accounts section showing avatar, display name, username, and host;
- visibly identify the active account;
- switch on row selection;
- add Add Account by reusing the complete existing sign-in scene;
- replace Sign Out with confirmed Remove Account behavior;
- disable concurrent account actions and present persistence errors inline;
- retain the Privacy/API access and read-only explanations for the active
  account.

Run focused tests, the complete signed suite, static analysis, and the
Simulator matrix before committing.

## Simulator verification

Use only an iPhone 17 Pro Simulator. Do not select, build for, install on,
launch, or inspect a physical device.

Use the local `.env` self-managed URL and read-only token only through a
non-logging Simulator sign-in helper. Never echo it, place it in a Maestro
flow, commit it, bundle it, or include it in screenshots/test results.

Verify:

1. clean launch and add the self-managed read-only account;
2. open Account and see its active marker, host, identity, and read-only state;
3. open Add Account and exercise GitLab.com/self-managed OAuth and token entry
   presentation without performing an unauthorized write;
4. add a deterministic second account for UI verification if a second live
   credential is unavailable;
5. switch both directions and confirm Home/Todos/navigation state rebuilds;
6. terminate/relaunch and confirm the selected account restores;
7. remove inactive and active accounts with cancel/confirm paths;
8. confirm only the removed account's cache disappears;
9. rapidly switch while a gated deterministic load is pending;
10. inspect light and dark appearance, large Dynamic Type, VoiceOver labels,
    loading/error presentation, and tap targets.

All simulators will be shut down after verification.

## Security and privacy scan

- Scan tracked source, built products, defaults data, Keychain test metadata,
  cache directory names, logs, and screenshots for the configured token,
  OAuth client secret, authorization headers, and private host text where it
  should be hashed.
- Confirm the account index contains summaries only.
- Confirm each Keychain item is non-synchronizing and
  `WhenUnlockedThisDeviceOnly`.
- Confirm every credential replace/delete call carries an exact account ID.
- Confirm all cache removal remains scoped by host plus user ID.

## Performance risks and budgets

The account list is expected to be small. Startup loads the index and only the
active credential; it must not decode every Keychain session. Switching makes
one Keychain read and reconstructs feature models synchronously without
networking on the main actor. Network loads begin through existing `.task`
work after the new hierarchy appears.

Targets:

- account-index decode and active credential lookup do not visibly delay the
  existing restoration screen;
- switch interaction publishes the stored session without waiting for Home or
  Todos network requests;
- no old model remains retained solely by account infrastructure after the
  root identity changes.

No speculative background refresh or cross-account preloading will be added.

## Deep-review findings and repair plan

The first implementation pass exposed the following material issues:

1. An account removal published its index only after credential deletion. A
   switch during that suspension could therefore recreate the removed account.
2. A stale failed account addition could unconditionally restore or delete a
   credential written by a newer addition for the same account.
3. A removal could unconditionally delete a newer credential when the same
   account was re-established while Keychain deletion was suspended.
4. Failure to load the fallback account after removing the active account left
   the app indefinitely in its restoring state.
5. A terminal authentication failure that successfully selected another
   account retained an authentication notice that no signed-in UI presented.
6. Keychain decoding did not verify that the decoded session identity matched
   the account identity used to address the Keychain item.

Repair plan, recorded before the remaining review edits:

- publish the removal index before suspension and retain last-transition-wins
  guards around every later state publication;
- make rollback and removal credential writes conditional on the exact session
  value they intend to replace or delete, with atomic production-store
  implementations;
- do not purge a cache partition if the same account was re-established during
  a stale removal;
- convert fallback Keychain-load errors into an explicit failed app state;
- present retained terminal-authentication notices over the newly selected
  signed-in hierarchy and add an explicit dismissal operation;
- reject a decoded Keychain session whose canonical host or user ID differs
  from the requested account;
- add deterministic regression tests for every race and failure path, then
  repeat focused and full verification.

## Explicit non-goals

- Migrating the unreleased single `current-session` Keychain item.
- A combined cross-account Home, Todo inbox, cache, or search.
- Background refresh for inactive accounts.
- Reusing navigation stacks, selected filters, or optimistic mutations across
  accounts.
- Reauthentication/editing for an existing account in place; Add Account can
  replace the exact same host/user identity after successful validation.
- iCloud Keychain synchronization or credential export.
- Account reordering or a configurable account limit.
- Draft implementation; P2-04 must use the account identity defined here.
- Any live mutation with the configured read-only token.

## Verification record

Not yet run. Record focused/full test counts, static-analysis result,
Simulator/runtime, live versus deterministic account rows, UI matrix, privacy
scan, review findings, repair plan, and final commit IDs here before marking
P2-01 complete.

## Required deep review

After implementation, review every P2-01 change for:

- incorrect identity or host normalization;
- wrong-account Keychain replace/delete operations;
- tokens or private data entering defaults, logs, filenames, screenshots, or
  descriptions;
- main-actor reentrancy and last-switch-wins races;
- late authentication, refresh, cache, or feature-model results crossing an
  account switch;
- non-atomic persistence and failed compensation;
- stale SwiftUI state surviving root reconstruction;
- duplicated account/session abstractions;
- inaccessible or ambiguous switching/removal UI;
- unnecessary architecture or code that should be simplified.

Record material findings here. If any exist, write a repair plan in this
document before editing, add regression tests, implement every fix, and repeat
the relevant verification and review.
