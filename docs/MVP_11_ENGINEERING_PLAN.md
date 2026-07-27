# MVP-11 engineering plan: projects

Last updated: 2026-07-27

## Outcome

Add read-only, paginated recent-member and starred-project lists. Both existing
Home shortcuts must route to the correct mode, and each project must expose a
validated link to GitLab without adding repository browsing or a native project
detail screen.

## Assumptions and API contract

- The instance is already represented by an authenticated
  `GitLabSessionClient`; MVP-11 adds no authentication behavior.
- Recent projects use:
  `GET /projects?membership=true&order_by=last_activity_at&sort=desc`.
- Starred projects use:
  `GET /projects?starred=true&order_by=last_activity_at&sort=desc`.
- Both initial lists request `simple=true` and `per_page=20`. The response still
  includes the project identity and presentation fields required by this
  phase.
- The loader follows GitLab's response `Link` URL for later pages instead of
  constructing page numbers.
- Project identity is the globally unique project `id`.
- Decode only `id`, name/path/namespace presentation, `avatar_url`, `web_url`,
  `visibility`, `star_count`, and `last_activity_at`.
- Treat `last_activity_at` as approximate. GitLab documents that it updates at
  most once per hour, so Glab must not describe it as an exact last-change
  timestamp.
- Decode unknown future visibility values without failing the page and present
  them neutrally.
- Expose API-provided project and avatar URLs only when they are HTTPS,
  host-bearing, and contain no URL credentials. A missing or unsafe avatar uses
  a local project-initial fallback; a missing or unsafe project URL disables
  the external-link affordance.

Sources:

- [GitLab Projects API](https://docs.gitlab.com/api/projects/)
- [GitLab REST pagination](https://docs.gitlab.com/api/rest/#pagination)

## Architecture

Keep the established SwiftUI Model-View shape:

- `GitLabProjectListMode` owns the recent/starred filter, title, symbol, and
  empty-state copy.
- `GitLabProject` decodes the small response contract and owns visibility and
  fallback-mark presentation values that require unit coverage.
- `GitLabProjectEndpoints` builds both initial list requests.
- `GitLabProjectLoading` is the test seam; the live loader delegates to
  `GitLabPaginatedSessionRequestSending`.
- A thin `GitLabPaginatedResourceModel<GitLabProject, Int>` adapter supplies
  project-specific page loading and search values while reusing the audited
  pagination, refresh, de-duplication, cancellation, and error behavior.
- `ProjectsView` owns its fixed mode, displays dense rows, and opens validated
  project links.
- `HomeView` maps both existing project shortcuts to the new view.

The project response remains separate from the compact Home preview response.
The preview intentionally decodes fewer fields and has a different request
size; combining them would couple two independently testable contracts.

## Test-first implementation order

### 1. Response type and endpoint contract

Write failing tests for:

- recent-member and starred query construction;
- decoding documented project, namespace, visibility, count, activity, avatar,
  and web URL fields;
- missing optional namespace/avatar data;
- private, internal, public, and unknown visibility presentation;
- rejection of unsafe project and avatar URLs;
- stable fallback marks for names with words, punctuation, or no usable
  alphanumeric characters.

Then add only the response fields and endpoint builders needed to pass them.

### 2. Loader and list state

Write failing tests for:

- passing the fixed mode into the initial request;
- following the server-provided next-page URL;
- de-duplicating by project ID;
- local filtering over name, path with namespace, namespace name/path, and
  visibility;
- retained-content refresh failures, incremental failures, cancellation, and
  authentication failures through the shared pagination engine.

Then implement the loader and project adapter.

### 3. UI and Home routing

Build:

- separate “Recent Projects” and “Starred Projects” list titles;
- GitHub-inspired dense rows with a rounded avatar/fallback mark, namespace,
  project name, visibility, star count, approximate relative activity, and a
  clear external-link affordance;
- search, pull to refresh, pagination, empty states, retained-content refresh
  failures, and retryable incremental failures;
- Home routing for both project shortcuts.

Do not add native project details, files, branches, commits, issues, merge
requests, starring mutations, or any other repository feature.

## Verification gates

1. Focused endpoint/decoding tests pass.
2. Focused loader/model tests pass.
3. The complete signed unit-test suite passes on iPhone 17 Pro, iOS 26.5.
4. Xcode static analysis reports no code findings.
5. With the existing read-only simulator session, both Home shortcuts load the
   correct live list mode; representative external-link, search, refresh,
   pagination, and back interactions are exercised.
6. Recent and starred lists, including available avatar and fallback-mark
   rows, are visually inspected in light and dark appearance.
7. The implementation is committed to `master` in small, passing increments.

