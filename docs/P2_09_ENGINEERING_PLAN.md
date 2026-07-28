# P2-09 Engineering Plan — Global Search and GitLab Deep Links

## Status

- Planning: complete
- Implementation: not started
- Verification: not started
- Deep review: not started

This document is the required plan for P2-09. Production code must not be
changed for this feature until this plan is committed.

## Outcome

A signed-in user can search projects, issues, and merge requests belonging to
the active GitLab account. A supported, trusted GitLab URL can select the
matching account and open the corresponding native project, issue, or merge
request screen.

The feature is read-only. It must never send one GitLab host's credential to a
different host.

## Existing-code audit

### Search

- `AssignedIssuesView`, `MergeRequestsView`, and `ProjectsView` use
  `.searchable`, but their models only filter items already loaded into memory.
- There is no instance-wide search client, search result model, search history,
  or global search screen.
- `GitLabPaginatedResourceModel` is appropriate for one homogeneous list, but
  global search needs three independently loading and paginating scopes. It
  should not be expanded into a multi-scope state container.
- `GitLabSessionClient` and `GitLabRequestBuilder` already provide read-access
  enforcement, account-scoped credentials, exact-host pagination validation,
  cancellation propagation, and defensive response decoding.

### Navigation and URLs

- `HomeView` owns the Home tab's `NavigationPath`.
- Issue and merge request detail screens already use
  `GitLabIssueRoute(projectID:issueIID:)` and
  `GitLabMergeRequestRoute(projectID:mergeRequestIID:)`.
- Projects currently open their validated `web_url` externally; there is no
  native project overview route.
- `GlabApp` and `AppRootView` do not currently consume incoming URLs.
- `GitLabWebURL` rejects non-HTTPS URLs and embedded credentials, but it does
  not establish that a URL belongs to a configured GitLab host.
- The existing `glab` custom scheme is registered for the OAuth callback.
  `glab://oauth/callback` must remain reserved for OAuth.

### Hosts and accounts

- `GitLabHost` normalizes HTTPS origins, explicit ports, API suffixes, and
  self-managed relative URL roots.
- `GitLabAccountID` includes the normalized `GitLabHost` and GitLab user ID.
- `AppSession` exposes account summaries and loads credentials only when
  `switchAccount(to:)` is explicitly called.
- More than one user account can exist on the same host, so a host match is not
  always enough to choose an account without user input.
- `AppRootView` recreates `SignedInShellView` for the active account. Any
  pending deep link that must survive account switching therefore needs a
  small owner above the signed-in shell.

### Resource payloads

- The live self-managed read-only probe returned `200` for `projects`,
  `issues`, and `merge_requests` using basic instance search.
- Search responses are intentionally not identical to detail responses. For
  example, the issue search payload did not include `references`, while the
  existing `GitLabIssue` requires it.
- Sparse, search-specific `Decodable` DTOs are required. Unknown fields must
  remain harmless and optional presentation fields must not make an entire
  scope fail decoding.

## Official GitLab contracts

- The [Search API](https://docs.gitlab.com/api/search/) is authenticated and
  available on Free, Premium, and Ultimate for GitLab.com, Self-Managed, and
  Dedicated. Instance search is `GET /search`, requires one `scope` and one
  `search` term, and supports offset pagination.
- The three P2-09 scopes are `projects`, `issues`, and `merge_requests`.
  Advanced/exact-code-only scopes are outside this feature.
- Requests will explicitly use `search_type=basic`. P2-09 will not use the
  Premium/Ultimate `fields=title` option or assume advanced/Zoekt search is
  enabled.
- GitLab's [REST pagination contract](https://docs.gitlab.com/api/rest/#pagination)
  says clients should follow the returned `Link` URL. Existing request
  construction already validates that URL against the active API origin and
  relative root before attaching authorization.
- The [Projects API](https://docs.gitlab.com/api/projects/) accepts a numeric
  project ID or URL-encoded project path for `GET /projects/:id`. This provides
  the safe bridge from a namespaced web URL to the existing numeric issue/MR
  routes.
- The [Issues API](https://docs.gitlab.com/api/issues/) and
  [Merge Requests API](https://docs.gitlab.com/api/merge_requests/) use a
  project ID or URL-encoded project path plus the resource IID.
- GitLab supports self-managed
  [relative URL installations](https://docs.gitlab.com/development/urls_in_gitlab/).
  Host matching must therefore include the configured relative root, not just
  the DNS name.

## Architecture

Use the app's existing SwiftUI MV style. Do not introduce TCA, a coordinator
framework, or a generic routing framework.

### State owners

1. `GitLabGlobalSearchModel`
   - Main-actor observable owner for the normalized query, recent in-memory
     queries, and one state value per search scope.
   - Receives one active-account loader at initialization.
   - Owns debounce, request generation, cancellation/stale-response guards,
     refresh, retry, and independent pagination.
2. `GitLabIncomingLinkModel`
   - Small main-actor observable owner created above `AppRootView`.
   - Stores only a validated pending GitLab HTTPS URL and the user decision
     needed to continue (sign in, add account, select account, browser
     fallback, or route).
   - Survives `SignedInShellView` recreation during an account switch.
   - Does not own networking, credentials, feature navigation stacks, or
     resource presentation.
3. `HomeView`
   - Remains the owner of the Home navigation path.
   - Consumes a resolved active-account destination and appends it once.
4. Pure nonisolated helpers
   - `GitLabDeepLinkParser` validates and parses URL structure.
   - `GitLabDeepLinkAccountMatcher` derives safe account choices.
   - `GitLabExternalAppLink` strictly unwraps
     `glab://open?url=<percent-encoded HTTPS URL>` and ignores the reserved
     OAuth callback.

Dependencies remain injected as protocols so endpoint, cancellation, failure,
and route behavior can be unit tested without network or UI rendering.

## Search design

### Supported scopes

| Scope | Endpoint value | Native destination |
| --- | --- | --- |
| Projects | `projects` | Native project overview |
| Issues | `issues` | Existing issue detail |
| Merge requests | `merge_requests` | Existing merge request detail |

Every nonempty normalized query starts the three first-page requests
concurrently. Results are shown in separate sections; they are never merged
into a relevance order that GitLab did not provide.

### Request contract

Each first-page request is:

```text
GET /search
scope=<scope>
search=<trimmed user query>
search_type=basic
per_page=20
```

It requires read access. Later pages use only GitLab's returned trusted
pagination URL.

### Result models and identity

Use separate defensive DTOs:

- `GitLabProjectSearchResult`
- `GitLabIssueSearchResult`
- `GitLabMergeRequestSearchResult`

Required routing identity:

- Project: global project ID plus `path_with_namespace`.
- Issue: project ID plus issue IID.
- Merge request: project ID plus merge request IID.

UI identity includes the active `GitLabAccountID`, scope, and routing identity.
This prevents accidental identity reuse when account switches recreate the
screen. Optional titles, descriptions, users, state, timestamps, labels, and
URLs decode defensively. Unknown fields are ignored by `Decodable`.

Search DTOs are not promoted into detail DTOs. Selecting an issue or MR loads
the authoritative detail endpoint through the existing loaders.

### Debounce, cancellation, and stale responses

- Normalize by trimming surrounding whitespace. Preserve the query's internal
  text and case when sending it to GitLab.
- An empty normalized query performs no request.
- Debounce for 300 milliseconds.
- The SwiftUI screen uses `.task(id: normalizedQuery)`, so a changed query
  cancels the prior task.
- The model also increments a monotonically increasing request generation.
  A response may mutate state only when its generation and normalized query
  are still current. This protects against transports that finish after
  cancellation.
- `.api(.cancelled)` and task cancellation do not appear as failures.
- A new query immediately stops presenting old-query results as if they match
  the new query.
- Account switching destroys the active account's search model and cancels its
  task. No model accepts a loader or result page from another account.

The debounce wait is injected for deterministic tests; tests will not sleep.

### Pagination

- Each scope stores its own `nextPageURL`, loaded page URLs, loading flag, and
  pagination error.
- Loading more in one scope does not block or mutate another scope.
- Duplicate resource identities are ignored while preserving GitLab order.
- Reusing the same next-page URL is treated as an invalid response rather than
  creating an infinite loop.
- Failed next-page loads retain already loaded results and expose an inline
  retry.

### Partial, permission, and unavailable states

The screen can show successful scopes alongside failed ones.

- `400`/`422`, `403`, and `404` from a fixed, valid scope are presented as
  unavailable or not permitted for that scope. The UI does not claim the scope
  was searched.
- Authentication failures are forwarded to `AppSession` for the active
  account.
- Connectivity, rate-limit, server, decoding, and unexpected failures are
  retryable scope failures.
- If all three scopes fail, the screen presents a global retry while retaining
  the per-scope explanations.

This classification is presentation-only. It does not weaken the existing API
error model.

### Search history and caching

- Keep at most five distinct recent queries in memory for the current active
  account and current app session.
- Add a query only after at least one scope completes successfully.
- Do not persist search terms to disk in P2-09.
- Do not write search response bodies to the disk response cache. Search terms
  can be sensitive and results are query-specific and volatile.
- The active screen retains its current results in memory. Debounce,
  cancellation, concurrent scopes, and incremental pagination provide the
  performance behavior for this phase.

Persistent or cross-account search history is a non-goal.

## Search UI

- Add a trailing Search control to the Home navigation toolbar. Keep the
  existing Home and Todos bottom tabs unchanged.
- The control pushes a native `Search` destination into Home's navigation
  stack.
- Use a native `.searchable` field with the prompt `Search GitLab`.
- Initial empty state explains the three supported resource types.
- After a successful query is cleared, show tappable recent queries.
- While debouncing/loading a new query, show a compact progress state without
  presenting stale results under the new text.
- Results use Projects, Issues, and Merge Requests sections with resource
  symbols, readable metadata, result counts when available, and independent
  load-more/retry rows.
- Empty scopes say that GitLab returned no matching resources.
- Unavailable/permission scopes state that the scope was not searched.
- A partial-results callout appears when at least one scope succeeds and at
  least one fails.
- Issue and MR rows navigate to their existing native detail screens.
- Project rows navigate to a small native project overview that loads
  `GET /projects/:path`, shows the project identity and existing metadata, and
  offers the existing compact validated “Open in GitLab” control.
- Add stable accessibility identifiers for the Search button, field, state,
  sections, rows, retry/load-more controls, and project overview.
- Support light/dark appearance, standard and accessibility Dynamic Type,
  VoiceOver labels, and Reduce Motion.
- Custom glass is reserved for interactive controls; static result content
  remains standard list content.

## Deep-link design

### Entry points

P2-09 supports:

1. A validated GitLab HTTPS link tapped inside Glab, including Markdown links.
2. The registered external custom scheme:
   `glab://open?url=<percent-encoded HTTPS GitLab URL>`.
3. Test and Simulator delivery through `simctl openurl` using that custom
   scheme.

`glab://oauth/callback` remains reserved and is never treated as a content
link.

An arbitrary `https://gitlab.com/...` tap in Safari cannot launch Glab without
an Apple universal-link association hosted by GitLab. Glab does not control
GitLab.com or self-managed instances' `apple-app-site-association` files.
Associated Domains and a share extension are non-goals for P2-09. This
limitation must not be represented as working behavior.

### Supported HTTPS grammar

After an exact configured-site match:

```text
<site-root>/<namespace...>/<project>
<site-root>/<namespace...>/<project>/-/issues/<positive-iid>
<site-root>/<namespace...>/<project>/-/merge_requests/<positive-iid>
```

- Namespace paths can contain subgroups.
- Percent-encoded namespace separators are decoded exactly once.
- A trailing slash is allowed.
- Query and fragment components do not change the native resource identity.
- A project path must contain at least a namespace and project component after
  the configured site root.
- Extra path components after an issue/MR IID are unsupported in P2-09 and can
  use the browser fallback.

### URL and host security rules

Reject native routing when any of these are true:

- Scheme is not HTTPS.
- The URL contains a username or password.
- Hostname is missing or is a suffix/prefix/lookalike rather than an exact
  case-insensitive match.
- Effective port differs.
- The configured self-managed relative root is not an exact decoded path
  prefix.
- A decoded segment is empty, `.`, `..`, contains a control character, or
  retains an encoded delimiter after one decoding pass.
- The route marker or IID grammar is malformed.
- The `glab://open` wrapper has an unexpected host/path, duplicate target
  values, or a non-HTTPS target.

No redirect is followed while choosing an account. No API authorization is
attached until an account has been explicitly resolved and, when needed,
selected.

### Account matching

1. Find accounts whose normalized `GitLabHost` exactly matches the URL origin
   and relative root.
2. If the active account matches, keep it active.
3. If exactly one inactive account matches, ask before switching.
4. If multiple accounts match, present their user identities and require a
   selection.
5. If no account matches, ask the user to add/sign in to that GitLab instance
   or open the validated URL in the system browser.
6. If signed out, retain only the validated URL, explain which host is needed,
   and continue after authentication.

The pending URL survives the account transition. It is reparsed after the new
session becomes active; it is not trusted based on an earlier partial result.

### Native route resolution

- Project URL: push `GitLabProjectRoute(pathWithNamespace:)`.
- Issue/MR URL: call `GET /projects/:url-encoded-path` through the active
  session client, then construct the existing numeric route from the returned
  project ID and URL IID.
- A forbidden/not-found project resolution does not guess an ID. Present the
  validated browser fallback.
- A cancellation or account change discards the old resolution response.

### Unsupported but safe URLs

A URL on the exact configured GitLab site that passes HTTPS/user-info/path
validation but is not one of the supported resource grammars remains visible
in an alert with `Open in GitLab` and `Cancel`.

Unsafe, malformed, and lookalike URLs are not offered as a GitLab browser
fallback from the custom app scheme.

## Test-first implementation order

### Commit 1 — Search contracts

Write failing tests for:

- Exact project/issue/MR endpoint paths, scopes, basic search, query encoding,
  page size, and read access.
- Sparse payloads, null optional values, and unknown fields.
- Search result identity across projects and accounts.
- Initial and next-page loader behavior, including trusted pagination.

Then implement the endpoint, DTO, page, protocol, and live loader layer.

### Commit 2 — Search state

Write failing tests for:

- Empty query performs no work.
- 300 ms debounce dependency is invoked.
- A changed query cancels prior work.
- A late prior response cannot replace current-query state.
- Three scopes load independently and concurrently.
- Partial success, permission/unavailable, total failure, and authentication
  failure.
- Independent pagination, duplicate suppression, next-page retry, and repeated
  pagination URL rejection.
- Recent-query behavior and five-item bound.
- Separate account models never share result identity or state.

Then implement `GitLabGlobalSearchModel`.

### Commit 3 — Deep-link core

Write failing table-driven tests for:

- GitLab.com and self-managed relative-root project, issue, and MR URLs.
- Subgroups, encoded namespace separators, trailing slash, query, and fragment.
- Positive IID validation.
- Exact host, case, and effective-port matching.
- Inactive single account, multiple same-host accounts, missing account, and
  signed-out decisions.
- HTTP, credentials, lookalike hosts, path-prefix lookalikes, dot traversal,
  encoded/double-encoded delimiters, malformed markers, duplicate wrapper
  targets, and the OAuth callback.
- Safe unsupported URLs retain a browser fallback; unsafe URLs do not.

Then implement the pure parser, wrapper, matcher, and incoming-link state.

### Commit 4 — Native routes and UI

Write focused tests for:

- Project-by-path endpoint encoding and route resolution.
- Deep-link resolution cancellation and account-generation guards.
- Project overview loading/failure behavior.

Then:

- Add the Home Search control and global search screen.
- Add the native project overview.
- Register issue/MR/project destinations at the Home navigation owner.
- Connect in-app links and `onOpenURL`.
- Add account selection/add-account/signed-out/unsupported-link prompts.

### Commit 5 — Verification and checklist

- Run focused tests after every vertical slice.
- Run the complete test suite.
- Run Release performance tests with testability enabled if required.
- Run `xcodebuild analyze`.
- Run source scans for unsafe URL matching, authorization in URL/query/log
  output, forced unwraps, and accidental credential descriptions.
- Verify the UI and deep-link matrix on an iPhone 17 Pro Simulator only.
- Update `docs/MVP_PHASE_2.md` only after all verification and review gates
  pass.

## Simulator verification matrix

Use the configured self-managed read-only token from `.env`. Never print the
token, mutate GitLab, or use a physical device.

- Sign in to the self-managed account in the iPhone 17 Pro Simulator.
- Open Search, enter a known project query, and inspect loading, results,
  clearing, and recent queries.
- Search issues and MRs using known read-only terms and open both native detail
  screens.
- Exercise a query that returns an empty scope.
- Exercise next-page loading if the live account has enough matching results;
  otherwise retain the deterministic pagination unit proof and record the live
  data limitation.
- Rapidly replace query text and confirm old results never flash under the new
  query.
- Pull to refresh and retry an injected/offline failure.
- Deliver GitLab.com, self-managed relative-root, encoded-path, unsupported,
  missing-account, lookalike, and malformed custom links with explicit
  `simctl openurl` calls.
- Confirm supported self-managed project/issue/MR links route natively.
- Confirm unmatched links never receive the self-managed credential.
- Verify dark and light appearance, standard and maximum Dynamic Type, Reduce
  Motion, VoiceOver labels/identifiers, scrolling, back navigation, and tab
  stability.
- Shut down all simulators and quit Simulator after verification.

## Deep-review gate

After implementation and verification, review every P2-09 change for:

- Credential/host confusion or authorization attached before account match.
- Suffix, prefix, port, relative-root, user-info, percent-decoding, traversal,
  lookalike, or wrapper parsing vulnerabilities.
- Cancellation races and late responses.
- Old-account or old-query state surviving a transition.
- Cross-account identity or search-history leakage.
- Incorrect scope availability claims or advanced-search assumptions.
- Pagination URL trust or infinite-loop errors.
- Sparse response decoding failures.
- Duplicate search, routing, project, or error-presentation models.
- View-owned networking, oversized state owners, or forwarding-only layers.
- Accessibility, Dynamic Type, loading, empty, partial, and error-state gaps.
- Any write request introduced by a read-only feature.

Record findings here. If any material issue is found, add a repair plan before
editing code, add regression/security tests, implement every repair, and repeat
the complete focused/full/analyzer/Simulator verification.

## Non-goals

- Advanced, exact-code, blob, commit, wiki, note, user, milestone, or work-item
  search.
- Search filters, saved searches, server-side recent searches, or persistent
  search history.
- Cross-account combined search.
- Disk caching of search terms or search response bodies.
- Search suggestions while offline.
- Universal links for GitLab-controlled HTTPS domains.
- A share extension.
- Native group, user, commit, pipeline, job, repository-tree, or settings
  routes.
- Creating, editing, merging, approving, reacting, or commenting from search.
- Following a web redirect to infer a GitLab account.

## Verification record

Not started.

## Deep-review findings

Not started.

## Repair plan

Not required unless the deep review records a material finding.
