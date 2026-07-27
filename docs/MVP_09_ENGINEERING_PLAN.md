# MVP-09 engineering plan

Last updated: 2026-07-27

## Scope

MVP-09 adds the first complete Home destination: a paginated, searchable list
of open issues assigned to the signed-in user and a read-only native issue
detail.

This plan is based on the current official GitLab documentation:

- [Issues API](https://docs.gitlab.com/api/issues/)
- [REST API pagination](https://docs.gitlab.com/api/rest/#pagination)

## Assumptions and boundaries

- The list uses
  `GET /issues?scope=assigned_to_me&state=opened&order_by=updated_at&sort=desc`
  with 20 results per page.
- Pagination follows the exact `rel="next"` URL returned in GitLab's `Link`
  header. Before attaching credentials, Glab verifies that the URL is HTTPS,
  belongs to the configured GitLab origin, remains below that host's
  `/api/v4` path, and contains no user information or fragment.
- Details use `GET /projects/:id/issues/:issue_iid`. Route identity therefore
  consists of both the project ID and issue IID.
- One issue response model covers list and detail fields because GitLab returns
  the required metadata in both documented responses.
- Search is intentionally local and covers only rows already loaded. It matches
  title, full reference, labels, and assignee names/usernames.
- Descriptions use native best-effort Markdown rendering in this MVP. Full
  GitLab Flavored Markdown rendering and issue notes are later work.
- “Open in GitLab” accepts only an HTTPS API-provided `web_url`.
- This item is read-only. Editing, commenting, subscribing, and other issue
  mutations are out of scope.

## Implementation checklist

### 1. Secure page-following support

- [x] Represent an initial typed request or a server-provided next-page URL as
  one typed page request.
- [x] Validate next-page URLs in the request builder before applying the
  session's authorization header.
- [x] Route page requests through the existing decoding, OAuth refresh, and
  one-retry behavior without duplicating the client state machine.
- [x] Test accepted same-host links and rejected cross-host, non-API, insecure,
  credential-bearing, fragmented, and traversal links.

### 2. Issue API contract

- [x] Add assigned-issue and project-issue endpoints.
- [x] Decode identity, project/reference, title/description, state,
  confidentiality, labels, author, assignees, milestone, due date, note count,
  timestamps, and `web_url`.
- [x] Add a live loader that returns issue pages plus the next link and fetches
  one issue by project ID and IID.
- [x] Test endpoint queries, optional/null fields, confidential issues, route
  identity, and safe web routing.

### 3. Deterministic feature state

- [x] Add an observable assigned-issues model with initial load, refresh,
  incremental load, duplicate suppression, and non-destructive error handling.
- [x] Add local filtering and compact relative-time formatting.
- [x] Add an observable detail model with loading, loaded, and retry states.
- [x] Test page append/de-duplication, filtering, refresh, cancellation/error
  behavior, detail loading, and relative-time boundaries.

### 4. SwiftUI integration

- [ ] Replace the Assigned Issues preview destination with the full list while
  leaving the other four MVP destinations unchanged.
- [ ] Build dense native rows with reference, title, state/confidentiality,
  labels, assignees, note count, and relative update time.
- [ ] Build a read-only detail with description, author, status, labels,
  assignees, milestone/due date, timestamps, and “Open in GitLab.”
- [ ] Preserve pull-to-refresh, incremental loading, search, retry,
  authentication-failure routing, Dynamic Type, and VoiceOver labels.

### 5. Verification and handoff

- [ ] Run focused tests after each core slice and push a small commit to
  `master`.
- [ ] Run the complete signed test suite and Xcode static analyzer.
- [ ] Exercise list loading, search, pagination, detail, refresh, back
  navigation, Home/Todos tabs, and light/dark appearance on iPhone 17 Pro.
- [ ] Mark MVP-09 complete in `docs/MVP.md` only after every criterion above
  passes.

## Success criteria

MVP-09 is complete when a signed-in user can open Assigned Issues, browse and
search every loaded page without duplicates, inspect a native issue detail,
open its validated GitLab web page, recover from load failures, and use the
flow in light and dark appearance with all core behavior covered by unit tests.
