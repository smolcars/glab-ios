# Glab iOS MVP

Last updated: 2026-07-27

## Product goal

Build a focused iPhone client that lets a GitLab user sign in, see the work that
needs their attention, inspect the relevant issue or merge request, and complete
GitLab Todos.

The visual direction comes from the GitHub iOS references in `github/`: native
large-title navigation, grouped "My Work" shortcuts, dense inbox-style rows, and
a Liquid Glass tab bar. Glab should use GitLab terminology, data, and semantic
colors rather than copying GitHub branding.

The MVP is complete when a user can:

1. Sign in with OAuth on GitLab.com or a configured self-managed GitLab
   instance, with a personal access token available as a fallback.
2. Use a two-tab app with **Home** and **Todos**.
3. Browse assigned issues, assigned merge requests, review requests, recent
   projects, and starred projects.
4. Read the essential details of an issue or merge request.
5. Browse pending and completed Todos, mark one Todo done, or mark all pending
   Todos done.
6. Recover cleanly from expired credentials, an unavailable server, decoding
   errors, pagination, and rate limiting.

## Decisions from API research

- Use the documented GitLab REST API v4. REST keeps this first release small and
  maps directly to the required resources. The API root is
  `https://<host>/api/v4`. See [REST API fundamentals and pagination][rest].
- The second tab is named **Todos**, not Notifications. GitLab provides a
  dedicated [To-Do List API][todos] with pending/done filters and completion
  operations.
- GitLab OAuth uses Authorization Code with PKCE. PKCE is intended for public
  clients such as an iOS app because no client secret can be kept safely in the
  app. OAuth access tokens expire and must be refreshed. See the
  [GitLab OAuth API][oauth] and [OAuth application scopes][oauth-scopes].
- OAuth supports both GitLab.com and self-managed GitLab in the MVP.
  GitLab.com uses Glab's registered Application ID. A self-managed instance
  requires a one-time Glab OAuth application registration on that instance and
  its Application ID during setup. The Application ID is not a user credential
  and can be shared by everyone on that instance.
- Self-managed users authenticate on their instance's normal web login page.
  Username/password, 2FA, LDAP, SAML, and other instance-configured methods stay
  between the user and GitLab; Glab receives only the resulting OAuth tokens.
- OAuth requests the `api` scope. `read_api` covers the browsing experience but
  cannot complete Todos; GitLab exposes Todo completion as a write operation
  and does not offer a narrower Todo-specific write scope.
- Personal access token sign-in also needs the `api` scope for the complete MVP.
  A `read_api` token may authenticate, but Glab must clearly identify the
  session as read-only and disable Todo completion. Glab can inspect the
  authenticating personal token with
  `GET /personal_access_tokens/self`. See [personal access tokens][pat-api] and
  [access token scopes][token-scopes].
- OAuth applications are registered per GitLab instance. Glab cannot reuse its
  GitLab.com Application ID on an arbitrary self-managed host or provide
  zero-configuration self-managed OAuth. If an instance has not registered
  Glab, the user can connect with a personal access token instead.
- Tokens and OAuth refresh tokens live only in Keychain. Tokens must never be
  written to logs, `UserDefaults`, fixtures, screenshots, or analytics.
- Self-managed instances must use HTTPS with a system-trusted certificate in
  the MVP. Custom certificate trust and HTTP exceptions are out of scope.
- Lists use server pagination. Follow GitLab's `Link` response rather than
  constructing a next URL; GitLab.com may omit some `X-*` pagination headers.
- A Todo target can be an issue, merge request, commit, epic, vulnerability, or
  another documented type. Issues and merge requests get native MVP details;
  every other target remains visible and opens its `target_url` in the system
  browser.

## Working agreement

- Complete the first unchecked item before starting another item.
- A checkbox is complete only when all acceptance criteria pass.
- Core logic changes include unit tests in the same item. Core logic includes
  authentication, endpoint/query construction, response decoding, pagination,
  error mapping, state transitions, filtering, and date/URL formatting.
- API tests use `URLProtocol` stubs or protocol fakes. Unit tests never depend on
  a live GitLab account.
- After each buildable item, run its unit tests and launch the app in an iOS
  Simulator. Visually inspect every screen changed by that item in light and
  dark appearance.
- Use the official GitLab API documentation as the source of truth. If observed
  behavior and this document disagree, verify the current docs before changing
  the contract.
- Keep changes surgical: the implementation for an item should not include
  unchecked features from later items.

## Ordered MVP checklist

### [x] MVP-00 — Define the MVP and API contract

Acceptance:

- The first release has a bounded goal, explicit non-goals, an ordered build
  queue, and verifiable completion criteria.
- Required endpoints and authentication constraints are backed by current
  official GitLab documentation.
- The GitHub reference images have been reviewed for navigation, hierarchy,
  list density, and detail presentation.

### [x] MVP-01 — Create the iOS project and test target

Deliver:

- Create the `Glab` SwiftUI iOS app and `GlabTests` unit-test target.
- Target iOS 26 or newer so the UI can use native Liquid Glass APIs without a
  compatibility implementation.
- Add a minimal dependency-free app entry point and testable folder structure.
- Add an initial smoke test and a shared Xcode scheme.

Verify:

- The app builds with no warnings.
- All tests pass from the command line.
- The app launches in an iPhone Simulator.

### [x] MVP-02 — Build the GitLab REST client foundation

Deliver:

- Normalize a GitLab host URL and derive its `/api/v4` base URL.
- Implement typed `GET` and `POST` requests, JSON decoding with ISO-8601 dates,
  request IDs, and injectable transport.
- Map authentication, authorization, not-found, validation, server,
  connectivity, decoding, cancellation, and `429` rate-limit failures to
  user-meaningful errors.
- Parse the documented `Link` header for next-page URLs.
- Inject either `Authorization: Bearer` for OAuth or `PRIVATE-TOKEN` for a
  personal access token.

Test:

- URL normalization and path/query encoding.
- Both authentication headers without exposing token values in descriptions or
  errors.
- Successful empty/object/array responses, malformed JSON, representative
  status codes, `Retry-After`, and pagination with missing optional headers.

### [x] MVP-03 — Add secure account and session storage

Deliver:

- Model the GitLab host, authenticated user summary, credential kind, per-host
  OAuth Application ID, OAuth expiry/refresh metadata, and session state.
- Store secret material in a small Keychain-backed credential store.
- Store only non-secret presentation preferences outside Keychain.
- Restore one signed-in account on launch and delete its credentials on sign
  out. Multiple accounts are post-MVP.

Test:

- Session state transitions with an in-memory credential store.
- Save, restore, replace, and delete behavior.
- Redacted debug descriptions and failures when stored data is corrupt.

### [x] MVP-04 — Implement personal access token/API-key sign-in

Deliver:

- Offer GitLab.com by default and an advanced custom-instance URL.
- Accept a masked/paste-friendly personal access token. In user-facing copy,
  describe this as an access token/API-key fallback while using GitLab's
  precise "personal access token" term in setup instructions.
- Validate the credentials with `GET /user` before saving them.
- Inspect `GET /personal_access_tokens/self` to derive the token's scopes and
  expiry.
- Explain that `api` scope is required to complete Todos. Permit `read_api`
  sessions in read-only mode and make their limitation visible.
- Show actionable messages for a malformed URL, untrusted/non-HTTPS host,
  `401`, `403`, connectivity failure, and unsupported response.

Test:

- Valid GitLab.com and custom-host requests.
- Failed validation never persists the token.
- Duplicate slashes/path fragments cannot produce a wrong API URL.
- Read-write versus read-only capability state.

### [ ] MVP-05 — Implement GitLab.com and self-managed OAuth with PKCE

Implementation status (2026-07-27): the OAuth/PKCE logic, refresh handling,
setup UI, personal-access-token fallback, unit tests, and simulator inspection
are complete. This item remains unchecked until a GitLab.com OAuth application
is registered, its real Application ID is supplied to the build, and a
clean-install live callback is verified. See [Glab OAuth setup](OAUTH_SETUP.md).

Deliver:

- Register the Glab OAuth redirect on GitLab.com and configure its public
  Application ID outside source-controlled secrets.
- Let a self-managed user enter their HTTPS instance URL and its Glab OAuth
  Application ID. Validate and store this non-secret configuration per host.
- Include setup guidance for registering Glab as a public/non-confidential
  OAuth application with the Glab redirect URI and `api` scope. Explain that an
  administrator can register one shared application for the instance.
- Start the authorization flow in `ASWebAuthenticationSession`.
- Build `/oauth/authorize` and `/oauth/token` URLs from the selected host so the
  instance's normal username/password, 2FA, or SSO page performs authentication.
- Generate a fresh verifier, S256 challenge, and unpredictable `state` for every
  attempt; reject callback state mismatches.
- Exchange the authorization code without a client secret, persist the access
  and refresh tokens, and validate the user with `GET /user`.
- Refresh expired access tokens once, coalescing simultaneous refresh attempts,
  then retry the original request once.
- Handle user cancellation and expired/revoked refresh tokens without loops.
- Handle an unknown Application ID, mismatched redirect URI, disabled
  user-created OAuth applications, and an unreachable instance with actionable
  setup errors and a personal-access-token fallback.

Test:

- RFC-compatible verifier/challenge generation.
- GitLab.com and custom-host authorization/token URLs, Application ID
  selection, and callback parsing.
- State mismatch, denial, cancellation, token response decoding, refresh
  success, refresh failure, coalescing, and one-retry limit.
- Self-managed configuration persistence and representative OAuth setup
  failures.

### [x] MVP-06 — Add launch routing and account controls

Deliver:

- Route signed-out users to authentication and valid sessions to the app.
- Present the current user's avatar, name, username, and GitLab host in an
  account sheet reachable from Home.
- Support sign out with confirmation.
- Return an expired or revoked session to authentication while preserving a
  clear explanation.

Test:

- Launch routing for missing, valid, refreshable, and invalid sessions.
- Sign out clears secrets and in-memory user data.

### [x] MVP-07 — Build the Home/Todos app shell

Deliver:

- Add exactly two root tabs: Home and Todos.
- Use the native iOS 26 tab/navigation APIs and Liquid Glass styling.
- Match the reference hierarchy: large titles, grouped content, readable dense
  rows, a prominent selected tab, and native materials.
- Establish GitLab semantic colors, spacing, symbols, loading placeholders,
  empty states, and retry states that work in light and dark appearance.
- Do not hard-code reference screenshot data into the running app.

Verify:

- Tab selection and independent navigation stacks behave correctly.
- Content remains legible with Increased Contrast and the largest accessibility
  text size.
- Reduce Motion is respected.

### [x] MVP-08 — Build the Home “My Work” dashboard

Deliver:

- Load the current user and compact previews/shortcuts for:
  - assigned open issues: `GET /issues?scope=assigned_to_me&state=opened`
  - assigned open merge requests:
    `GET /merge_requests?scope=assigned_to_me&state=opened`
  - open review requests:
    `GET /merge_requests?scope=reviews_for_me&state=opened`
  - recent member projects:
    `GET /projects?membership=true&order_by=last_activity_at&sort=desc`
  - starred projects: `GET /projects?starred=true`
- Load independent sections concurrently so one failed endpoint does not erase
  successful content.
- Support pull to refresh and route each shortcut to its corresponding list.

Test:

- Endpoint queries and sorting.
- Partial success, total failure, empty responses, refresh, and cancellation.
- Section view-state derivation without relying on exact total-count headers.

### [ ] MVP-09 — Add assigned issues and issue details

Deliver:

- Show a paginated list of assigned open issues with project/reference, title,
  state, labels, assignees, comment count, and relative update time.
- Provide refresh, incremental loading, and local list search over loaded rows.
- Show a read-only native detail with title, description, author, status,
  labels, assignees, milestone/due date when present, and timestamps.
- Provide “Open in GitLab” using the API-provided `web_url`.

Test:

- Issue decoding with null/optional fields and confidential issues.
- Page append/de-duplication, local filtering, relative date formatting, and
  route identity using project ID plus issue IID.

### [ ] MVP-10 — Add merge request lists and details

Deliver:

- Show assigned and review-requested merge requests in distinct filter modes.
- Include project/reference, draft/state, title, author, assignees/reviewers,
  source/target branches, comment count, and relative update time.
- Show a read-only native detail with essential metadata and description.
- Provide “Open in GitLab” using the API-provided `web_url`.

Test:

- Assigned versus `reviews_for_me` query construction.
- Merge-request decoding, including draft and missing optional data.
- Pagination, de-duplication, filtering, and project ID plus MR IID routing.
- Do not infer mergeability from stale list fields.

### [ ] MVP-11 — Add recent and starred project lists

Deliver:

- Show paginated recent-member and starred project modes.
- Include avatar/fallback mark, namespace/path, visibility, star count, and last
  activity.
- Provide local list search and “Open in GitLab.”
- Treat `last_activity_at` as approximate; GitLab documents that it can lag.

Test:

- Recent/starred queries, project decoding, visibility presentation,
  pagination, filtering, avatar fallback, and URL routing.

### [ ] MVP-12 — Build the Todos inbox

Deliver:

- Fetch `GET /todos` with pending as the default and a pending/done state
  control.
- Add filters for all targets, issues, and merge requests without hiding
  unsupported target types from the unfiltered inbox.
- Show target type, action, project, title/body, author, and relative time in a
  dense inbox row inspired by the GitHub reference.
- Support pull to refresh, pagination, empty/error states, and an unread-style
  pending badge on the tab when a reliable count is available.
- Decode unknown future `target_type` and `action_name` values without failing
  the whole page.

Test:

- Every currently documented action and target type plus unknown values.
- Pending/done/type query construction.
- Polymorphic target decoding with missing project/author/target data.
- Filtering, pagination, refresh, and badge derivation.

### [ ] MVP-13 — Add Todo routing and completion actions

Deliver:

- Route issue and merge-request Todos to their native details.
- Open every other supported/unknown target through its validated `target_url`.
- Mark one pending Todo done with `POST /todos/:id/mark_as_done`.
- Mark all pending Todos done with `POST /todos/mark_as_done` after
  confirmation.
- Use optimistic row removal/state changes with rollback and an accessible
  error if the request fails.
- Disable completion in a read-only token session and explain the required
  permission.

Test:

- Native versus browser routing and unsafe/missing target URLs.
- Successful completion, `204` mark-all response, rollback, duplicate taps,
  in-flight refresh, partial stale data, and read-only capability handling.

### [ ] MVP-14 — Finish resilience, accessibility, and privacy

Deliver:

- Add consistent offline, timeout, server, permission, expired-session, and
  rate-limit recovery UI.
- Preserve already-loaded content during a failed refresh.
- Audit VoiceOver labels/order, Dynamic Type, color contrast, Reduce Motion,
  button hit areas, loading announcements, and destructive confirmations.
- Confirm no secrets or confidential response bodies appear in logs, error
  messages, analytics, screenshots, or test fixtures.
- Add an in-app privacy/auth explanation for the broad GitLab `api` scope.

Test:

- Core retry/backoff and state-preservation logic.
- Redaction of requests, responses, and errors.
- Accessibility identifiers for the critical sign-in, tab, refresh, Todo, and
  sign-out paths.

### [ ] MVP-15 — Verify and release the MVP

Deliver:

- Run the complete unit-test suite.
- Perform clean installs for GitLab.com OAuth, GitLab.com personal token,
  configured self-managed OAuth with username/password and 2FA, and a
  trusted-HTTPS self-managed instance token.
- Exercise empty, populated, read-only, expired-token, offline, and rate-limited
  states.
- Walk the complete Home and Todos flows on a current small-screen and
  large-screen iPhone Simulator in light/dark appearance and with a large
  accessibility text size.
- Resolve all build warnings and document any server-version compatibility
  limitations discovered during testing.

Exit criteria:

- Every checklist item above is complete.
- There are no known crashes, credential leaks, dead-end screens, or blocking
  accessibility issues in the MVP paths.

## Explicitly out of MVP

- Push notifications, background refresh, Live Activities, widgets, and badges
  derived from background polling.
- Creating or editing issues, merge requests, projects, labels, or milestones.
- Comments, threaded discussions, reactions, approvals, merges, rebases, branch
  updates, and pipeline actions.
- Diff/file/repository browsing, commits, pipelines/jobs/logs, releases,
  packages, groups, members, snippets, epics, and vulnerabilities.
- Global search/explore, offline persistence, multiple accounts, and account
  switching.
- Automatic/dynamic self-managed OAuth application registration,
  SAML-provider-specific configuration UI, client-certificate authentication,
  custom CA trust, and non-HTTPS hosts.
- iPad-specific layouts, macOS, visionOS, watchOS, and non-Apple platforms.
- Pixel-for-pixel GitHub reproduction or copying GitHub assets/branding.

## Post-MVP candidates

Prioritize these only after MVP-15:

1. Read discussions and render more complete GitLab Flavored Markdown.
2. Comment on issues and merge requests.
3. Review diffs and pipelines.
4. Approve and merge with explicit permission/safety design.
5. Create and edit issues.
6. Search, groups, repository browsing, and multiple accounts.
7. Push notifications and carefully budgeted background refresh.
8. Automatic discovery or administrator provisioning of self-managed OAuth
   configuration.

## Official API references

- [REST API fundamentals and pagination][rest]
- [REST API authentication][rest-auth]
- [OAuth 2.0 identity provider API][oauth]
- [OAuth applications and scopes][oauth-scopes]
- [Personal access tokens API][pat-api]
- [Access token scopes][token-scopes]
- [Users API (`GET /user`)][users]
- [To-Do List API][todos]
- [Issues API][issues]
- [Merge requests API][merge-requests]
- [Projects API][projects]
- [Rate-limit response headers][rate-limits]

[rest]: https://docs.gitlab.com/api/rest/
[rest-auth]: https://docs.gitlab.com/api/rest/authentication/
[oauth]: https://docs.gitlab.com/api/oauth2/
[oauth-scopes]: https://docs.gitlab.com/integration/oauth_provider/
[pat-api]: https://docs.gitlab.com/api/personal_access_tokens/#self-inform
[token-scopes]: https://docs.gitlab.com/security/tokens/access_token_scopes/
[users]: https://docs.gitlab.com/api/users/#retrieve-the-current-user
[todos]: https://docs.gitlab.com/api/todos/
[issues]: https://docs.gitlab.com/api/issues/
[merge-requests]: https://docs.gitlab.com/api/merge_requests/
[projects]: https://docs.gitlab.com/api/projects/
[rate-limits]: https://docs.gitlab.com/administration/settings/user_and_ip_rate_limits/#response-headers
